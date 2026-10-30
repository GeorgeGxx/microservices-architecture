package com.georgegxx.orders_service.utils;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class SecurityUtilsTest {

    @Test
    @DisplayName("isUserAdmin returns true when realm_access contains ADMIN role")
    void testIsUserAdmin_WithAdminRole() {
        Jwt jwt = mock(Jwt.class);
        when(jwt.getClaims()).thenReturn(Map.of("realm_access", Map.of("roles", List.of("USER", "ADMIN"))));

        assertTrue(SecurityUtils.isUserAdmin(jwt));
    }

    @Test
    @DisplayName("isUserAdmin returns false when realm_access does not contain ADMIN role or jwt is null")
    void testIsUserAdmin_WithoutAdminRole() {
        assertFalse(SecurityUtils.isUserAdmin(null));

        Jwt jwt = mock(Jwt.class);
        when(jwt.getClaims()).thenReturn(Map.of("realm_access", Map.of("roles", List.of("USER"))));
        assertFalse(SecurityUtils.isUserAdmin(jwt));
    }

    @Test
    @DisplayName("isAdmin with Authentication returns true when ROLE_ADMIN authority present")
    void testIsAdmin_WithAuthority() {
        Authentication auth = new UsernamePasswordAuthenticationToken(
                "user", "pass", List.of(new SimpleGrantedAuthority("ROLE_ADMIN"))
        );
        assertTrue(SecurityUtils.isAdmin(auth));
    }

    @Test
    @DisplayName("isUser with Authentication returns true when ROLE_USER authority present")
    void testIsUser_WithUserAuthority() {
        Authentication auth = new UsernamePasswordAuthenticationToken(
                "user", "pass", List.of(new SimpleGrantedAuthority("ROLE_USER"))
        );
        assertTrue(SecurityUtils.isUser(auth));
    }

    @Test
    @DisplayName("getUserId and getUsername extract claims properly with fallbacks")
    void testGetUserIdAndUsername() {
        assertEquals("", SecurityUtils.getUserId(null));
        assertEquals("", SecurityUtils.getUsername(null));

        Jwt jwt = mock(Jwt.class);
        when(jwt.getSubject()).thenReturn("usr-12345");
        when(jwt.getClaimAsString("preferred_username")).thenReturn("george");

        assertEquals("usr-12345", SecurityUtils.getUserId(jwt));
        assertEquals("george", SecurityUtils.getUsername(jwt));

        // Fallback to userId when preferred_username is blank
        when(jwt.getClaimAsString("preferred_username")).thenReturn(" ");
        assertEquals("usr-12345", SecurityUtils.getUsername(jwt));
    }

    @Test
    @DisplayName("null and unauthenticated authentication branches")
    void testAuthenticationNullAndUnauthenticated() {
        assertFalse(SecurityUtils.isAdmin(null));
        assertFalse(SecurityUtils.isUser(null));

        Authentication unauth = mock(Authentication.class);
        when(unauth.isAuthenticated()).thenReturn(false);
        assertFalse(SecurityUtils.isAdmin(unauth));
        assertFalse(SecurityUtils.isUser(unauth));
    }

    @Test
    @DisplayName("isAdmin and isUser with Jwt principal without authorities")
    void testIsAdminWithJwtPrincipal() {
        Jwt jwt = mock(Jwt.class);
        when(jwt.getClaims()).thenReturn(Map.of("realm_access", Map.of("roles", List.of("ADMIN"))));
        Authentication auth = new UsernamePasswordAuthenticationToken(jwt, "pass", List.of());
        assertTrue(SecurityUtils.isAdmin(auth));
        assertTrue(SecurityUtils.isUser(auth));
    }

    @Test
    @DisplayName("isUserAdmin with non-map realm_access or non-list roles")
    void testIsUserAdminMalformedClaims() {
        Jwt jwt1 = mock(Jwt.class);
        when(jwt1.getClaims()).thenReturn(Map.of("realm_access", "invalid_type"));
        assertFalse(SecurityUtils.isUserAdmin(jwt1));

        Jwt jwt2 = mock(Jwt.class);
        when(jwt2.getClaims()).thenReturn(Map.of("realm_access", Map.of("roles", "invalid_list")));
        assertFalse(SecurityUtils.isUserAdmin(jwt2));
    }
}
