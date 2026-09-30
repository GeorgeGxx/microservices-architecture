import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import {
  Package,
  Search,
  Truck,
  CheckCircle2,
  Clock,
  XCircle,
  FileText,
  Ban,
  ExternalLink,
  ChevronDown,
  ChevronUp,
  ChevronLeft,
  ChevronRight,
  MapPin,
  Calendar,
  AlertCircle,
  Lock
} from 'lucide-react';
import { Order } from '../types';
import { fetchOrders, submitCancelOrder } from '../services/graphql';
import { useAuth } from '../context/AuthContext';
import { useCurrency } from '../context/CurrencyContext';
import { useNotifications } from '../context/NotificationContext';
import { processOrders } from '../utils/orderProcessing';
import { canCancelOrder } from '../utils/orderPipeline';
import { OrderLivePipeline } from '../components/OrderLivePipeline';
import { sseService } from '../services/sse';
import { getOrderStatusPresentation } from '../utils/orderFulfillment';

interface OrdersPageProps {
  onOpenReceipt: (order: Order) => void;
  onNavigateToCatalog: () => void;
}

export const OrdersPage: React.FC<OrdersPageProps> = ({ onOpenReceipt, onNavigateToCatalog }) => {
  const { user, login } = useAuth();
  const accessToken = user?.token;
  const hasUser = Boolean(user);
  const { formatPrice } = useCurrency();
  const { showToast } = useNotifications();

  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('ALL');
  const [expandedOrders, setExpandedOrders] = useState<Record<string, boolean>>({});
  const [cancellingId, setCancellingId] = useState<string | null>(null);

  // Pagination states
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState(5);

  const orderRefreshInProgress = useRef(false);
  const ordersRef = useRef<Order[]>([]);
  const orderEventRefreshTimeout = useRef<number | null>(null);
  const loadOrders = useCallback(async (showLoading = false) => {
    if (orderRefreshInProgress.current) return;
    if (!hasUser) {
      setOrders([]);
      setLoading(false);
      return;
    }

    orderRefreshInProgress.current = true;
    if (showLoading) {
      setLoading(true);
      setError(null);
    }

    try {
      const data = await fetchOrders(accessToken);
      const nextOrders = data || [];
      ordersRef.current = nextOrders;
      setOrders(nextOrders);
      setError(null);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Error loading orders';
      if (showLoading) {
        setError(message);
        setOrders([]);
      }
    } finally {
      if (showLoading) setLoading(false);
      orderRefreshInProgress.current = false;
    }
  }, [accessToken, hasUser]);

  useEffect(() => {
    if (!hasUser) {
      void loadOrders(true);
      return;
    }

    void loadOrders(true);

    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') void loadOrders();
    };
    const intervalId = window.setInterval(refreshWhenVisible, 30_000);
    document.addEventListener('visibilitychange', refreshWhenVisible);

    const unsubscribeOrderEvents = sseService.subscribeOrderStatus((event) => {
      // The SSE stream is shared. Only refresh when the order belongs to this user's
      // already-authorized result set; the API remains the source of truth.
      const ownOrder = ordersRef.current.find((order) => order.orderNumber === event.orderNumber);
      if (!ownOrder || ownOrder.orderStatus.toUpperCase() === event.orderStatus) return;
      if (orderEventRefreshTimeout.current !== null) window.clearTimeout(orderEventRefreshTimeout.current);
      orderEventRefreshTimeout.current = window.setTimeout(() => {
        orderEventRefreshTimeout.current = null;
        void loadOrders();
      }, 500);
    });

    return () => {
      window.clearInterval(intervalId);
      if (orderEventRefreshTimeout.current !== null) window.clearTimeout(orderEventRefreshTimeout.current);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
      unsubscribeOrderEvents();
    };
  }, [hasUser, loadOrders]);

  // Reset page when filters change
  useEffect(() => {
    setCurrentPage(1);
  }, [searchTerm, statusFilter]);

  // Statuses are authoritative values returned by Orders Service.
  const effectiveOrders = orders;

  // Tab count metrics calculated dynamically from effectiveOrders
  const tabCounts = useMemo(() => {
    const counts: Record<string, number> = {
      ALL: effectiveOrders.length,
      PLACED: 0,
      SHIPPED: 0,
      DELIVERED: 0,
      CANCELLED: 0,
    };
    effectiveOrders.forEach((o) => {
      const s = o.orderStatus.toUpperCase();
      if (counts[s] !== undefined) {
        counts[s]++;
      }
    });
    return counts;
  }, [effectiveOrders]);

  // Pure domain processing: Inverted (newest first), filtered, and paginated
  const {
    paginatedOrders,
    totalOrders,
    totalPages,
    startIndex,
    endIndex,
  } = useMemo(() => {
    return processOrders(effectiveOrders, {
      searchTerm,
      statusFilter,
      page: currentPage,
      pageSize,
    });
  }, [effectiveOrders, searchTerm, statusFilter, currentPage, pageSize]);

  if (!user) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-20 text-center animate-in fade-in">
        <div className="glass-card p-10 rounded-3xl border border-slate-800 space-y-4">
          <div className="w-16 h-16 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 flex items-center justify-center mx-auto">
            <Package className="w-8 h-8" />
          </div>
          <h2 className="text-2xl font-black text-white">Sign In to View Your Orders</h2>
          <p className="text-sm text-slate-400 max-w-md mx-auto">
            You are currently browsing in guest mode. Sign in with your Keycloak account to view your orders, download receipts, and check persisted fulfillment status.
          </p>
          <div className="pt-4 flex items-center justify-center gap-3">
            <button
              onClick={login}
              className="px-6 py-3 rounded-xl bg-gradient-to-r from-indigo-600 to-violet-600 hover:opacity-90 text-white font-bold text-sm shadow-xl shadow-indigo-500/25 transition active:scale-95"
            >
              Sign In with Keycloak
            </button>
            <button
              onClick={onNavigateToCatalog}
              className="px-5 py-3 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 font-semibold text-sm transition"
            >
              Back to Catalog
            </button>
          </div>
        </div>
      </div>
    );
  }

  const toggleExpand = (id: string) => {
    setExpandedOrders((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const handleCancelOrder = async (orderId: string, orderNumber: string) => {
    if (!confirm(`Are you sure you want to cancel order ${orderNumber}?`)) return;
    try {
      setCancellingId(orderId);
      await submitCancelOrder(orderId, user?.token);
      showToast('Order Cancelled', `Order #${orderNumber} was cancelled before dispatch. Inventory was restored.`, 'system');
      // Reflect the persisted mutation immediately while the periodic refresh catches up.
      setOrders((prev) =>
        prev.map((o) => (o.id === orderId ? { ...o, orderStatus: 'CANCELLED' } : o))
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Could not cancel order';
      showToast('Cancellation Failed', msg, 'system');
    } finally {
      setCancellingId(null);
    }
  };

  const getStatusBadge = (status: string) => {
    const s = status.toUpperCase();
    const presentation = getOrderStatusPresentation(s);
    switch (s) {
      case 'DELIVERED':
        return (
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
            <CheckCircle2 className="w-3.5 h-3.5" /> {presentation.label}
          </span>
        );
      case 'SHIPPED':
        return (
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20">
            <Truck className="w-3.5 h-3.5" /> {presentation.label}
          </span>
        );
      case 'PLACED':
        return (
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
            <Clock className="w-3.5 h-3.5" /> {presentation.label}
          </span>
        );
      case 'CANCELLED':
        return (
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-rose-500/10 text-rose-600 dark:text-rose-400 border border-rose-500/20">
            <XCircle className="w-3.5 h-3.5" /> {presentation.label}
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20">
            {status}
          </span>
        );
    }
  };

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 animate-in fade-in">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-8">
        <div>
          <div className="flex items-center gap-2">
            <span className="p-2 rounded-xl bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 border border-indigo-500/20">
              <Package className="w-6 h-6" />
            </span>
            <h1 className="text-3xl font-extrabold tracking-tight text-slate-900 dark:text-white">
              Order History & Tracking
            </h1>
          </div>
          <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">
            Order events refresh this history automatically; a 30-second check is the fallback. Carrier codes are references, not live carrier telemetry.
          </p>
        </div>

      </div>

      {/* Filter and Search Bar */}
      <div className="glass-card p-4 rounded-2xl mb-8 flex flex-col md:flex-row gap-4 items-center justify-between">
        {/* Search */}
        <div className="relative w-full md:w-96">
          <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Search by order #, customer, or tracking code..."
            className="w-full pl-10 pr-4 py-2 rounded-xl text-sm bg-slate-50 dark:bg-slate-800/70 border border-slate-200 dark:border-slate-700/60 text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500/50"
          />
        </div>

        {/* Status Filter Tabs with Dynamic Counters */}
        <div className="flex items-center gap-1.5 overflow-x-auto w-full md:w-auto pb-1 md:pb-0">
          {[
            { id: 'ALL', label: 'All Orders' },
            { id: 'PLACED', label: 'Placed' },
            { id: 'SHIPPED', label: 'In Transit' },
            { id: 'DELIVERED', label: 'Delivered' },
            { id: 'CANCELLED', label: 'Cancelled' },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setStatusFilter(tab.id)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium whitespace-nowrap transition-all flex items-center gap-1.5 ${
                statusFilter === tab.id
                  ? 'bg-indigo-600 text-white shadow-sm shadow-indigo-500/20'
                  : 'text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800/50'
              }`}
            >
              <span>{tab.label}</span>
              <span
                className={`text-[10px] font-bold px-1.5 py-0.2 rounded-full ${
                  statusFilter === tab.id
                    ? 'bg-white/20 text-white'
                    : 'bg-slate-200 dark:bg-slate-800 text-slate-500 dark:text-slate-400'
                }`}
              >
                {tabCounts[tab.id] || 0}
              </span>
            </button>
          ))}
        </div>
      </div>

      {/* Error state */}
      {error && (
        <div className="p-4 mb-6 rounded-2xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 flex items-center gap-3">
          <AlertCircle className="w-5 h-5 shrink-0" />
          <p className="text-sm font-medium">{error}</p>
        </div>
      )}

      {/* Loading Skeleton */}
      {loading ? (
        <div className="space-y-4">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="glass-card rounded-2xl p-6 border border-slate-200/80 dark:border-slate-800/80 animate-pulse space-y-4"
            >
              <div className="flex items-center justify-between">
                <div className="h-6 bg-slate-200 dark:bg-slate-800 rounded w-1/4"></div>
                <div className="h-6 bg-slate-200 dark:bg-slate-800 rounded w-20"></div>
              </div>
              <div className="h-4 bg-slate-200 dark:bg-slate-800 rounded w-1/2"></div>
            </div>
          ))}
        </div>
      ) : totalOrders === 0 ? (
        /* Empty State */
        <div className="glass-card rounded-2xl border border-slate-200/80 dark:border-slate-800/80 p-12 text-center">
          <div className="w-16 h-16 rounded-2xl bg-slate-100 dark:bg-slate-800 text-slate-400 flex items-center justify-center mx-auto mb-4">
            <Package className="w-8 h-8" />
          </div>
          <h3 className="text-lg font-bold text-slate-900 dark:text-white mb-1">
            No matching orders found
          </h3>
          <p className="text-sm text-slate-500 dark:text-slate-400 max-w-sm mx-auto mb-6">
            {searchTerm || statusFilter !== 'ALL'
              ? 'Try adjusting your search criteria or resetting your status filters.'
              : 'You have not placed any orders yet. Discover high-precision electronics in our catalog!'}
          </p>
          <button
            onClick={onNavigateToCatalog}
            className="px-6 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm transition-colors shadow-md shadow-indigo-500/20"
          >
            Explore Catalog
          </button>
        </div>
      ) : (
        /* Orders List (Sorted Newest-First and Paginated) */
        <div className="space-y-4">
          {paginatedOrders.map((order) => {
            const isExpanded = expandedOrders[order.id];
            const effectiveStatus = order.orderStatus;
            const canCancel = canCancelOrder(effectiveStatus);

            return (
              <div
                key={order.id}
                className="glass-card rounded-2xl border border-slate-200/80 dark:border-slate-800/80 overflow-hidden transition-all hover:border-indigo-500/30"
              >
                {/* Main Order Row */}
                <div className="p-5 flex flex-col lg:flex-row lg:items-center justify-between gap-4">
                  <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                    <div className="p-3 rounded-xl bg-indigo-50 dark:bg-indigo-950/40 text-indigo-600 dark:text-indigo-400 border border-indigo-100 dark:border-indigo-900/40 self-start">
                      <Package className="w-6 h-6" />
                    </div>

                    <div>
                      <div className="flex items-center gap-3 flex-wrap">
                        <span className="font-mono text-base font-bold text-slate-900 dark:text-white">
                          {order.orderNumber}
                        </span>
                        {getStatusBadge(effectiveStatus)}
                      </div>
                      <div className="flex items-center gap-4 mt-1 text-xs text-slate-500 dark:text-slate-400 flex-wrap">
                        <span className="flex items-center gap-1">
                          <Calendar className="w-3.5 h-3.5" />
                          {order.createdAt
                            ? new Date(order.createdAt).toLocaleDateString('en-US', {
                                day: '2-digit',
                                month: 'short',
                                year: 'numeric',
                                hour: '2-digit',
                                minute: '2-digit',
                              })
                            : 'Recent Order'}
                        </span>
                        <span>•</span>
                        <span>
                          Customer: <strong className="text-slate-700 dark:text-slate-300">{order.customerName}</strong>
                        </span>
                        {order.trackingNumber && (
                          <>
                            <span>•</span>
                            <span className="flex items-center gap-1 font-mono text-indigo-500 dark:text-indigo-400">
                              <Truck className="w-3.5 h-3.5" /> {order.trackingNumber}
                            </span>
                          </>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Actions & Price */}
                  <div className="flex items-center justify-between lg:justify-end gap-4 pt-3 lg:pt-0 border-t lg:border-t-0 border-slate-100 dark:border-slate-800">
                    <div className="text-right">
                      <div className="text-xs text-slate-500 dark:text-slate-400">Total Amount</div>
                      <div className="text-lg font-black text-slate-900 dark:text-white font-mono">
                        {formatPrice(order.totalAmount || 0)}
                      </div>
                    </div>

                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => onOpenReceipt(order)}
                        title="Download official PDF receipt"
                        className="p-2 rounded-xl bg-slate-100 dark:bg-slate-800/80 hover:bg-indigo-50 dark:hover:bg-indigo-950/50 text-slate-700 dark:text-slate-300 hover:text-indigo-600 dark:hover:text-indigo-400 border border-slate-200 dark:border-slate-700/60 transition-colors"
                      >
                        <FileText className="w-4 h-4" />
                      </button>

                      {canCancel && (
                        <button
                          onClick={() => handleCancelOrder(order.id, order.orderNumber)}
                          disabled={cancellingId === order.id}
                          title="Cancel before dispatch"
                          aria-label={`Cancel order ${order.orderNumber} before dispatch`}
                          className="inline-flex items-center gap-1.5 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-600 shadow-sm transition-all hover:scale-[1.02] hover:bg-rose-100 active:scale-95 disabled:cursor-wait disabled:opacity-60 dark:border-rose-900/40 dark:bg-rose-950/30 dark:text-rose-400 dark:hover:bg-rose-900/40"
                        >
                          <Ban className={`h-3.5 w-3.5 ${cancellingId === order.id ? 'animate-pulse' : ''}`} />
                          {cancellingId === order.id ? 'Cancelling…' : 'Cancel order'}
                        </button>
                      )}

                      <button
                        onClick={() => toggleExpand(order.id)}
                        className="inline-flex items-center gap-1 px-3 py-2 rounded-xl bg-slate-100 dark:bg-slate-800/80 hover:bg-slate-200 dark:hover:bg-slate-700/60 text-xs font-semibold text-slate-700 dark:text-slate-300 border border-slate-200 dark:border-slate-700/60 transition-colors"
                      >
                        {isExpanded ? (
                          <>
                            <span>Hide Details</span>
                            <ChevronUp className="w-3.5 h-3.5" />
                          </>
                        ) : (
                          <>
                            <span>Tracking & Items</span>
                            <ChevronDown className="w-3.5 h-3.5" />
                          </>
                        )}
                      </button>
                    </div>
                  </div>
                </div>

                {/* Expanded Details: Tracking Steps & Items */}
                {isExpanded && (
                  <div className="border-t border-slate-100 dark:border-slate-800/80 bg-slate-50/50 dark:bg-slate-900/30 p-6 space-y-6 animate-in slide-in-from-top-2 duration-200">
                    {/* Fulfillment stepper derived from persisted Orders Service status */}
                    <OrderLivePipeline
                      orderNumber={order.orderNumber}
                      carrier={order.carrier || 'DHL Express'}
                      trackingNumber={order.trackingNumber}
                      initialStatus={order.orderStatus}
                    />

                    {/* Order Line Items */}
                    <div>
                      <h4 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-3">
                        Purchased Items ({order.orderItems?.length || 0})
                      </h4>
                      <div className="space-y-2">
                        {order.orderItems?.map((item, idx) => (
                          <div
                            key={idx}
                            className="flex items-center justify-between p-3 rounded-xl bg-white dark:bg-slate-800/80 border border-slate-200/60 dark:border-slate-700/60 text-xs"
                          >
                            <div className="flex items-center gap-3">
                              <span className="font-mono font-bold text-indigo-600 dark:text-indigo-400">
                                {item.sku}
                              </span>
                              <span className="text-slate-400">×</span>
                              <span className="font-semibold text-slate-900 dark:text-white">
                                {item.quantity} {item.quantity === 1 ? 'unit' : 'units'}
                              </span>
                            </div>
                            <span className="font-mono font-bold text-slate-900 dark:text-white">
                              {formatPrice(item.price * item.quantity)}
                            </span>
                          </div>
                        ))}
                      </div>
                    </div>

                    {/* Shipping & Payment summary */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs pt-2">
                      <div className="p-3.5 rounded-xl bg-white dark:bg-slate-800/80 border border-slate-200/60 dark:border-slate-700/60 space-y-1">
                        <div className="font-bold text-slate-700 dark:text-slate-300 flex items-center gap-1.5">
                          <MapPin className="w-3.5 h-3.5 text-indigo-500" /> Shipping Destination
                        </div>
                        <p className="text-slate-600 dark:text-slate-400">
                          {order.shippingAddress || 'Not specified'}
                        </p>
                        <p className="text-slate-600 dark:text-slate-400">
                          {order.city} {order.postalCode}
                        </p>
                      </div>

                      <div className="p-3.5 rounded-xl bg-white dark:bg-slate-800/80 border border-slate-200/60 dark:border-slate-700/60 space-y-1">
                        <div className="font-bold text-slate-700 dark:text-slate-300 flex items-center gap-1.5">
                          <AlertCircle className="w-3.5 h-3.5 text-indigo-500" /> Billing & Payment
                        </div>
                        <p className="text-slate-600 dark:text-slate-400">
                          Method: <strong>{order.paymentMethod || 'Credit Card'}</strong>
                        </p>
                        <p className="text-slate-600 dark:text-slate-400">
                          Email: {order.customerEmail || 'Not registered'}
                        </p>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Full Pagination Toolbar */}
      {!loading && !error && totalOrders > 0 && (
        <div className="mt-8 glass-card p-4 rounded-2xl border border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex flex-wrap items-center gap-3 text-xs text-slate-400">
            <span>
              Showing <strong className="text-white">{startIndex}</strong> to{' '}
              <strong className="text-white">{endIndex}</strong> of{' '}
              <strong className="text-white">{totalOrders}</strong> orders
            </span>
            <div className="flex items-center gap-1.5 ml-1">
              <span className="text-slate-500">Per page:</span>
              {[5, 10, 20, 50].map((size) => (
                <button
                  key={size}
                  onClick={() => {
                    setPageSize(size);
                    setCurrentPage(1);
                  }}
                  className={`px-2 py-1 rounded-lg text-xs font-mono font-semibold transition ${
                    pageSize === size
                      ? 'bg-indigo-600 text-white shadow-sm'
                      : 'bg-slate-900 text-slate-400 hover:text-white border border-slate-800'
                  }`}
                >
                  {size}
                </button>
              ))}
            </div>
          </div>

          {totalPages > 1 && (
            <div className="flex items-center gap-2">
              <button
                onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                disabled={currentPage === 1}
                className="p-2 rounded-xl bg-slate-900 border border-slate-800 text-slate-300 hover:text-white disabled:opacity-40 transition"
                title="Previous Page"
              >
                <ChevronLeft className="w-4 h-4" />
              </button>

              <div className="flex items-center gap-1">
                {Array.from({ length: totalPages }, (_, i) => i + 1).map((p) => (
                  <button
                    key={p}
                    onClick={() => setCurrentPage(p)}
                    className={`w-8 h-8 rounded-xl text-xs font-bold font-mono transition ${
                      currentPage === p
                        ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/25'
                        : 'bg-slate-900 text-slate-400 hover:text-white border border-slate-800'
                    }`}
                  >
                    {p}
                  </button>
                ))}
              </div>

              <button
                onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                disabled={currentPage === totalPages}
                className="p-2 rounded-xl bg-slate-900 border border-slate-800 text-slate-300 hover:text-white disabled:opacity-40 transition"
                title="Next Page"
              >
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
export default OrdersPage;
