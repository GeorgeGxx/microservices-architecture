import React, { useEffect, useRef, useState } from 'react';
import { useCart } from '../context/CartContext';
import { useCurrency } from '../context/CurrencyContext';
import { useAuth } from '../context/AuthContext';
import { useNotifications } from '../context/NotificationContext';
import { createIdempotencyKey, placeOrderUseCase } from '../application/use-cases/PlaceOrderUseCase';
import { CheckoutStateMachine, CheckoutStep } from '../application/use-cases/CheckoutFSM';
import { Order } from '../types';
import { getOrderStatusNotificationCopy } from '../utils/orderNotificationCopy';
import { recordFunnelTelemetry } from '../services/api';
import confetti from 'canvas-confetti';
import {
  X,
  ShieldCheck,
  CreditCard,
  Truck,
  CheckCircle2,
  Loader2,
  Lock,
  ArrowRight,
  ArrowLeft,
  MapPin,
  AlertCircle,
  AlertTriangle,
  XCircle,
  RefreshCw
} from 'lucide-react';

interface DeclineInfo {
  code: string;
  badge: string;
  title: string;
  description: string;
  suggestion: string;
}

const DECLINE_PROFILES: Record<string, DeclineInfo> = {
  SIMULATED_DECLINED_INSUFFICIENT_FUNDS: {
    code: '51',
    badge: 'ISO 8583 - RESP 51',
    title: 'Insufficient Funds / Credit Limit Exceeded',
    description: 'The issuing financial institution declined the charge because the card has insufficient available balance or credit limit.',
    suggestion: 'Try another credit or debit card, or contact your issuing bank to request a temporary limit adjustment.',
  },
  SIMULATED_DECLINED_INCORRECT_PIN: {
    code: '55',
    badge: 'ISO 8583 - RESP 55',
    title: 'Invalid Security PIN or CVV Code',
    description: 'The cryptographic chip PIN or dynamic CVV security code failed issuing bank authentication.',
    suggestion: 'Verify your card PIN in your mobile banking app or re-enter the dynamic CVV security code.',
  },
  SIMULATED_DECLINED_SUSPECTED_FRAUD: {
    code: '59',
    badge: 'ISO 8583 - RESP 59',
    title: 'Security Hold / Suspected Fraud Prevention',
    description: 'The card issuer fraud risk engine placed a preventive hold on this online transaction for account protection.',
    suggestion: 'Call the customer service phone number on the back of your card or approve the transaction in your bank app.',
  },
  SIMULATED_DECLINED_EXPIRED_CARD: {
    code: '54',
    badge: 'ISO 8583 - RESP 54',
    title: 'Expired Card / Validity Period Elapsed',
    description: 'The expiration date on record has elapsed or the physical card was superseded by a reissue.',
    suggestion: 'Please enter the details of your renewed card or an alternative active payment method.',
  },
  SIMULATED_DECLINED: {
    code: '05',
    badge: 'ISO 8583 - RESP 05',
    title: 'Transaction Declined by Card Issuer',
    description: 'The card issuing financial institution declined authorization for this merchant purchase.',
    suggestion: 'Please select an alternate payment method or try another payment card.',
  },
};

interface CheckoutModalProps {
  isOpen: boolean;
  onClose: () => void;
  onOrderSuccess: (order: Order) => void;
}

function getCheckoutStepClass(isActive: boolean, isCompleted: boolean): string {
  if (isActive) {
    return 'bg-indigo-600 text-white shadow-md shadow-indigo-500/30';
  }
  if (isCompleted) {
    return 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 border border-emerald-500/30';
  }
  return 'bg-slate-100 dark:bg-slate-800 text-slate-400';
}

