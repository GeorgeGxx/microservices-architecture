import Keycloak from 'keycloak-js';
import { UserProfile } from '../types';

const localFrontendHosts = new Set(['localhost', '127.0.0.1']);
const isLocalFrontend = localFrontendHosts.has(window.location.hostname);

const keycloakConfig = {
  // Local Compose/Minikube uses the dedicated forwarded Keycloak port. Behind
  // the shared Istio host, /realms, /resources, /admin, and /js are routed to
  // Keycloak at the origin root; there is no /auth context path.
  url: isLocalFrontend
    ? `${window.location.protocol}//${window.location.hostname}:8181`
    : window.location.origin,
  realm: 'microservices-realm',
  clientId: 'microservices_frontend',
};

export const keycloak = new Keycloak(keycloakConfig);

let isInitialized = false;
let tokenRefreshInProgress: Promise<boolean> | null = null;

export async function getValidAccessToken(fallbackToken?: string): Promise<string | undefined> {
  if (!keycloak.authenticated) return fallbackToken;

  if (!tokenRefreshInProgress) {
    tokenRefreshInProgress = keycloak.updateToken(30).finally(() => {
      tokenRefreshInProgress = null;
    });
  }

  await tokenRefreshInProgress;
  return keycloak.token || fallbackToken;
}

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
