import React, { createContext, useContext } from 'react';
import { Product } from '../../types';
import { useCurrency } from '../../context/CurrencyContext';
import { useCart } from '../../context/CartContext';
import { useWishlist } from '../../context/WishlistContext';
import { useAuth } from '../../context/AuthContext';
import { Star, Eye, QrCode, ShoppingBag, Heart, CheckCircle2, AlertTriangle } from 'lucide-react';

interface ProductCardContextType {
  product: Product;
  isInStock: boolean;
  isFavorited: boolean;
  toggleFavorite: () => void;
  onOpenQuickView?: (product: Product) => void;
  onOpenQR?: (product: Product) => void;
}

const ProductCardContext = createContext<ProductCardContextType | null>(null);

function useProductCardContext() {
  const context = useContext(ProductCardContext);
  if (!context) {
    throw new Error('ProductCard compound subcomponents must be rendered within a ProductCard');
  }
  return context;
}

export interface ProductCardProps {
  product: Product;
  onOpenQuickView?: (product: Product) => void;
  onOpenQR?: (product: Product) => void;
  children?: React.ReactNode;
  className?: string;
}

export const ProductCard: React.FC<ProductCardProps> & {
  Image: React.FC;
  Category: React.FC;
  Title: React.FC;
  Rating: React.FC;
  StockBadge: React.FC;
  Price: React.FC;
  Actions: React.FC;
} = ({ product, onOpenQuickView, onOpenQR, children, className = '' }) => {
  const { isInWishlist, toggleWishlist } = useWishlist();

  const isFavorited = isInWishlist(product.sku);
  const isInStock = product.isInStock !== false && (product.quantity === undefined || product.quantity > 0);

  return (
    <ProductCardContext.Provider
      value={{
        product,
        isInStock,
        isFavorited,
        toggleFavorite: () => toggleWishlist(product.sku),
        onOpenQuickView,
        onOpenQR,
      }}
    >
      <div
        className={`glass-card rounded-2xl overflow-hidden border border-slate-200/80 dark:border-slate-800/80 flex flex-col justify-between group hover:border-indigo-500/50 hover:shadow-xl hover:shadow-indigo-500/5 transition-all duration-300 ${className}`}
      >
        {children ? (
          children
        ) : (
          <>
            <ProductCard.Image />
            <div className="p-4 flex-1 flex flex-col justify-between space-y-3">
              <div>
                <div className="flex items-center justify-between gap-2 mb-1">
                  <ProductCard.Category />
                  <ProductCard.StockBadge />
                </div>
                <ProductCard.Title />
                <ProductCard.Rating />
              </div>
              <div className="pt-2 border-t border-slate-100 dark:border-slate-800 flex items-center justify-between gap-2">
                <ProductCard.Price />
                <ProductCard.Actions />
              </div>
            </div>
          </>
        )}
      </div>
    </ProductCardContext.Provider>
  );
};

// Subcomponent: Image
ProductCard.Image = function ProductCardImage() {
  const { product, isFavorited, toggleFavorite, onOpenQuickView } = useProductCardContext();

  return (
    <div className="relative aspect-[16/10] overflow-hidden bg-slate-100 dark:bg-slate-800/50">
      <img
        src={product.imageUrl}
        alt={product.name}
        loading="lazy"
        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
      />

      {/* Floating Badges */}
      <div className="absolute top-2.5 left-2.5 flex flex-col gap-1">
        {product.isBestSeller && (
          <span className="px-2 py-0.5 rounded-md text-[10px] font-extrabold uppercase tracking-wider bg-amber-500 text-white shadow-sm">
            #1 Best Seller
          </span>
        )}
      </div>

      {/* Wishlist Button */}
      <button
        onClick={(e) => {
          e.stopPropagation();
          toggleFavorite();
        }}
        aria-label="Add to Wishlist"
        className={`absolute top-2.5 right-2.5 p-2 rounded-xl backdrop-blur-md transition-all ${
          isFavorited
            ? 'bg-rose-500 text-white shadow-md shadow-rose-500/30'
            : 'bg-white/80 dark:bg-slate-900/80 text-slate-600 dark:text-slate-300 hover:text-rose-500 hover:bg-white'
        }`}
      >
        <Heart className={`w-3.5 h-3.5 ${isFavorited ? 'fill-current' : ''}`} />
      </button>

      {/* Quick View Overlay on hover */}
      {onOpenQuickView && (
        <div
          onClick={() => onOpenQuickView(product)}
          className="absolute inset-0 bg-slate-950/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center cursor-pointer"
        >
          <span className="px-3 py-1.5 rounded-xl bg-white/95 dark:bg-slate-900/95 text-slate-900 dark:text-white text-xs font-bold shadow-lg flex items-center gap-1.5 transform translate-y-2 group-hover:translate-y-0 transition-transform">
            <Eye className="w-3.5 h-3.5 text-indigo-500" />
            Quick View
          </span>
        </div>
      )}
    </div>
  );
};

