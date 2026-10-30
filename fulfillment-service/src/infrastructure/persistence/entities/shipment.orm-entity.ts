import { Entity, PrimaryColumn, Column, OneToMany, CreateDateColumn, UpdateDateColumn } from 'typeorm';
import { ShipmentStatus } from '../../../domain/value-objects/shipment-status.enum';
import { TrackingEventOrmEntity } from './tracking-event.orm-entity';

@Entity('shipments')
export class ShipmentOrmEntity {
  @PrimaryColumn('uuid')
  id: string;

  @Column({ name: 'order_number', type: 'varchar', length: 64, unique: true })
  orderNumber: string;

  @Column({
    type: 'enum',
    enum: ShipmentStatus,
    default: ShipmentStatus.AWAITING_PICKUP,
  })
  status: ShipmentStatus;

  @Column({ type: 'varchar', length: 50, default: 'DHL Express' })
  carrier: string;

  @Column({ name: 'tracking_number', type: 'varchar', length: 64, unique: true })
  trackingNumber: string;

  @Column({ name: 'recipient_name', type: 'varchar', length: 150 })
  recipientName: string;

  @Column({ type: 'varchar', length: 255 })
  street: string;

  @Column({ type: 'varchar', length: 100 })
  city: string;

  @Column({ name: 'postal_code', type: 'varchar', length: 20 })
  postalCode: string;

  @Column({ type: 'varchar', length: 50, nullable: true })
  phone: string;

  @Column({ type: 'jsonb', nullable: true })
  items: Array<{ sku: string; quantity: number }>;

  @Column({ name: 'dispatched_at', type: 'timestamptz', nullable: true })
  dispatchedAt: Date;

  @Column({ name: 'delivered_at', type: 'timestamptz', nullable: true })
  deliveredAt: Date;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt: Date;

  @OneToMany(() => TrackingEventOrmEntity, event => event.shipment, { cascade: true, eager: true })
  trackingEvents: TrackingEventOrmEntity[];
}
