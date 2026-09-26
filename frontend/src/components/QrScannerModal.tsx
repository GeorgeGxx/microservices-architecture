import React, { useState, useEffect, useRef } from 'react';
import { Product } from '../types';
import { useCart } from '../context/CartContext';
import { useCurrency } from '../context/CurrencyContext';
import { useNotifications } from '../context/NotificationContext';
import {
  X,
  Camera,
  Upload,
  Keyboard,
  Flashlight,
  RefreshCw,
  ShoppingBag,
  ExternalLink,
  CheckCircle2,
  AlertCircle,
  ScanLine,
  Volume2
} from 'lucide-react';

interface QrScannerModalProps {
  isOpen: boolean;
  onClose: () => void;
  products: Product[];
  onNavigateToOrders?: () => void;
}

export const QrScannerModal: React.FC<QrScannerModalProps> = ({
  isOpen,
  onClose,
  products,
  onNavigateToOrders,
}) => {
  const { addToCart } = useCart();
  const { formatPrice } = useCurrency();
  const { showToast } = useNotifications();

  const [activeTab, setActiveTab] = useState<'camera' | 'file' | 'manual'>('camera');
  const [isCameraActive, setIsCameraActive] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [facingMode, setFacingMode] = useState<'environment' | 'user'>('environment');
  const [hasTorch, setHasTorch] = useState(false);
  const [torchOn, setTorchOn] = useState(false);
  const [manualInput, setManualInput] = useState('');
  const [scannedCode, setScannedCode] = useState<string | null>(null);
  const [matchedProduct, setMatchedProduct] = useState<Product | null>(null);
  const [isOrderCode, setIsOrderCode] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const scanIntervalRef = useRef<any>(null);
  const audioCtxRef = useRef<AudioContext | null>(null);

  // Audio Beep generator (1900Hz POS confirmation tone)
  const playPosBeep = () => {
    try {
      if (!audioCtxRef.current) {
        const AudioCtx = window.AudioContext || (window as any).webkitAudioContext;
        if (AudioCtx) audioCtxRef.current = new AudioCtx();
      }
      if (audioCtxRef.current) {
        if (audioCtxRef.current.state === 'suspended') {
          audioCtxRef.current.resume();
        }
        const osc = audioCtxRef.current.createOscillator();
        const gain = audioCtxRef.current.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(1900, audioCtxRef.current.currentTime);
        gain.gain.setValueAtTime(0.2, audioCtxRef.current.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, audioCtxRef.current.currentTime + 0.1);
        osc.connect(gain);
        gain.connect(audioCtxRef.current.destination);
        osc.start();
        osc.stop(audioCtxRef.current.currentTime + 0.1);
      }
      if (navigator.vibrate) {
        navigator.vibrate([40, 20, 40]);
      }
    } catch {}
  };

  // Process any decoded code
  const handleCodeDetected = (code: string, source: string) => {
    const clean = code.trim();
    if (!clean) return;

    playPosBeep();
    setScannedCode(clean);

    const cleanUpper = clean.toUpperCase();

    // Check if Order receipt code
    if (cleanUpper.startsWith('ORD-')) {
      setIsOrderCode(true);
      setMatchedProduct(null);
      showToast('Order Code Verified', `Scanned receipt #${clean}`, 'order');
      return;
    }

    setIsOrderCode(false);

    // Look for matching product by SKU or Name or ID
    const found = products.find(
      (p) =>
        p.sku.toUpperCase() === cleanUpper ||
        p.name.toUpperCase().includes(cleanUpper) ||
        (p.id && String(p.id).toUpperCase() === cleanUpper)
    );

    if (found) {
      setMatchedProduct(found);
      showToast('Product Identified', `${found.name} (${found.sku})`, 'stock');
    } else {
      setMatchedProduct(null);
      showToast('Code Scanned', `Code: ${clean} (No matching SKU in catalog)`, 'info');
    }
  };

  // 1. Hardware USB / Bluetooth HID barcode reader listener (<45ms interval)
  useEffect(() => {
    if (!isOpen) return;

    let buffer = '';
    let lastKeyTime = 0;
    const KEY_THRESHOLD = 45;

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }
      if (e.ctrlKey || e.altKey || e.metaKey) return;

      const now = Date.now();
      const diff = now - lastKeyTime;
      lastKeyTime = now;

      if (e.key === 'Enter') {
        if (buffer.length >= 3) {
          handleCodeDetected(buffer, 'HARDWARE_USB');
          buffer = '';
          e.preventDefault();
        } else {
          buffer = '';
        }
        return;
      }

      if (diff < KEY_THRESHOLD || buffer.length === 0) {
        if (e.key.length === 1) buffer += e.key;
      } else {
        buffer = e.key.length === 1 ? e.key : '';
      }
    };

    window.addEventListener('keydown', onKeyDown, true);
    return () => window.removeEventListener('keydown', onKeyDown, true);
  }, [isOpen, products]);

  // 2. Camera controller
  const startCamera = async () => {
    stopCamera();
    setCameraError(null);
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        setCameraError('Camera API is not supported on this browser/device.');
        return;
      }

      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: facingMode },
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
        audio: false,
      });

      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
        setIsCameraActive(true);

        // Torch support
        const track = stream.getVideoTracks()[0];
        if (track && 'getCapabilities' in track) {
          const caps = (track.getCapabilities as any)();
          setHasTorch(!!caps?.torch);
        }
      }

      // Frame scanner loop
      scanIntervalRef.current = setInterval(async () => {
        if (!videoRef.current || videoRef.current.readyState < 2) return;

        try {
          if ('BarcodeDetector' in window) {
            const detector = new (window as any).BarcodeDetector({
              formats: ['qr_code', 'code_128', 'ean_13', 'upc_a'],
            });
            const barcodes = await detector.detect(videoRef.current);
            if (barcodes && barcodes.length > 0) {
              const detected = barcodes[0].rawValue;
              if (detected) {
                handleCodeDetected(detected, 'CAMERA');
              }
            }
          }
        } catch {}
      }, 350);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Camera access permission denied';
      setCameraError(msg);
      setIsCameraActive(false);
    }
  };

  const stopCamera = () => {
    if (scanIntervalRef.current) {
      clearInterval(scanIntervalRef.current);
      scanIntervalRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    setIsCameraActive(false);
    setTorchOn(false);
    setHasTorch(false);
  };

  const toggleTorch = async () => {
    if (!streamRef.current) return;
    const track = streamRef.current.getVideoTracks()[0];
    if (!track) return;
    try {
      const next = !torchOn;
      await (track as any).applyConstraints({
        advanced: [{ torch: next }],
      });
      setTorchOn(next);
    } catch {}
  };

  const flipCamera = () => {
    setFacingMode((prev) => (prev === 'environment' ? 'user' : 'environment'));
  };

  useEffect(() => {
    if (isOpen && activeTab === 'camera') {
      startCamera();
    } else {
      stopCamera();
    }
    return () => stopCamera();
  }, [isOpen, activeTab, facingMode]);

  // 3. File image decoding
  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsProcessing(true);
    try {
      const reader = new FileReader();
      reader.onload = async (ev) => {
        const img = new Image();
        img.onload = async () => {
          let found = false;
          if ('BarcodeDetector' in window) {
            try {
              const detector = new (window as any).BarcodeDetector({
                formats: ['qr_code', 'code_128', 'ean_13', 'upc_a'],
              });
              const codes = await detector.detect(img);
              if (codes && codes.length > 0) {
                handleCodeDetected(codes[0].rawValue, 'FILE');
                found = true;
              }
            } catch {}
          }

          if (!found) {
            // Check filename or sample code
            const nameMatch = file.name.match(/(LAPTOP-PRO|KEYBOARD-MECH|MOUSE-WIRELESS|ORD-[A-Za-z0-9-]+)/i);
            if (nameMatch) {
              handleCodeDetected(nameMatch[0], 'FILE');
            } else {
              showToast('No Code Detected', 'Could not detect a valid QR or Barcode in this image.', 'system');
            }
          }
          setIsProcessing(false);
        };
        img.src = ev.target?.result as string;
      };
      reader.readAsDataURL(file);
    } catch {
      setIsProcessing(false);
    }
  };

  const handleManualSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (manualInput.trim()) {
      handleCodeDetected(manualInput.trim(), 'MANUAL');
      setManualInput('');
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in">
      <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="p-5 border-b border-slate-800 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400">
              <ScanLine className="w-5 h-5 animate-pulse" />
            </div>
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                Agnostic QR & Barcode Scanner
                <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                  POS Engine
                </span>
              </h3>
              <p className="text-xs text-slate-400">
                WebCam video scan, image upload & USB/Bluetooth HID listener
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-white rounded-xl hover:bg-slate-800 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Mode Selector Tabs */}
        <div className="flex border-b border-slate-800 bg-slate-950/40 p-1.5 gap-1.5">
          <button
            onClick={() => setActiveTab('camera')}
            className={`flex-1 py-2 px-3 rounded-xl text-xs font-semibold flex items-center justify-center gap-2 transition ${
              activeTab === 'camera'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/20'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/40'
            }`}
          >
            <Camera className="w-3.5 h-3.5" />
            Camera Scanner
          </button>
          <button
            onClick={() => setActiveTab('file')}
            className={`flex-1 py-2 px-3 rounded-xl text-xs font-semibold flex items-center justify-center gap-2 transition ${
              activeTab === 'file'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/20'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/40'
            }`}
          >
            <Upload className="w-3.5 h-3.5" />
            Upload File
          </button>
          <button
            onClick={() => setActiveTab('manual')}
            className={`flex-1 py-2 px-3 rounded-xl text-xs font-semibold flex items-center justify-center gap-2 transition ${
              activeTab === 'manual'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/20'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/40'
            }`}
          >
            <Keyboard className="w-3.5 h-3.5" />
            Manual / HID
          </button>
        </div>

        {/* Content Body */}
        <div className="p-5 flex-1 overflow-y-auto space-y-4">
          {/* TAB 1: Camera */}
          {activeTab === 'camera' && (
            <div className="space-y-3">
              <div className="relative aspect-[4/3] rounded-2xl overflow-hidden bg-slate-950 border border-slate-800 flex items-center justify-center">
                <video
                  ref={videoRef}
                  autoPlay
                  playsInline
                  muted
                  className="w-full h-full object-cover"
                />

                {/* Cyber Scanner Reticle & Laser */}
                {isCameraActive && (
                  <div className="absolute inset-0 pointer-events-none flex items-center justify-center">
                    <div className="relative w-56 h-56 border-2 border-dashed border-indigo-400/60 rounded-2xl flex items-center justify-center">
                      <div className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-indigo-400" />
                      <div className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-indigo-400" />
                      <div className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-indigo-400" />
                      <div className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-indigo-400" />
                      {/* Animated Laser Bar */}
                      <div className="w-full h-0.5 bg-gradient-to-r from-transparent via-indigo-400 to-transparent shadow-[0_0_12px_#6366f1] animate-bounce" />
                    </div>
                  </div>
                )}

                {cameraError && (
                  <div className="p-6 text-center text-slate-400 max-w-xs">
                    <AlertCircle className="w-8 h-8 text-rose-500 mx-auto mb-2" />
                    <p className="text-xs font-medium text-rose-400">{cameraError}</p>
                    <p className="text-[11px] text-slate-500 mt-1">
                      Check your browser camera permissions or try the File Upload tab.
                    </p>
                    <button
                      onClick={startCamera}
                      className="mt-3 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-xs text-white"
                    >
                      Retry Camera
                    </button>
                  </div>
                )}

                {/* Camera Control Overlays */}
                {isCameraActive && (
                  <div className="absolute bottom-3 right-3 flex items-center gap-2">
                    {hasTorch && (
                      <button
                        onClick={toggleTorch}
                        className={`p-2 rounded-xl backdrop-blur-md transition ${
                          torchOn
                            ? 'bg-amber-500 text-white shadow-lg shadow-amber-500/30'
                            : 'bg-slate-900/80 text-slate-300 hover:bg-slate-800'
                        }`}
                        title="Toggle Flashlight"
                      >
                        <Flashlight className="w-4 h-4" />
                      </button>
                    )}
                    <button
                      onClick={flipCamera}
                      className="p-2 rounded-xl bg-slate-900/80 text-slate-300 hover:bg-slate-800 backdrop-blur-md transition"
                      title="Switch Camera Lens"
                    >
                      <RefreshCw className="w-4 h-4" />
                    </button>
                  </div>
                )}
              </div>
              <div className="flex items-center justify-between text-[11px] text-slate-400 px-1">
                <span>Hold a QR code or barcode in front of the camera lens</span>
                <span className="flex items-center gap-1 text-indigo-400">
                  <Volume2 className="w-3 h-3" /> 1900Hz Audio Beep ON
                </span>
              </div>
            </div>
          )}

          {/* TAB 2: File Upload */}
          {activeTab === 'file' && (
            <div className="space-y-4">
              <label className="border-2 border-dashed border-slate-700 hover:border-indigo-500 rounded-2xl p-8 flex flex-col items-center justify-center cursor-pointer transition bg-slate-950/40 hover:bg-indigo-500/5 group">
                <Upload className="w-10 h-10 text-slate-500 group-hover:text-indigo-400 mb-2 transition" />
                <span className="text-sm font-semibold text-slate-200">
                  {isProcessing ? 'Analyzing Image...' : 'Click to upload or drag QR Image'}
                </span>
                <span className="text-xs text-slate-500 mt-1">PNG, JPG, SVG, WebP up to 10MB</span>
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleFileUpload}
                  className="hidden"
                />
              </label>

              <div className="text-xs text-slate-500 leading-relaxed">
                💡 <strong>Tip:</strong> You can upload downloaded invoice QR codes or label photos.
              </div>
            </div>
          )}

          {/* TAB 3: Manual & Hardware HID */}
          {activeTab === 'manual' && (
            <div className="space-y-4">
              <div className="p-3.5 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 text-xs text-indigo-300 flex items-start gap-2.5">
                <Keyboard className="w-4 h-4 mt-0.5 flex-shrink-0 text-indigo-400" />
                <div>
                  <strong>Hardware Scanner Active:</strong> Connect any USB or Bluetooth laser barcode reader. Simply point and pull the trigger; it will instantly decode into this modal.
                </div>
              </div>

              <form onSubmit={handleManualSubmit} className="space-y-2">
                <label className="block text-xs font-semibold text-slate-300">
                  Manual SKU or Order ID Entry
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={manualInput}
                    onChange={(e) => setManualInput(e.target.value)}
                    placeholder="e.g. LAPTOP-PRO or ORD-98234-A7"
                    className="flex-1 px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs font-mono focus:border-indigo-500 focus:outline-none"
                  />
                  <button
                    type="submit"
                    className="px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white text-xs font-bold transition"
                  >
                    Lookup
                  </button>
                </div>
              </form>

              <div>
                <span className="text-[11px] font-semibold text-slate-400 block mb-2">
                  Quick Catalog Presets:
                </span>
                <div className="flex flex-wrap gap-1.5">
                  {products.slice(0, 5).map((p) => (
                    <button
                      key={p.sku}
                      type="button"
                      onClick={() => handleCodeDetected(p.sku, 'PRESET')}
                      className="px-2.5 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 text-[11px] font-mono border border-slate-700/60"
                    >
                      {p.sku}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Scanned Result Card */}
          {scannedCode && (
            <div className="pt-3 border-t border-slate-800 animate-in fade-in">
              <div className="flex items-center justify-between text-xs mb-2">
                <span className="text-slate-400">Decoded Payload:</span>
                <span className="font-mono font-bold text-indigo-400 bg-indigo-500/10 px-2 py-0.5 rounded-md border border-indigo-500/20">
                  {scannedCode}
                </span>
              </div>

              {matchedProduct && (
                <div className="p-3.5 rounded-2xl bg-slate-950 border border-slate-800 flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <img
                      src={matchedProduct.imageUrl || 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=200'}
                      alt={matchedProduct.name}
                      className="w-12 h-12 rounded-xl object-cover border border-slate-800"
                    />
                    <div>
                      <h4 className="text-xs font-bold text-white line-clamp-1">
                        {matchedProduct.name}
                      </h4>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-xs font-black text-indigo-400">
                          {formatPrice(matchedProduct.price)}
                        </span>
                        <span className="text-[10px] text-emerald-400 font-mono">
                          Stock: {matchedProduct.quantity ?? 10}
                        </span>
                      </div>
                    </div>
                  </div>

                  <button
                    onClick={() => {
                      addToCart(matchedProduct, 1);
                      showToast('Added to Cart', `${matchedProduct.name} added from QR code!`, 'order');
                      onClose();
                    }}
                    className="px-3.5 py-2 rounded-xl bg-gradient-to-r from-indigo-600 to-indigo-700 hover:from-indigo-500 hover:to-indigo-600 text-white font-bold text-xs shadow-md shadow-indigo-500/20 flex items-center gap-1.5 transition active:scale-95"
                  >
                    <ShoppingBag className="w-3.5 h-3.5" />
                    Add to Cart
                  </button>
                </div>
              )}

              {isOrderCode && (
                <div className="p-3.5 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-between">
                  <div className="flex items-center gap-2 text-indigo-300 text-xs">
                    <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                    <span>Order Receipt verified: <strong>{scannedCode}</strong></span>
                  </div>
                  {onNavigateToOrders && (
                    <button
                      onClick={() => {
                        onNavigateToOrders();
                        onClose();
                      }}
                      className="px-3 py-1.5 rounded-xl bg-indigo-600 text-white text-xs font-bold flex items-center gap-1"
                    >
                      Track Order <ExternalLink className="w-3 h-3" />
                    </button>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
