import React, { createContext, useContext, useState, useEffect } from 'react';
import { useAuth } from './AuthContext';
import { useNotifications } from './NotificationContext';

interface WishlistContextType {
  wishlist: string[];
  toggleWishlist: (sku: string) => boolean;
  isInWishlist: (sku: string) => boolean;
  clearWishlist: () => void;
}

const WishlistContext = createContext<WishlistContextType>({
  wishlist: [],
  toggleWishlist: () => false,
  isInWishlist: () => false,
  clearWishlist: () => {},
});

export const WishlistProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user, login } = useAuth();
  const { showToast } = useNotifications();

  const [wishlist, setWishlist] = useState<string[]>(() => {
    if (!user) return [];
    try {
      const saved = localStorage.getItem(`novashop_wishlist_${user.username}`);
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  });

  // Load user-scoped wishlist whenever active user changes
  useEffect(() => {
    if (!user) {
      setWishlist([]);
      return;
    }
    try {
      const saved = localStorage.getItem(`novashop_wishlist_${user.username}`);
      setWishlist(saved ? JSON.parse(saved) : []);
    } catch {
      setWishlist([]);
    }
  }, [user?.username]);

  // Persist user-scoped wishlist
  useEffect(() => {
    if (user) {
      localStorage.setItem(`novashop_wishlist_${user.username}`, JSON.stringify(wishlist));
    }
  }, [wishlist, user]);

  const toggleWishlist = (sku: string): boolean => {
    // Best practice for mature ecommerce: guest favoriting prompts authentication
    if (!user) {
      showToast(
        'Sign In Required',
        'Please sign in to save items to your personal wishlist and sync across devices.',
        'info'
      );
      login();
      return false;
    }

    setWishlist((prev) => {
      const exists = prev.includes(sku);
      if (exists) {
        showToast('Wishlist Updated', `Item ${sku} removed from your saved favorites.`, 'info');
        return prev.filter((s) => s !== sku);
      } else {
        showToast('Saved to Wishlist', `Item ${sku} added to your personal favorites.`, 'info');
        return [...prev, sku];
      }
    });
    return true;
  };

  const isInWishlist = (sku: string) => (user ? wishlist.includes(sku) : false);

  const clearWishlist = () => setWishlist([]);

  return (
    <WishlistContext.Provider value={{ wishlist, toggleWishlist, isInWishlist, clearWishlist }}>
      {children}
    </WishlistContext.Provider>
  );
};

export const useWishlist = () => useContext(WishlistContext);
