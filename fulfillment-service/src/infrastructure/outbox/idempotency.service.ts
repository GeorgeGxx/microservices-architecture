import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ProcessedMessageOrmEntity } from '../persistence/entities/processed-message.orm-entity';

@Injectable()
export class IdempotencyService {
  private readonly logger = new Logger(IdempotencyService.name);

  constructor(
    @InjectRepository(ProcessedMessageOrmEntity)
    private readonly processedRepo: Repository<ProcessedMessageOrmEntity>,
  ) {}

  /**
   * Checks whether the message was already processed by the consumer.
   */
  async isProcessed(messageId: string): Promise<boolean> {
    if (!messageId) return false;
    try {
      const found = await this.processedRepo.findOne({ where: { messageId } });
      return Boolean(found);
    } catch (err: unknown) {
      this.logger.warn(`Could not verify idempotency for message ${messageId}: ${String(err)}`);
      return false;
    }
  }

  /**
   * Marks a message as processed. Idempotent on duplicate key insertion.
   */
  async markProcessed(messageId: string, consumer: string, eventType?: string): Promise<void> {
    if (!messageId) return;
    try {
      await this.processedRepo
        .createQueryBuilder()
        .insert()
        .into(ProcessedMessageOrmEntity)
        .values({
          messageId,
          consumer,
          eventType,
        })
        .orIgnore()
        .execute();
    } catch (err: unknown) {
      this.logger.warn(`Error persisting processed message #${messageId}: ${String(err)}`);
    }
  }
}
