import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

import { ThemeProvider } from './context/ThemeContext';
import { AuthProvider } from './context/AuthContext';
import { CurrencyProvider } from './context/CurrencyContext';
import { NotificationProvider } from './context/NotificationContext';
import { CartProvider } from './context/CartContext';
import { WishlistProvider } from './context/WishlistContext';

const rootElement = document.getElementById('root');

if (!rootElement) {
  throw new Error('Failed to find root element with id "root"');
}

ReactDOM.createRoot(rootElement).render(
  <React.StrictMode>
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
  </React.StrictMode>
);