// Subcomponent: Category
ProductCard.Category = function ProductCardCategory() {
  const { product } = useProductCardContext();
  return (
    <span className="text-[11px] font-bold uppercase tracking-wider text-indigo-600 dark:text-indigo-400">
      {product.category || 'Technology'}
    </span>
  );
};

// Subcomponent: Title
ProductCard.Title = function ProductCardTitle() {
  const { product, onOpenQuickView } = useProductCardContext();
  return (
    <h3
      onClick={() => onOpenQuickView?.(product)}
      className="font-bold text-sm text-slate-900 dark:text-white line-clamp-2 hover:text-indigo-600 dark:hover:text-indigo-400 cursor-pointer transition-colors"
    >
      {product.name}
    </h3>
  );
};

// Subcomponent: Rating
ProductCard.Rating = function ProductCardRating() {
  const { product } = useProductCardContext();
  const rating = product.rating || 4.8;
  const reviews = product.reviewCount || 120;

  return (
    <div className="flex items-center gap-1.5 mt-1.5">
      <div className="flex items-center text-amber-400">
        <Star className="w-3.5 h-3.5 fill-current" />
      </div>
      <span className="text-xs font-bold text-slate-800 dark:text-slate-200">{rating}</span>
      <span className="text-[11px] text-slate-400">({reviews})</span>
    </div>
  );
};

// Subcomponent: StockBadge
ProductCard.StockBadge = function ProductCardStockBadge() {
  const { product, isInStock } = useProductCardContext();
  const qty = product.quantity;

  if (!isInStock) {
    return (
      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20">
        <AlertTriangle className="w-2.5 h-2.5" /> Out of Stock
      </span>
    );
  }

  if (qty !== undefined && qty < 10) {
    return (
      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
        Only {qty} left
      </span>
    );
  }

  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
      <CheckCircle2 className="w-2.5 h-2.5" /> In Stock
    </span>
  );
};

// Subcomponent: Price
ProductCard.Price = function ProductCardPrice() {
  const { product } = useProductCardContext();
  const { formatPrice } = useCurrency();

  return (
    <div>
      <span className="text-[10px] uppercase font-bold text-slate-400 block -mb-0.5">Price</span>
      <span className="text-lg font-black text-slate-900 dark:text-white">
        {formatPrice(product.price)}
      </span>
    </div>
  );
};

// Subcomponent: Actions
ProductCard.Actions = function ProductCardActions() {
  const { product, isInStock, onOpenQR } = useProductCardContext();
  const { addToCart } = useCart();
  const { user, login } = useAuth();

  return (
    <div className="flex items-center gap-1.5">
      {onOpenQR && user?.isAdmin && (
        <button
          onClick={() => onOpenQR(product)}
          title="Generate QR Code Label (Admin)"
          className="p-2 rounded-xl text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-800 border border-slate-200 dark:border-slate-800 transition"
        >
          <QrCode className="w-4 h-4" />
        </button>
      )}

      {user ? (
        <button
          onClick={() => addToCart(product, 1)}
          disabled={!isInStock}
          className="inline-flex items-center gap-1 px-3 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-700 disabled:opacity-40 text-white font-bold text-xs shadow-md shadow-indigo-500/20 transition active:scale-95"
        >
          <ShoppingBag className="w-3.5 h-3.5" />
          Add to Cart
        </button>
      ) : (
        <button
          onClick={login}
          className="inline-flex items-center gap-1 px-3 py-2 rounded-xl bg-slate-100 dark:bg-slate-800 hover:bg-slate-200 dark:hover:bg-slate-700 text-indigo-600 dark:text-indigo-400 font-bold text-xs border border-slate-200 dark:border-slate-700 transition active:scale-95"
          title="Sign in with Keycloak to place orders"
        >
          Sign in to Buy
        </button>
      )}
    </div>
  );
};
