import { jest } from '@jest/globals';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { IdempotencyService } from './idempotency.service';
import { ProcessedMessageOrmEntity } from '../persistence/entities/processed-message.orm-entity';

describe('IdempotencyService', () => {
  let service: IdempotencyService;
  let mockRepo: any;

  beforeEach(async () => {
    mockRepo = {
      findOne: jest.fn(),
      createQueryBuilder: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        IdempotencyService,
        {
          provide: getRepositoryToken(ProcessedMessageOrmEntity),
          useValue: mockRepo,
        },
      ],
    }).compile();

    service = module.get<IdempotencyService>(IdempotencyService);
  });

  describe('isProcessed', () => {
    it('should return false if messageId is empty', async () => {
      expect(await service.isProcessed('')).toBe(false);
      expect(mockRepo.findOne).not.toHaveBeenCalled();
    });

    it('should return true if message was found in repository', async () => {
      mockRepo.findOne.mockResolvedValue({ messageId: 'msg-1' });
      expect(await service.isProcessed('msg-1')).toBe(true);
      expect(mockRepo.findOne).toHaveBeenCalledWith({ where: { messageId: 'msg-1' } });
    });

    it('should return false if message was not found in repository', async () => {
      mockRepo.findOne.mockResolvedValue(null);
      expect(await service.isProcessed('msg-new')).toBe(false);
    });

    it('should return false and catch error gracefully if repository throws', async () => {
      mockRepo.findOne.mockRejectedValue(new Error('DB failure'));
      expect(await service.isProcessed('msg-err')).toBe(false);
    });
  });

  describe('markProcessed', () => {
    it('should ignore if messageId is empty', async () => {
      await service.markProcessed('', 'test-consumer');
      expect(mockRepo.createQueryBuilder).not.toHaveBeenCalled();
    });

    it('should execute insert with orIgnore', async () => {
      const mockQb = {
        insert: jest.fn().mockReturnThis(),
        into: jest.fn().mockReturnThis(),
        values: jest.fn().mockReturnThis(),
        orIgnore: jest.fn().mockReturnThis(),
        execute: jest.fn().mockResolvedValue({}),
      };
      mockRepo.createQueryBuilder.mockReturnValue(mockQb);

      await service.markProcessed('msg-100', 'fulfillment-consumer', 'ORDER_PLACED');

      expect(mockRepo.createQueryBuilder).toHaveBeenCalled();
      expect(mockQb.values).toHaveBeenCalledWith({
        messageId: 'msg-100',
        consumer: 'fulfillment-consumer',
        eventType: 'ORDER_PLACED',
      });
      expect(mockQb.orIgnore).toHaveBeenCalled();
      expect(mockQb.execute).toHaveBeenCalled();
    });

    it('should catch error gracefully if insert throws', async () => {
      mockRepo.createQueryBuilder.mockImplementation(() => {
        throw new Error('Connection refused');
      });

      await expect(service.markProcessed('msg-err', 'consumer')).resolves.toBeUndefined();
    });
  });
});
