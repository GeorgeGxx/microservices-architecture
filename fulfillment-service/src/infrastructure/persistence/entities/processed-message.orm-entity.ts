import { Entity, PrimaryColumn, Column, CreateDateColumn } from 'typeorm';

@Entity('processed_messages')
export class ProcessedMessageOrmEntity {
  @PrimaryColumn({ name: 'message_id', length: 128 })
  messageId: string;

  @Column({ length: 64 })
  consumer: string;

  @Column({ name: 'event_type', length: 64, nullable: true })
  eventType?: string;

  @CreateDateColumn({ name: 'processed_at' })
  processedAt: Date;
}
