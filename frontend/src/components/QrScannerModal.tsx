import React, { useState, useEffect, useRef, useCallback } from 'react';
import jsQR from 'jsqr';
import { Product, Order } from '../types';
import { useCart } from '../context/CartContext';
import { useCurrency } from '../context/CurrencyContext';
import { useNotifications } from '../context/NotificationContext';
import { useAuth } from '../context/AuthContext';
import {
  fetchInventoryBySku,
  updateStockQuantity,
  recordFunnelTelemetry,
  InventoryDetailResponse
} from '../services/api';
import {
  fetchOrders,
  submitShipOrder,
  submitDeliverOrder
} from '../services/graphql';
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
  Volume2,
  Truck,
  Package,
  Plus,
  FileText
} from 'lucide-react';

interface QrScannerModalProps {
  isOpen: boolean;
  onClose: () => void;
  products: Product[];
  onNavigateToOrders?: () => void;
  onOpenReceipt?: (order: Order) => void;
}

export const QrScannerModal: React.FC<QrScannerModalProps> = ({
  isOpen,
  onClose,
  products,
  onNavigateToOrders,
  onOpenReceipt,
}) => {
  const { user } = useAuth();
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
  const [matchedOrder, setMatchedOrder] = useState<Order | null>(null);
  const [liveInventory, setLiveInventory] = useState<InventoryDetailResponse | null>(null);
  const [isFetchingInventory, setIsFetchingInventory] = useState(false);
  const [isUpdatingStock, setIsUpdatingStock] = useState(false);
  const [isFulfillingOrder, setIsFulfillingOrder] = useState(false);
  const [isOrderCode, setIsOrderCode] = useState(false);
  const [isProcessingFile, setIsProcessingFile] = useState(false);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const scanIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const offscreenCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const isStartingCameraRef = useRef(false);

  // Audio Beep generator (1900Hz POS confirmation tone)
  const playPosBeep = () => {
    try {
      if (!audioCtxRef.current) {
        const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
        if (AudioCtx) audioCtxRef.current = new AudioCtx();
      }
      if (audioCtxRef.current) {
        if (audioCtxRef.current.state === 'suspended') {
          void audioCtxRef.current.resume();
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

  // Microservices correlation: Process any decoded payload
  const handleCodeDetected = useCallback(async (rawCode: string) => {
    const rawClean = rawCode.trim();
    if (!rawClean) return;

    playPosBeep();
    setScannedCode(rawClean);

    // 1. Intelligent parsing: JSON receipt/label vs raw string
    let parsedSku: string | null = null;
    let parsedOrderNum: string | null = null;
    let fallbackName: string | null = null;
    let fallbackPrice: number | null = null;

    try {
      const json = JSON.parse(rawClean);
      if (json && typeof json === 'object') {
        if (json.sku) parsedSku = String(json.sku).trim();
        if (json.orderNumber) parsedOrderNum = String(json.orderNumber).trim();
        if (json.name) fallbackName = String(json.name).trim();
        if (typeof json.price === 'number') fallbackPrice = json.price;
      }
    } catch {
      // Raw string format
    }

    if (!parsedSku && !parsedOrderNum) {
      if (rawClean.toUpperCase().startsWith('ORD-')) {
        parsedOrderNum = rawClean;
      } else {
        parsedSku = rawClean;
      }
    }

    // 2. Scenario A: ORDER RECEIPT
    if (parsedOrderNum) {
      const orderCode = parsedOrderNum;
      setIsOrderCode(true);
      setMatchedProduct(null);
      setLiveInventory(null);

      showToast('Order Code Verified', `Scanned receipt #${orderCode}`, 'order');
      void recordFunnelTelemetry({ eventType: 'QR_ORDER_SCANNED', step: orderCode }, user?.token);

      try {
        const userOrders = await fetchOrders(user?.token);
        const foundOrder = userOrders.find(
          (o) =>
            o.orderNumber.toUpperCase() === orderCode.toUpperCase() ||
            String(o.id) === orderCode
        );
        setMatchedOrder(foundOrder || null);
      } catch {
        setMatchedOrder(null);
      }
      return;
    }

    // 3. Scenario B: PRODUCT CATALOG & INVENTORY
    if (parsedSku) {
      const targetSku = parsedSku;
      setIsOrderCode(false);
      setMatchedOrder(null);

      const found = products.find(
        (p) =>
          p.sku.toUpperCase() === targetSku.toUpperCase() ||
          p.name.toUpperCase().includes(targetSku.toUpperCase()) ||
          (p.id && String(p.id).toUpperCase() === targetSku.toUpperCase())
      );

      const productResolved: Product = found || {
        id: 'pos-scanned',
        sku: targetSku.toUpperCase(),
        name: fallbackName || `Scanned Item (${targetSku})`,
        price: fallbackPrice ?? 0,
        status: true,
        category: 'POS Scanned',
        quantity: 0,
        isInStock: false,
      };

      setMatchedProduct(productResolved);

      // Correlation with inventory-service (Authoritative real-time stock lookup)
      setIsFetchingInventory(true);
      try {
        const invDetail = await fetchInventoryBySku(productResolved.sku, user?.token);
        setLiveInventory(invDetail);
        if (invDetail) {
          showToast(
            'Product & Stock Synced',
            `${productResolved.name} | Live Stock: ${invDetail.quantity} units`,
            'stock'
          );
        } else {
          showToast('Product Identified', `${productResolved.name} (${productResolved.sku})`, 'stock');
        }
      } catch {
        setLiveInventory(null);
        showToast('Product Identified', `${productResolved.name} (${productResolved.sku})`, 'stock');
      } finally {
        setIsFetchingInventory(false);
      }

      void recordFunnelTelemetry(
        { eventType: 'QR_PRODUCT_SCANNED', sku: productResolved.sku, category: productResolved.category },
        user?.token
      );
    }
  }, [products, user?.token, showToast]);

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
          void handleCodeDetected(buffer);
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
  }, [isOpen, handleCodeDetected]);

  // Helper to stop camera and scan interval cleanly
  const stopCamera = useCallback(() => {
    if (scanIntervalRef.current) {
      clearInterval(scanIntervalRef.current);
      scanIntervalRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    if (videoRef.current) {
      videoRef.current.srcObject = null;
    }
    setIsCameraActive(false);
    setTorchOn(false);
    setHasTorch(false);
  }, []);

  // 2. Camera controller with resilient fallback
  const startCamera = useCallback(async () => {
    if (isStartingCameraRef.current) return;
    isStartingCameraRef.current = true;

    stopCamera();
    setCameraError(null);

    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error('Camera API is not supported on this browser or origin (requires HTTPS or localhost).');
      }

      let stream: MediaStream | null = null;

      // Attempt 1: Standard ideal facingMode + 720p
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: {
            facingMode: { ideal: facingMode },
            width: { ideal: 1280 },
            height: { ideal: 720 },
          },
          audio: false,
        });
      } catch (err: unknown) {
        if (err instanceof DOMException && (err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError')) {
          throw err;
        }
      }

      // Attempt 2: Basic ideal facingMode without resolution constraints
      if (!stream) {
        try {
          stream = await navigator.mediaDevices.getUserMedia({
            video: { facingMode: { ideal: facingMode } },
            audio: false,
          });
        } catch (err: unknown) {
          if (err instanceof DOMException && (err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError')) {
            throw err;
          }
        }
      }

      // Attempt 3: Universal fallback ({ video: true })
      if (!stream) {
        stream = await navigator.mediaDevices.getUserMedia({
          video: true,
          audio: false,
        });
      }

      streamRef.current = stream;

      const video = videoRef.current;
      if (video) {
        video.setAttribute('playsinline', 'true');
        video.muted = true;
        video.srcObject = stream;
        await video.play().catch(() => {});
        setIsCameraActive(true);

        const track = stream.getVideoTracks()[0];
        if (track && 'getCapabilities' in track) {
          const caps = (track.getCapabilities as () => { torch?: boolean })?.();
          setHasTorch(Boolean(caps?.torch));
        }
      }

      // Hybrid Frame Scanner loop (BarcodeDetector + jsQR)
      scanIntervalRef.current = setInterval(async () => {
        const vid = videoRef.current;
        if (!vid || vid.readyState < 2 || vid.videoWidth === 0) return;

        // 1. Native BarcodeDetector
        if ('BarcodeDetector' in window) {
          try {
            const detector = new (window as unknown as {
              BarcodeDetector: new (opts: { formats: string[] }) => {
                detect: (source: HTMLVideoElement) => Promise<Array<{ rawValue: string }>>;
              };
            }).BarcodeDetector({
              formats: ['qr_code', 'code_128', 'ean_13', 'upc_a'],
            });
            const barcodes = await detector.detect(vid);
            if (barcodes && barcodes.length > 0 && barcodes[0].rawValue) {
              void handleCodeDetected(barcodes[0].rawValue);
              return;
            }
          } catch {}
        }

        // 2. jsQR software fallback
        try {
          if (!offscreenCanvasRef.current) {
            offscreenCanvasRef.current = document.createElement('canvas');
          }
          const canvas = offscreenCanvasRef.current;
          const vw = vid.videoWidth;
          const vh = vid.videoHeight;

          if (vw > 0 && vh > 0) {
            const scale = Math.min(1, 640 / Math.max(vw, vh));
            const targetW = Math.floor(vw * scale);
            const targetH = Math.floor(vh * scale);

            canvas.width = targetW;
            canvas.height = targetH;
            const ctx = canvas.getContext('2d', { willReadFrequently: true });
            if (ctx) {
              ctx.drawImage(vid, 0, 0, targetW, targetH);
              const imgData = ctx.getImageData(0, 0, targetW, targetH);
              const qr = jsQR(imgData.data, targetW, targetH, {
                inversionAttempts: 'attemptBoth',
              });
              if (qr && qr.data) {
                void handleCodeDetected(qr.data);
              }
            }
          }
        } catch {}
      }, 250);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Camera access permission denied';
      setCameraError(msg);
      setIsCameraActive(false);
    } finally {
      isStartingCameraRef.current = false;
    }
  }, [facingMode, handleCodeDetected, stopCamera]);

  const toggleTorch = async () => {
    if (!streamRef.current) return;
    const track = streamRef.current.getVideoTracks()[0];
    if (!track) return;
    try {
      const next = !torchOn;
      await (track as MediaStreamTrack & {
        applyConstraints: (c: { advanced: Array<{ torch?: boolean }> }) => Promise<void>;
      }).applyConstraints({
        advanced: [{ torch: next }],
      });
      setTorchOn(next);
    } catch {}
  };

  const flipCamera = () => {
    setFacingMode((prev) => (prev === 'environment' ? 'user' : 'environment'));
  };

  // Mount/unmount lifecycle for camera tab
  useEffect(() => {
    let timerId: ReturnType<typeof setTimeout> | null = null;

    if (isOpen && activeTab === 'camera') {
      timerId = setTimeout(() => {
        void startCamera();
      }, 100);
    } else {
      stopCamera();
    }

    return () => {
      if (timerId) clearTimeout(timerId);
      stopCamera();
    };
  }, [isOpen, activeTab, facingMode, startCamera, stopCamera]);

  // 3. File image decoding (jsQR + BarcodeDetector)
  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsProcessingFile(true);
    try {
      const reader = new FileReader();
      reader.onload = (ev) => {
        const img = new Image();
        img.onload = async () => {
          let found = false;

          // Native BarcodeDetector
          if ('BarcodeDetector' in window) {
            try {
              const detector = new (window as unknown as {
                BarcodeDetector: new (opts: { formats: string[] }) => {
                  detect: (source: HTMLImageElement) => Promise<Array<{ rawValue: string }>>;
                };
              }).BarcodeDetector({
                formats: ['qr_code', 'code_128', 'ean_13', 'upc_a'],
              });
              const codes = await detector.detect(img);
              if (codes && codes.length > 0 && codes[0].rawValue) {
                void handleCodeDetected(codes[0].rawValue);
                found = true;
              }
            } catch {}
          }

          // jsQR canvas decoding
          if (!found) {
            try {
              const canvas = document.createElement('canvas');
              canvas.width = img.width;
              canvas.height = img.height;
              const ctx = canvas.getContext('2d', { willReadFrequently: true });
              if (ctx) {
                ctx.drawImage(img, 0, 0);
                const imgData = ctx.getImageData(0, 0, img.width, img.height);
                const qr = jsQR(imgData.data, img.width, img.height, {
                  inversionAttempts: 'attemptBoth',
                });
                if (qr && qr.data) {
                  void handleCodeDetected(qr.data);
                  found = true;
                }
              }
            } catch {}
          }

          // Filename match fallback
          if (!found) {
            const nameMatch = file.name.match(/(LAPTOP-[A-Za-z0-9-]+|KEYBOARD-[A-Za-z0-9-]+|MOUSE-[A-Za-z0-9-]+|ORD-[A-Za-z0-9-]+)/i);
            if (nameMatch) {
              void handleCodeDetected(nameMatch[0]);
            } else {
              showToast('No Code Detected', 'Could not detect a valid QR or Barcode in this image.', 'system');
            }
          }
          setIsProcessingFile(false);
        };
        img.src = ev.target?.result as string;
      };
      reader.readAsDataURL(file);
    } catch {
      setIsProcessingFile(false);
    }
  };

  const handleManualSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (manualInput.trim()) {
      void handleCodeDetected(manualInput.trim());
      setManualInput('');
    }
  };

  // Microservice Action: Quick Stock Increment for Admin
  const handleQuickAdjustStock = async (delta: number) => {
    if (!matchedProduct || isUpdatingStock) return;
    const currentQty = liveInventory?.quantity ?? matchedProduct.quantity ?? 0;
    const newQty = Math.max(0, currentQty + delta);

    setIsUpdatingStock(true);
    try {
      await updateStockQuantity(matchedProduct.sku, newQty, user?.token);
      setLiveInventory((prev) => (prev ? { ...prev, quantity: newQty, isInStock: newQty > 0 } : null));
      showToast('Inventory Updated', `SKU ${matchedProduct.sku} set to ${newQty} units.`, 'stock');
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to update stock';
      showToast('Stock Update Failed', msg, 'system');
    } finally {
      setIsUpdatingStock(false);
    }
  };

  // Microservice Action: Ship Order (Orders Service Mutation)
  const handleShipOrder = async () => {
    if (!matchedOrder || isFulfillingOrder) return;
    setIsFulfillingOrder(true);
    try {
      const updated = await submitShipOrder(matchedOrder.id, user?.token);
      setMatchedOrder(updated);
      showToast('Order Shipped', `Order #${updated.orderNumber} marked as SHIPPED.`, 'order');
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to ship order';
      showToast('Shipping Failed', msg, 'system');
    } finally {
      setIsFulfillingOrder(false);
    }
  };

  // Microservice Action: Deliver Order (Orders Service Mutation)
  const handleDeliverOrder = async () => {
    if (!matchedOrder || isFulfillingOrder) return;
    setIsFulfillingOrder(true);
    try {
      const updated = await submitDeliverOrder(matchedOrder.id, user?.token);
      setMatchedOrder(updated);
      showToast('Order Delivered', `Order #${updated.orderNumber} marked as DELIVERED.`, 'order');
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to mark delivery';
      showToast('Delivery Failed', msg, 'system');
    } finally {
      setIsFulfillingOrder(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in">
      <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="p-3.5 sm:p-5 border-b border-slate-800 flex items-center justify-between">
          <div className="flex items-center gap-2.5 sm:gap-3">
            <div className="w-9 h-9 sm:w-10 sm:h-10 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400 shrink-0">
              <ScanLine className="w-5 h-5 animate-pulse" />
            </div>
            <div>
              <h3 className="text-sm sm:text-base font-bold text-white flex items-center gap-1.5 sm:gap-2">
                Agnostic QR & Barcode POS
                <span className="text-[9px] sm:text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 hidden xs:inline">
                  Microservices POS
                </span>
              </h3>
              <p className="text-[11px] sm:text-xs text-slate-400">
                WebCam video scan, image upload & USB/Bluetooth HID listener
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 sm:p-2 text-slate-400 hover:text-white rounded-xl hover:bg-slate-800 transition shrink-0"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Mode Selector Tabs */}
        <div className="flex border-b border-slate-800 bg-slate-950/40 p-1 sm:p-1.5 gap-1">
          <button
            onClick={() => setActiveTab('camera')}
            className={`flex-1 py-2 px-1.5 sm:px-3 rounded-xl text-[11px] sm:text-xs font-semibold flex items-center justify-center gap-1.5 sm:gap-2 transition ${
              activeTab === 'camera'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/20'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/40'
            }`}
          >
            <Camera className="w-3.5 h-3.5 shrink-0" />
            <span className="truncate">Camera</span>
          </button>
          <button
            onClick={() => setActiveTab('file')}
            className={`flex-1 py-2 px-1.5 sm:px-3 rounded-xl text-[11px] sm:text-xs font-semibold flex items-center justify-center gap-1.5 sm:gap-2 transition ${
              activeTab === 'file'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/20'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/40'
            }`}
          >
            <Upload className="w-3.5 h-3.5 shrink-0" />
            <span className="truncate">Upload File</span>
          </button>
          <button
            onClick={() => setActiveTab('manual')}
            className={`flex-1 py-2 px-1.5 sm:px-3 rounded-xl text-[11px] sm:text-xs font-semibold flex items-center justify-center gap-1.5 sm:gap-2 transition ${
              activeTab === 'manual'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/20'
                : 'text-slate-400 hover:text-white hover:bg-slate-800/40'
            }`}
          >
            <Keyboard className="w-3.5 h-3.5 shrink-0" />
            <span className="truncate">Manual / HID</span>
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

                {/* Laser Overlay */}
                {isCameraActive && (
                  <div className="absolute inset-0 pointer-events-none flex items-center justify-center">
                    <div className="relative w-56 h-56 border-2 border-dashed border-indigo-400/60 rounded-2xl flex items-center justify-center">
                      <div className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-indigo-400" />
                      <div className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-indigo-400" />
                      <div className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-indigo-400" />
                      <div className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-indigo-400" />
                      <div className="w-full h-0.5 bg-gradient-to-r from-transparent via-indigo-400 to-transparent shadow-[0_0_12px_#6366f1] animate-bounce" />
                    </div>
                  </div>
                )}

                {/* Camera Error Display (Clean & Non-Redundant) */}
                {cameraError && (
                  <div className="p-6 text-center text-slate-400 max-w-xs z-10">
                    <AlertCircle className="w-8 h-8 text-rose-500 mx-auto mb-2" />
                    <p className="text-xs font-semibold text-rose-400">{cameraError}</p>
                    <button
                      onClick={() => void startCamera()}
                      className="mt-3 px-3.5 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-xs font-bold text-white transition"
                    >
                      Retry Camera
                    </button>
                  </div>
                )}

                {/* Camera Controls */}
                {isCameraActive && (
                  <div className="absolute bottom-3 right-3 flex items-center gap-2 z-10">
                    {hasTorch && (
                      <button
                        onClick={() => void toggleTorch()}
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
                  <Volume2 className="w-3 h-3" /> POS Beep ON
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
                  {isProcessingFile ? 'Analyzing Image...' : 'Click to upload or drag QR Image'}
                </span>
                <span className="text-xs text-slate-500 mt-1">PNG, JPG, SVG, WebP up to 10MB</span>
                <input
                  type="file"
                  accept="image/*"
                  onChange={(e) => void handleFileUpload(e)}
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
                  <strong>Hardware Scanner Active:</strong> Connect any USB or Bluetooth laser barcode reader. Point and pull the trigger; it will instantly decode into this modal.
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
                    placeholder="e.g. LAPTOP-PRO-01 or ORD-12345"
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
                      onClick={() => void handleCodeDetected(p.sku)}
                      className="px-2.5 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 text-[11px] font-mono border border-slate-700/60"
                    >
                      {p.sku}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Scanned Result Card with Microservices Correlation */}
          {scannedCode && (
            <div className="pt-3 border-t border-slate-800 animate-in fade-in space-y-3">
              <div className="flex items-center justify-between text-xs">
                <span className="text-slate-400">Decoded Payload:</span>
                <span className="font-mono font-bold text-indigo-400 bg-indigo-500/10 px-2 py-0.5 rounded-md border border-indigo-500/20 max-w-[260px] truncate">
                  {scannedCode}
                </span>
              </div>

              {/* PRODUCT RESULT with LIVE INVENTORY CORRELATION */}
              {matchedProduct && (
                <div className="p-3.5 rounded-2xl bg-slate-950 border border-slate-800 space-y-3">
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center gap-3">
                      <img
                        src={matchedProduct.imageUrl || 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=200'}
                        alt={matchedProduct.name}
                        className="w-12 h-12 rounded-xl object-cover border border-slate-800 shrink-0"
                      />
                      <div>
                        <h4 className="text-xs font-bold text-white line-clamp-1">
                          {matchedProduct.name}
                        </h4>
                        <div className="flex items-center gap-2 mt-0.5">
                          <span className="text-xs font-black text-indigo-400">
                            {formatPrice(matchedProduct.price)}
                          </span>
                          <span className="text-[10px] text-slate-400 font-mono">
                            SKU: {matchedProduct.sku}
                          </span>
                        </div>
                      </div>
                    </div>

                    <button
                      onClick={() => {
                        addToCart(matchedProduct, 1);
                        showToast('Added to Cart', `${matchedProduct.name} added from POS QR!`, 'order');
                        onClose();
                      }}
                      className="px-3.5 py-2 rounded-xl bg-gradient-to-r from-indigo-600 to-indigo-700 hover:from-indigo-500 hover:to-indigo-600 text-white font-bold text-xs shadow-md shadow-indigo-500/20 flex items-center gap-1.5 transition active:scale-95 shrink-0"
                    >
                      <ShoppingBag className="w-3.5 h-3.5" />
                      Add to Cart
                    </button>
                  </div>

                  {/* Microservice Live Stock Status from inventory-service */}
                  <div className="pt-2 border-t border-slate-800/80 flex items-center justify-between text-xs">
                    <div className="flex items-center gap-2">
                      <Package className="w-3.5 h-3.5 text-slate-400" />
                      <span className="text-slate-400">PostgreSQL Live Stock:</span>
                      {isFetchingInventory ? (
                        <span className="text-[11px] text-slate-500 animate-pulse">Syncing stock...</span>
                      ) : (
                        <span className={`font-mono font-bold px-2 py-0.5 rounded-md text-[11px] ${
                          (liveInventory?.quantity ?? matchedProduct.quantity ?? 0) > 0
                            ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                            : 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                        }`}>
                          {liveInventory?.quantity ?? matchedProduct.quantity ?? 0} units available
                        </span>
                      )}
                    </div>

                    {/* Admin Quick Stock Increment Action */}
                    {user?.isAdmin && (
                      <button
                        onClick={() => void handleQuickAdjustStock(1)}
                        disabled={isUpdatingStock}
                        className="px-2 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 text-[11px] font-medium flex items-center gap-1 transition"
                        title="Increment stock in inventory-service"
                      >
                        <Plus className="w-3 h-3 text-emerald-400" />
                        {isUpdatingStock ? 'Saving...' : '+1 Stock'}
                      </button>
                    )}
                  </div>
                </div>
              )}

              {/* ORDER RESULT with ORDERS-SERVICE FULFILLMENT CORRELATION */}
              {isOrderCode && (
                <div className="p-3.5 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2 text-indigo-300 text-xs font-semibold">
                      <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
                      <span>Order Verified: <strong className="font-mono text-white">{scannedCode}</strong></span>
                    </div>
                    {matchedOrder && (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                        {matchedOrder.orderStatus}
                      </span>
                    )}
                  </div>

                  {matchedOrder && (
                    <div className="grid grid-cols-2 gap-2 text-xs bg-slate-950/60 p-2.5 rounded-xl border border-slate-800 text-slate-300">
                      <div>
                        <span className="text-[10px] text-slate-500 block">Customer</span>
                        <span className="font-medium truncate block">{matchedOrder.customerName || 'Customer'}</span>
                      </div>
                      <div>
                        <span className="text-[10px] text-slate-500 block">Total</span>
                        <span className="font-bold text-indigo-400 font-mono">
                          {formatPrice(matchedOrder.totalAmount ?? 0)}
                        </span>
                      </div>
                      <div>
                        <span className="text-[10px] text-slate-500 block">Tracking Reference</span>
                        <span className="font-mono text-[11px] truncate block text-slate-400">
                          {matchedOrder.trackingNumber || 'Pending'}
                        </span>
                      </div>
                      <div>
                        <span className="text-[10px] text-slate-500 block">Carrier</span>
                        <span className="truncate block text-slate-400">
                          {matchedOrder.carrier || 'DHL Express'}
                        </span>
                      </div>
                    </div>
                  )}

                  {/* Microservice Mutation Actions */}
                  <div className="flex items-center gap-2 pt-1">
                    {/* Admin Fulfillment Step: Ship */}
                    {user?.isAdmin && matchedOrder && matchedOrder.orderStatus === 'PROCESSING' && (
                      <button
                        onClick={() => void handleShipOrder()}
                        disabled={isFulfillingOrder}
                        className="flex-1 px-3 py-2 rounded-xl bg-amber-600 hover:bg-amber-500 text-white text-xs font-bold flex items-center justify-center gap-1.5 transition shadow-sm"
                      >
                        <Truck className="w-3.5 h-3.5" />
                        {isFulfillingOrder ? 'Fulfilling...' : 'Ship Order'}
                      </button>
                    )}

                    {/* Admin Fulfillment Step: Deliver */}
                    {user?.isAdmin && matchedOrder && matchedOrder.orderStatus === 'SHIPPED' && (
                      <button
                        onClick={() => void handleDeliverOrder()}
                        disabled={isFulfillingOrder}
                        className="flex-1 px-3 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold flex items-center justify-center gap-1.5 transition shadow-sm"
                      >
                        <CheckCircle2 className="w-3.5 h-3.5" />
                        {isFulfillingOrder ? 'Fulfilling...' : 'Confirm Delivery'}
                      </button>
                    )}

                    {/* View Receipt in Modal */}
                    {matchedOrder && onOpenReceipt && (
                      <button
                        onClick={() => {
                          onOpenReceipt(matchedOrder);
                          onClose();
                        }}
                        className="px-3 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-white text-xs font-medium flex items-center justify-center gap-1.5 transition"
                      >
                        <FileText className="w-3.5 h-3.5 text-indigo-400" />
                        Receipt
                      </button>
                    )}

                    {/* Navigate to Order History */}
                    {onNavigateToOrders && (
                      <button
                        onClick={() => {
                          onNavigateToOrders();
                          onClose();
                        }}
                        className="px-3 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center justify-center gap-1 transition"
                      >
                        Track <ExternalLink className="w-3 h-3" />
                      </button>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
