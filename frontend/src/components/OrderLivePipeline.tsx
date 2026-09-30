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
  const status = (initialStatus || '').trim().toUpperCase();
  const isCancelled = status === 'CANCELLED';
  const currentIndex = getOrderFulfillmentStageIndex(status);
  const progress = currentIndex < 0 ? 0 : (currentIndex / (ORDER_FULFILLMENT_STAGES.length - 1)) * 100;

  return (
    <section
      aria-label={`Fulfillment status for order ${orderNumber}`}
      className="overflow-hidden rounded-2xl border border-slate-200/80 bg-white/70 shadow-sm dark:border-slate-800/80 dark:bg-slate-900/60"
    >
      <div className="flex flex-col justify-between gap-3 border-b border-slate-100 px-5 py-4 dark:border-slate-800/80 sm:flex-row sm:items-center">
        <div>
          <h3 className="text-xs font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">Order fulfillment</h3>
          <p className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">
            {isCancelled
              ? 'Cancelled before dispatch. The order service has stopped fulfillment.'
              : 'Progress follows the latest order status recorded by Orders Service.'}
          </p>
        </div>
        {trackingNumber && !isCancelled && (
          <span className="inline-flex items-center gap-1.5 self-start rounded-md border border-slate-200 bg-slate-100 px-2 py-1 font-mono text-[10px] text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300 sm:self-auto">
            <Truck className="h-3 w-3 text-indigo-500" />
            {carrier || 'Carrier'}: {trackingNumber}
          </span>
        )}
      </div>

      {isCancelled ? (
        <div className="flex items-center gap-3 bg-gradient-to-r from-rose-500/10 via-rose-500/5 to-transparent px-5 py-5 text-rose-600 dark:text-rose-400">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-rose-500/20 bg-rose-500/10">
            <XCircle className="h-5 w-5" />
          </span>
          <div>
            <strong className="block text-sm font-bold">Order cancelled</strong>
            <span className="text-xs text-rose-700/80 dark:text-rose-300/80">Cancellation was accepted before dispatch.</span>
          </div>
        </div>
      ) : (
        <div className="px-3 py-6 sm:px-6">
          <div className="relative">
            <div className="absolute left-[16.667%] right-[16.667%] top-4 h-1 rounded-full bg-slate-200 dark:bg-slate-800" />
            <div
              aria-hidden="true"
              className="absolute left-[16.667%] top-4 h-1 rounded-full bg-gradient-to-r from-indigo-500 via-violet-500 to-emerald-400 shadow-[0_0_12px_rgba(99,102,241,0.35)] transition-[width] duration-1000 ease-out motion-reduce:transition-none"
              style={{ width: `calc(${progress * 0.66666}%)` }}
            />
            <ol className="relative grid grid-cols-3 gap-1">
              {ORDER_FULFILLMENT_STAGES.map(({ status: stageStatus, title, detail }, index) => {
                const Icon = stageStatus === 'PLACED' ? Clock : stageStatus === 'SHIPPED' ? Truck : CheckCircle2;
                const isComplete = currentIndex > index;
                const isCurrent = currentIndex === index;
                const isPending = currentIndex < index;
                return (
                  <li key={stageStatus} aria-current={isCurrent ? 'step' : undefined} className="flex min-w-0 flex-col items-center text-center">
                    <span className={`relative z-10 mb-3 flex h-8 w-8 items-center justify-center rounded-full ring-4 ring-white transition-[transform,background-color,box-shadow] duration-500 dark:ring-slate-900 ${
                      isComplete
                        ? 'scale-100 bg-emerald-500 text-white shadow-[0_0_18px_rgba(16,185,129,0.3)]'
                        : isCurrent
                        ? 'scale-110 bg-indigo-600 text-white shadow-[0_0_0_5px_rgba(99,102,241,0.15),0_0_22px_rgba(99,102,241,0.35)]'
                        : 'bg-slate-100 text-slate-400 dark:bg-slate-800 dark:text-slate-500'
                    }`}>
                      {isComplete ? <Check className="h-4 w-4" /> : <Icon className={`h-4 w-4 ${isCurrent && stageStatus === 'SHIPPED' ? 'motion-safe:animate-pulse' : ''}`} />}
                    </span>
                    <span className={`text-[11px] font-bold transition-colors duration-500 ${
                      isPending ? 'text-slate-400 dark:text-slate-500' : isComplete ? 'text-emerald-600 dark:text-emerald-400' : 'text-indigo-600 dark:text-indigo-300'
                    }`}>{title}</span>
                    <span className="mt-1 max-w-32 text-[10px] leading-relaxed text-slate-500 dark:text-slate-400">{detail}</span>
                  </li>
                );
              })}
            </ol>
          </div>
          <div className="mt-5 flex justify-center">
            <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide ${
              currentIndex === 2
                ? 'border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                : currentIndex === 1
                ? 'border-indigo-500/20 bg-indigo-500/10 text-indigo-600 dark:text-indigo-300'
                : 'border-amber-500/20 bg-amber-500/10 text-amber-700 dark:text-amber-300'
            }`}>
              {currentIndex === 1 ? <Truck className="h-3 w-3" /> : currentIndex === 2 ? <CheckCircle2 className="h-3 w-3" /> : <Clock className="h-3 w-3" />}
              {currentIndex === 1 ? 'In transit' : currentIndex === 2 ? 'Delivered' : currentIndex === 0 ? 'Placed' : 'Awaiting status'}
            </span>
          </div>
        </div>
      )}
    </section>
  );
};
