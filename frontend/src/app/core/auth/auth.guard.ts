import { inject } from '@angular/core';
import { CanActivateFn } from '@angular/router';
import { KeycloakService } from './keycloak.service';

export const authGuard: CanActivateFn = async (route, state) => {
  const keycloakService = inject(KeycloakService);

  if (keycloakService.isAuthenticated()) {
    return true;
  }

  await keycloakService.login();
  return false;
};
