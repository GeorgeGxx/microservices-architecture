import React, { useState } from 'react';
import { AlertTriangle, CheckCircle, XCircle } from 'lucide-react';

interface HITLWidgetProps {
  payload: {
    refund_ticket: string;
    order_id: string;
    amount: number;
    reason: string;
  };
  onResolved: (ticketId: string, action: 'APPROVE' | 'REJECT') => void;
}

export const HITLWidget: React.FC<HITLWidgetProps> = ({ payload, onResolved }) => {
  const [resolved, setResolved] = useState<string | null>(null);

  const handleAction = async (action: 'APPROVE' | 'REJECT') => {
    try {
      await fetch('/api/ai/hitl/approve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ticket_id: payload.refund_ticket,
          action: action,
          supervisor_notes: `Manual action via supervisor UI: ${action}`
        })
      });
      setResolved(action);
      onResolved(payload.refund_ticket, action);
    } catch (e) {
      console.error(e);
      setResolved(action);
    }
  };

  return (
    <div className="mt-3 p-3.5 rounded-xl border border-amber-500/40 bg-amber-950/20 text-slate-200">
      <div className="flex items-center gap-2 mb-2 text-amber-400 font-semibold text-xs sm:text-sm">
        <AlertTriangle className="h-4 w-4 shrink-0" />
        <span>Human-in-the-Loop Gate (Amount &gt; $50)</span>
      </div>

      <div className="text-xs space-y-1 mb-3 bg-slate-900/60 dark:bg-slate-900/90 p-2 rounded-lg border border-slate-800 font-mono">
        <div><span className="text-slate-400">Ticket:</span> {payload.refund_ticket}</div>
        <div><span className="text-slate-400">Order ID:</span> {payload.order_id}</div>
        <div><span className="text-slate-400">Amount:</span> <span className="text-emerald-400 font-bold">${payload.amount?.toFixed(2)} USD</span></div>
        <div><span className="text-slate-400">Reason:</span> {payload.reason}</div>
      </div>

      {resolved ? (
        <div className="flex items-center gap-2 text-xs font-medium py-1 px-2 rounded bg-slate-900 border border-slate-800">
          {resolved === 'APPROVE' ? (
            <span className="text-emerald-400 flex items-center gap-1">
              <CheckCircle className="h-3.5 w-3.5" /> Refund Approved by Store Supervisor
            </span>
          ) : (
            <span className="text-rose-400 flex items-center gap-1">
              <XCircle className="h-3.5 w-3.5" /> Refund Denied by Store Supervisor
            </span>
          )}
        </div>
      ) : (
        <div className="flex items-center gap-2">
          <button
            onClick={() => handleAction('APPROVE')}
            className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-semibold shadow-sm transition"
          >
            <CheckCircle className="h-3.5 w-3.5" />
            Authorize Refund
          </button>
          <button
            onClick={() => handleAction('REJECT')}
            className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-rose-950/80 hover:text-rose-300 border border-slate-700 text-slate-300 text-xs font-semibold transition"
          >
            <XCircle className="h-3.5 w-3.5" />
            Reject
          </button>
        </div>
      )}
    </div>
  );
};
