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
      className="pointer-events-none fixed bottom-4 right-3 z-50 flex max-h-[min(65vh,480px)] w-[calc(100vw-1.5rem)] max-w-[310px] sm:max-w-[320px] flex-col space-y-2 overflow-y-auto sm:bottom-5 sm:right-5"
    >
      {toasts.map((toast) => {
        let Icon = Info;
        let borderClass = 'border-indigo-500/40 hover:border-indigo-500/60';
        let iconColor = 'text-indigo-400';
        let bgGlow = 'from-indigo-950/40';

        if (toast.type === 'order') {
          Icon = CheckCircle2;
          borderClass = 'border-emerald-500/40 hover:border-emerald-500/60';
          iconColor = 'text-emerald-400';
          bgGlow = 'from-emerald-950/40';
        } else if (toast.type === 'stock') {
          Icon = AlertTriangle;
          borderClass = 'border-amber-500/40 hover:border-amber-500/60';
          iconColor = 'text-amber-400';
          bgGlow = 'from-amber-950/40';
        } else if (toast.type === 'system') {
          Icon = Bell;
          borderClass = 'border-purple-500/40 hover:border-purple-500/60';
          iconColor = 'text-purple-400';
          bgGlow = 'from-purple-950/40';
        }

        return (
          <div
            key={toast.id}
            role="status"
            className={`pointer-events-auto relative flex items-start gap-2.5 px-3 py-2.5 rounded-xl border bg-gradient-to-r ${bgGlow} to-slate-900/95 bg-slate-900/95 shadow-xl backdrop-blur-md transition-all duration-200 hover:shadow-2xl ${borderClass}`}
          >
            <div className={`shrink-0 mt-0.5 p-1 rounded-md bg-slate-800/80 ${iconColor}`}>
              <Icon className="w-3.5 h-3.5" />
            </div>
            <div className="flex-1 min-w-0 pr-1">
              <h4 className="text-xs font-semibold text-slate-100 leading-snug truncate">{toast.title}</h4>
              <p className="text-[11px] text-slate-400 mt-0.5 line-clamp-2 leading-tight break-words">{toast.message}</p>
            </div>
            <button
              onClick={() => removeToast(toast.id)}
              aria-label={`Dismiss notification: ${toast.title}`}
              className="text-slate-400 hover:text-slate-200 transition-colors p-0.5 rounded hover:bg-slate-800/60 shrink-0"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        );
      })}
    </div>
  );
};
