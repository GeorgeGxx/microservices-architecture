import React, { useEffect, useRef, useState } from 'react';
import {
  Play,
  Pause,
  RotateCcw,
  Check,
  Truck,
  Box,
  CheckCircle2,
  Clock,
  ShieldCheck,
  Radio,
  Lock,
  XCircle,
} from 'lucide-react';
import {
  DeliveryStage,
  DELIVERY_STAGES,
  getDeliveryStageIndex,
  getNextDeliveryStage,
} from '../utils/orderPipeline';
import { useNotifications } from '../context/NotificationContext';

interface OrderLivePipelineProps {
  orderId: string;
  orderNumber: string;
  carrier?: string;
  trackingNumber?: string;
  initialStatus: string;
  onStatusChange?: (newStatus: string) => void;
}

export const OrderLivePipeline: React.FC<OrderLivePipelineProps> = ({
  orderId,
  orderNumber,
  carrier = 'DHL Express',
  trackingNumber,
  initialStatus,
  onStatusChange,
}) => {
  const { showToast } = useNotifications();

  // Active simulated or actual stage
  const [currentStatus, setCurrentStatus] = useState<string>(initialStatus || 'PLACED');
  const [isSimulating, setIsSimulating] = useState<boolean>(false);
  const [simSeconds, setSimSeconds] = useState<number>(0);
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  // Sync if initial status changes from parent or backend (e.g. cancellation or auto-progression)
  useEffect(() => {
    if (initialStatus?.toUpperCase() === 'CANCELLED') {
      stopSimulation();
      setCurrentStatus('CANCELLED');
    } else {
      setCurrentStatus(initialStatus || 'PLACED');
    }
  }, [initialStatus]);

  // Cleanup simulation timer on unmount
  useEffect(() => {
    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
    };
  }, []);

  const isCancelled = currentStatus.toUpperCase() === 'CANCELLED';
  const currentIndex = getDeliveryStageIndex(currentStatus);
  const isDelivered = currentStatus.toUpperCase() === 'DELIVERED';

  const stopSimulation = () => {
    setIsSimulating(false);
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  };

  const toggleSimulation = () => {
    if (isSimulating) {
      stopSimulation();
      return;
    }

    // If already delivered, restart from beginning
    if (isDelivered) {
      setCurrentStatus('PLACED');
      onStatusChange?.('PLACED');
      setSimSeconds(0);
    }

    setIsSimulating(true);

    let secondsElapsed = 0;
    let localStatus = isDelivered ? 'PLACED' : currentStatus;

    if (timerRef.current) clearInterval(timerRef.current);

    timerRef.current = setInterval(() => {
      secondsElapsed += 1;
      setSimSeconds((s) => s + 1);

      // Transition to next stage every 3.5 seconds
      if (secondsElapsed % 4 === 0) {
        const next = getNextDeliveryStage(localStatus, orderNumber);
        if (next) {
          localStatus = next.nextStatus;
          setCurrentStatus(next.nextStatus);
          onStatusChange?.(next.nextStatus);

          // Trigger live toast notification
          showToast(next.milestoneTitle, next.milestoneMessage, next.notificationType);

          if (next.nextStatus === 'DELIVERED') {
            stopSimulation();
          }
        } else {
          stopSimulation();
        }
      }
    }, 1000);
  };

  const resetToInitial = () => {
    stopSimulation();
    setSimSeconds(0);
    setCurrentStatus(initialStatus || 'PLACED');
    onStatusChange?.(initialStatus || 'PLACED');
  };

  // Helper icons for each stage
  const getStageIcon = (key: DeliveryStage) => {
    switch (key) {
      case 'PLACED':
        return <Clock className="w-3.5 h-3.5" />;
      case 'CONFIRMED':
        return <ShieldCheck className="w-3.5 h-3.5" />;
      case 'PREPARING':
        return <Box className="w-3.5 h-3.5" />;
      case 'SHIPPED':
        return <Truck className="w-3.5 h-3.5" />;
      case 'DELIVERED':
        return <CheckCircle2 className="w-3.5 h-3.5" />;
    }
  };

  if (isCancelled) {
    return (
      <div className="p-4 rounded-2xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 flex items-center gap-3 animate-in fade-in">
        <XCircle className="w-5 h-5 shrink-0 text-rose-500" />
        <div className="text-xs">
          <strong className="font-bold block text-rose-700 dark:text-rose-400 text-sm">Order Cancelled (Saga Rollback)</strong>
          <span>Inventory stock was restored via distributed Saga compensation. Delivery pipeline transit is permanently terminated.</span>
        </div>
      </div>
    );
  }

  return (
    <div className="p-5 rounded-2xl bg-white/70 dark:bg-slate-900/60 border border-slate-200/80 dark:border-slate-800/80 shadow-sm space-y-5">
      {/* Top Bar: Stage Label, Tracking Pill, and Simulation Action */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-3 border-b border-slate-100 dark:border-slate-800/80">
        <div className="flex items-center gap-2.5 flex-wrap">
          <span className="text-xs font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
            Live 5-Stage Delivery Pipeline
          </span>

          {/* Active status indicator */}
          <span className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 border border-indigo-500/20">
            {isSimulating ? (
              <>
                <Radio className="w-3 h-3 animate-pulse text-indigo-500" />
                <span>Simulating Live ({simSeconds}s)</span>
              </>
            ) : (
              <span>Active: {DELIVERY_STAGES[Math.max(0, currentIndex)]?.shortTitle || currentStatus}</span>
            )}
          </span>

          {/* Cancellation Disabled Pill when in CONFIRMED or later */}
          {currentIndex >= 1 && (
            <span
              title="Order is confirmed and being prepared for delivery. Cancellation is disabled."
              className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/20"
            >
              <Lock className="w-3 h-3 text-amber-500" />
              <span>Cancellation Disabled</span>
            </span>
          )}

          {trackingNumber && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md font-mono text-[10px] bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 border border-slate-200 dark:border-slate-700">
              <Truck className="w-3 h-3 text-indigo-500" />
              <span>{carrier}: {trackingNumber}</span>
            </span>
          )}
        </div>

        {/* Simulation Controls (Play/Pause & Reset) */}
        <div className="flex items-center gap-2 self-start sm:self-auto">
          {simSeconds > 0 && !isSimulating && (
            <button
              onClick={resetToInitial}
              title="Reset to original order status"
              className="p-1.5 rounded-lg text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 transition"
            >
              <RotateCcw className="w-3.5 h-3.5" />
            </button>
          )}

          <button
            onClick={toggleSimulation}
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition-all shadow-sm active:scale-95 ${
              isSimulating
                ? 'bg-amber-500 text-white shadow-amber-500/20 hover:bg-amber-600 animate-pulse'
                : isDelivered
                ? 'bg-slate-800 hover:bg-slate-700 text-slate-200'
                : 'bg-indigo-600 hover:bg-indigo-500 text-white shadow-indigo-500/20'
            }`}
          >
            {isSimulating ? (
              <>
                <Pause className="w-3.5 h-3.5" />
                <span>Pause Simulation</span>
              </>
            ) : isDelivered ? (
              <>
                <RotateCcw className="w-3.5 h-3.5" />
                <span>Replay Simulation</span>
              </>
            ) : (
              <>
                <Play className="w-3.5 h-3.5 fill-current" />
                <span>Simulate Live Transit</span>
              </>
            )}
          </button>
        </div>
      </div>

      {/* Stepper Track: 5-Stage Stepper with animated connectors */}
      <div className="relative pt-2 pb-2">
        <div className="grid grid-cols-5 gap-2 relative">
          {DELIVERY_STAGES.map((stage, idx) => {
            const isCompleted = currentIndex > idx;
            const isCurrent = currentIndex === idx;
            const isPending = currentIndex < idx;

            return (
              <div key={stage.key} className="flex flex-col items-center text-center relative group">
                {/* Connector line between steps */}
                {idx < DELIVERY_STAGES.length - 1 && (
                  <div
                    className={`absolute top-4 left-[50%] w-full h-1 -z-0 transition-all duration-700 ${
                      currentIndex > idx
                        ? 'bg-gradient-to-r from-emerald-500 to-indigo-500 shadow-sm'
                        : isCurrent && isSimulating
                        ? 'bg-gradient-to-r from-indigo-500 via-indigo-300 to-slate-200 dark:to-slate-800 animate-pulse'
                        : 'bg-slate-200 dark:bg-slate-800'
                    }`}
                  />
                )}

                {/* Stage Circle Node with Radar Pulsing Ring */}
                <div className="relative z-10 mb-2">
                  {/* Radar halo for the active/simulating stage */}
                  {isCurrent && (
                    <div className="absolute -inset-1.5 rounded-full bg-indigo-500/30 dark:bg-indigo-400/20 animate-ping pointer-events-none" />
                  )}

                  <div
                    className={`w-8 h-8 rounded-full flex items-center justify-center transition-all duration-500 font-bold text-xs shadow-sm ${
                      isCompleted
                        ? 'bg-emerald-500 text-white shadow-emerald-500/25 ring-2 ring-emerald-500/30'
                        : isCurrent
                        ? 'bg-indigo-600 text-white ring-4 ring-indigo-500/20 shadow-indigo-500/30 scale-110'
                        : 'bg-slate-100 dark:bg-slate-800 text-slate-400 dark:text-slate-500 border border-slate-300 dark:border-slate-700'
                    }`}
                  >
                    {isCompleted ? (
                      <Check className="w-4 h-4 stroke-[3]" />
                    ) : isCurrent ? (
                      getStageIcon(stage.key)
                    ) : (
                      <span>{stage.id}</span>
                    )}
                  </div>
                </div>

                {/* Stage Labels */}
                <div className="space-y-0.5 max-w-[120px]">
                  <div
                    className={`text-[11px] font-bold transition-colors ${
                      isCurrent
                        ? 'text-indigo-600 dark:text-indigo-400'
                        : isCompleted
                        ? 'text-emerald-600 dark:text-emerald-400'
                        : 'text-slate-400 dark:text-slate-500'
                    }`}
                  >
                    {stage.label}
                  </div>
                  <div className="text-[10px] text-slate-500 dark:text-slate-400 leading-tight hidden sm:block">
                    {stage.desc}
                  </div>
                  {stage.key === 'CONFIRMED' && (
                    <div className="text-[9px] font-semibold text-amber-600 dark:text-amber-400/90 pt-0.5">
                      🔒 Cancellation disabled
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
