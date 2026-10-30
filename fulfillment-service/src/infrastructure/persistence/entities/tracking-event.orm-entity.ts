import { Entity, PrimaryColumn, Column, ManyToOne, JoinColumn, CreateDateColumn } from 'typeorm';
import { ShipmentOrmEntity } from './shipment.orm-entity';
import { ShipmentStatus } from '../../../domain/value-objects/shipment-status.enum';

@Entity('tracking_events')
export class TrackingEventOrmEntity {
  @PrimaryColumn('uuid')
  id: string;

  @Column({ name: 'shipment_id', type: 'uuid' })
  shipmentId: string;

  @Column({
    type: 'enum',
    enum: ShipmentStatus,
    default: ShipmentStatus.AWAITING_PICKUP,
  })
  status: ShipmentStatus;

  @Column({ type: 'varchar', length: 150 })
  location: string;

  @Column({ type: 'text' })
  description: string;

  @CreateDateColumn({ name: 'timestamp', type: 'timestamptz' })
  timestamp: Date;

  @ManyToOne(() => ShipmentOrmEntity, shipment => shipment.trackingEvents, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'shipment_id' })
  shipment: ShipmentOrmEntity;
}
