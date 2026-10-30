import { Controller, Get, Res } from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { Response } from 'express';
import { FulfillmentMetricsService } from '../../infrastructure/metrics/fulfillment-metrics.service';

@ApiTags('system')
@Controller()
export class HealthController {
  constructor(private readonly metricsService: FulfillmentMetricsService) {}

  @Get('health')
  @ApiOperation({ summary: 'Health check endpoint' })
  getHealth() {
    return {
      status: 'UP',
      service: 'fulfillment-service',
      framework: 'nestjs-v12.2.0',
      orm: 'typeorm-1.1.2',
      engine: 'nodejs-24',
    };
  }

  @Get('actuator/health')
  @ApiOperation({ summary: 'Spring Boot compatible actuator health check' })
  getActuatorHealth() {
    return this.getHealth();
  }

  @Get('metrics')
  @ApiOperation({ summary: 'Prometheus metrics endpoint' })
  async getMetrics(@Res() res: Response) {
    const metrics = await this.metricsService.getMetrics();
    res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    res.end(metrics);
  }
}
