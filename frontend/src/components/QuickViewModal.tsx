import React, { useState } from 'react';
import { Product } from '../types';
import { useCart } from '../context/CartContext';
import { useCurrency } from '../context/CurrencyContext';
import { useWishlist } from '../context/WishlistContext';
import { useAuth } from '../context/AuthContext';
import { X, Star, ShoppingBag, Heart, QrCode, ShieldCheck, Truck, RefreshCw } from 'lucide-react';

interface QuickViewModalProps {
  product: Product | null;
  onClose: () => void;
  onOpenQR: (product: Product) => void;
}

export const QuickViewModal: React.FC<QuickViewModalProps> = ({ product, onClose, onOpenQR }) => {
  const [quantity, setQuantity] = useState(1);
  const { addToCart } = useCart();
  const { formatPrice } = useCurrency();
  const { isInWishlist, toggleWishlist } = useWishlist();
  const { user, login } = useAuth();

  if (!product) return null;

  const isFavorited = isInWishlist(product.sku);
  const isInStock = product.isInStock !== false && (product.quantity === undefined || product.quantity > 0);

  const handleAddToCart = () => {
    addToCart(product, quantity);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in duration-200">
      <div className="relative w-full max-w-3xl bg-slate-900 border border-slate-800 rounded-2xl shadow-2xl overflow-hidden grid grid-cols-1 md:grid-cols-2">
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute top-4 right-4 z-10 p-2 text-slate-400 hover:text-white bg-slate-950/60 rounded-full border border-slate-800 transition"
        >
          <X className="w-4 h-4" />
        </button>

        {/* Product Media */}
        <div className="relative bg-slate-950 flex items-center justify-center p-6 border-b md:border-b-0 md:border-r border-slate-800">
          <img
            src={product.imageUrl || 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=600'}
            alt={product.name}
            className="w-full h-72 md:h-80 object-contain rounded-xl"
          />
          {product.isBestSeller && (
            <span className="absolute top-4 left-4 bg-amber-500/20 text-amber-300 border border-amber-500/40 text-[11px] font-bold px-2.5 py-1 rounded-full uppercase tracking-wider">
              ⭐ Best Seller
            </span>
          )}
        </div>

        {/* Product Details */}
        <div className="p-6 md:p-8 flex flex-col justify-between space-y-4">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                {product.category || 'Electronics'}
              </span>
              <span className="text-xs font-mono text-slate-500">SKU: {product.sku}</span>
            </div>

            <h2 className="text-xl md:text-2xl font-bold text-white mb-2 leading-tight">
              {product.name}
            </h2>

            {/* Ratings */}
            <div className="flex items-center gap-2 mb-3">
              <div className="flex text-amber-400">
                {[...Array(5)].map((_, i) => (
                  <Star
                    key={i}
                    className={`w-4 h-4 ${
                      i < Math.floor(product.rating || 4.8) ? 'fill-current' : 'text-slate-700'
                    }`}
                  />
                ))}
              </div>
              <span className="text-xs font-medium text-slate-400">
                {product.rating || 4.8} ({product.reviewCount || 120} reviews)
              </span>
            </div>

            <p className="text-sm text-slate-400 line-clamp-3 leading-relaxed mb-4">
              {product.description ||
                'High-performance precision engineered product with enterprise durability and seamless federated catalog integration.'}
            </p>

            <div className="flex items-baseline gap-3 mb-4">
              <span className="text-2xl font-extrabold text-white">
                {formatPrice(product.price)}
              </span>
              <span
                className={`text-xs font-semibold px-2.5 py-1 rounded-full border ${
                  isInStock
                    ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                    : 'bg-red-500/10 text-red-400 border-red-500/30'
                }`}
              >
                {isInStock ? `In Stock (${product.quantity ?? 50} units)` : 'Out of Stock'}
              </span>
            </div>
          </div>

          <div className="space-y-4 pt-2 border-t border-slate-800">
            {/* Cart actions require an authenticated user. */}
            <div className="flex items-center gap-3">
              {user ? (
                <>
                  <div className="flex items-center bg-slate-950 border border-slate-800 rounded-xl p-1">
                    <button
                      onClick={() => setQuantity(Math.max(1, quantity - 1))}
                      className="w-8 h-8 flex items-center justify-center text-slate-400 hover:text-white rounded-lg hover:bg-slate-800"
                    >
                      -
                    </button>
                    <span className="w-8 text-center text-sm font-bold text-white">{quantity}</span>
                    <button
                      onClick={() => setQuantity(quantity + 1)}
                      className="w-8 h-8 flex items-center justify-center text-slate-400 hover:text-white rounded-lg hover:bg-slate-800"
                    >
                      +
                    </button>
                  </div>

                  <button
                    onClick={handleAddToCart}
                    disabled={!isInStock}
                    className="flex-1 py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:bg-slate-800 disabled:text-slate-600 text-white font-semibold text-sm shadow-lg shadow-indigo-500/25 flex items-center justify-center gap-2 transition"
                  >
                    <ShoppingBag className="w-4 h-4" />
                    Add to Cart
                  </button>
                </>
              ) : (
                <button
                  onClick={login}
                  className="flex-1 py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm shadow-lg shadow-indigo-500/25 transition"
                >
                  Sign in to Buy
                </button>
              )}

              <button
                onClick={() => toggleWishlist(product.sku)}
                className={`p-3 rounded-xl border transition ${
                  isFavorited
                    ? 'bg-rose-500/10 border-rose-500/30 text-rose-400'
                    : 'bg-slate-950 border-slate-800 text-slate-400 hover:text-white'
                }`}
              >
                <Heart className={`w-4 h-4 ${isFavorited ? 'fill-current' : ''}`} />
              </button>

              {user?.isAdmin && (
                <button
                  onClick={() => onOpenQR(product)}
                  title="View Barcode / QR Label"
                  className="p-3 rounded-xl bg-slate-950 border border-slate-800 text-slate-400 hover:text-indigo-400 transition"
                >
                  <QrCode className="w-4 h-4" />
                </button>
              )}
            </div>

            {/* Guarantees */}
            <div className="grid grid-cols-3 gap-2 pt-2 text-[11px] text-slate-500">
              <div className="flex items-center gap-1.5">
                <Truck className="w-3.5 h-3.5 text-indigo-400 shrink-0" />
                <span>DHL Express</span>
              </div>
              <div className="flex items-center gap-1.5">
                <ShieldCheck className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                <span>2-Year Warranty</span>
              </div>
              <div className="flex items-center gap-1.5">
                <RefreshCw className="w-3.5 h-3.5 text-amber-400 shrink-0" />
                <span>30-Day Return</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
