package com.georgegxx.orders_service.model.entities;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class OrderItems {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String sku;
    private Double price;
    private Long quantity;

    @ManyToOne
    @JoinColumn(name = "order_id")
    private Order order;

    /**
     * Calculates the line item total amount (price * quantity) with null safety.
     *
     * @return the total price for this line item
     */
    public double getLineTotal() {
        double unitPrice = this.price != null ? this.price : 0.0;
        long qty = this.quantity != null ? this.quantity : 0L;
        return unitPrice * qty;
    }
}
