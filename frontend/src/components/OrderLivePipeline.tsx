import React from 'react';
import { Check, CheckCircle2, Clock, Truck, XCircle } from 'lucide-react';
import { getOrderFulfillmentStageIndex, ORDER_FULFILLMENT_STAGES } from '../utils/orderFulfillment';

interface OrderLivePipelineProps {
  orderNumber: string;
  carrier?: string;
  trackingNumber?: string;
  initialStatus: string;
}

export const OrderLivePipeline: React.FC<OrderLivePipelineProps> = ({
  orderNumber,
  carrier,
  trackingNumber,
  initialStatus,
}) => {
  const status = (initialStatus || 'PLACED').toUpperCase();
  const isCancelled = status === 'CANCELLED';
  const currentIndex = getOrderFulfillmentStageIndex(status);

  if (isCancelled) {
    return (
      <div className="p-4 rounded-2xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 flex items-center gap-3">
        <XCircle className="w-5 h-5 shrink-0 text-rose-500" />
        <div className="text-xs">
          <strong className="font-bold block text-rose-700 dark:text-rose-400 text-sm">Order Cancelled</strong>
          <span>The order status is cancelled in Orders Service.</span>
        </div>
      </div>
    );
  }

  return (
    <section
      aria-label={`Persisted fulfillment status for order ${orderNumber}`}
      className="p-5 rounded-2xl bg-white/70 dark:bg-slate-900/60 border border-slate-200/80 dark:border-slate-800/80 shadow-sm space-y-5"
    >
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pb-3 border-b border-slate-100 dark:border-slate-800/80">
        <div>
          <h3 className="text-xs font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">Order fulfillment</h3>
          <p className="text-[11px] text-slate-500 dark:text-slate-400">Status is read from Orders Service and refreshes automatically.</p>
        </div>
        {trackingNumber && (
          <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md font-mono text-[10px] bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 border border-slate-200 dark:border-slate-700">
            <Truck className="w-3 h-3 text-indigo-500" />
            {carrier || 'Carrier'}: {trackingNumber}
          </span>
        )}
      </div>

      <ol className="grid grid-cols-3 gap-2">
        {ORDER_FULFILLMENT_STAGES.map(({ status: stageStatus, title, detail }, index) => {
          const Icon = stageStatus === 'PLACED' ? Clock : stageStatus === 'SHIPPED' ? Truck : CheckCircle2;
          const isComplete = currentIndex > index;
          const isCurrent = currentIndex === index;
          const isPending = currentIndex < 0 || currentIndex < index;
          return (
            <li key={stageStatus} aria-current={isCurrent ? 'step' : undefined} className="relative flex flex-col items-center text-center">
              {index < ORDER_FULFILLMENT_STAGES.length - 1 && (
                <span className={`absolute top-4 left-1/2 w-full h-1 ${isComplete ? 'bg-emerald-500' : 'bg-slate-200 dark:bg-slate-800'}`} />
              )}
              <span className={`relative z-10 mb-2 w-8 h-8 rounded-full flex items-center justify-center ${
                isComplete ? 'bg-emerald-500 text-white' : isCurrent ? 'bg-indigo-600 text-white ring-4 ring-indigo-500/20' : 'bg-slate-100 dark:bg-slate-800 text-slate-400 border border-slate-300 dark:border-slate-700'
              }`}>
                {isComplete ? <Check className="w-4 h-4" /> : <Icon className="w-4 h-4" />}
              </span>
              <span className={`text-[11px] font-bold ${isPending ? 'text-slate-400 dark:text-slate-500' : isComplete ? 'text-emerald-600 dark:text-emerald-400' : 'text-indigo-600 dark:text-indigo-400'}`}>{title}</span>
              <span className="mt-0.5 text-[10px] text-slate-500 dark:text-slate-400">{detail}</span>
            </li>
          );
        })}
      </ol>
    </section>
  );
};
