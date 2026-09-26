import React, { useState, useEffect } from 'react';
import { Navbar } from './components/Navbar';
import { Footer } from './components/Footer';
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

const DEFAULT_MOCK_PRODUCTS: Product[] = [
  {
    id: '1',
    sku: 'LAPTOP-PRO',
    name: 'Laptop Pro 16',
    description: 'High-end developer laptop 16-inch 32GB RAM and 1TB SSD.',
    price: 1499.99,
    category: 'Computers',
    imageUrl: 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?auto=format&fit=crop&w=800&q=80',
    rating: 4.9,
    reviewCount: 2450,
    isBestSeller: true,
    isInStock: true,
    quantity: 9,
  },
  {
    id: '2',
    sku: '000001',
    name: 'Pro Mechanical Keyboard',
    description: 'Custom RGB Mechanical Keyboard with Blue Switches.',
    price: 69.99,
    category: 'Peripherals',
    imageUrl: 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?auto=format&fit=crop&w=800&q=80',
    rating: 4.7,
    reviewCount: 890,
    isBestSeller: false,
    isInStock: true,
    quantity: 10,
  },
  {
    id: '3',
    sku: '000002',
    name: 'Pro Gaming Mouse',
    description: 'Ergonomic Wireless Gaming Mouse 16000 DPI.',
    price: 49.99,
    category: 'Peripherals',
    imageUrl: 'https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?auto=format&fit=crop&w=800&q=80',
    rating: 4.8,
    reviewCount: 1420,
    isBestSeller: true,
    isInStock: true,
    quantity: 20,
  },
  {
    id: '4',
    sku: '000003',
    name: '27-inch UltraWide Monitor',
    description: '27-inch Curved Gaming Monitor 144Hz IPS HDR.',
    price: 299.99,
    category: 'Displays',
    imageUrl: 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?auto=format&fit=crop&w=800&q=80',
    rating: 4.6,
    reviewCount: 640,
    isBestSeller: false,
    isInStock: true,
    quantity: 30,
  },
  {
    id: '5',
    sku: '000004',
    name: 'Studio Wireless Headphones HD',
    description: 'Active Noise Cancelling Wireless Headphones BT 5.3.',
    price: 119.99,
    category: 'Audio',
    imageUrl: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=800&q=80',
    rating: 4.8,
    reviewCount: 1180,
    isBestSeller: false,
    isInStock: false,
    quantity: 0,
  },
];

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

  // Modals state
  const [quickViewProduct, setQuickViewProduct] = useState<Product | null>(null);
  const [qrProduct, setQrProduct] = useState<Product | null>(null);
  const [isCheckoutOpen, setIsCheckoutOpen] = useState(false);
  const [receiptOrder, setReceiptOrder] = useState<Order | null>(null);
  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [isQrScannerOpen, setIsQrScannerOpen] = useState(false);

  // Load products from Apollo Router Federation
  useEffect(() => {
    let isMounted = true;
    const loadProducts = async () => {
      try {
        setIsLoadingProducts(true);
        const data = await fetchProducts(user?.token);
        if (isMounted) {
          setProducts(data && data.length > 0 ? data : DEFAULT_MOCK_PRODUCTS);
        }
      } catch {
        if (isMounted) {
          setProducts(DEFAULT_MOCK_PRODUCTS);
        }
      } finally {
        if (isMounted) {
          setIsLoadingProducts(false);
        }
      }
    };
    loadProducts();
    return () => {
      isMounted = false;
    };
  }, [user?.token]);

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

      {/* Global Footer */}
      <Footer />

      {/* Sliding Drawers */}
      <CartDrawer onOpenCheckout={() => setIsCheckoutOpen(true)} />
      <NotificationDrawer />

      {/* Modals */}
      <QuickViewModal
        product={quickViewProduct}
        onClose={() => setQuickViewProduct(null)}
        onOpenQR={(p) => setQrProduct(p)}
      />

      <ProductQRModal
        product={qrProduct}
        onClose={() => setQrProduct(null)}
      />

      <CheckoutModal
        isOpen={isCheckoutOpen}
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
