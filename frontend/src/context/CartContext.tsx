import React, { createContext, useContext, useState, useEffect, useMemo } from 'react';
import { CartItem, Product } from '../types';
import { CartAggregate } from '../domain/aggregates/CartAggregate';
import { cartStorage } from '../infrastructure/adapters/LocalStorageCartRepository';

interface CartContextType {
  cart: CartItem[];
  aggregate: CartAggregate;
  addToCart: (product: Product, quantity?: number) => void;
  removeFromCart: (sku: string) => void;
  updateQuantity: (sku: string, quantity: number) => void;
  clearCart: () => void;
  subtotal: number;
  shipping: number;
  tax: number;
  total: number;
  itemCount: number;
  qualifiesForFreeShipping: boolean;
  remainingForFreeShipping: number;
  freeShippingProgressPercent: number;
  isCartOpen: boolean;
  setIsCartOpen: (open: boolean) => void;
}

const CartContext = createContext<CartContextType>({
  cart: [],
  aggregate: new CartAggregate([]),
  addToCart: () => {},
  removeFromCart: () => {},
  updateQuantity: () => {},
  clearCart: () => {},
  subtotal: 0,
  shipping: 0,
  tax: 0,
  total: 0,
  itemCount: 0,
  qualifiesForFreeShipping: false,
  remainingForFreeShipping: 100,
  freeShippingProgressPercent: 0,
  isCartOpen: false,
  setIsCartOpen: () => {},
});

export const CartProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [aggregate, setAggregate] = useState<CartAggregate>(() => {
    const saved = cartStorage.load();
    return new CartAggregate(saved);
  });

  const [isCartOpen, setIsCartOpen] = useState(false);

  // Sync to local storage whenever aggregate items change
  useEffect(() => {
    cartStorage.save(aggregate.items);
  }, [aggregate]);

  const addToCart = (product: Product, quantity: number = 1) => {
    setAggregate((prev) => prev.addItem(product, quantity));
    setIsCartOpen(true);
  };

  const removeFromCart = (sku: string) => {
    setAggregate((prev) => prev.removeItem(sku));
  };

  const updateQuantity = (sku: string, quantity: number) => {
    setAggregate((prev) => prev.updateQuantity(sku, quantity));
  };

  const clearCart = () => {
    setAggregate((prev) => prev.clear());
    cartStorage.clear();
  };

  const cart = useMemo(() => [...aggregate.items], [aggregate]);

  return (
    <CartContext.Provider
      value={{
        cart,
        aggregate,
        addToCart,
        removeFromCart,
        updateQuantity,
        clearCart,
        subtotal: aggregate.subtotalAmount,
        shipping: aggregate.shippingAmount,
        tax: aggregate.taxAmount,
        total: aggregate.totalAmount,
        itemCount: aggregate.itemCount,
        qualifiesForFreeShipping: aggregate.qualifiesForFreeShipping,
        remainingForFreeShipping: aggregate.remainingForFreeShipping,
        freeShippingProgressPercent: aggregate.freeShippingProgressPercent,
        isCartOpen,
        setIsCartOpen,
      }}
    >
      {children}
    </CartContext.Provider>
  );
};

export const useCart = () => useContext(CartContext);
