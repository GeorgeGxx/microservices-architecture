import React, { createContext, useContext, useState, useEffect } from 'react';
import { AppNotification } from '../types';
import { sseService } from '../services/sse';
import { useAuth } from './AuthContext';

interface Toast {
  id: string;
  title: string;
  message: string;
  type: 'order' | 'stock' | 'system' | 'info';
}

interface NotificationContextType {
  notifications: AppNotification[];
  toasts: Toast[];
  unreadCount: number;
  markAllAsRead: () => void;
  removeToast: (id: string) => void;
  showToast: (title: string, message: string, type?: Toast['type']) => void;
  isDrawerOpen: boolean;
  setIsDrawerOpen: (open: boolean) => void;
}

const NotificationContext = createContext<NotificationContextType>({
  notifications: [],
  toasts: [],
  unreadCount: 0,
  markAllAsRead: () => {},
  removeToast: () => {},
  showToast: () => {},
  isDrawerOpen: false,
  setIsDrawerOpen: () => {},
});

export const NotificationProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();

  const [notifications, setNotifications] = useState<AppNotification[]>(() => {
    if (!user) return [];
    try {
      const saved = localStorage.getItem(`novashop_notifications_${user.username}`);
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  });

  const [toasts, setToasts] = useState<Toast[]>([]);
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);

  // Sync user notifications when authenticated user changes
  useEffect(() => {
    if (!user) {
      setNotifications([]);
      return;
    }
    try {
      const saved = localStorage.getItem(`novashop_notifications_${user.username}`);
      setNotifications(saved ? JSON.parse(saved) : []);
    } catch {
      setNotifications([]);
    }
  }, [user?.username]);

  // Persist notifications for current authenticated user
  useEffect(() => {
    if (user) {
      localStorage.setItem(`novashop_notifications_${user.username}`, JSON.stringify(notifications));
    }
  }, [notifications, user]);

  const removeToast = (id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  };

  const showToast = (title: string, message: string, type: Toast['type'] = 'info') => {
    const id = `toast-${Date.now()}-${Math.random().toString(36).substr(2, 4)}`;
    const newToast: Toast = { id, title, message, type };
    setToasts((prev) => [...prev, newToast]);

    // Auto dismiss after 5s
    setTimeout(() => {
      removeToast(id);
    }, 5000);
  };

  // SSE subscription: Only append personal notifications to user feed if signed in
  useEffect(() => {
    const unsubscribe = sseService.subscribe((notif) => {
      // In mature e-commerce, show live toast and store in user history if authenticated
      if (user) {
        setNotifications((prev) => [notif, ...prev.slice(0, 49)]); // keep latest 50
        showToast(notif.title, notif.message, notif.type);
      }
    });

    return () => {
      unsubscribe();
    };
  }, [user]);

  const markAllAsRead = () => {
    setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
  };

  const unreadCount = user ? notifications.filter((n) => !n.read).length : 0;

  return (
    <NotificationContext.Provider
      value={{
        notifications,
        toasts,
        unreadCount,
        markAllAsRead,
        removeToast,
        showToast,
        isDrawerOpen,
        setIsDrawerOpen,
      }}
    >
      {children}
    </NotificationContext.Provider>
  );
};

export const useNotifications = () => useContext(NotificationContext);
