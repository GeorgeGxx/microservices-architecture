import React from 'react';
import { Product } from '../types';
import { useCart } from '../context/CartContext';
import { useCurrency } from '../context/CurrencyContext';
import { useNotifications } from '../context/NotificationContext';
import { X, ShoppingBag, Star, Check, AlertTriangle, Layers } from 'lucide-react';

interface ProductComparisonModalProps {
  isOpen: boolean;
  onClose: () => void;
  products: Product[];
  onRemoveProduct: (sku: string) => void;
}

export const ProductComparisonModal: React.FC<ProductComparisonModalProps> = ({
  isOpen,
  onClose,
  products,
  onRemoveProduct,
}) => {
  const { addToCart } = useCart();
  const { formatPrice } = useCurrency();
  const { showToast } = useNotifications();

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in">
      <div className="relative w-full max-w-5xl bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="p-6 border-b border-slate-800 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400">
              <Layers className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-white">Product Technical Comparison</h3>
              <p className="text-xs text-slate-400">
                Side-by-side hardware specifications, inventory availability, and pricing
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-white rounded-xl hover:bg-slate-800 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Table */}
        <div className="p-6 flex-1 overflow-x-auto overflow-y-auto">
          {products.length === 0 ? (
            <div className="text-center py-16 text-slate-400">
              <Layers className="w-12 h-12 mx-auto mb-3 text-slate-600" />
              <p className="font-semibold text-slate-300">No products selected for comparison</p>
              <p className="text-xs text-slate-500 mt-1">
                Select products from the catalog to compare their specs.
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              {products.map((p) => {
                const isInStock = p.isInStock !== false && (p.quantity === undefined || p.quantity > 0);
                return (
                  <div
                    key={p.sku}
                    className="p-4 rounded-2xl bg-slate-950/60 border border-slate-800 flex flex-col justify-between space-y-4"
                  >
                    <div>
                      <div className="flex justify-between items-start mb-2">
                        <span className="text-[10px] font-mono text-indigo-400 font-bold px-2 py-0.5 rounded-md bg-indigo-500/10">
                          {p.sku}
                        </span>
                        <button
                          onClick={() => onRemoveProduct(p.sku)}
                          className="text-slate-500 hover:text-red-400 p-1 rounded-lg"
                        >
                          <X className="w-3.5 h-3.5" />
                        </button>
                      </div>

                      <img
                        src={p.imageUrl || 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400'}
                        alt={p.name}
                        className="w-full aspect-[4/3] rounded-xl object-cover border border-slate-800 mb-3"
                      />

                      <h4 className="text-sm font-bold text-white line-clamp-2">{p.name}</h4>
                      <p className="text-xs text-slate-400 mt-1 line-clamp-3">{p.description}</p>
                    </div>

                    <div className="space-y-3 pt-3 border-t border-slate-800/80 text-xs">
                      <div className="flex justify-between">
                        <span className="text-slate-500">Price</span>
                        <span className="font-black text-indigo-400 text-sm">
                          {formatPrice(p.price)}
                        </span>
                      </div>

                      <div className="flex justify-between items-center">
                        <span className="text-slate-500">Availability</span>
                        <span
                          className={`inline-flex items-center gap-1 font-semibold ${
                            isInStock ? 'text-emerald-400' : 'text-rose-400'
                          }`}
                        >
                          {isInStock ? (
                            <>
                              <Check className="w-3 h-3" /> {p.quantity ?? 10} in stock
                            </>
                          ) : (
                            <>
                              <AlertTriangle className="w-3 h-3" /> Out of stock
                            </>
                          )}
                        </span>
                      </div>

                      <div className="flex justify-between items-center">
                        <span className="text-slate-500">Category</span>
                        <span className="text-slate-300 font-medium">{p.category || 'Electronics'}</span>
                      </div>

                      <div className="flex justify-between items-center">
                        <span className="text-slate-500">Rating</span>
                        <span className="flex items-center gap-1 text-amber-400 font-bold">
                          <Star className="w-3 h-3 fill-current" /> {p.rating || 4.8}
                        </span>
                      </div>

                      <button
                        onClick={() => {
                          addToCart(p, 1);
                          showToast('Added to Cart', `${p.name} added to cart`, 'order');
                        }}
                        disabled={!isInStock}
                        className="w-full mt-2 py-2.5 px-3 rounded-xl bg-indigo-600 hover:bg-indigo-700 disabled:opacity-40 text-white font-bold text-xs shadow-md shadow-indigo-500/20 flex items-center justify-center gap-1.5 transition active:scale-95"
                      >
                        <ShoppingBag className="w-3.5 h-3.5" />
                        Add to Cart
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
