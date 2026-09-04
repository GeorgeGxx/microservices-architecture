import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { inject } from '@angular/core';
import { from, switchMap, catchError, throwError } from 'rxjs';
import { KeycloakService } from './keycloak.service';
import { environment } from '../../../environments/environment';

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const keycloakService = inject(KeycloakService);

  const isGatewayRequest = req.url.startsWith(environment.gatewayUrl) || req.url.startsWith('/api/');

  if (!isGatewayRequest || !keycloakService.isAuthenticated()) {
    return next(req);
  }

  return from(keycloakService.getToken()).pipe(
    switchMap(token => {
      const authReq = token
        ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
        : req;

      return next(authReq).pipe(
        catchError((err: HttpErrorResponse) => {
          if (err.status === 401) {
            console.warn('[AUTH] 401 Unauthorized received. Retrying public request without stale token if applicable...');
            if (req.method === 'GET' && (req.url.includes('/api/product') || req.url.includes('/api/inventory'))) {
              const unauthReq = req.clone({
                headers: req.headers.delete('Authorization')
              });
              return next(unauthReq);
            }
          }
          return throwError(() => err);
        })
      );
    })
  );
};
