package com.georgegxx.orders_service.repositories;

import com.georgegxx.orders_service.model.entities.Order;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import org.springframework.data.repository.query.Param;

import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {

    @EntityGraph(attributePaths = {"orderItems"})
    @Query("SELECT o FROM Order o")
    List<Order> findAllWithItems();

    @EntityGraph(attributePaths = {"orderItems"})
    @Query("SELECT o FROM Order o WHERE o.userId = :userId ORDER BY o.id DESC")
    List<Order> findAllByUserIdWithItems(@Param("userId") String userId);
}