export const CheckoutModal: React.FC<CheckoutModalProps> = ({ isOpen, onClose, onOrderSuccess }) => {
  const { cart, total, clearCart } = useCart();
  const { formatPrice } = useCurrency();
  const { user } = useAuth();
  const { showToast } = useNotifications();

  const [fsm] = useState(() => new CheckoutStateMachine());
  const [currentStep, setCurrentStep] = useState<CheckoutStep>('CUSTOMER_INFO');
  const [isLoading, setIsLoading] = useState(false);
  const [stepError, setStepError] = useState<string | null>(null);
  const [declineDetails, setDeclineDetails] = useState<DeclineInfo | null>(null);
  const isSubmittingRef = useRef(false);
  const orderAttemptRef = useRef<{ signature: string; key: string } | null>(null);

  const [formData, setFormData] = useState({
    customerName: user ? `${user.firstName || ''} ${user.lastName || ''}`.trim() || user.username : 'Alex Mercer',
    customerEmail: user?.email || 'alex.mercer@enterprise.dev',
    shippingAddress: '742 Evergreen Terrace',
    city: 'Springfield',
    postalCode: '97477',
    phone: '+1 555 123 4567',
    deliveryMethod: 'DHL Express Delivery (Priority 24h)',
    paymentMethod: 'SIMULATED_APPROVED',
  });

  // App keeps this modal mounted while it is closed. Reset its UI state each
  // time a new checkout starts so a previous PROCESSING state cannot survive
  // a completed or interrupted attempt.
  useEffect(() => {
    if (!isOpen) return;

    fsm.reset();
    isSubmittingRef.current = false;
    setCurrentStep('CUSTOMER_INFO');
    setIsLoading(false);
    setStepError(null);
    setDeclineDetails(null);

    void recordFunnelTelemetry({ eventType: 'CHECKOUT_START' }, user?.token);
  }, [fsm, isOpen, user?.token]);

  if (!isOpen) return null;

  const handleNextStep = (target: CheckoutStep) => {
    const success = fsm.transition(target, formData);
    if (success) {
      setCurrentStep(fsm.step);
      setStepError(null);
      setDeclineDetails(null);
      if (target === 'DELIVERY_TIER') {
        void recordFunnelTelemetry({ eventType: 'CHECKOUT_STEP', step: 'DELIVERY' }, user?.token);
      } else if (target === 'PAYMENT') {
        void recordFunnelTelemetry({ eventType: 'CHECKOUT_STEP', step: 'PAYMENT' }, user?.token);
      }
    } else {
      setStepError(fsm.errorMessage);
    }
  };

  const handlePrevStep = (target: CheckoutStep) => {
    fsm.transition(target, formData);
    setCurrentStep(fsm.step);
    setStepError(null);
    setDeclineDetails(null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isSubmittingRef.current || cart.length === 0) return;

    isSubmittingRef.current = true;
    setIsLoading(true);
    setStepError(null);
    setDeclineDetails(null);

    try {
      if (!fsm.transition('PROCESSING', formData)) {
        setStepError(fsm.errorMessage);
        return;
      }
      setCurrentStep(fsm.step);

      if (formData.paymentMethod !== 'SIMULATED_APPROVED') {
        const profile = DECLINE_PROFILES[formData.paymentMethod] || DECLINE_PROFILES.SIMULATED_DECLINED;

        // Dispatch call to payments-service to register the failed transaction in Prometheus & PostgreSQL
        const declinePayload = {
          order_number: `SIM-DECLINE-${Date.now().toString().slice(-6)}`,
          amount: total,
          currency: 'USD',
          payment_method: formData.paymentMethod,
          idempotency_key: `decline-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
          customer_email: formData.customerEmail,
          customer_name: formData.customerName,
          shipping_address: formData.shippingAddress,
          city: formData.city,
          postal_code: formData.postalCode,
        };

        try {
          await fetch('/api/v1/payments/process', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(declinePayload),
          });
        } catch (fetchErr) {
          console.warn('[Payments] Backend call error in simulated decline demo:', fetchErr);
        }

        // Simulated interbank authorization roundtrip
        await new Promise((r) => setTimeout(r, 850));

        fsm.forceFail(profile.description);
        fsm.retry();
        setCurrentStep(fsm.step);
        setStepError(profile.description);
        setDeclineDetails(profile);
        showToast('Payment Declined', `${profile.badge}: ${profile.title}`, 'stock');
        return;
      }

      const orderRequest = {
        items: cart,
        customerName: formData.customerName,
        customerEmail: formData.customerEmail,
        shippingAddress: formData.shippingAddress,
        city: formData.city,
        postalCode: formData.postalCode,
        phone: formData.phone,
        deliveryMethod: formData.deliveryMethod,
        paymentMethod: formData.paymentMethod,
      };
      const signature = JSON.stringify({
        ...orderRequest,
        items: cart.map(({ product, quantity }) => ({ sku: product.sku, quantity, price: product.price })),
      });
      if (orderAttemptRef.current?.signature !== signature) {
        orderAttemptRef.current = { signature, key: createIdempotencyKey() };
      }

      // Keep the same key on retry so an uncertain response cannot duplicate an order.
      const newOrder = await placeOrderUseCase.execute(
        orderRequest,
        user?.token,
        orderAttemptRef.current.key
      );

      fsm.transition('CONFIRMED', formData);

      // Trigger Celebration Confetti
      try {
        confetti({
          particleCount: 120,
          spread: 80,
          origin: { y: 0.6 },
          colors: ['#6366f1', '#10b981', '#f59e0b', '#ec4899', '#3b82f6'],
        });
      } catch {}

      const placedNotification = getOrderStatusNotificationCopy('PLACED', newOrder.orderNumber);
      showToast(placedNotification.title, placedNotification.message, 'order');

      clearCart();
      orderAttemptRef.current = null;
      fsm.reset();
      setCurrentStep('CUSTOMER_INFO');
      onClose();
      onOrderSuccess(newOrder);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Error processing order';
      fsm.forceFail(msg);
      fsm.retry();
      setCurrentStep(fsm.step);
      setStepError(msg);
      showToast('Checkout Error', msg, 'stock');
    } finally {
      isSubmittingRef.current = false;
      setIsLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-slate-950/80 backdrop-blur-md animate-in fade-in">
      <div className="relative w-full max-w-xl bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-3xl shadow-2xl p-4 sm:p-6 md:p-8 max-h-[90vh] overflow-y-auto">
        {/* Close Button */}
        <button
          onClick={onClose}
          disabled={isLoading}
          className="absolute top-5 right-5 p-2 text-slate-400 hover:text-slate-900 dark:hover:text-white rounded-xl hover:bg-slate-100 dark:hover:bg-slate-800 transition"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Modal Header */}
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-600 dark:text-indigo-400">
            <Lock className="w-5 h-5" />
          </div>
          <div>
            <h3 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">
              Secure Transactional Checkout
            </h3>
            <p className="text-xs text-slate-500 dark:text-slate-400">
              Cosmo Router v2 Federated Orchestration & Idempotent Saga
            </p>
          </div>
        </div>

        {/* FSM Step Indicator */}
        <div className="flex items-center justify-between mb-6 pb-4 border-b border-slate-100 dark:border-slate-800">
          {[
            { id: 'CUSTOMER_INFO', label: '1. Shipping', icon: MapPin },
            { id: 'DELIVERY_TIER', label: '2. Delivery', icon: Truck },
            { id: 'PAYMENT', label: '3. Payment', icon: CreditCard },
          ].map((s) => {
            const Icon = s.icon;
            const isActive = currentStep === s.id;
            const isCompleted =
              (s.id === 'CUSTOMER_INFO' && currentStep !== 'CUSTOMER_INFO') ||
              (s.id === 'DELIVERY_TIER' && currentStep === 'PAYMENT');

            return (
              <div key={s.id} className="flex items-center gap-2">
                <div
                  className={`w-7 h-7 rounded-xl flex items-center justify-center text-xs font-bold transition-all ${getCheckoutStepClass(isActive, isCompleted)}`}
                >
                  {isCompleted ? <CheckCircle2 className="w-4 h-4" /> : <Icon className="w-3.5 h-3.5" />}
                </div>
                <span
                  className={`text-xs font-semibold hidden sm:inline ${
                    isActive ? 'text-indigo-600 dark:text-indigo-400 font-bold' : 'text-slate-400'
                  }`}
                >
                  {s.label}
                </span>
              </div>
            );
          })}
        </div>

        {/* Decline Alert Card */}
        {declineDetails && (
          <div className="mb-5 p-4 rounded-2xl bg-gradient-to-br from-rose-500/10 via-rose-500/5 to-slate-900/10 border-2 border-rose-500/30 text-rose-700 dark:text-rose-300 shadow-lg shadow-rose-500/5 animate-in fade-in zoom-in-95 duration-200">
            <div className="flex items-start gap-3">
              <div className="p-2.5 rounded-xl bg-rose-500/20 border border-rose-500/30 text-rose-600 dark:text-rose-400 flex-shrink-0">
                <CreditCard className="w-5 h-5" />
              </div>
              <div className="flex-1 space-y-1.5">
                <div className="flex items-center justify-between gap-2 flex-wrap">
                  <span className="text-xs font-black tracking-wider uppercase text-rose-600 dark:text-rose-400 flex items-center gap-1.5">
                    <XCircle className="w-4 h-4" /> Bank Authorization Declined
                  </span>
                  <span className="font-mono text-[10px] font-bold px-2.5 py-0.5 rounded-md bg-rose-500/20 text-rose-700 dark:text-rose-300 border border-rose-500/30">
                    {declineDetails.badge}
                  </span>
                </div>
                <h4 className="text-sm font-bold text-slate-900 dark:text-slate-100">
                  {declineDetails.title}
                </h4>
                <p className="text-xs text-slate-600 dark:text-slate-300 leading-relaxed">
                  {declineDetails.description}
                </p>
                <div className="pt-2 text-[11px] text-amber-800 dark:text-amber-200 bg-amber-500/10 border border-amber-500/20 rounded-xl p-2.5 flex items-start gap-2">
                  <span className="font-bold text-amber-600 dark:text-amber-400 flex-shrink-0">💡 Recommendation:</span>
                  <span>{declineDetails.suggestion}</span>
                </div>
                <div className="pt-1 flex items-center justify-between text-[11px] text-slate-500 dark:text-slate-400">
                  <span>Audit recorded in Prometheus & Grafana</span>
                  <button
                    type="button"
                    onClick={() => {
                      setDeclineDetails(null);
                      setStepError(null);
                      setFormData({ ...formData, paymentMethod: 'SIMULATED_APPROVED' });
                    }}
                    className="inline-flex items-center gap-1 text-xs font-bold text-indigo-600 dark:text-indigo-400 hover:underline cursor-pointer"
                  >
                    <RefreshCw className="w-3 h-3" /> Switch to Approved Card
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Regular Step Error Notification (when not a decline card) */}
        {!declineDetails && stepError && (
          <div className="mb-4 p-3.5 rounded-2xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            <span>{stepError}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* STEP 1: Customer & Address */}
          {currentStep === 'CUSTOMER_INFO' && (
            <div className="space-y-4 animate-in fade-in">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label htmlFor="checkout-customer-name" className="block text-xs font-bold text-slate-700 dark:text-slate-300 mb-1.5">
                    Full Name
                  </label>
                  <input
                    id="checkout-customer-name"
                    type="text"
                    required
                    value={formData.customerName}
                    onChange={(e) => setFormData({ ...formData, customerName: e.target.value })}
                    className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-slate-900 dark:text-slate-100 text-sm focus:border-indigo-500 focus:outline-none transition"
                  />
                </div>
                <div>
                  <label htmlFor="checkout-customer-email" className="block text-xs font-bold text-slate-700 dark:text-slate-300 mb-1.5">
                    Email Address
                  </label>
                  <input
                    id="checkout-customer-email"
                    type="email"
                    required
                    value={formData.customerEmail}
                    onChange={(e) => setFormData({ ...formData, customerEmail: e.target.value })}
                    className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-slate-900 dark:text-slate-100 text-sm focus:border-indigo-500 focus:outline-none transition"
                  />
                </div>
              </div>

              <div>
                <label htmlFor="checkout-shipping-address" className="block text-xs font-bold text-slate-700 dark:text-slate-300 mb-1.5">
                  Shipping Address
                </label>
                <input
                  id="checkout-shipping-address"
                  type="text"
                  required
                  value={formData.shippingAddress}
                  onChange={(e) => setFormData({ ...formData, shippingAddress: e.target.value })}
                  placeholder="Street, suite, building"
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-slate-900 dark:text-slate-100 text-sm focus:border-indigo-500 focus:outline-none transition"
                />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <label htmlFor="checkout-city" className="block text-xs font-bold text-slate-700 dark:text-slate-300 mb-1.5">
                    City
                  </label>
                  <input
                    id="checkout-city"
                    type="text"
                    required
                    value={formData.city}
                    onChange={(e) => setFormData({ ...formData, city: e.target.value })}
                    className="w-full px-3 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-slate-900 dark:text-slate-100 text-sm focus:border-indigo-500 focus:outline-none transition"
                  />
                </div>
                <div>
                  <label htmlFor="checkout-postal-code" className="block text-xs font-bold text-slate-700 dark:text-slate-300 mb-1.5">
                    ZIP Code
                  </label>
                  <input
                    id="checkout-postal-code"
                    type="text"
                    required
                    value={formData.postalCode}
                    onChange={(e) => setFormData({ ...formData, postalCode: e.target.value })}
                    className="w-full px-3 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-slate-900 dark:text-slate-100 text-sm focus:border-indigo-500 focus:outline-none transition"
                  />
                </div>
                <div>
                  <label htmlFor="checkout-phone" className="block text-xs font-bold text-slate-700 dark:text-slate-300 mb-1.5">
                    Phone
                  </label>
                  <input
                    id="checkout-phone"
                    type="text"
                    required
                    value={formData.phone}
                    onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                    className="w-full px-3 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-slate-900 dark:text-slate-100 text-sm focus:border-indigo-500 focus:outline-none transition"
                  />
                </div>
              </div>

              <button
                type="button"
                onClick={() => handleNextStep('DELIVERY_TIER')}
                className="w-full mt-4 py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-lg shadow-indigo-500/25 flex items-center justify-center gap-2 transition"
              >
                Continue to Delivery Method
                <ArrowRight className="w-4 h-4" />
              </button>
            </div>
          )}

          {/* STEP 2: Delivery Method */}
          {currentStep === 'DELIVERY_TIER' && (
            <div className="space-y-4 animate-in fade-in">
              <div className="block text-xs font-bold text-slate-700 dark:text-slate-300 mb-1.5">
                Select Shipping Carrier Service
              </div>

              <div className="space-y-3">
                {[
                  {
                    id: 'DHL Express Delivery (Priority 24h)',
                    title: 'DHL Express Priority (24-48 hrs)',
                    desc: 'Local demo shipping option with an order tracking reference. No live carrier connection or signature capture.',
                    badge: 'Recommended',
                  },
                  {
                    id: 'FedEx Standard Ground (3-5 days)',
                    title: 'FedEx Ground Standard (3-5 business days)',
                    desc: 'Reliable nationwide ground shipping',
                    badge: 'Economy',
                  },
                ].map((tier) => (
                  <button
                    type="button"
                    key={tier.id}
                    onClick={() => setFormData({ ...formData, deliveryMethod: tier.id })}
                    className={`w-full text-left p-4 rounded-2xl border cursor-pointer transition-all flex items-start justify-between ${
                      formData.deliveryMethod === tier.id
                        ? 'border-indigo-600 bg-indigo-50/50 dark:bg-indigo-950/30'
                        : 'border-slate-200 dark:border-slate-800 hover:bg-slate-50 dark:hover:bg-slate-800/40'
                    }`}
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-sm text-slate-900 dark:text-white">
                          {tier.title}
                        </span>
                        <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 border border-indigo-500/20">
                          {tier.badge}
                        </span>
                      </div>
                      <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">{tier.desc}</p>
                    </div>
                    <Truck className="w-5 h-5 text-indigo-600 dark:text-indigo-400 flex-shrink-0" />
                  </button>
                ))}
              </div>

              <div className="flex gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => handlePrevStep('CUSTOMER_INFO')}
                  className="w-1/3 py-3 px-4 rounded-xl border border-slate-200 dark:border-slate-700 text-slate-700 dark:text-slate-300 font-bold text-xs flex items-center justify-center gap-1.5 transition"
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                  Back
                </button>
                <button
                  type="button"
                  onClick={() => handleNextStep('PAYMENT')}
                  className="w-2/3 py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-lg shadow-indigo-500/25 flex items-center justify-center gap-2 transition"
                >
                  Continue to Payment
                  <ArrowRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          )}

          {/* STEP 3: Payment */}
          {currentStep === 'PROCESSING' && (
            <div className="py-12 flex flex-col items-center text-center gap-4" role="status" aria-live="polite">
              <Loader2 className="w-10 h-10 text-indigo-500 animate-spin" />
              <div>
                <p className="font-bold text-slate-900 dark:text-white">
                  {formData.paymentMethod === 'SIMULATED_APPROVED'
                    ? 'Executing Distributed Saga & Verifying Inventory...'
                    : 'Contacting Card Issuer Interbank Network (Visa / Mastercard)...'}
                </p>
                <p className="text-sm text-slate-500 dark:text-slate-400">
                  {formData.paymentMethod === 'SIMULATED_APPROVED'
                    ? 'Transactional outbox dispatch with atomic stock reservation.'
                    : 'Validating credit line, expiration date, and cryptographic chip PIN...'}
                </p>
              </div>
            </div>
          )}

          {currentStep === 'PAYMENT' && (
            <div className="space-y-4 animate-in fade-in">
              <div>
                <label htmlFor="checkout-payment-method" className="block text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider mb-2 flex items-center justify-between">
                  <span>Payment Method & Issuer Simulation</span>
                  <span className="text-[10px] font-normal text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-950/60 px-2 py-0.5 rounded-full border border-indigo-200/50 dark:border-indigo-800/50">
                    POS Sandbox Terminal
                  </span>
                </label>
                <select
                  id="checkout-payment-method"
                  required
                  value={formData.paymentMethod}
                  onChange={(e) => {
                    setFormData({ ...formData, paymentMethod: e.target.value });
                    setDeclineDetails(null);
                    setStepError(null);
                  }}
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-800 text-slate-900 dark:text-slate-100 text-sm focus:border-indigo-500 focus:outline-none transition font-medium"
                >
                  <optgroup label="✅ Approved Transactions">
                    <option value="SIMULATED_APPROVED">
                      Visa / Mastercard Credit (Standard Approval)
                    </option>
                  </optgroup>
                  <optgroup label="❌ Realistic Bank Declines (Grafana Telemetry)">
                    <option value="SIMULATED_DECLINED_INSUFFICIENT_FUNDS">
                      ❌ Insufficient Funds / Credit Limit Exceeded (Code 51)
                    </option>
                    <option value="SIMULATED_DECLINED_INCORRECT_PIN">
                      ❌ Invalid Security PIN or CVV Code (Code 55)
                    </option>
                    <option value="SIMULATED_DECLINED_SUSPECTED_FRAUD">
                      ❌ Security Hold / Suspected Fraud Lock (Code 59)
                    </option>
                    <option value="SIMULATED_DECLINED_EXPIRED_CARD">
                      ❌ Expired Card / Validity Elapsed (Code 54)
                    </option>
                    <option value="SIMULATED_DECLINED">
                      ❌ General Issuer Decline (Code 05)
                    </option>
                  </optgroup>
                </select>
                <p className="mt-2 text-xs text-slate-500 dark:text-slate-400 bg-slate-100 dark:bg-slate-900/60 border border-slate-200 dark:border-slate-800 rounded-xl p-3 flex items-start gap-2">
                  <Lock className="w-4 h-4 text-slate-400 flex-shrink-0 mt-0.5" />
                  <span>
                    Sandbox simulation connected to <code>payments-service</code>. Bank declines populate real-time Grafana telemetry without mutating warehouse inventory.
                  </span>
                </p>
              </div>

              {/* Order Summary Line */}
              <div className="p-4 rounded-2xl bg-slate-50 dark:bg-slate-950 border border-slate-200/80 dark:border-slate-800/80 flex justify-between items-center my-4">
                <div>
                  <span className="text-xs text-slate-500 dark:text-slate-400 block">
                    Total Due ({cart.length} item(s))
                  </span>
                  <span className="text-2xl font-black text-indigo-600 dark:text-indigo-400">
                    {formatPrice(total)}
                  </span>
                </div>
                <div className="flex items-center gap-1.5 text-xs text-emerald-600 dark:text-emerald-400 font-semibold bg-emerald-500/10 border border-emerald-500/20 px-3 py-1.5 rounded-xl">
                  <ShieldCheck className="w-4 h-4" />
                  Saga Guarantee
                </div>
              </div>

              <div className="flex gap-3 pt-2">
                <button
                  type="button"
                  disabled={isLoading}
                  onClick={() => handlePrevStep('DELIVERY_TIER')}
                  className="w-1/3 py-3.5 px-4 rounded-xl border border-slate-200 dark:border-slate-700 text-slate-700 dark:text-slate-300 font-bold text-xs flex items-center justify-center gap-1.5 transition disabled:opacity-50"
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                  Back
                </button>

                <button
                  type="submit"
                  disabled={isLoading || cart.length === 0}
                  className={`w-2/3 py-3.5 px-4 rounded-xl font-bold text-sm shadow-xl flex items-center justify-center gap-2 transition transform active:scale-95 ${
                    formData.paymentMethod === 'SIMULATED_APPROVED'
                      ? 'bg-gradient-to-r from-indigo-600 to-violet-600 hover:opacity-95 text-white shadow-indigo-500/25'
                      : 'bg-gradient-to-r from-rose-600 to-red-600 hover:opacity-95 text-white shadow-rose-500/25'
                  }`}
                >
                  {isLoading ? (
                    <>
                      <Loader2 className="w-5 h-5 animate-spin" />
                      {formData.paymentMethod === 'SIMULATED_APPROVED'
                        ? 'Processing Saga...'
                        : 'Authorizing with Issuer...'}
                    </>
                  ) : formData.paymentMethod === 'SIMULATED_APPROVED' ? (
                    <>
                      <CheckCircle2 className="w-5 h-5" />
                      Confirm & Place Order ({formatPrice(total)})
                    </>
                  ) : (
                    <>
                      <XCircle className="w-5 h-5" />
                      Test Bank Decline ({formatPrice(total)})
                    </>
                  )}
                </button>
              </div>
            </div>
          )}
        </form>
      </div>
    </div>
  );
};
