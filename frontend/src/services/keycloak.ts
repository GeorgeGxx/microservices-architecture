import Keycloak from 'keycloak-js';
import { UserProfile } from '../types';

const keycloakConfig = {
  url: window.location.hostname === 'localhost' ? 'http://localhost:8181' : `${window.location.origin}/auth`,
  realm: 'microservices-realm',
  clientId: 'microservices_frontend',
};

export const keycloak = new Keycloak(keycloakConfig);

let isInitialized = false;

export async function initKeycloak(): Promise<boolean> {
  if (isInitialized) return keycloak.authenticated || false;

  try {
    const authenticated = await keycloak.init({
      onLoad: 'check-sso',
      silentCheckSsoRedirectUri: `${window.location.origin}/silent-check-sso.html`,
      pkceMethod: 'S256',
      checkLoginIframe: false,
    });
    isInitialized = true;
    return authenticated;
  } catch (err) {
    console.warn('Keycloak SSO initialization bypassed or offline:', err);
    isInitialized = true;
    return false;
  }
}

export function getUserProfile(): UserProfile | null {
  if (!keycloak.authenticated || !keycloak.tokenParsed) {
    return null;
  }

  const parsed = keycloak.tokenParsed as Record<string, unknown>;
  const realmAccess = (parsed['realm_access'] as { roles?: string[] }) || {};
  const roles = realmAccess.roles || [];

  return {
    username: (parsed['preferred_username'] as string) || 'User',
    email: (parsed['email'] as string) || '',
    firstName: (parsed['given_name'] as string) || '',
    lastName: (parsed['family_name'] as string) || '',
    roles,
    isAdmin: roles.includes('ADMIN') || roles.includes('admin'),
    token: keycloak.token,
  };
}

export async function login(): Promise<void> {
  try {
    await keycloak.login({
      redirectUri: window.location.href,
    });
  } catch (e) {
    console.error('Login redirect failed:', e);
  }
}

export async function logout(): Promise<void> {
  try {
    await keycloak.logout({
      redirectUri: window.location.origin,
    });
  } catch (e) {
    console.error('Logout failed:', e);
  }
}
