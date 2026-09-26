import React from 'react';
import { Order } from '../types';
import { useCurrency } from '../context/CurrencyContext';
import { X, Printer, PackageCheck, Copy, Check, Truck, ShieldAlert } from 'lucide-react';

interface ReceiptModalProps {
  order: Order | null;
  onClose: () => void;
}

export const ReceiptModal: React.FC<ReceiptModalProps> = ({ order, onClose }) => {
  const { formatPrice } = useCurrency();
  const [copied, setCopied] = React.useState(false);

  if (!order) return null;

  const tracking = order.trackingNumber || `DHL-EXP-${order.orderNumber.replace(/[^0-9]/g, '').slice(-8) || '84729103'}`;

  const handleCopyTracking = () => {
    navigator.clipboard.writeText(tracking);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in">
      <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-2xl shadow-2xl p-6 md:p-8 max-h-[90vh] overflow-y-auto">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 p-2 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Header Icon */}
        <div className="text-center mb-6">
          <div className="w-12 h-12 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 flex items-center justify-center mx-auto mb-3 shadow-lg shadow-emerald-500/10">
            <PackageCheck className="w-6 h-6" />
          </div>
          <h3 className="text-xl font-bold text-white">Order Receipt & Tracking</h3>
          <p className="text-xs font-mono text-slate-400 mt-1">#{order.orderNumber}</p>
        </div>

        {/* Tracking Card */}
        <div className="p-4 rounded-xl bg-slate-950 border border-slate-800 mb-5">
          <div className="flex items-center justify-between text-xs mb-1.5">
            <div className="flex items-center gap-1.5 text-indigo-400 font-semibold">
              <Truck className="w-4 h-4" />
              <span>{order.carrier || 'DHL Express Priority'}</span>
            </div>
            <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/30">
              {order.orderStatus || 'CONFIRMED'}
            </span>
          </div>
          <div className="flex items-center justify-between mt-2 pt-2 border-t border-slate-800/80 text-xs">
            <span className="text-slate-400">Tracking Code:</span>
            <button
              onClick={handleCopyTracking}
              className="flex items-center gap-1 text-slate-200 font-mono text-[11px] bg-slate-900 px-2 py-1 rounded hover:bg-slate-800 transition"
            >
              {copied ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
              {tracking}
            </button>
          </div>
        </div>

        {/* Customer & Shipping Details */}
        <div className="grid grid-cols-2 gap-3 text-xs p-3.5 rounded-xl bg-slate-950/60 border border-slate-800/60 mb-5 text-slate-400">
          <div>
            <span className="text-slate-500 block mb-0.5">Customer</span>
            <span className="text-slate-200 font-semibold">{order.customerName || 'Anonymous Customer'}</span>
            <span className="text-[11px] text-slate-500 block">{order.customerEmail}</span>
          </div>
          <div>
            <span className="text-slate-500 block mb-0.5">Shipping Destination</span>
            <span className="text-slate-200 font-medium">{order.city || 'Springfield'}, {order.postalCode}</span>
            <span className="text-[11px] text-slate-500 block">{order.shippingAddress}</span>
          </div>
        </div>

        {/* Order Items */}
        <div className="border-t border-b border-slate-800 py-3 mb-5 space-y-2 max-h-48 overflow-y-auto">
          {order.orderItems?.map((item, idx) => (
            <div key={idx} className="flex justify-between items-center text-xs">
              <div className="min-w-0 pr-2">
                <span className="text-slate-200 font-medium truncate block">
                  {item.product?.name || item.sku}
                </span>
                <span className="text-[10px] text-slate-500 font-mono">
                  Qty: {item.quantity} × {formatPrice(item.price)}
                </span>
              </div>
              <span className="text-slate-100 font-bold font-mono">
                {formatPrice(item.price * item.quantity)}
              </span>
            </div>
          ))}
        </div>

        {/* Totals */}
        <div className="space-y-1.5 text-xs text-slate-400 mb-6">
          <div className="flex justify-between">
            <span>Payment Method</span>
            <span className="text-slate-200 font-medium">{order.paymentMethod || 'Credit Card'}</span>
          </div>
          <div className="flex justify-between text-base font-extrabold text-white pt-2 border-t border-slate-800">
            <span>Total Paid</span>
            <span className="text-indigo-400">{formatPrice(order.totalAmount || 0)}</span>
          </div>
        </div>

        {/* Actions */}
        <div className="flex gap-2">
          <button
            onClick={handlePrint}
            className="flex-1 py-2.5 px-4 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 font-medium text-xs flex items-center justify-center gap-2 transition"
          >
            <Printer className="w-4 h-4" />
            Print Receipt
          </button>
          <button
            onClick={onClose}
            className="py-2.5 px-6 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-xs transition shadow-lg shadow-indigo-500/20"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
