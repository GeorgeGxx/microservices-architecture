import './tracer';
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
  const config = new DocumentBuilder()
    .setTitle('Fulfillment Service API')
    .setDescription('Logistics and shipment tracking microservice built with TypeScript, NestJS v12.2.0, TypeORM 1.1.2 and PostgreSQL 18')
    .setVersion('1.0.0')
    .addTag('shipments')
    .addTag('system')
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('swagger', app, document);
  SwaggerModule.setup('swagger-ui', app, document);
  SwaggerModule.setup('docs', app, document);
  SwaggerModule.setup('api/docs', app, document);

  const port = process.env.PORT || 8086;
  await app.listen(port, '0.0.0.0');

  logger.log(`fulfillment-service running on port ${port}`, 'FulfillmentBootstrap');
  logger.log(`Swagger UI available at: http://localhost:${port}/swagger`, 'FulfillmentBootstrap');
}

void bootstrap();
