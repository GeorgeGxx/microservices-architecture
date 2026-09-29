import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Navbar } from './components/Navbar';
import { ToastContainer } from './components/ToastContainer';
import { CartDrawer } from './components/CartDrawer';
import { NotificationDrawer } from './components/NotificationDrawer';
import { QuickViewModal } from './components/QuickViewModal';
import { ProductQRModal } from './components/ProductQRModal';
import { CheckoutModal } from './components/CheckoutModal';
import { ReceiptModal } from './components/ReceiptModal';
import { CommandPalette } from './components/CommandPalette';
import { QrScannerModal } from './components/QrScannerModal';

import { CatalogPage } from './pages/CatalogPage';
import { OrdersPage } from './pages/OrdersPage';
import { AdminDashboardPage } from './pages/AdminDashboardPage';

import { Product, Order } from './types';
import { fetchProducts } from './services/graphql';
import { useAuth } from './context/AuthContext';

export const App: React.FC = () => {
  const { user } = useAuth();

  // Navigation
  const [activeTab, setActiveTab] = useState<'catalog' | 'orders' | 'admin'>('catalog');

  // Unified Search & Wishlist filter state
  const [searchQuery, setSearchQuery] = useState('');
  const [favoritesOnly, setFavoritesOnly] = useState(false);

  // Products state for Catalog & Command Palette
  const [products, setProducts] = useState<Product[]>([]);
  const [isLoadingProducts, setIsLoadingProducts] = useState(true);
  const productRefreshInProgress = useRef(false);

  // Modals state
  const [quickViewProduct, setQuickViewProduct] = useState<Product | null>(null);
  const [qrProduct, setQrProduct] = useState<Product | null>(null);
  const [isCheckoutOpen, setIsCheckoutOpen] = useState(false);
  const [receiptOrder, setReceiptOrder] = useState<Order | null>(null);
  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [isQrScannerOpen, setIsQrScannerOpen] = useState(false);
  const currentQuickViewProduct = quickViewProduct
    ? products.find((product) => product.sku === quickViewProduct.sku) ?? quickViewProduct
    : null;

  // Load products from Cosmo Router Federation
  const loadProducts = useCallback(async (showLoading = false) => {
    if (productRefreshInProgress.current) return;
    productRefreshInProgress.current = true;
    if (showLoading) setIsLoadingProducts(true);

    try {
      const data = await fetchProducts(user?.token);
      setProducts(data);
    } catch {
      // Keep the last known catalog when a background refresh fails.
    } finally {
      if (showLoading) setIsLoadingProducts(false);
      productRefreshInProgress.current = false;
    }
  }, [user?.token]);

  useEffect(() => {
    void loadProducts(true);

    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') void loadProducts();
    };
    const intervalId = window.setInterval(refreshWhenVisible, 30_000);
    document.addEventListener('visibilitychange', refreshWhenVisible);

    return () => {
      window.clearInterval(intervalId);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
    };
  }, [loadProducts]);

  useEffect(() => {
    if (activeTab === 'catalog') void loadProducts();
  }, [activeTab, loadProducts]);

  // Global Ctrl+K / Cmd+K listener
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        setIsCommandPaletteOpen((prev) => !prev);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  const handleOrderPlaced = (order: Order) => {
    setIsCheckoutOpen(false);
    setReceiptOrder(order);
  };

  return (
    <div className="min-h-screen flex flex-col bg-slate-50 dark:bg-slate-950 text-slate-900 dark:text-slate-100 transition-colors">
      {/* Toast Notifications Overlay */}
      <ToastContainer />

      {/* Global Navbar */}
      <Navbar
        activeTab={activeTab}
        setActiveTab={(tab: 'catalog' | 'orders' | 'admin') => {
          setActiveTab(tab);
          window.scrollTo({ top: 0, behavior: 'smooth' });
        }}
        searchQuery={searchQuery}
        setSearchQuery={setSearchQuery}
        onOpenCommandPalette={() => setIsCommandPaletteOpen(true)}
        onOpenQrScanner={user?.isAdmin ? () => setIsQrScannerOpen(true) : undefined}
        onToggleFavoritesFilter={() => setFavoritesOnly((prev) => !prev)}
        isFavoritesFilterActive={favoritesOnly}
      />

      {/* Main Content Area */}
      <main className="flex-1">
        {activeTab === 'catalog' && (
          <CatalogPage
            products={products}
            isLoading={isLoadingProducts}
            searchQuery={searchQuery}
            onClearSearch={() => setSearchQuery('')}
            favoritesOnly={favoritesOnly}
            onToggleFavorites={() => setFavoritesOnly((prev) => !prev)}
            onOpenQuickView={(p) => setQuickViewProduct(p)}
            onOpenQR={(p) => setQrProduct(p)}
          />
        )}

        {activeTab === 'orders' && (
          <OrdersPage
            onOpenReceipt={(o) => setReceiptOrder(o)}
            onNavigateToCatalog={() => setActiveTab('catalog')}
          />
        )}

        {activeTab === 'admin' && <AdminDashboardPage />}
      </main>

      {/* Sliding Drawers */}
      {user && <CartDrawer onOpenCheckout={() => setIsCheckoutOpen(true)} />}
      <NotificationDrawer />

      {/* Modals */}
      <QuickViewModal
        product={currentQuickViewProduct}
        onClose={() => setQuickViewProduct(null)}
        onOpenQR={(p) => setQrProduct(p)}
      />

      <ProductQRModal
        product={qrProduct}
        onClose={() => setQrProduct(null)}
      />

      <CheckoutModal
        isOpen={isCheckoutOpen && !!user}
        onClose={() => setIsCheckoutOpen(false)}
        onOrderSuccess={handleOrderPlaced}
      />

      <ReceiptModal
        order={receiptOrder}
        onClose={() => setReceiptOrder(null)}
      />

      <CommandPalette
        isOpen={isCommandPaletteOpen}
        onClose={() => setIsCommandPaletteOpen(false)}
        products={products}
        onSelectProduct={(p) => setQuickViewProduct(p)}
        onNavigate={(tab) => setActiveTab(tab)}
        onOpenQrScanner={user?.isAdmin ? () => setIsQrScannerOpen(true) : undefined}
      />

      {user?.isAdmin && (
        <QrScannerModal
          isOpen={isQrScannerOpen}
          onClose={() => setIsQrScannerOpen(false)}
          products={products}
          onNavigateToOrders={() => setActiveTab('orders')}
        />
      )}
    </div>
  );
};
export default App;
