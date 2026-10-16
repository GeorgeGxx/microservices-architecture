import React, { useEffect, useState } from 'react';
import { useCart } from '../context/CartContext';
import { useNotifications } from '../context/NotificationContext';
import { useWishlist } from '../context/WishlistContext';
import { useAuth } from '../context/AuthContext';
import {
  ShoppingBag,
  Bell,
  Heart,
  Search,
  User,
  LogOut,
  Sparkles,
  Package,
  LayoutDashboard,
  ScanLine,
  X,
  Menu,
} from 'lucide-react';
import { checkStorefrontApiHealth } from '../services/storefrontHealth';

type StorefrontHealth = 'checking' | 'healthy' | 'unavailable';

interface NavbarProps {
  activeTab: 'catalog' | 'orders' | 'admin';
  setActiveTab: (tab: 'catalog' | 'orders' | 'admin') => void;
  searchQuery: string;
  setSearchQuery: (query: string) => void;
  onOpenCommandPalette: () => void;
  onOpenQrScanner?: () => void;
  onToggleFavoritesFilter?: () => void;
  isFavoritesFilterActive?: boolean;
}

export const Navbar: React.FC<NavbarProps> = ({
  activeTab,
  setActiveTab,
  searchQuery,
  setSearchQuery,
  onOpenCommandPalette,
  onOpenQrScanner,
  onToggleFavoritesFilter,
  isFavoritesFilterActive = false,
}) => {
  const { itemCount, setIsCartOpen } = useCart();
  const { unreadCount, setIsDrawerOpen, showToast } = useNotifications();
  const { wishlist } = useWishlist();
  const { user, login, logout } = useAuth();
  const [storefrontHealth, setStorefrontHealth] = useState<StorefrontHealth>('checking');
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [isMobileSearchOpen, setIsMobileSearchOpen] = useState(false);

  useEffect(() => {
    let disposed = false;
    let checking = false;
    let controller: AbortController | undefined;

    const refreshHealth = async () => {
      if (checking) return;
      checking = true;
      controller = new AbortController();
      const timeout = window.setTimeout(() => controller?.abort(), 4000);

      try {
        const healthy = await checkStorefrontApiHealth(controller.signal);
        if (!disposed) setStorefrontHealth(healthy ? 'healthy' : 'unavailable');
      } catch {
        if (!disposed) setStorefrontHealth('unavailable');
      } finally {
        window.clearTimeout(timeout);
        checking = false;
      }
    };

    void refreshHealth();
    const interval = window.setInterval(() => void refreshHealth(), 30000);
    return () => {
      disposed = true;
      controller?.abort();
      window.clearInterval(interval);
    };
  }, []);

  const healthLabel = {
    checking: 'Checking storefront API',
    healthy: 'Cosmo Router and Products subgraph reachable',
    unavailable: 'Storefront API unavailable',
  }[storefrontHealth];

  const healthColor = {
    checking: 'bg-amber-400',
    healthy: 'bg-emerald-500',
    unavailable: 'bg-rose-500',
  }[storefrontHealth];

  const handleWishlistClick = () => {
    if (!user) {
      showToast('Sign In Required', 'Please sign in with Keycloak to access your saved wishlist.', 'info');
      login();
      return;
    }
    setActiveTab('catalog');
    if (onToggleFavoritesFilter) {
      onToggleFavoritesFilter();
    }
  };

  return (
    <header className="sticky top-0 z-40 w-full glass border-b border-slate-800/80 transition-all">
      <div className="max-w-7xl mx-auto px-3 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-2 sm:gap-4">
        {/* Brand / Logo */}
        <div className="flex items-center gap-3 sm:gap-6 shrink-0">
          <div
            onClick={() => {
              setActiveTab('catalog');
              setSearchQuery('');
              setIsMobileMenuOpen(false);
            }}
            className="flex items-center gap-2 sm:gap-2.5 cursor-pointer group"
          >
            <div className="w-8 h-8 sm:w-9 sm:h-9 rounded-xl bg-gradient-to-tr from-indigo-500 to-violet-500 p-0.5 shadow-lg shadow-indigo-500/25 group-hover:scale-105 transition-transform flex items-center justify-center shrink-0">
              <Sparkles className="w-4 h-4 sm:w-5 sm:h-5 text-white" />
            </div>
            <div>
              <span className="font-extrabold text-sm sm:text-base tracking-tight text-white flex items-center gap-1 sm:gap-1.5">
                NOVASHOP
                <span className="relative flex h-2 w-2" role="img" aria-label={healthLabel} title={healthLabel}>
                  {storefrontHealth === 'healthy' && (
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  )}
                  <span className={`relative inline-flex rounded-full h-2 w-2 ${healthColor}`}></span>
                </span>
              </span>
              <span className="text-[9px] sm:text-[10px] font-mono text-indigo-400 block -mt-1 tracking-wider">
                FEDERATION v2
              </span>
            </div>
          </div>

          {/* Desktop Navigation Links */}
          <nav className="hidden lg:flex items-center gap-1">
            <button
              onClick={() => setActiveTab('catalog')}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition ${
                activeTab === 'catalog'
                  ? 'bg-indigo-600/20 text-indigo-400 border border-indigo-500/30'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
              }`}
            >
              Catalog
            </button>
            <button
              onClick={() => setActiveTab('orders')}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition flex items-center gap-1.5 ${
                activeTab === 'orders'
                  ? 'bg-indigo-600/20 text-indigo-400 border border-indigo-500/30'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
              }`}
            >
              <Package className="w-3.5 h-3.5" />
              Orders & Tracking
            </button>
            {user?.isAdmin && (
              <button
                onClick={() => setActiveTab('admin')}
                className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition flex items-center gap-1.5 ${
                  activeTab === 'admin'
                    ? 'bg-indigo-600/20 text-indigo-400 border border-indigo-500/30'
                    : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
                }`}
              >
                <LayoutDashboard className="w-3.5 h-3.5" />
                Admin Console
              </button>
            )}
          </nav>
        </div>

        {/* Desktop Product Search */}
        <div className={`hidden md:flex items-center gap-2 flex-1 max-w-md ${activeTab === 'orders' ? 'justify-end' : 'justify-center'}`}>
          {activeTab !== 'orders' && (
            <div className="relative w-full">
              <Search className="w-3.5 h-3.5 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => {
                  setSearchQuery(e.target.value);
                  if (activeTab !== 'catalog') {
                    setActiveTab('catalog');
                  }
                }}
                placeholder="Search products by SKU, name, or description..."
                className="w-full pl-9 pr-16 py-1.5 rounded-xl bg-slate-900/90 border border-slate-800 hover:border-slate-700 focus:border-indigo-500 text-slate-200 placeholder-slate-500 text-xs transition focus:outline-none focus:ring-1 focus:ring-indigo-500/50 shadow-inner"
              />
              <div className="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
                {searchQuery && (
                  <button
                    onClick={() => setSearchQuery('')}
                    className="p-1 text-slate-400 hover:text-white rounded transition"
                    title="Clear search"
                  >
                    <X className="w-3 h-3" />
                  </button>
                )}
                <button
                  onClick={onOpenCommandPalette}
                  title="Command Palette (Ctrl+K)"
                  className="hidden sm:inline-flex items-center px-1.5 py-0.5 rounded bg-slate-800/80 text-[10px] font-mono text-slate-400 border border-slate-700 hover:border-slate-600 hover:text-slate-200 transition"
                >
                  ⌘K
                </button>
              </div>
            </div>
          )}

          {onOpenQrScanner && user?.isAdmin && (
            <button
              onClick={onOpenQrScanner}
              title="Agnostic QR & Barcode Scanner (Admin Only)"
              className="p-2 rounded-xl bg-slate-900/80 hover:bg-indigo-600/20 text-slate-400 hover:text-indigo-400 border border-slate-800 hover:border-indigo-500/30 transition flex items-center gap-1.5 shrink-0"
            >
              <ScanLine className="w-4 h-4 text-indigo-400" />
              <span className="hidden xl:inline text-xs font-semibold">Scan QR</span>
            </button>
          )}
        </div>

        {/* User Controls: Wishlist, Live Notifications, Cart, User, Mobile Toggles */}
        <div className="flex items-center gap-1.5 sm:gap-2.5 shrink-0">
          {/* Mobile Search Toggle (Catalog Tab) */}
          {activeTab !== 'orders' && (
            <button
              onClick={() => setIsMobileSearchOpen((prev) => !prev)}
              title="Search Products"
              className={`md:hidden p-1.5 sm:p-2 rounded-lg border transition ${
                isMobileSearchOpen
                  ? 'bg-indigo-600/20 text-indigo-400 border-indigo-500/40'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/70 border-slate-800'
              }`}
            >
              <Search className="w-4 h-4" />
            </button>
          )}

          {/* Wishlist Indicator */}
          <button
            onClick={handleWishlistClick}
            title={user ? (isFavoritesFilterActive ? "Showing Wishlist Only" : "Filter by Wishlist") : "Sign in to access Wishlist"}
            className={`p-1.5 sm:p-2 rounded-lg border transition relative ${
              isFavoritesFilterActive
                ? 'bg-rose-500/20 text-rose-400 border-rose-500/40'
                : 'text-slate-400 hover:text-rose-400 hover:bg-slate-800/70 border-slate-800'
            }`}
          >
            <Heart className={`w-4 h-4 ${isFavoritesFilterActive ? 'fill-rose-500 text-rose-500' : ''}`} />
            {user && wishlist.length > 0 && (
              <span className="absolute -top-1 -right-1 bg-rose-500 text-white font-mono text-[9px] font-bold w-4 h-4 rounded-full flex items-center justify-center shadow">
                {wishlist.length}
              </span>
            )}
          </button>

          {/* Live Notification Bell - Restricted strictly to Signed-In Users */}
          {user && (
            <button
              onClick={() => setIsDrawerOpen(true)}
              title="Live Event Notifications"
              className="relative p-1.5 sm:p-2 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800/70 border border-slate-800 transition"
            >
              <Bell className="w-4 h-4" />
              {unreadCount > 0 && (
                <span className="absolute -top-1 -right-1 bg-indigo-500 text-white font-mono text-[9px] font-bold w-4 h-4 rounded-full flex items-center justify-center animate-pulse">
                  {unreadCount > 9 ? '9+' : unreadCount}
                </span>
              )}
            </button>
          )}

          {/* Cart is available only after signing in */}
          {user && (
            <button
              onClick={() => setIsCartOpen(true)}
              className="flex items-center gap-1 sm:gap-2 px-2.5 sm:px-3 py-1.5 rounded-xl bg-gradient-to-r from-indigo-600 to-indigo-700 hover:from-indigo-500 hover:to-indigo-600 text-white font-semibold text-xs shadow-md shadow-indigo-500/20 transition transform active:scale-95"
            >
              <ShoppingBag className="w-4 h-4" />
              <span className="hidden sm:inline">Cart</span>
              {itemCount > 0 && (
                <span className="bg-white/20 text-white px-1.5 py-0.5 rounded-full font-mono text-[10px] font-bold">
                  {itemCount}
                </span>
              )}
            </button>
          )}

          {/* User Account / Keycloak Authentication */}
          {user ? (
            <div className="flex items-center gap-1 pl-0.5">
              <div
                title={`${user.username} (${user.roles.join(', ')})`}
                className="w-7 h-7 sm:w-8 sm:h-8 rounded-lg bg-indigo-500/20 border border-indigo-500/30 flex items-center justify-center text-xs font-bold text-indigo-400 font-mono shadow-inner shrink-0"
              >
                {user.username.charAt(0).toUpperCase()}
              </div>
              <button
                onClick={logout}
                title="Sign out"
                className="hidden sm:flex p-1.5 text-slate-400 hover:text-red-400 rounded-lg hover:bg-slate-800 transition"
              >
                <LogOut className="w-3.5 h-3.5" />
              </button>
            </div>
          ) : (
            <button
              onClick={login}
              className="flex items-center gap-1 px-2.5 sm:px-3 py-1.5 rounded-xl bg-slate-900 border border-slate-700 hover:border-indigo-500/50 hover:bg-slate-800 text-xs font-semibold text-slate-200 hover:text-white transition shadow-sm"
            >
              <User className="w-3.5 h-3.5 text-indigo-400" />
              <span className="hidden xs:inline">Sign In</span>
            </button>
          )}

          {/* Mobile Menu Hamburger Toggle (lg:hidden) */}
          <button
            onClick={() => setIsMobileMenuOpen((prev) => !prev)}
            title="Navigation Menu"
            className="lg:hidden p-1.5 sm:p-2 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800/70 border border-slate-800 transition"
          >
            {isMobileMenuOpen ? <X className="w-5 h-5 text-indigo-400" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {/* Mobile Expandable Search Bar */}
      {activeTab !== 'orders' && isMobileSearchOpen && (
        <div className="md:hidden px-4 py-2.5 bg-slate-950/95 border-t border-slate-800/80 animate-in slide-in-from-top-2">
          <div className="relative w-full">
            <Search className="w-3.5 h-3.5 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
            <input
              type="text"
              autoFocus
              value={searchQuery}
              onChange={(e) => {
                setSearchQuery(e.target.value);
                if (activeTab !== 'catalog') setActiveTab('catalog');
              }}
              placeholder="Search products by SKU, name, or description..."
              className="w-full pl-9 pr-14 py-2 rounded-xl bg-slate-900 border border-slate-700 text-slate-100 placeholder-slate-500 text-xs focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500/50 shadow-inner"
            />
            <div className="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
              {searchQuery && (
                <button
                  onClick={() => setSearchQuery('')}
                  className="p-1 text-slate-400 hover:text-white"
                  title="Clear search"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              )}
              <button
                onClick={() => setIsMobileSearchOpen(false)}
                className="text-[11px] text-slate-400 hover:text-slate-200 px-1 py-0.5"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Mobile Navigation Dropdown Menu (lg:hidden) */}
      {isMobileMenuOpen && (
        <div className="lg:hidden border-t border-slate-800 bg-slate-950/95 backdrop-blur-xl px-4 py-3 space-y-2 animate-in slide-in-from-top-2 shadow-2xl">
          <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 px-1">Navigation</div>
          <div className="space-y-1">
            <button
              onClick={() => {
                setActiveTab('catalog');
                setIsMobileMenuOpen(false);
              }}
              className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-semibold transition ${
                activeTab === 'catalog'
                  ? 'bg-indigo-600/20 text-indigo-400 border border-indigo-500/30 font-bold'
                  : 'text-slate-300 hover:bg-slate-900'
              }`}
            >
              <div className="flex items-center gap-2.5">
                <Sparkles className="w-4 h-4 text-indigo-400" />
                <span>Product Catalog</span>
              </div>
              {activeTab === 'catalog' && (
                <span className="text-[10px] font-mono bg-indigo-500/20 text-indigo-300 px-2 py-0.5 rounded-full">Active</span>
              )}
            </button>

            <button
              onClick={() => {
                setActiveTab('orders');
                setIsMobileMenuOpen(false);
              }}
              className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-semibold transition ${
                activeTab === 'orders'
                  ? 'bg-indigo-600/20 text-indigo-400 border border-indigo-500/30 font-bold'
                  : 'text-slate-300 hover:bg-slate-900'
              }`}
            >
              <div className="flex items-center gap-2.5">
                <Package className="w-4 h-4 text-emerald-400" />
                <span>Orders & Tracking</span>
              </div>
              {activeTab === 'orders' && (
                <span className="text-[10px] font-mono bg-indigo-500/20 text-indigo-300 px-2 py-0.5 rounded-full">Active</span>
              )}
            </button>

            {user?.isAdmin && (
              <button
                onClick={() => {
                  setActiveTab('admin');
                  setIsMobileMenuOpen(false);
                }}
                className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-semibold transition ${
                  activeTab === 'admin'
                    ? 'bg-indigo-600/20 text-indigo-400 border border-indigo-500/30 font-bold'
                    : 'text-slate-300 hover:bg-slate-900'
                }`}
              >
                <div className="flex items-center gap-2.5">
                  <LayoutDashboard className="w-4 h-4 text-violet-400" />
                  <span>Admin Console</span>
                </div>
                {activeTab === 'admin' && (
                  <span className="text-[10px] font-mono bg-indigo-500/20 text-indigo-300 px-2 py-0.5 rounded-full">Active</span>
                )}
              </button>
            )}
          </div>

          {/* Quick Tools in Mobile Menu */}
          <div className="pt-2 border-t border-slate-800/80 space-y-1">
            <div className="text-[10px] font-mono uppercase tracking-wider text-slate-500 px-1">Quick Actions</div>
            <button
              onClick={() => {
                setIsMobileMenuOpen(false);
                onOpenCommandPalette();
              }}
              className="w-full flex items-center justify-between px-3.5 py-2 rounded-xl text-xs text-slate-300 hover:bg-slate-900 transition"
            >
              <div className="flex items-center gap-2.5">
                <Search className="w-3.5 h-3.5 text-indigo-400" />
                <span>Command Palette</span>
              </div>
              <span className="text-[10px] font-mono bg-slate-800 text-slate-400 px-1.5 py-0.5 rounded border border-slate-700">⌘K</span>
            </button>

            {onOpenQrScanner && user?.isAdmin && (
              <button
                onClick={() => {
                  setIsMobileMenuOpen(false);
                  onOpenQrScanner();
                }}
                className="w-full flex items-center justify-between px-3.5 py-2 rounded-xl text-xs text-slate-300 hover:bg-slate-900 transition"
              >
                <div className="flex items-center gap-2.5">
                  <ScanLine className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Agnostic QR Scanner POS</span>
                </div>
                <span className="text-[10px] font-mono text-emerald-400">ADMIN</span>
              </button>
            )}
          </div>

          {/* User Status / Logout on Mobile */}
          {user && (
            <div className="pt-2 border-t border-slate-800/80 flex items-center justify-between px-1">
              <div className="flex items-center gap-2 text-xs">
                <div className="w-7 h-7 rounded-lg bg-indigo-500/20 border border-indigo-500/30 flex items-center justify-center text-xs font-bold text-indigo-400 font-mono">
                  {user.username.charAt(0).toUpperCase()}
                </div>
                <div className="leading-tight">
                  <div className="font-semibold text-slate-200">{user.username}</div>
                  <div className="text-[10px] text-slate-500 font-mono">{user.roles.join(', ')}</div>
                </div>
              </div>
              <button
                onClick={() => {
                  setIsMobileMenuOpen(false);
                  logout();
                }}
                className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-semibold text-red-400 hover:bg-red-500/10 border border-red-500/20 transition"
              >
                <LogOut className="w-3.5 h-3.5" />
                <span>Sign Out</span>
              </button>
            </div>
          )}
        </div>
      )}
    </header>
  );
};
export default Navbar;
