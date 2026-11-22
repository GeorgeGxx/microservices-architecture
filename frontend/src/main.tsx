import React from 'react';
import ReactDOM from 'react-dom/client';
import * as Sentry from '@sentry/react';
import App from './App';
import './index.css';

import { ThemeProvider } from './context/ThemeContext';
import { AuthProvider } from './context/AuthContext';
import { CurrencyProvider } from './context/CurrencyContext';
import { NotificationProvider } from './context/NotificationContext';
import { CartProvider } from './context/CartContext';
import { WishlistProvider } from './context/WishlistContext';
import { ErrorBoundary } from './components/ErrorBoundary';

Sentry.init({
  dsn: window.__APP_CONFIG__?.VITE_GLITCHTIP_DSN || import.meta.env.VITE_GLITCHTIP_DSN || undefined,
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_APP_RELEASE || 'unknown',
  maxBreadcrumbs: 0,
  tracesSampleRate: 0,
  beforeSend(event) {
    event.request = undefined;
    event.user = undefined;
    event.contexts = undefined;
    event.extra = undefined;
    event.breadcrumbs = [];
    event.message = undefined;
    event.transaction = undefined;
    for (const exception of event.exception?.values ?? []) exception.value = '[redacted]';
    return event;
  },
});

const rootElement = document.getElementById('root');

if (!rootElement) {
  throw new Error('Failed to find root element with id "root"');
}

ReactDOM.createRoot(rootElement).render(
  <React.StrictMode>
    <ErrorBoundary>
      <ThemeProvider>
        <AuthProvider>
          <CurrencyProvider>
            <NotificationProvider>
              <CartProvider>
                <WishlistProvider>
                  <App />
                </WishlistProvider>
              </CartProvider>
            </NotificationProvider>
          </CurrencyProvider>
        </AuthProvider>
      </ThemeProvider>
    </ErrorBoundary>
  </React.StrictMode>
);
