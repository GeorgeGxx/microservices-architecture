import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { KeycloakService } from './keycloak.service';

export const roleGuard = (requiredRole: string): CanActivateFn => {
  return async (route, state) => {
    const keycloakService = inject(KeycloakService);
    const router = inject(Router);

    if (!keycloakService.isAuthenticated()) {
      await keycloakService.login();
      return false;
    }

    if (keycloakService.hasRole(requiredRole)) {
      return true;
    }

    // Redirect to home if the user lacks the required role
    router.navigate(['/']);
    return false;
  };
};
