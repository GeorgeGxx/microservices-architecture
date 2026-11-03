import React, { useEffect } from 'react';
import { useNotifications } from '../context/NotificationContext';
import { X, Bell, CheckCheck, Trash2, Package, AlertCircle } from 'lucide-react';

export const NotificationDrawer: React.FC = () => {
  const { notifications, isDrawerOpen, setIsDrawerOpen, markAllAsRead, clearNotifications } = useNotifications();

  useEffect(() => {
    if (!isDrawerOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsDrawerOpen(false);
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isDrawerOpen, setIsDrawerOpen]);

  if (!isDrawerOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-hidden">
      <button
        type="button"
        aria-label="Close notifications backdrop"
        className="absolute inset-0 w-full h-full bg-slate-950/60 backdrop-blur-sm transition-opacity border-none cursor-default p-0"
        onClick={() => setIsDrawerOpen(false)}
      />
      <div className="fixed inset-y-0 right-0 max-w-full flex sm:pl-8 pl-0">
        <div className="w-full sm:w-screen sm:max-w-sm bg-slate-900 border-l border-slate-800 p-4 sm:p-5 flex flex-col shadow-2xl">
          <div className="flex items-center justify-between pb-3.5 border-b border-slate-800">
            <div className="flex items-center gap-2">
              <Bell className="w-4 h-4 text-indigo-400" />
              <h3 className="text-sm sm:text-base font-bold text-white">Live Event Notifications</h3>
            </div>
            <div className="flex items-center gap-1.5">
              {notifications.length > 0 && (
                <>
                  <button
                    onClick={markAllAsRead}
                    title="Mark all as read"
                    className="p-1.5 text-slate-400 hover:text-indigo-400 rounded-lg hover:bg-slate-800 transition"
                  >
                    <CheckCheck className="w-3.5 h-3.5" />
                  </button>
                  <button
                    onClick={clearNotifications}
                    title="Clear all notifications"
                    className="p-1.5 text-slate-400 hover:text-rose-400 rounded-lg hover:bg-slate-800 transition"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </>
              )}
              <button
                onClick={() => setIsDrawerOpen(false)}
                className="p-1.5 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition"
                aria-label="Close drawer"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          </div>

          <div className="flex-1 overflow-y-auto py-3 space-y-2.5">
            {notifications.length === 0 ? (
              <div className="text-center py-16 text-slate-500">
                <Bell className="w-10 h-10 mx-auto mb-2.5 opacity-30" />
                <p className="text-xs font-medium text-slate-400">No notifications yet.</p>
                <p className="text-[11px] text-slate-600 mt-1">Real-time SSE events will appear here.</p>
              </div>
            ) : (
              notifications.map((notif) => (
                <div
                  key={notif.id}
                  className={`p-3 rounded-lg border transition-all ${
                    notif.read
                      ? 'bg-slate-950/40 border-slate-800/60 opacity-70'
                      : 'bg-slate-800/60 border-indigo-500/30 shadow-md'
                  }`}
                >
                  <div className="flex items-start gap-2.5">
                    {notif.type === 'order' ? (
                      <Package className="w-3.5 h-3.5 text-emerald-400 shrink-0 mt-0.5" />
                    ) : (
                      <AlertCircle className="w-3.5 h-3.5 text-indigo-400 shrink-0 mt-0.5" />
                    )}
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-semibold text-slate-200">{notif.title}</p>
                      <p className="text-[11px] text-slate-400 mt-0.5 leading-snug">{notif.message}</p>
                      <span className="text-[10px] text-slate-500 mt-1 block">
                        {new Date(notif.timestamp).toLocaleTimeString()}
                      </span>
                    </div>
                  </div>
                </div>
              ))
            )}
            {notifications.length > 0 && (
              <div className="pt-2.5 border-t border-slate-800/80 flex justify-center">
                <button
                  onClick={clearNotifications}
                  className="inline-flex items-center gap-1.5 px-2.5 py-1 text-[11px] text-slate-400 hover:text-rose-400 hover:bg-slate-800/70 rounded-lg transition"
                >
                  <Trash2 className="w-3 h-3" />
                  Clear notification history
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
