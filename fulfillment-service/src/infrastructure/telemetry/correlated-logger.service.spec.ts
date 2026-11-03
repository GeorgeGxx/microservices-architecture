import { jest } from '@jest/globals';
import { CorrelatedLoggerService } from './correlated-logger.service';

describe('CorrelatedLoggerService', () => {
  let service: CorrelatedLoggerService;
  let logSpy: jest.SpyInstance;
  let errorSpy: jest.SpyInstance;
  let warnSpy: jest.SpyInstance;
  let debugSpy: jest.SpyInstance;
  let infoSpy: jest.SpyInstance;

  beforeEach(() => {
    service = new CorrelatedLoggerService();
    logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
    warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
    debugSpy = jest.spyOn(console, 'debug').mockImplementation(() => {});
    infoSpy = jest.spyOn(console, 'info').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('formats and outputs info log with string message', () => {
    service.log('Shipment created', 'ShipmentModule');
    expect(logSpy).toHaveBeenCalledTimes(1);
    const logged = logSpy.mock.calls[0][0];
    expect(logged).toContain('[fulfillment-service,,]');
    expect(logged).toContain('[ShipmentModule]');
    expect(logged).toContain('Shipment created');
  });

  it('formats and outputs object message as JSON', () => {
    service.log({ orderNumber: 'ORD-101', status: 'PLACED' });
    expect(logSpy).toHaveBeenCalledTimes(1);
    const logged = logSpy.mock.calls[0][0];
    expect(logged).toContain('{"orderNumber":"ORD-101","status":"PLACED"}');
  });

  it('formats and outputs error log with stack trace', () => {
    service.error('Database connection failed', 'Error stack line 1', 'DatabaseModule');
    expect(errorSpy).toHaveBeenCalledTimes(2);
    expect(errorSpy.mock.calls[0][0]).toContain('Database connection failed');
    expect(errorSpy.mock.calls[1][0]).toBe('Error stack line 1');
  });

  it('formats and outputs error log without stack trace', () => {
    service.error('Generic failure');
    expect(errorSpy).toHaveBeenCalledTimes(1);
    expect(errorSpy.mock.calls[0][0]).toContain('Generic failure');
  });

  it('formats and outputs warn log', () => {
    service.warn('Address normalization alert', 'ValidationService');
    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][0]).toContain('Address normalization alert');
  });

  it('formats and outputs debug log', () => {
    service.debug('Kafka offset committed', 'KafkaConsumer');
    expect(debugSpy).toHaveBeenCalledTimes(1);
    expect(debugSpy.mock.calls[0][0]).toContain('Kafka offset committed');
  });

  it('formats and outputs verbose log', () => {
    service.verbose('Payload received', 'HttpHandler');
    expect(infoSpy).toHaveBeenCalledTimes(1);
    expect(infoSpy.mock.calls[0][0]).toContain('Payload received');
  });
});
