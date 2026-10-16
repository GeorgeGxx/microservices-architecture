import { describe, expect, it, vi, beforeEach } from 'vitest';
import { keycloak, getUserProfile, getValidAccessToken, initKeycloak, login, logout } from './keycloak';

describe('Keycloak Authentication Service', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    (globalThis as any).window = {
      setTimeout: globalThis.setTimeout,
      clearTimeout: globalThis.clearTimeout,
      location: {
        href: 'http://localhost:5173',
        origin: 'http://localhost:5173',
        hostname: 'localhost',
        protocol: 'http:',
      },
    };
  });

  describe('getUserProfile', () => {
    it('returns null when user is not authenticated', () => {
      (keycloak as any).authenticated = false;
      (keycloak as any).tokenParsed = undefined;
      expect(getUserProfile()).toBeNull();
    });

    it('returns formatted UserProfile when authenticated with roles', () => {
      (keycloak as any).authenticated = true;
      (keycloak as any).token = 'mock-jwt-token';
      (keycloak as any).tokenParsed = {
        sub: 'user-sub-123',
        preferred_username: 'johndoe',
        email: 'john@example.com',
        given_name: 'John',
        family_name: 'Doe',
        realm_access: {
          roles: ['USER', 'ADMIN'],
        },
      };

      const profile = getUserProfile();
      expect(profile).toEqual({
        userId: 'user-sub-123',
        username: 'johndoe',
        email: 'john@example.com',
        firstName: 'John',
        lastName: 'Doe',
        roles: ['USER', 'ADMIN'],
        isAdmin: true,
        token: 'mock-jwt-token',
      });
    });

    it('defaults user fields when claims are missing', () => {
      (keycloak as any).authenticated = true;
      (keycloak as any).token = undefined;
      (keycloak as any).tokenParsed = {};

      const profile = getUserProfile();
      expect(profile).toEqual({
        userId: undefined,
        username: 'User',
        email: '',
        firstName: '',
        lastName: '',
        roles: [],
        isAdmin: false,
        token: undefined,
      });
    });
  });

  describe('getValidAccessToken', () => {
    it('returns undefined if not authenticated', async () => {
      (keycloak as any).authenticated = false;
      const token = await getValidAccessToken('fallback');
      expect(token).toBeUndefined();
    });

    it('returns keycloak.token when authenticated and refreshed', async () => {
      (keycloak as any).authenticated = true;
      (keycloak as any).token = 'active-jwt-token';
      (keycloak as any).updateToken = vi.fn().mockResolvedValue(true);

      const token = await getValidAccessToken();
      expect(token).toBe('active-jwt-token');
      expect((keycloak as any).updateToken).toHaveBeenCalledWith(30);
    });

    it('falls back to fallbackToken if keycloak.token is empty', async () => {
      (keycloak as any).authenticated = true;
      (keycloak as any).token = '';
      (keycloak as any).updateToken = vi.fn().mockResolvedValue(true);

      const token = await getValidAccessToken('fallback-token');
      expect(token).toBe('fallback-token');
    });
  });

  describe('initKeycloak', () => {
    it('initializes keycloak SSO', async () => {
      (keycloak as any).init = vi.fn().mockResolvedValue(true);
      (keycloak as any).authenticated = true;

      const auth = await initKeycloak();
      expect(typeof auth).toBe('boolean');
    });
  });

  describe('login and logout redirects', () => {
    it('calls keycloak.login', async () => {
      (keycloak as any).login = vi.fn().mockResolvedValue(undefined);
      await login();
      expect((keycloak as any).login).toHaveBeenCalled();
    });

    it('calls keycloak.logout', async () => {
      (keycloak as any).logout = vi.fn().mockResolvedValue(undefined);
      await logout();
      expect((keycloak as any).logout).toHaveBeenCalled();
    });

    it('handles keycloak.login error gracefully', async () => {
      const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      (keycloak as any).login = vi.fn().mockRejectedValue(new Error('Redirect blocked'));
      await expect(login()).resolves.not.toThrow();
      expect(consoleErrorSpy).toHaveBeenCalled();
    });

    it('handles keycloak.logout error gracefully', async () => {
      const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      (keycloak as any).logout = vi.fn().mockRejectedValue(new Error('Logout failed'));
      await expect(logout()).resolves.not.toThrow();
      expect(consoleErrorSpy).toHaveBeenCalled();
    });
  });
});
