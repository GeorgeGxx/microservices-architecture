package com.georgegxx.orders_service.utils;

import com.georgegxx.orders_service.constants.OrderConstants;
import lombok.AccessLevel;
import lombok.NoArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.Collection;
import java.util.List;
import java.util.Map;

/**
 * Secure coding utility for Keycloak JWT claims extraction, authority verification,
 * and user identity isolation.
 */
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class SecurityUtils {

    private static final String ROLE_PREFIX = "ROLE_";
    private static final String ROLE_ADMIN_AUTHORITY = ROLE_PREFIX + OrderConstants.ROLE_ADMIN;
    private static final String ROLE_USER_AUTHORITY = ROLE_PREFIX + OrderConstants.ROLE_USER;

    /**
     * Verifies if the authenticated caller holds the ADMIN role from Spring authorities or JWT claims.
     *
     * @param jwt Keycloak JWT token
     * @return true if caller is admin, false otherwise
     */
    public static boolean isUserAdmin(Jwt jwt) {
        if (jwt == null) {
            return false;
        }
        Object realmAccess = jwt.getClaims().get(OrderConstants.CLAIM_REALM_ACCESS);
        if (realmAccess instanceof Map<?, ?> accessMap) {
            Object roles = accessMap.get(OrderConstants.CLAIM_ROLES);
            if (roles instanceof List<?> roleList) {
                return roleList.contains(OrderConstants.ROLE_ADMIN);
            }
        }
        return false;
    }

    /**
     * Checks if the Spring Authentication holds the ADMIN authority.
     *
     * @param auth current SecurityContext authentication
     * @return true if admin, false otherwise
     */
    public static boolean isAdmin(Authentication auth) {
        if (auth == null || !auth.isAuthenticated()) {
            return false;
        }
        Collection<? extends GrantedAuthority> authorities = auth.getAuthorities();
        if (authorities.stream().anyMatch(a -> ROLE_ADMIN_AUTHORITY.equals(a.getAuthority()))) {
            return true;
        }
        if (auth.getPrincipal() instanceof Jwt jwt) {
            return isUserAdmin(jwt);
        }
        return false;
    }

    /**
     * Checks if the Spring Authentication holds a valid USER or ADMIN role.
     *
     * @param auth current SecurityContext authentication
     * @return true if valid user or admin
     */
    public static boolean isUser(Authentication auth) {
        if (auth == null || !auth.isAuthenticated()) {
            return false;
        }
        if (isAdmin(auth)) {
            return true;
        }
        Collection<? extends GrantedAuthority> authorities = auth.getAuthorities();
        return authorities.stream()
                .anyMatch(a -> ROLE_USER_AUTHORITY.equals(a.getAuthority()));
    }

    /**
     * Extracts the Subject User ID from the JWT token with safe fallback.
     *
     * @param jwt Keycloak JWT token
     * @return user ID string or empty string if null
     */
    public static String getUserId(Jwt jwt) {
        return jwt != null && jwt.getSubject() != null ? jwt.getSubject() : "";
    }

    /**
     * Extracts the Preferred Username from JWT claims.
     *
     * @param jwt Keycloak JWT token
     * @return preferred username or user subject fallback
     */
    public static String getUsername(Jwt jwt) {
        if (jwt == null) {
            return "";
        }
        String preferred = jwt.getClaimAsString(OrderConstants.CLAIM_PREFERRED_USERNAME);
        return (preferred != null && !preferred.isBlank()) ? preferred : getUserId(jwt);
    }
}
