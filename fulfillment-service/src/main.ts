import './tracer';
import './telemetry/glitchtip.js';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { CorrelatedLoggerService } from './infrastructure/telemetry/correlated-logger.service';
import { MetricsInterceptor } from './infrastructure/metrics/metrics.interceptor';
import { FulfillmentMetricsService } from './infrastructure/metrics/fulfillment-metrics.service';

async function bootstrap() {
  const logger = new CorrelatedLoggerService();
  const app = await NestFactory.create(AppModule, {
    logger,
  });

  const metricsService = app.get(FulfillmentMetricsService);
  app.useGlobalInterceptors(new MetricsInterceptor(metricsService));

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  const allowedOrigins = (
    process.env.CORS_ALLOWED_ORIGINS ||
    'http://localhost:5173,http://localhost:8080,https://shop.georgegxx.dev'
  )
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.enableCors({
    origin: allowedOrigins,
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
  });

  // Swagger OpenAPI 3.0 Documentation
  const swaggerDarkCss = `
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
  `;
  const swaggerUiOptions = {
    customCss: swaggerDarkCss,
    customSiteTitle: 'Fulfillment Service API · Swagger UI',
    swaggerOptions: {
      persistAuthorization: true,
      displayRequestDuration: true,
      filter: true,
      tryItOutEnabled: true,
      deepLinking: true,
      docExpansion: 'list',
      defaultModelsExpandDepth: 1,
      showExtensions: true,
      showCommonExtensions: true,
      syntaxHighlight: { theme: 'monokai' },
    },
  };
  const config = new DocumentBuilder()
    .setTitle('Fulfillment Service API')
    .setDescription('Logistics and shipment tracking microservice built with TypeScript, NestJS v12.2.0, TypeORM 1.1.2 and PostgreSQL 18')
    .setVersion('1.0.0')
    .addBearerAuth({ type: 'http', scheme: 'bearer', bearerFormat: 'JWT' }, 'BearerAuth')
    .addTag('shipments')
    .addTag('system')
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('swagger', app, document, swaggerUiOptions);
  SwaggerModule.setup('swagger-ui', app, document, swaggerUiOptions);
  SwaggerModule.setup('docs', app, document, swaggerUiOptions);
  SwaggerModule.setup('api/docs', app, document, swaggerUiOptions);

  // Enable shutdown hooks for graceful termination in Kubernetes
  app.enableShutdownHooks();

  const port = process.env.PORT || 8086;
  await app.listen(port, '0.0.0.0');

  logger.log(`fulfillment-service running on port ${port}`, 'FulfillmentBootstrap');
  logger.log(`Swagger UI available at: http://localhost:${port}/swagger`, 'FulfillmentBootstrap');
}

void bootstrap();
