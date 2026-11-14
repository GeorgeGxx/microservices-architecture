import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, Index } from 'typeorm';

export type OutboxStatus = 'PENDING' | 'PROCESSING' | 'PUBLISHED' | 'FAILED';

@Entity('outbox_events')
export class OutboxEventOrmEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'aggregate_type', length: 64 })
  aggregateType: string;

  @Column({ name: 'aggregate_id', length: 128 })
  aggregateId: string;

  @Column({ name: 'event_type', length: 64 })
  eventType: string;

  @Column('text')
  payload: string;

  @Index()
  @Column({ length: 20, default: 'PENDING' })
  status: OutboxStatus;

  @Column({ name: 'retry_count', default: 0 })
  retryCount: number;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @Column({ name: 'locked_at', type: 'timestamp', nullable: true })
  lockedAt?: Date;

  @Column({ name: 'processed_at', type: 'timestamp', nullable: true })
  processedAt?: Date;
}
