package main

import (
	"bytes"
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/georgegxx/payments-service/config"
	_ "github.com/georgegxx/payments-service/docs" // Swagger OpenAPI documentation
	"github.com/georgegxx/payments-service/internal/handlers"
	"github.com/georgegxx/payments-service/internal/kafka"
	"github.com/georgegxx/payments-service/internal/metrics"
	"github.com/georgegxx/payments-service/internal/models"
	"github.com/georgegxx/payments-service/internal/repository"
	"github.com/georgegxx/payments-service/internal/services"
	"github.com/georgegxx/payments-service/internal/telemetry"
	sentrygin "github.com/getsentry/sentry-go/gin"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"
)

const serviceName = "payments-service"

// @title Payments Service API
// @version 1.0
// @description High-performance payments microservice with Go 1.26, Gin v1.12.0, GORM v1.31.2, goroutines and PostgreSQL 18
// @contact.name GeorgeGxx Architecture
// @host localhost:8085
// @BasePath /
func main() {
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		client := http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get("http://127.0.0.1:8085/health")
		if err != nil {
			os.Exit(1)
		}
		statusCode := resp.StatusCode
		_ = resp.Body.Close()
		if statusCode != http.StatusOK {
			os.Exit(1)
		}
		os.Exit(0)
	}

	cfg := config.LoadConfig()

	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// 0. Initialize OpenTelemetry Distributed Tracing & Correlated Logging
	ctx, stopSignals := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stopSignals()
	telemetry.InitGlitchTip(serviceName, cfg.Environment)
	defer telemetry.FlushGlitchTip()
	tp, err := telemetry.InitTracer(ctx, serviceName, cfg.Environment)
	if err != nil {
		log.Printf("[Main] Warning: Failed to initialize OpenTelemetry tracer: %v", err)
	}
	appLogger := telemetry.NewCorrelatedLogger(serviceName)
	appLogger.InfoContext(ctx, "Starting payments-service with OpenTelemetry and Tempo correlation")

	// 1. Connect to PostgreSQL 18 via GORM
	log.Printf("[Main] Connecting to PostgreSQL 18 at %s:%s/%s...", cfg.DBHost, cfg.DBPort, cfg.DBName)
	var db *gorm.DB

	// Retry loop for database readiness during container cold starts
	for attempts := 1; attempts <= 15; attempts++ {
		db, err = gorm.Open(postgres.Open(cfg.GetDSN()), &gorm.Config{
			Logger: gormlogger.Default.LogMode(gormlogger.Warn),
		})
		if err == nil {
			break
		}
		log.Printf("[Main] Database not ready yet (attempt %d/15): %v. Retrying in 2s...", attempts, err)
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		log.Fatalf("[Main] CRITICAL: Failed to connect to PostgreSQL 18: %v", err)
	}

	sqlDB, err := db.DB()
	if err == nil {
		sqlDB.SetMaxIdleConns(5)
		sqlDB.SetMaxOpenConns(25)
		sqlDB.SetConnMaxIdleTime(5 * time.Minute)
		sqlDB.SetConnMaxLifetime(30 * time.Minute)
	}

	// 2. Auto-migrate schema in PostgreSQL 18
	log.Println("[Main] Running GORM auto-migrations for Payment, PaymentAuditLog, ProcessedMessage, and OutboxEvent...")
	if err := db.AutoMigrate(&models.Payment{}, &models.PaymentAuditLog{}, &models.ProcessedMessage{}, &models.OutboxEvent{}); err != nil {
		log.Fatalf("[Main] Failed to migrate database: %v", err)
	}

	// 3. Initialize Kafka Producer & Consumer
	brokers := strings.Split(cfg.KafkaBrokers, ",")
	producer := kafka.NewEventProducer(brokers, cfg.KafkaPaymentsTopic)

	repo := repository.NewPaymentRepository(db)
	paymentSvc := services.NewPaymentService(repo, producer)
	handler := handlers.NewPaymentHandler(paymentSvc)

	// Start Kafka Consumers in dedicated background goroutines (orders-topic & fulfillment-topic for Saga compensation)
	consumerCtx, stopConsumer := context.WithCancel(ctx)
	consumer := kafka.NewOrderEventConsumer(brokers, cfg.KafkaOrdersTopic, cfg.KafkaGroupID, paymentSvc, repo)
	fulfillmentConsumer := kafka.NewOrderEventConsumer(brokers, cfg.KafkaFulfillmentTopic, cfg.KafkaGroupID+"-fulfillment", paymentSvc, repo)
	go consumer.Start(consumerCtx)
	go fulfillmentConsumer.Start(consumerCtx)

	// 4. Setup Gin HTTP Server & Routes with Observability Middlewares
	router := gin.New()

	// Global Middlewares (Observability, OpenTelemetry, Metrics, Recovery, CORS)
	router.Use(sentrygin.New(sentrygin.Options{}))
	router.Use(gin.Logger(), gin.Recovery())
	router.Use(otelgin.Middleware(serviceName))
	router.Use(metrics.GinMetricsMiddleware(serviceName))
	router.Use(corsMiddleware())

	// System & Observability endpoints
	router.GET("/health", handler.Health)
	router.GET("/actuator/health", handler.Health)
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Swagger documentation (dark theme + enhanced Swagger UI capabilities)
	swaggerHandler := ginSwagger.WrapHandler(
		swaggerFiles.Handler,
		ginSwagger.PersistAuthorization(true),
		ginSwagger.DocExpansion("list"),
		ginSwagger.DeepLinking(true),
		ginSwagger.DefaultModelsExpandDepth(1),
	)
	router.GET("/swagger/*any", swaggerDarkThemeHandler(swaggerHandler))

	// Business APIs
	apiV1 := router.Group("/api/v1/payments")
	{
		apiV1.POST("/process", handler.ProcessPayment)
		apiV1.POST("/refund", handler.RefundPayment)
		apiV1.GET("/order/:orderNumber", handler.GetPaymentByOrder)
		apiV1.GET("/:id", handler.GetPaymentByID)
	}

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// 5. Start Server with Graceful Shutdown
	go func() {
		log.Printf("[Main] payments-service listening on port %s (Swagger UI: http://localhost:%s/swagger/index.html)", cfg.Port, cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[Main] Server listen error: %v", err)
		}
	}()

	// Wait for OS interrupt signal
	<-ctx.Done()
	log.Println("[Main] Shutting down payments-service gracefully...")

	// 1. Drain in-flight HTTP requests before stopping background workers and Kafka producers
	shutdownCtx, cancelShutdown := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
	defer cancelShutdown()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("[Main] HTTP server shutdown error: %v", err)
	}

	// 2. Stop Kafka Consumers, Service Workers, and Producer
	stopConsumer()
	_ = consumer.Close()
	_ = fulfillmentConsumer.Close()
	paymentSvc.Stop()
	_ = producer.Close()

	if tp != nil {
		_ = tp.Shutdown(shutdownCtx)
	}

	log.Println("[Main] payments-service exited cleanly.")
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With, Idempotency-Key")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, PATCH, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

type swaggerResponseWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (w *swaggerResponseWriter) Write(b []byte) (int, error) {
	return w.body.Write(b)
}

func (w *swaggerResponseWriter) WriteString(s string) (int, error) {
	return w.body.WriteString(s)
}

func swaggerDarkThemeHandler(next gin.HandlerFunc) gin.HandlerFunc {
	const darkStyle = `<style>
		body, .swagger-ui { background: #0f172a !important; color: #e2e8f0 !important; }
		.swagger-ui .topbar { background: #020617 !important; border-bottom: 1px solid #334155; }
		.swagger-ui .info .title, .swagger-ui .info h1, .swagger-ui .info h2, .swagger-ui .info h3,
		.swagger-ui .opblock-tag, .swagger-ui .opblock .opblock-summary-operation-id,
		.swagger-ui .opblock .opblock-summary-path, .swagger-ui .opblock .opblock-summary-description,
		.swagger-ui .tab li, .swagger-ui label, .swagger-ui .parameter__name, .swagger-ui .parameter__type,
		.swagger-ui table thead tr th, .swagger-ui table thead tr td, .swagger-ui .response-col_status,
		.swagger-ui .response-col_description, .swagger-ui .model-title, .swagger-ui .model { color: #e2e8f0 !important; }
		.swagger-ui .scheme-container, .swagger-ui .opblock .opblock-section-header,
		.swagger-ui section.models, .swagger-ui .model-box, .swagger-ui .dialog-ux .modal-ux { background: #1e293b !important; border-color: #334155 !important; }
		.swagger-ui input, .swagger-ui textarea, .swagger-ui select { background: #0f172a !important; color: #f8fafc !important; border: 1px solid #475569 !important; }
		.swagger-ui .btn { color: #f8fafc !important; border-color: #475569 !important; }
		.swagger-ui .filter .operation-filter-input { background: #1e293b !important; color: #f8fafc !important; border-color: #475569 !important; }
	</style>`
	return func(c *gin.Context) {
		if !strings.HasSuffix(c.Request.URL.Path, "index.html") {
			next(c)
			return
		}
		origWriter := c.Writer
		bufWriter := &swaggerResponseWriter{ResponseWriter: origWriter, body: &bytes.Buffer{}}
		c.Writer = bufWriter
		next(c)
		c.Writer = origWriter

		html := bufWriter.body.String()
		html = strings.Replace(html, "</head>", darkStyle+"</head>", 1)
		html = strings.Replace(html, "SwaggerUIBundle({", "SwaggerUIBundle({\n      filter: true,\n      displayRequestDuration: true,\n      tryItOutEnabled: true,\n      syntaxHighlight: { theme: 'monokai' },", 1)
		origWriter.Header().Set("Content-Length", strconv.Itoa(len(html)))
		_, _ = origWriter.WriteString(html)
	}
}
