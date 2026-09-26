package com.georgegxx.products_service.utils;

import com.georgegxx.products_service.model.entities.Product;
import com.georgegxx.products_service.repositories.ProductRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class DataLoader implements CommandLineRunner {
    private final ProductRepository productRepository;

    @Override
    @Transactional
    public void run(String... args) throws Exception {
        log.info("Checking product catalog seed data...");
        List<Product> existingProducts = productRepository.findAll();
        if (existingProducts.isEmpty()) {
            log.info("Loading initial product catalog in USD...");
            
            Product p1 = Product.builder()
                    .sku("LAPTOP-PRO")
                    .name("Laptop Pro 16")
                    .description("High-end developer laptop 16-inch 32GB RAM")
                    .price(1499.99)
                    .status(true)
                    .imageUrl("https://images.unsplash.com/photo-1517336714731-489689fd1ca8?auto=format&fit=crop&w=800&q=80")
                    .category("Computers")
                    .rating(4.9)
                    .reviewCount(2450)
                    .isBestSeller(true)
                    .build();

            Product p2 = Product.builder()
                    .sku("000001")
                    .name("Pro Mechanical Keyboard")
                    .description("Custom RGB Mechanical Keyboard with Blue Switches")
                    .price(69.99)
                    .status(true)
                    .imageUrl("https://images.unsplash.com/photo-1587829741301-dc798b83add3?auto=format&fit=crop&w=800&q=80")
                    .category("Peripherals")
                    .rating(4.7)
                    .reviewCount(890)
                    .isBestSeller(false)
                    .build();

            Product p3 = Product.builder()
                    .sku("000002")
                    .name("Pro Gaming Mouse")
                    .description("Ergonomic Wireless Gaming Mouse 16000 DPI")
                    .price(49.99)
                    .status(true)
                    .imageUrl("https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?auto=format&fit=crop&w=800&q=80")
                    .category("Peripherals")
                    .rating(4.8)
                    .reviewCount(1420)
                    .isBestSeller(true)
                    .build();

            Product p4 = Product.builder()
                    .sku("000003")
                    .name("27-inch UltraWide Monitor")
                    .description("27-inch Curved Gaming Monitor 144Hz IPS HDR")
                    .price(299.99)
                    .status(true)
                    .imageUrl("https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?auto=format&fit=crop&w=800&q=80")
                    .category("Displays")
                    .rating(4.6)
                    .reviewCount(640)
                    .isBestSeller(false)
                    .build();

            Product p5 = Product.builder()
                    .sku("000004")
                    .name("Studio Wireless Headphones HD")
                    .description("Active Noise Cancelling Wireless Headphones BT 5.3")
                    .price(119.99)
                    .status(true)
                    .imageUrl("https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=800&q=80")
                    .category("Audio")
                    .rating(4.8)
                    .reviewCount(1180)
                    .isBestSeller(false)
                    .build();

            try {
                productRepository.saveAll(List.of(p1, p2, p3, p4, p5));
                log.info("Product catalog seed data loaded successfully in USD.");
            } catch (Exception ex) {
                log.warn("Product catalog seed data already exists or concurrent insertion skipped: {}", ex.getMessage());
            }
        } else {
            // Ensure existing items have defaults if null
            for (Product p : existingProducts) {
                boolean changed = false;
                if (p.getRating() == null) {
                    p.setRating(4.8);
                    p.setReviewCount(420);
                    changed = true;
                }
                if (p.getCategory() == null) {
                    p.setCategory("Electronics");
                    changed = true;
                }
                if (p.getIsBestSeller() == null) {
                    p.setIsBestSeller(false);
                    changed = true;
                }
                if (changed) {
                    productRepository.save(p);
                }
            }
        }
    }
}
