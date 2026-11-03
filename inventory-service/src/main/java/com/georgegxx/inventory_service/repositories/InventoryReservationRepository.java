package com.georgegxx.inventory_service.repositories;

import com.georgegxx.inventory_service.model.entities.InventoryReservation;
import com.georgegxx.inventory_service.model.enums.InventoryReservationStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

public interface InventoryReservationRepository extends JpaRepository<InventoryReservation, String> {

    @Modifying
    @Query(value = """
            INSERT INTO inventory_reservations
                (order_number, items_payload, status, expires_at, created_at, updated_at)
            VALUES
                (:orderNumber, :itemsPayload, 'PENDING', :expiresAt, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (order_number) DO NOTHING
            """, nativeQuery = true)
    int insertPendingIfAbsent(
            @Param("orderNumber") String orderNumber,
            @Param("itemsPayload") String itemsPayload,
            @Param("expiresAt") Instant expiresAt
    );

    @Modifying
    @Query(value = """
            INSERT INTO inventory_reservations
                (order_number, status, created_at, updated_at)
            VALUES
                (:orderNumber, 'RELEASED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (order_number) DO NOTHING
            """, nativeQuery = true)
    int insertReleasedIfAbsent(@Param("orderNumber") String orderNumber);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT reservation FROM InventoryReservation reservation WHERE reservation.orderNumber = :orderNumber")
    Optional<InventoryReservation> findByIdForUpdate(@Param("orderNumber") String orderNumber);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT reservation FROM InventoryReservation reservation
            WHERE reservation.status = :status AND reservation.expiresAt <= :now
            ORDER BY reservation.expiresAt
            """)
    List<InventoryReservation> findExpiredForUpdate(
            @Param("status") InventoryReservationStatus status,
            @Param("now") Instant now,
            Pageable pageable
    );
}
