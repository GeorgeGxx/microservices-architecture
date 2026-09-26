import React, { useEffect, useRef } from 'react';
import { Product } from '../types';
import QRCode from 'qrcode';
import { X, Download, Copy, Check } from 'lucide-react';

interface ProductQRModalProps {
  product: Product | null;
  onClose: () => void;
}

export const ProductQRModal: React.FC<ProductQRModalProps> = ({ product, onClose }) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [copied, setCopied] = React.useState(false);

  useEffect(() => {
    if (product && canvasRef.current) {
      const qrData = JSON.stringify({
        sku: product.sku,
        name: product.name,
        price: product.price,
        timestamp: new Date().toISOString(),
      });

      QRCode.toCanvas(canvasRef.current, qrData, {
        width: 240,
        margin: 2,
        color: {
          dark: '#0f172a',
          light: '#ffffff',
        },
      });
    }
  }, [product]);

  if (!product) return null;

  const handleCopy = () => {
    navigator.clipboard.writeText(product.sku);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDownload = () => {
    if (canvasRef.current) {
      const url = canvasRef.current.toDataURL('image/png');
      const a = document.createElement('a');
      a.download = `QR-${product.sku}.png`;
      a.href = url;
      a.click();
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in">
      <div className="relative w-full max-w-sm bg-slate-900 border border-slate-800 rounded-2xl shadow-2xl p-6 text-center">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 p-1.5 text-slate-400 hover:text-white rounded-lg hover:bg-slate-800 transition"
        >
          <X className="w-4 h-4" />
        </button>

        <h3 className="text-lg font-bold text-white mb-1">Product Barcode Label</h3>
        <p className="text-xs text-slate-400 mb-4">{product.name}</p>

        {/* QR Canvas */}
        <div className="bg-white p-4 rounded-xl inline-block shadow-inner mb-4">
          <canvas ref={canvasRef} className="mx-auto block" />
        </div>

        <div className="bg-slate-950/80 border border-slate-800 rounded-xl p-3 mb-4 text-left">
          <div className="flex justify-between items-center text-xs">
            <span className="text-slate-500 font-medium">SKU Identifier</span>
            <button
              onClick={handleCopy}
              className="flex items-center gap-1 text-indigo-400 hover:text-indigo-300 font-mono text-[11px]"
            >
              {copied ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
              {product.sku}
            </button>
          </div>
          <div className="flex justify-between items-center text-xs mt-1.5">
            <span className="text-slate-500 font-medium">Catalog Price</span>
            <span className="text-slate-200 font-bold font-mono">${product.price.toFixed(2)}</span>
          </div>
        </div>

        <div className="flex gap-2">
          <button
            onClick={handleDownload}
            className="flex-1 py-2.5 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-xs flex items-center justify-center gap-2 transition shadow-lg shadow-indigo-500/20"
          >
            <Download className="w-4 h-4" />
            Download QR
          </button>
          <button
            onClick={onClose}
            className="py-2.5 px-4 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 font-medium text-xs transition"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
};
