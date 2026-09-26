import React from 'react';
import { useNotifications } from '../context/NotificationContext';
import { X, Bell, CheckCheck, Package, AlertCircle } from 'lucide-react';

export const NotificationDrawer: React.FC = () => {
  const { notifications, isDrawerOpen, setIsDrawerOpen, markAllAsRead } = useNotifications();

  if (!isDrawerOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-hidden">
      <div
        className="absolute inset-0 bg-slate-950/60 backdrop-blur-sm transition-opacity"
        onClick={() => setIsDrawerOpen(false)}
      />
      <div className="fixed inset-y-0 right-0 max-w-full flex pl-10">
        <div className="w-screen max-w-md bg-slate-900 border-l border-slate-800 p-6 flex flex-col shadow-2xl">
          <div className="flex items-center justify-between pb-4 border-b border-slate-800">
            <div className="flex items-center gap-2">
              <Bell className="w-5 h-5 text-indigo-400" />
              <h3 className="text-lg font-bold text-white">Live Event Notifications</h3>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={markAllAsRead}
                title="Mark all as read"
                className="p-1.5 text-slate-400 hover:text-indigo-400 rounded-lg hover:bg-slate-800 transition"
              >
                <CheckCheck className="w-4 h-4" />
              </button>
              <button
                onClick={() => setIsDrawerOpen(false)}
                className="p-1.5 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
          </div>

          <div className="flex-1 overflow-y-auto py-4 space-y-3">
            {notifications.length === 0 ? (
              <div className="text-center py-16 text-slate-500">
                <Bell className="w-12 h-12 mx-auto mb-3 opacity-30" />
                <p className="text-sm">No notifications yet.</p>
                <p className="text-xs text-slate-600 mt-1">Real-time SSE events will appear here.</p>
              </div>
            ) : (
              notifications.map((notif) => (
                <div
                  key={notif.id}
                  className={`p-3.5 rounded-xl border transition-all ${
                    notif.read
                      ? 'bg-slate-950/40 border-slate-800/60 opacity-70'
                      : 'bg-slate-800/60 border-indigo-500/30 shadow-lg'
                  }`}
                >
                  <div className="flex items-start gap-2.5">
                    {notif.type === 'order' ? (
                      <Package className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                    ) : (
                      <AlertCircle className="w-4 h-4 text-indigo-400 shrink-0 mt-0.5" />
                    )}
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-semibold text-slate-200">{notif.title}</p>
                      <p className="text-xs text-slate-400 mt-0.5">{notif.message}</p>
                      <span className="text-[10px] text-slate-500 mt-1.5 block">
                        {new Date(notif.timestamp).toLocaleTimeString()}
                      </span>
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
