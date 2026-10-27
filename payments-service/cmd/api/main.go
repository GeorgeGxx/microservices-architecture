package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/georgegxx/payments-service/config"
	_ "github.com/georgegxx/payments-service/docs"
	"github.com/georgegxx/payments-service/internal/handlers"
	"github.com/georgegxx/payments-service/internal/kafka"
	"github.com/georgegxx/payments-service/internal/models"
	"github.com/georgegxx/payments-service/internal/repository"
	"github.com/georgegxx/payments-service/internal/services"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// @title Payments Service API
// @version 1.0
// @description High-performance payments microservice with Go 1.26, Gin v1.12.0, GORM v1.31.2, goroutines and PostgreSQL 18
// @contact.name GeorgeGxx Architecture
// @host localhost:8085
// @BasePath /
func main() {
	cfg := config.LoadConfig()

	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// 1. Connect to PostgreSQL 18 via GORM
	log.Printf("[Main] Connecting to PostgreSQL 18 at %s:%s/%s...", cfg.DBHost, cfg.DBPort, cfg.DBName)
	var db *gorm.DB
	var err error

	// Retry loop for database readiness during container cold starts
	for attempts := 1; attempts <= 15; attempts++ {
		db, err = gorm.Open(postgres.Open(cfg.GetDSN()), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Warn),
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
		sqlDB.SetMaxIdleConns(10)
		sqlDB.SetMaxOpenConns(50)
		sqlDB.SetConnMaxLifetime(time.Hour)
	}

	// 2. Auto-migrate schema in PostgreSQL 18
	log.Println("[Main] Running GORM auto-migrations for Payment and PaymentAuditLog...")
	if err := db.AutoMigrate(&models.Payment{}, &models.PaymentAuditLog{}); err != nil {
		log.Fatalf("[Main] Failed to migrate database: %v", err)
	}

	// 3. Initialize Kafka Producer & Consumer
	brokers := strings.Split(cfg.KafkaBrokers, ",")
	producer := kafka.NewEventProducer(brokers, cfg.KafkaPaymentsTopic)

	repo := repository.NewPaymentRepository(db)
	paymentSvc := services.NewPaymentService(repo, producer)
	handler := handlers.NewPaymentHandler(paymentSvc)

	// Start Kafka Consumer in a dedicated background goroutine
	ctx, stopConsumer := context.WithCancel(context.Background())
	consumer := kafka.NewOrderEventConsumer(brokers, cfg.KafkaOrdersTopic, cfg.KafkaGroupID, paymentSvc)
	go consumer.Start(ctx)

	// 4. Setup Gin HTTP Server & Routes
	router := gin.Default()

	// Global Middlewares
	router.Use(gin.Recovery())
	router.Use(corsMiddleware())

	// System & Observability endpoints
	router.GET("/health", handler.Health)
	router.GET("/actuator/health", handler.Health)
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Swagger documentation
	router.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	// Business APIs
	apiV1 := router.Group("/api/v1/payments")
	{
		apiV1.POST("/process", handler.ProcessPayment)
		apiV1.POST("/refund", handler.RefundPayment)
		apiV1.GET("/order/:orderNumber", handler.GetPaymentByOrder)
		apiV1.GET("/:id", handler.GetPaymentByID)
	}

	server := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: router,
	}

	// 5. Start Server with Graceful Shutdown
	go func() {
		log.Printf("[Main] payments-service listening on port %s (Swagger UI: http://localhost:%s/swagger/index.html)", cfg.Port, cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[Main] Server listen error: %v", err)
		}
	}()

	// Wait for OS interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("[Main] Shutting down payments-service gracefully...")

	// Stop Kafka Consumer & Service Workers
	stopConsumer()
	_ = consumer.Close()
	paymentSvc.Stop()
	_ = producer.Close()

	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelShutdown()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("[Main] Server forced to shutdown: %v", err)
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
