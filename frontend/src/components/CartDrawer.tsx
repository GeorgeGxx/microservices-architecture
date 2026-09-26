import React from 'react';
import { useCart } from '../context/CartContext';
import { useCurrency } from '../context/CurrencyContext';
import { useAuth } from '../context/AuthContext';
import { X, Plus, Minus, Trash2, ShoppingBag, ArrowRight } from 'lucide-react';

interface CartDrawerProps {
  onOpenCheckout: () => void;
}

export const CartDrawer: React.FC<CartDrawerProps> = ({ onOpenCheckout }) => {
  const { cart, isCartOpen, setIsCartOpen, updateQuantity, removeFromCart, subtotal, shipping, total, itemCount } = useCart();
  const { formatPrice } = useCurrency();
  const { user, login } = useAuth();

  if (!isCartOpen) return null;

  const freeShippingThreshold = 100;
  const progressPercent = Math.min(100, (subtotal / freeShippingThreshold) * 100);

  return (
    <div className="fixed inset-0 z-50 overflow-hidden">
      <div
        className="absolute inset-0 bg-slate-950/70 backdrop-blur-sm transition-opacity"
        onClick={() => setIsCartOpen(false)}
      />
      <div className="fixed inset-y-0 right-0 max-w-full flex pl-10">
        <div className="w-screen max-w-md bg-slate-900 border-l border-slate-800 p-6 flex flex-col shadow-2xl">
          <div className="flex items-center justify-between pb-4 border-b border-slate-800">
            <div className="flex items-center gap-2">
              <ShoppingBag className="w-5 h-5 text-indigo-400" />
              <h3 className="text-lg font-bold text-white">Your Cart ({itemCount})</h3>
            </div>
            <button
              onClick={() => setIsCartOpen(false)}
              className="p-1.5 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Free Shipping Progress Indicator */}
          {subtotal > 0 && (
            <div className="py-3 px-3 bg-slate-950/60 rounded-xl border border-slate-800/80 my-3">
              <div className="flex justify-between text-xs mb-1.5">
                <span className="text-slate-400">
                  {subtotal >= freeShippingThreshold ? (
                    <span className="text-emerald-400 font-semibold">🎉 Free Express Shipping Unlocked!</span>
                  ) : (
                    <>Add <span className="text-indigo-400 font-bold">{formatPrice(freeShippingThreshold - subtotal)}</span> for Free Shipping</>
                  )}
                </span>
                <span className="text-slate-500 font-mono text-[11px]">{Math.round(progressPercent)}%</span>
              </div>
              <div className="w-full bg-slate-800 h-1.5 rounded-full overflow-hidden">
                <div
                  className="bg-gradient-to-r from-indigo-500 to-emerald-400 h-full transition-all duration-300 rounded-full"
                  style={{ width: `${progressPercent}%` }}
                />
              </div>
            </div>
          )}

          {/* Items List */}
          <div className="flex-1 overflow-y-auto py-2 space-y-3">
            {cart.length === 0 ? (
              <div className="text-center py-20 text-slate-500">
                <ShoppingBag className="w-12 h-12 mx-auto mb-3 opacity-30" />
                <p className="text-base font-medium text-slate-400">Your shopping cart is empty</p>
                <p className="text-xs text-slate-500 mt-1">Explore our product catalog and add items.</p>
              </div>
            ) : (
              cart.map(({ product, quantity }) => (
                <div
                  key={product.sku}
                  className="flex gap-3.5 p-3 rounded-xl bg-slate-950/40 border border-slate-800/70 hover:border-slate-700 transition"
                >
                  <img
                    src={product.imageUrl || 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=200'}
                    alt={product.name}
                    className="w-16 h-16 rounded-lg object-cover bg-slate-800 shrink-0"
                  />
                  <div className="flex-1 min-w-0 flex flex-col justify-between">
                    <div>
                      <div className="flex justify-between items-start">
                        <h4 className="text-xs font-semibold text-slate-100 truncate pr-2">{product.name}</h4>
                        <button
                          onClick={() => removeFromCart(product.sku)}
                          className="text-slate-500 hover:text-red-400 transition p-0.5"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                      <p className="text-[11px] text-slate-400 font-mono mt-0.5">{product.sku}</p>
                    </div>

                    <div className="flex justify-between items-center mt-2">
                      <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 rounded-lg p-0.5">
                        <button
                          onClick={() => updateQuantity(product.sku, quantity - 1)}
                          className="p-1 text-slate-400 hover:text-white rounded"
                        >
                          <Minus className="w-3 h-3" />
                        </button>
                        <span className="text-xs font-bold text-white px-1.5">{quantity}</span>
                        <button
                          onClick={() => updateQuantity(product.sku, quantity + 1)}
                          className="p-1 text-slate-400 hover:text-white rounded"
                        >
                          <Plus className="w-3 h-3" />
                        </button>
                      </div>
                      <span className="text-xs font-bold text-indigo-400">
                        {formatPrice(product.price * quantity)}
                      </span>
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>

          {/* Footer Summary */}
          {cart.length > 0 && (
            <div className="pt-4 border-t border-slate-800 space-y-3">
              <div className="space-y-1.5 text-xs text-slate-400">
                <div className="flex justify-between">
                  <span>Subtotal</span>
                  <span className="text-slate-200 font-medium">{formatPrice(subtotal)}</span>
                </div>
                <div className="flex justify-between">
                  <span>Estimated Shipping</span>
                  <span className="text-slate-200 font-medium">
                    {shipping === 0 ? <span className="text-emerald-400 font-semibold">FREE</span> : formatPrice(shipping)}
                  </span>
                </div>
                <div className="flex justify-between pt-2 border-t border-slate-800 text-sm font-bold text-white">
                  <span>Total</span>
                  <span className="text-indigo-400 text-base">{formatPrice(total)}</span>
                </div>
              </div>

              {user ? (
                <button
                  onClick={() => {
                    setIsCartOpen(false);
                    onOpenCheckout();
                  }}
                  className="w-full py-3 px-4 rounded-xl bg-gradient-to-r from-indigo-500 to-indigo-600 hover:from-indigo-600 hover:to-indigo-700 text-white font-semibold text-sm shadow-lg shadow-indigo-500/25 flex items-center justify-center gap-2 transition-all transform active:scale-95"
                >
                  Proceed to Checkout
                  <ArrowRight className="w-4 h-4" />
                </button>
              ) : (
                <button
                  onClick={() => {
                    setIsCartOpen(false);
                    login();
                  }}
                  className="w-full py-3 px-4 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-100 font-semibold text-sm border border-slate-700 shadow-md flex items-center justify-center gap-2 transition-all transform active:scale-95"
                >
                  Sign In with Keycloak to Checkout
                  <ArrowRight className="w-4 h-4" />
                </button>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
