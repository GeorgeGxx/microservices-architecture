import { Injectable, signal } from '@angular/core';
import Keycloak from 'keycloak-js';
import { environment } from '../../../environments/environment';
import { UserProfile } from '../models/user.model';

@Injectable({
  providedIn: 'root'
})
export class KeycloakService {
  private keycloakInstance?: Keycloak;

  readonly isAuthenticated = signal<boolean>(false);
  readonly userProfile = signal<UserProfile | null>(null);
  readonly isInitialized = signal<boolean>(false);

  async init(): Promise<boolean> {
    try {
      this.keycloakInstance = new Keycloak({
        url: environment.keycloak.url,
        realm: environment.keycloak.realm,
        clientId: environment.keycloak.clientId
      });

      const initPromise = this.keycloakInstance.init({
        onLoad: 'check-sso',
        silentCheckSsoRedirectUri: window.location.origin + '/silent-check-sso.html',
        pkceMethod: 'S256',
        checkLoginIframe: false
      });

      // 3.5-second guard timeout to avoid freezing startup if Keycloak is unreachable
      const timeoutPromise = new Promise<boolean>((resolve) => {
        setTimeout(() => {
          console.warn('Keycloak init timeout: Continuing application initialization in guest mode...');
          resolve(false);
        }, 3500);
      });

      const authenticated = await Promise.race([initPromise, timeoutPromise]);

      this.isAuthenticated.set(authenticated);
      if (authenticated) {
        await this.loadUserProfile();
      }

      this.isInitialized.set(true);
      return authenticated;
    } catch (error) {
      console.warn('Keycloak unavailable or initialization error:', error);
      this.isAuthenticated.set(false);
      this.isInitialized.set(true);
      return false;
    }
  }

  async login(): Promise<void> {
    if (this.keycloakInstance) {
      await this.keycloakInstance.login({
        redirectUri: window.location.origin
      });
    }
  }

  async logout(): Promise<void> {
    if (this.keycloakInstance) {
      await this.keycloakInstance.logout({
        redirectUri: window.location.origin
      });
      this.isAuthenticated.set(false);
      this.userProfile.set(null);
    }
  }

  private refreshPromise?: Promise<boolean>;

  async getToken(): Promise<string | undefined> {
    if (!this.keycloakInstance) return undefined;
    try {
      // If the token is still valid for more than 20s, return immediately without network overhead
      if (this.keycloakInstance.token && !this.keycloakInstance.isTokenExpired(20)) {
        return this.keycloakInstance.token;
      }

      // Mutex lock to prevent concurrent requests from colliding during token refresh
      this.refreshPromise ??= this.keycloakInstance.updateToken(30)
        .then(refreshed => {
          this.refreshPromise = undefined;
          return refreshed;
        })
        .catch(err => {
          this.refreshPromise = undefined;
          console.warn('Notice while refreshing token:', err);
          return false;
        });

      await this.refreshPromise;
      return this.keycloakInstance.token;
    } catch (error) {
      console.warn('Error in getToken:', error);
      return this.keycloakInstance.token;
    }
  }

  getRoles(): string[] {
    if (!this.keycloakInstance?.tokenParsed) return [];
    const realmAccess = (this.keycloakInstance.tokenParsed as Record<string, unknown>)['realm_access'] as { roles?: string[] } | undefined;
    return realmAccess?.roles || [];
  }

  hasRole(role: string): boolean {
    const roles = this.getRoles();
    return roles.includes(role) || roles.includes(`ROLE_${role}`);
  }

  isAdmin(): boolean {
    return this.hasRole('ADMIN');
  }

  private async loadUserProfile(): Promise<void> {
    if (!this.keycloakInstance) return;
    try {
      const profile = await this.keycloakInstance.loadUserProfile();
      const roles = this.getRoles();
      this.userProfile.set({
        id: profile.id,
        username: profile.username || 'User',
        email: profile.email,
        firstName: profile.firstName,
        lastName: profile.lastName,
        roles
      });
    } catch (error) {
      console.error('Error loading user profile:', error);
    }
  }
}
