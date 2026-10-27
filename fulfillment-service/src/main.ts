import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';

async function bootstrap() {
  const logger = new Logger('FulfillmentBootstrap');
  const app = await NestFactory.create(AppModule);

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  app.enableCors({
    origin: '*',
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
  SwaggerModule.setup('api/docs', app, document);

  const port = process.env.PORT || 8086;
  await app.listen(port, '0.0.0.0');

  logger.log(`fulfillment-service running on port ${port}`);
  logger.log(`Swagger UI available at: http://localhost:${port}/swagger`);
}

bootstrap();
