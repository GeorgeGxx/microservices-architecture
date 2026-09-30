package com.georgegxx.orders_service.controllers;

import com.georgegxx.orders_service.repositories.OrderRepository;
import com.georgegxx.orders_service.services.OrderService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

@ExtendWith(MockitoExtension.class)
class OrderGraphQlControllerTest {
    @Mock
    private OrderService orderService;

    @Mock
    private OrderRepository orderRepository;

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @ParameterizedTest
    @ValueSource(strings = {"ROLE_USER", "ROLE_BASIC_USER"})
    void fulfillmentMutationsRejectNonAdminRoles(String role) {
        authenticateAs(role);
        OrderGraphQlController controller = new OrderGraphQlController(orderService, orderRepository);

        assertThrows(AccessDeniedException.class, () -> controller.shipOrder(42L));
        assertThrows(AccessDeniedException.class, () -> controller.deliverOrder(42L));
        verifyNoInteractions(orderService);
    }

    @Test
    void fulfillmentMutationsDelegateForAdminRole() {
        authenticateAs("ROLE_ADMIN");
        OrderGraphQlController controller = new OrderGraphQlController(orderService, orderRepository);

        controller.shipOrder(42L);
        controller.deliverOrder(42L);

        verify(orderService).shipOrder(42L);
        verify(orderService).deliverOrder(42L);
    }

    private void authenticateAs(String role) {
        Jwt jwt = Jwt.withTokenValue("test-token")
                .header("alg", "none")
                .subject("test-user")
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, List.of(new SimpleGrantedAuthority(role)))
        );
    }
}
