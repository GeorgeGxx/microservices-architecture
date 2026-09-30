import React from 'react';
import { useNotifications } from '../context/NotificationContext';
import { CheckCircle2, AlertTriangle, Info, Bell, X } from 'lucide-react';

export const ToastContainer: React.FC = () => {
  const { toasts, removeToast } = useNotifications();

  if (toasts.length === 0) return null;

  return (
    <div
      aria-label="Notifications"
      aria-live="polite"
      aria-relevant="additions text"
      className="pointer-events-none fixed bottom-6 right-4 z-50 flex max-h-[min(70vh,600px)] w-[calc(100vw-2rem)] flex-col space-y-3 overflow-y-auto sm:right-6 sm:w-full sm:max-w-md"
    >
      {toasts.map((toast) => {
        let Icon = Info;
        let colorClasses = 'border-indigo-500/30 bg-slate-900/90 text-indigo-400';

        if (toast.type === 'order') {
          Icon = CheckCircle2;
          colorClasses = 'border-emerald-500/30 bg-slate-900/90 text-emerald-400';
        } else if (toast.type === 'stock') {
          Icon = AlertTriangle;
          colorClasses = 'border-amber-500/30 bg-slate-900/90 text-amber-400';
        } else if (toast.type === 'system') {
          Icon = Bell;
          colorClasses = 'border-purple-500/30 bg-slate-900/90 text-purple-400';
        }

        return (
          <div
            key={toast.id}
            className={`pointer-events-auto flex items-start gap-3 p-4 rounded-xl border shadow-2xl backdrop-blur-xl transition-all duration-300 transform translate-y-0 opacity-100 ${colorClasses}`}
          >
            <Icon className="w-5 h-5 shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <h4 className="text-sm font-semibold text-slate-100">{toast.title}</h4>
              <p className="text-xs text-slate-400 mt-0.5 break-words">{toast.message}</p>
            </div>
            <button
              onClick={() => removeToast(toast.id)}
              aria-label={`Dismiss notification: ${toast.title}`}
              className="text-slate-400 hover:text-slate-200 transition-colors p-1"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        );
      })}
    </div>
  );
};
