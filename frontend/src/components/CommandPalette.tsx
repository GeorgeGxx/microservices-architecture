import React, { useState, useEffect, useMemo } from 'react';
import { Product } from '../types';
import { Search, ShoppingBag, Package, LayoutDashboard, LogIn, LogOut, X, ScanLine } from 'lucide-react';
import { useAuth } from '../context/AuthContext';

interface CommandPaletteProps {
  isOpen: boolean;
  onClose: () => void;
  products: Product[];
  onSelectProduct: (product: Product) => void;
  onNavigate: (tab: 'catalog' | 'orders' | 'admin') => void;
  onOpenQrScanner?: () => void;
}

export const CommandPalette: React.FC<CommandPaletteProps> = ({
  isOpen,
  onClose,
  products,
  onSelectProduct,
  onNavigate,
  onOpenQrScanner,
}) => {
  const [query, setQuery] = useState('');
  const { user, login, logout } = useAuth();

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        if (isOpen) onClose();
        else setQuery('');
      } else if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  const normalizedQuery = query.trim().toLowerCase();

  // Must declare all hooks BEFORE any early return (React Rules of Hooks)
  const filteredProducts = useMemo(() => {
    if (!isOpen) return [];
    const list = [...(products || [])].reverse();
    if (!normalizedQuery) {
      return list;
    }
    return list.filter(
      (p) =>
        (p.name && p.name.toLowerCase().includes(normalizedQuery)) ||
        (p.sku && p.sku.toLowerCase().includes(normalizedQuery)) ||
        (p.category && p.category.toLowerCase().includes(normalizedQuery)) ||
        (p.description && p.description.toLowerCase().includes(normalizedQuery))
    );
  }, [products, normalizedQuery, isOpen]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center pt-10 sm:pt-24 p-3 sm:p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in">
      <div className="w-full max-w-xl bg-slate-900 border border-slate-800 rounded-2xl shadow-2xl overflow-hidden">
        {/* Search Input */}
        <div className="flex items-center px-3 sm:px-4 border-b border-slate-800">
          <Search className="w-5 h-5 text-slate-400 shrink-0 mr-2 sm:mr-3" />
          <input
            type="text"
            autoFocus
            placeholder="Type a command or search products..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-full py-3.5 sm:py-4 bg-transparent text-white placeholder-slate-500 text-xs sm:text-sm focus:outline-none"
          />
          <button onClick={onClose} className="p-1 text-slate-400 hover:text-white rounded">
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Results List */}
        <div className="max-h-96 overflow-y-auto p-2 space-y-1">
          {/* Matching Products */}
          {filteredProducts.length > 0 ? (
            <div className="mb-2">
              <div className="flex items-center justify-between px-3 py-1">
                <span className="text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                  Products
                </span>
                <span className="text-[10px] text-slate-400 font-mono">
                  {filteredProducts.length} {filteredProducts.length === 1 ? 'item' : 'items'}
                </span>
              </div>
              <div className="max-h-56 overflow-y-auto space-y-1 pr-1 scrollbar-thin">
                {filteredProducts.map((p) => (
                  <button
                    key={p.sku}
                    onClick={() => {
                      onSelectProduct(p);
                      onClose();
                    }}
                    className="w-full flex items-center justify-between px-3 py-2 rounded-xl text-left hover:bg-slate-800 text-slate-200 transition group"
                  >
                    <div className="flex items-center gap-2.5 min-w-0">
                      {p.imageUrl ? (
                        <img
                          src={p.imageUrl}
                          alt=""
                          className="w-7 h-7 rounded-lg object-cover shrink-0 bg-slate-800 border border-slate-700/60"
                          onError={(e) => {
                            (e.target as HTMLElement).style.display = 'none';
                          }}
                        />
                      ) : (
                        <div className="w-7 h-7 rounded-lg bg-slate-800 border border-slate-700/60 flex items-center justify-center shrink-0 text-slate-400">
                          <ShoppingBag className="w-3.5 h-3.5" />
                        </div>
                      )}
                      <div className="min-w-0 flex-1">
                        <span className="text-xs font-medium text-slate-200 group-hover:text-indigo-400 truncate block">
                          {p.name}
                        </span>
                        <span className="text-[10px] font-mono text-slate-400 truncate block">
                          {p.sku} {p.category ? `• ${p.category}` : ''}
                        </span>
                      </div>
                    </div>
                    <span className="text-xs font-mono font-bold text-slate-300 ml-2 shrink-0">
                      ${typeof p.price === 'number' ? p.price.toFixed(2) : Number(p.price || 0).toFixed(2)}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          ) : query.trim() ? (
            <div className="px-3 py-3 text-center">
              <p className="text-xs text-slate-400">No products found matching "{query}"</p>
            </div>
          ) : null}

          {/* Quick Navigation Commands */}
          <div>
            <span className="text-[11px] font-semibold text-slate-500 px-3 uppercase tracking-wider block py-1">
              Navigation & Actions
            </span>
            <button
              onClick={() => {
                onNavigate('catalog');
                onClose();
              }}
              className="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-left hover:bg-slate-800 text-slate-300 text-xs transition"
            >
              <ShoppingBag className="w-4 h-4 text-indigo-400" />
              <span>Browse Catalog</span>
            </button>
            <button
              onClick={() => {
                onNavigate('orders');
                onClose();
              }}
              className="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-left hover:bg-slate-800 text-slate-300 text-xs transition"
            >
              <Package className="w-4 h-4 text-emerald-400" />
              <span>View Orders & Tracking</span>
            </button>
            {onOpenQrScanner && user?.isAdmin && (
              <button
                onClick={() => {
                  onClose();
                  onOpenQrScanner();
                }}
                className="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-left hover:bg-slate-800 text-slate-300 text-xs transition"
              >
                <ScanLine className="w-4 h-4 text-violet-400" />
                <span>Scan QR Code or Barcode (Admin Only)</span>
              </button>
            )}
            {user?.isAdmin && (
              <button
                onClick={() => {
                  onNavigate('admin');
                  onClose();
                }}
                className="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-left hover:bg-slate-800 text-slate-300 text-xs transition"
              >
                <LayoutDashboard className="w-4 h-4 text-amber-400" />
                <span>Admin Console</span>
              </button>
            )}
          </div>

          {/* User Auth */}
          <div className="pt-2 border-t border-slate-800/80">
            <span className="text-[11px] font-semibold text-slate-500 px-3 uppercase tracking-wider block py-1">
              Authentication
            </span>

            {user ? (
              <button
                onClick={() => {
                  logout();
                  onClose();
                }}
                className="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-left hover:bg-slate-800 text-rose-400 text-xs transition"
              >
                <LogOut className="w-4 h-4" />
                <span>Sign Out ({user.username})</span>
              </button>
            ) : (
              <button
                onClick={() => {
                  login();
                  onClose();
                }}
                className="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-left hover:bg-slate-800 text-indigo-400 text-xs transition"
              >
                <LogIn className="w-4 h-4" />
                <span>Sign In via Keycloak</span>
              </button>
            )}
          </div>
        </div>

        {/* Footer shortcuts hint */}
        <div className="px-4 py-2 bg-slate-950 border-t border-slate-800/80 flex items-center justify-between text-[11px] text-slate-500">
          <span>Tip: Press <kbd className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-300 font-mono text-[10px]">Ctrl+K</kbd> to open anywhere</span>
          <span>Novashop Command Engine</span>
        </div>
      </div>
    </div>
  );
};
