import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  AlertTriangle,
  DollarSign,
  Package,
  Layers,
  ShieldCheck,
  TrendingUp,
  Search,
  Plus,
  Edit2,
  Trash2,
  QrCode,
  Image as ImageIcon,
  Sparkles,
  Lock,
  Ban,
  Clock,
  Truck,
  XCircle,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import { Product, Order, InventoryItem } from '../types';
import { fetchProducts, fetchOrders, fetchInventories, submitCancelOrder, submitDeliverOrder, submitShipOrder } from '../services/graphql';
import { deleteProduct, saveOrUpdateStock, updateProduct, updateStockQuantity } from '../services/api';
import { createProductWithInitialStock } from '../services/adminCatalog';
import { compressProductImage } from '../utils/compressProductImage';
import { useAuth } from '../context/AuthContext';
import { useCurrency } from '../context/CurrencyContext';
import { useNotifications } from '../context/NotificationContext';
import { ProductQRModal } from '../components/ProductQRModal';
import { getOrderStatusPresentation } from '../utils/orderFulfillment';
import { sortOrdersNewestFirst } from '../utils/orderProcessing';
import { getOrderStatusNotificationCopy } from '../utils/orderNotificationCopy';

// Popular 1-Click Hardware Presets for Rapid Admin Upload
const HARDWARE_PRESETS = [
  {
    sku: 'LAPTOP-PRO-16',
    name: 'MacBook Pro 16" M3 Max Liquid Retina',
    description: '16-core CPU, 40-core GPU, 48GB Unified Memory, 1TB SSD Storage with Liquid Retina XDR display.',
    price: 3499.99,
    category: 'Computers',
    stock: 25,
    imageUrl: 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=800&auto=format&fit=crop&q=80',
  },
  {
    sku: 'MONITOR-OLED-34',
    name: 'UltraWide OLED Gaming Monitor 34" 175Hz',
    description: 'Quantum Dot OLED display, 0.1ms response time, HDR True Black 400, curved 1800R immersive panel.',
    price: 999.99,
    category: 'Displays',
    stock: 15,
    imageUrl: 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?w=800&auto=format&fit=crop&q=80',
  },
  {
    sku: 'KEYBOARD-RGB-PRO',
    name: 'Custom Mechanical Keyboard Hot-Swap RGB',
    description: 'CNC Anodized Aluminum frame, Gateron Oil King linear switches, PBT dye-sub keycaps, QMK/VIA programmable.',
    price: 189.99,
    category: 'Peripherals',
    stock: 45,
    imageUrl: 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=800&auto=format&fit=crop&q=80',
  },
  {
    sku: 'MOUSE-ERGO-WL',
    name: 'Master Precision Wireless Ergonomic Mouse',
    description: '8000 DPI Darkfield sensor, MagSpeed electromagnetic wheel, Quiet Click buttons, multi-device flow.',
    price: 99.99,
    category: 'Peripherals',
    stock: 60,
    imageUrl: 'https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?w=800&auto=format&fit=crop&q=80',
  },
  {
    sku: 'HEADPHONES-ANC-8',
    name: 'Studio Wireless Headphones Active Noise Canceling',
    description: 'Custom 40mm drivers, lossless audio over USB-C, 30-hour battery life with active smart transparency.',
    price: 349.99,
    category: 'Audio',
    stock: 35,
    imageUrl: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=800&auto=format&fit=crop&q=80',
  },
  {
    sku: 'GPU-RTX-4080-SUPER',
    name: 'GeForce RTX 4080 Super 16GB GDDR6X',
    description: 'Ada Lovelace architecture, DLSS 3 frame generation, 4th gen Tensor cores with triple axial fans.',
    price: 1199.99,
    category: 'Components',
    stock: 10,
    imageUrl: 'https://images.unsplash.com/photo-1591799264318-7e6ef8ddb7ea?w=800&auto=format&fit=crop&q=80',
  },
];

export const AdminDashboardPage: React.FC = () => {
  const { user, login } = useAuth();
  const { formatPrice } = useCurrency();
  const { showToast } = useNotifications();

  const [activeTab, setActiveTab] = useState<'catalog' | 'inventory' | 'orders'>('catalog');
  const [products, setProducts] = useState<Product[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [inventories, setInventories] = useState<InventoryItem[]>([]);
  const refreshInProgress = useRef(false);

  // Filters
  const [productSearch, setProductSearch] = useState('');
  const [inventorySearch, setInventorySearch] = useState('');
  const [orderSearch, setOrderSearch] = useState('');

  // Pagination states
  const [productsPage, setProductsPage] = useState(1);
  const [productsPageSize, setProductsPageSize] = useState(5);

  const [inventoryPage, setInventoryPage] = useState(1);
  const [inventoryPageSize, setInventoryPageSize] = useState(6);

  const [ordersPage, setOrdersPage] = useState(1);
  const [ordersPageSize, setOrdersPageSize] = useState(5);

  useEffect(() => {
    setProductsPage(1);
  }, [productSearch]);

  useEffect(() => {
    setInventoryPage(1);
  }, [inventorySearch]);

  useEffect(() => {
    setOrdersPage(1);
  }, [orderSearch]);

  // Product Form State
  const [productForm, setProductForm] = useState({
    sku: '',
    name: '',
    description: '',
    price: 299.99,
    category: 'Computers',
    imageUrl: 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=800&auto=format&fit=crop&q=80',
    initialStock: 50,
    status: true,
  });
  const [selectedImageName, setSelectedImageName] = useState('');
  const previousProductImageUrl = useRef<string | null>(null);
  const productImageInputRef = useRef<HTMLInputElement | null>(null);
  const [isCompressingImage, setIsCompressingImage] = useState(false);
  const [isSubmittingProduct, setIsSubmittingProduct] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [pendingStockInitializations, setPendingStockInitializations] = useState<Array<{ sku: string; name: string; quantity: number }>>([]);
  const [isRetryingStockSku, setIsRetryingStockSku] = useState<string | null>(null);

  // Inventory Quick Adjust Form
  const [inventoryForm, setInventoryForm] = useState({
    sku: '',
    quantity: 50,
  });
  const [isSubmittingInventory, setIsSubmittingInventory] = useState(false);

  // Modals
  const [selectedQRProduct, setSelectedQRProduct] = useState<Product | null>(null);
  const [cancellingOrderId, setCancellingOrderId] = useState<string | null>(null);
  const [updatingOrderId, setUpdatingOrderId] = useState<string | null>(null);

  const loadDashboardData = useCallback(async () => {
    if (refreshInProgress.current) return;
    refreshInProgress.current = true;

    try {
      const [prodRes, ordRes, invRes] = await Promise.allSettled([
        fetchProducts(user?.token),
        fetchOrders(user?.token),
        fetchInventories(user?.token),
      ]);

      if (prodRes.status === 'fulfilled') setProducts(prodRes.value || []);
      if (ordRes.status === 'fulfilled') setOrders(ordRes.value || []);
      if (invRes.status === 'fulfilled') setInventories(invRes.value || []);
    } catch {
      // Graceful fallback
    } finally {
      refreshInProgress.current = false;
    }
  }, [user?.token]);

  useEffect(() => {
    void loadDashboardData();

    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') void loadDashboardData();
    };
    const intervalId = window.setInterval(refreshWhenVisible, 30_000);
    document.addEventListener('visibilitychange', refreshWhenVisible);

    return () => {
      window.clearInterval(intervalId);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
    };
  }, [loadDashboardData]);

  // Check RBAC
  if (!user || !user.isAdmin) {
    return (
      <div className="max-w-3xl mx-auto px-4 py-20 text-center animate-in fade-in">
        <div className="glass-card p-10 rounded-3xl border border-slate-800 space-y-4">
          <div className="w-16 h-16 rounded-2xl bg-rose-500/10 border border-rose-500/20 text-rose-500 flex items-center justify-center mx-auto">
            <Lock className="w-8 h-8" />
          </div>
          <h2 className="text-2xl font-black text-white">Administrator Access Required</h2>
          <p className="text-sm text-slate-400 max-w-md mx-auto">
            The Admin Console requires the <span className="font-mono text-indigo-400">ADMIN</span> role granted by Keycloak IAM SSO.
          </p>
          <div className="pt-4">
            <button
              onClick={login}
              className="px-6 py-3 rounded-xl bg-gradient-to-r from-indigo-600 to-violet-600 hover:opacity-90 text-white font-bold text-sm shadow-xl shadow-indigo-500/25 transition active:scale-95"
            >
              Sign In as Administrator
            </button>
          </div>
        </div>
      </div>
    );
  }

  // Quick Preset Helper
  const applyPreset = (preset: typeof HARDWARE_PRESETS[0]) => {
    setEditingProduct(null);
    setSelectedImageName('');
    previousProductImageUrl.current = null;
    setProductForm({
      sku: preset.sku,
      name: preset.name,
      description: preset.description,
      price: preset.price,
      category: preset.category,
      imageUrl: preset.imageUrl,
      initialStock: preset.stock,
      status: true,
    });
    showToast('Preset Loaded', `Applied template for ${preset.name}`, 'info');
  };

  const beginProductEdit = (product: Product) => {
    setEditingProduct(product);
    setSelectedImageName('');
    previousProductImageUrl.current = null;
    setProductForm({
      sku: product.sku,
      name: product.name,
      description: product.description || '',
      price: product.price,
      category: product.category || 'Computers',
      imageUrl: product.imageUrl || '',
      initialStock: product.quantity ?? 0,
      status: product.status ?? true,
    });
    setActiveTab('catalog');
  };

  const resetProductForm = () => {
    setEditingProduct(null);
    setSelectedImageName('');
    previousProductImageUrl.current = null;
    setProductForm({
      sku: '', name: '', description: '', price: 99.99, category: 'Computers',
      imageUrl: 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=800',
      initialStock: 50, status: true,
    });
  };

  // Update catalog data or create a product and initialize its inventory in the owning services.
  const handleCreateProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    if (editingProduct && !editingProduct.id) {
      showToast('Product Update Failed', 'The catalog response did not include a product ID, so this item cannot be updated safely.', 'system');
      return;
    }
    if (!productForm.sku || !productForm.name || productForm.price <= 0) {
      showToast('Validation Error', 'SKU, name, and positive price are required.', 'system');
      return;
    }

    setIsSubmittingProduct(true);
    const skuClean = productForm.sku.toUpperCase().trim();

    const payload = {
      sku: skuClean,
      name: productForm.name.trim(),
      description: productForm.description.trim(),
      price: Number(productForm.price),
      category: productForm.category,
      imageUrl: productForm.imageUrl.trim() || undefined,
      status: productForm.status,
      rating: editingProduct?.rating ?? 5.0,
      reviewCount: editingProduct?.reviewCount ?? 1,
      isBestSeller: editingProduct?.isBestSeller ?? true,
    };

    try {
      if (editingProduct?.id) {
        await updateProduct(editingProduct.id, payload, user?.token);
        showToast('Product Updated', `${payload.name} was updated in products-service.`, 'order');
        resetProductForm();
        await loadDashboardData();
        return;
      }

      const stockUnits = Math.max(0, Number(productForm.initialStock) || 0);
      const setupResult = await createProductWithInitialStock(payload, stockUnits, user?.token);
      resetProductForm();

      if (setupResult.inventoryInitialized) {
        setPendingStockInitializations((pending) => pending.filter((item) => item.sku !== skuClean));
        showToast('Product & Stock Initialized', `SKU ${skuClean} created with ${stockUnits} units.`, 'order');
      } else {
        setPendingStockInitializations((pending) => [
          ...pending.filter((item) => item.sku !== skuClean),
          { sku: skuClean, name: payload.name, quantity: stockUnits },
        ]);
        const stockError = setupResult.inventoryError;
        showToast('Product Created; Stock Needs Retry', stockError instanceof Error ? stockError.message : 'The product exists, but inventory initialization failed.', 'system');
      }

      await loadDashboardData();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to register product';
      showToast(editingProduct ? 'Product Update Failed' : 'Product Creation Failed', msg, 'system');
    } finally {
      setIsSubmittingProduct(false);
    }
  };

  const retryStockInitialization = async (pendingItem: { sku: string; name: string; quantity: number }) => {
    setIsRetryingStockSku(pendingItem.sku);
    try {
      await saveOrUpdateStock(
        { sku: pendingItem.sku, quantity: pendingItem.quantity },
        user?.token
      );
      showToast('Inventory Initialized', `${pendingItem.sku} now has ${pendingItem.quantity} units.`, 'stock');
      setPendingStockInitializations((pending) => pending.filter((item) => item.sku !== pendingItem.sku));
      await loadDashboardData();
    } catch (err: unknown) {
      showToast('Inventory Retry Failed', err instanceof Error ? err.message : 'Could not initialize inventory.', 'system');
    } finally {
      setIsRetryingStockSku(null);
    }
  };

  // Delete product
  const handleDeleteProduct = async (id: string, name: string) => {
    if (!confirm(`Are you sure you want to delete product "${name}"?`)) return;
    try {
      await deleteProduct(id, user?.token);
      showToast('Product Removed', `Product ${name} has been removed.`, 'system');
      await loadDashboardData();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Could not delete product';
      showToast('Delete Failed', msg, 'system');
    }
  };

  // 1-Click Quick Restock
  const handleQuickRestock = async (sku: string, currentQty: number, delta: number) => {
    const nextQty = Math.max(0, currentQty + delta);
    try {
      await updateStockQuantity(sku, nextQty, user?.token);
      setPendingStockInitializations((pending) => pending.filter((item) => item.sku !== sku));
      showToast('Stock Adjusted', `SKU ${sku}: ${nextQty} units.`, 'stock');
      setInventories((prev) =>
        prev.map((i) => (i.sku === sku ? { ...i, quantity: nextQty, isInStock: nextQty > 0 } : i))
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Stock update failed';
      showToast('Update Failed', msg, 'system');
    }
  };

  // Submit manual inventory update form
  const handleSaveInventory = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inventoryForm.sku) return;

    setIsSubmittingInventory(true);
    try {
      const sku = inventoryForm.sku.toUpperCase().trim();
      await saveOrUpdateStock(
        {
          sku,
          quantity: Number(inventoryForm.quantity),
        },
        user?.token
      );
      setPendingStockInitializations((pending) => pending.filter((item) => item.sku !== sku));
      showToast(
        'Inventory Allocated',
        `SKU ${inventoryForm.sku} set to ${inventoryForm.quantity} units.`,
        'stock'
      );
      setInventoryForm({ sku: '', quantity: 50 });
      await loadDashboardData();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Could not allocate inventory';
      showToast('Inventory Error', msg, 'system');
    } finally {
      setIsSubmittingInventory(false);
    }
  };

  // Cancel Order & Refund Stock
  const handleAdminCancelOrder = async (orderId: string, orderNumber: string) => {
    if (!confirm(`Cancel order ${orderNumber} before dispatch? Inventory compensation will be requested.`)) return;
    try {
      setCancellingOrderId(orderId);
      await submitCancelOrder(orderId, user?.token);
      const cancellationNotification = getOrderStatusNotificationCopy('CANCELLED', orderNumber);
      showToast(cancellationNotification.title, cancellationNotification.message, 'order');
      setOrders((prev) =>
        prev.map((o) => (o.id === orderId ? { ...o, orderStatus: 'CANCELLED' } : o))
      );
      await loadDashboardData();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Cancellation failed';
      showToast('Cancel Failed', msg, 'system');
    } finally {
      setCancellingOrderId(null);
    }
  };

  const handleOrderFulfillment = async (orderId: string, orderNumber: string, action: 'ship' | 'deliver') => {
    setUpdatingOrderId(orderId);
    try {
      const updated = action === 'ship'
        ? await submitShipOrder(orderId, user?.token)
        : await submitDeliverOrder(orderId, user?.token);
      setOrders((previous) => previous.map((order) => order.id === orderId ? { ...order, ...updated } : order));
      const statusNotification = getOrderStatusNotificationCopy(action === 'ship' ? 'SHIPPED' : 'DELIVERED', orderNumber);
      showToast(statusNotification.title, statusNotification.message, 'order');
      await loadDashboardData();
    } catch (err: unknown) {
      showToast('Order Update Failed', err instanceof Error ? err.message : `Could not ${action} order.`, 'system');
    } finally {
      setUpdatingOrderId(null);
    }
  };

  // Calculations
  const totalRevenue = orders.reduce((sum, o) => sum + (o.totalAmount || 0), 0);
  const lowStockCount = inventories.filter((i) => i.quantity > 0 && i.quantity < 10).length;
  const outOfStockCount = inventories.filter((i) => i.quantity === 0 || !i.isInStock).length;

  // Filtered lists
  const filteredProducts = products.filter(
    (p) =>
      p.name.toLowerCase().includes(productSearch.toLowerCase()) ||
      p.sku.toLowerCase().includes(productSearch.toLowerCase()) ||
      (p.category && p.category.toLowerCase().includes(productSearch.toLowerCase()))
  );

  const filteredInventory = inventories.filter((i) =>
    i.sku.toLowerCase().includes(inventorySearch.toLowerCase())
  );

  const filteredOrders = sortOrdersNewestFirst(orders).filter(
    (o) =>
      o.orderNumber.toLowerCase().includes(orderSearch.toLowerCase()) ||
      (o.customerName && o.customerName.toLowerCase().includes(orderSearch.toLowerCase())) ||
      (o.trackingNumber && o.trackingNumber.toLowerCase().includes(orderSearch.toLowerCase()))
  );

  // Paginated slices
  const productsTotalPages = Math.max(1, Math.ceil(filteredProducts.length / productsPageSize));
  const paginatedProducts = filteredProducts.slice(
    (productsPage - 1) * productsPageSize,
    productsPage * productsPageSize
  );

  const inventoryTotalPages = Math.max(1, Math.ceil(filteredInventory.length / inventoryPageSize));
  const paginatedInventory = filteredInventory.slice(
    (inventoryPage - 1) * inventoryPageSize,
    inventoryPage * inventoryPageSize
  );

  const ordersTotalPages = Math.max(1, Math.ceil(filteredOrders.length / ordersPageSize));
  const paginatedOrders = filteredOrders.slice(
    (ordersPage - 1) * ordersPageSize,
    ordersPage * ordersPageSize
  );

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8 animate-in fade-in">
      {/* Top Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="p-2 rounded-xl bg-violet-500/10 text-violet-400 border border-violet-500/20">
              <ShieldCheck className="w-6 h-6" />
            </span>
            <h1 className="text-3xl font-extrabold tracking-tight text-white">
              Administrator Command Center
            </h1>
            <span className="px-2.5 py-0.5 rounded-full text-xs font-mono font-bold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
              ROLE_ADMIN
            </span>
          </div>
          <p className="mt-1 text-sm text-slate-400">
            Manual item uploads, stock allocations, and order management
          </p>
        </div>

      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        <div className="glass-card p-5 rounded-2xl border border-slate-800">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Gross Sales</span>
            <DollarSign className="w-5 h-5 text-emerald-400" />
          </div>
          <div className="mt-3 text-2xl font-black text-white">{formatPrice(totalRevenue)}</div>
          <div className="mt-1 text-xs text-emerald-400 flex items-center gap-1 font-medium">
            <TrendingUp className="w-3.5 h-3.5" /> Cosmo Router Transactions
          </div>
        </div>

        <div className="glass-card p-5 rounded-2xl border border-slate-800">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Total Orders</span>
            <Package className="w-5 h-5 text-indigo-400" />
          </div>
          <div className="mt-3 text-2xl font-black text-white">{orders.length}</div>
          <div className="mt-1 text-xs text-slate-400">
            {orders.filter((o) => o.orderStatus === 'DELIVERED').length} delivered
          </div>
        </div>

        <div className="glass-card p-5 rounded-2xl border border-slate-800">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Catalog SKUs</span>
            <Layers className="w-5 h-5 text-blue-400" />
          </div>
          <div className="mt-3 text-2xl font-black text-white">{products.length}</div>
          <div className="mt-1 text-xs text-slate-400">Active in PostgreSQL</div>
        </div>

        <div className="glass-card p-5 rounded-2xl border border-slate-800">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Stock Alerts</span>
            <AlertTriangle className="w-5 h-5 text-amber-400" />
          </div>
          <div className="mt-3 text-2xl font-black text-amber-400">
            {lowStockCount + outOfStockCount}
          </div>
          <div className="mt-1 text-xs text-slate-400">
            {outOfStockCount} out of stock • {lowStockCount} low
          </div>
        </div>
      </div>

      {/* Tabs Navigation */}
      <div className="flex items-center gap-2 border-b border-slate-800 pb-3 overflow-x-auto">
        {[
          { id: 'catalog', label: `Catalog & Item Upload (${products.length})`, icon: Plus },
          { id: 'inventory', label: `Stock & Allocations (${inventories.length})`, icon: Package },
          { id: 'orders', label: `Orders Oversight (${orders.length})`, icon: Clock },
        ].map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as any)}
              className={`px-4 py-2 rounded-xl text-xs font-bold whitespace-nowrap flex items-center gap-2 transition ${
                isActive
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/25'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
              }`}
            >
              <Icon className="w-4 h-4" />
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* ================= TAB 1: CATALOG & ITEM UPLOAD ================= */}
      {activeTab === 'catalog' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Item Creation and Editing Form */}
          <div className="lg:col-span-1 glass-card p-6 rounded-2xl border border-slate-800 space-y-5">
            <div>
              <div className="flex items-center gap-2 text-indigo-400 text-xs font-bold uppercase tracking-wider mb-1">
                <Sparkles className="w-4 h-4" />
                {editingProduct ? 'Edit Catalog Item' : 'Upload New Item'}
              </div>
              <h3 className="text-lg font-bold text-white">{editingProduct ? 'Edit Product' : 'Manual Product Creation'}</h3>
              <p className="text-xs text-slate-400">
                {editingProduct
                  ? 'Updates catalog fields in products-service. SKU and inventory remain managed by their owning services.'
                  : 'Registers the catalog item in products-service and initializes stock in inventory-service.'}
              </p>
            </div>

            {pendingStockInitializations.length > 0 && (
              <div role="status" className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 space-y-3">
                <p className="text-xs font-semibold text-amber-200">Catalog items created without their initial inventory:</p>
                {pendingStockInitializations.map((pendingItem) => (
                  <div key={pendingItem.sku} className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-[11px] text-amber-100">{pendingItem.name} ({pendingItem.sku})</span>
                    <button
                      type="button"
                      onClick={() => void retryStockInitialization(pendingItem)}
                      disabled={isRetryingStockSku === pendingItem.sku}
                      className="px-3 py-1.5 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 disabled:opacity-50 text-amber-100 text-xs font-bold"
                    >
                      {isRetryingStockSku === pendingItem.sku ? 'Retrying...' : `Retry (${pendingItem.quantity} units)`}
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* 1-Click Hardware Presets Bar */}
            {!editingProduct && <div>
              <span className="text-[11px] font-bold text-slate-400 block mb-2">
                ⚡ 1-Click Hardware Presets:
              </span>
              <div className="flex flex-wrap gap-1.5">
                {HARDWARE_PRESETS.map((preset) => (
                  <button
                    key={preset.sku}
                    type="button"
                    onClick={() => applyPreset(preset)}
                    className="px-2.5 py-1 rounded-lg bg-slate-800/80 hover:bg-slate-700 text-slate-300 text-[11px] font-medium border border-slate-700/60 transition"
                  >
                    {preset.name.split(' ')[0]} {preset.name.split(' ')[1]}
                  </button>
                ))}
              </div>
            </div>}

            <form onSubmit={handleCreateProduct} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Product SKU <span className="text-rose-400">*</span>
                </label>
                <input
                  type="text"
                  required
                  readOnly={Boolean(editingProduct)}
                  value={productForm.sku}
                  onChange={(e) =>
                    setProductForm({ ...productForm, sku: e.target.value.toUpperCase() })
                  }
                  placeholder="e.g. LAPTOP-PRO-01"
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 read-only:text-slate-500 text-white text-xs font-mono focus:border-indigo-500 focus:outline-none"
                />
                <span className="text-[10px] text-slate-500 mt-1 block">
                  Pattern: 6-20 uppercase alphanumeric or hyphen characters
                </span>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Product Name <span className="text-rose-400">*</span>
                </label>
                <input
                  type="text"
                  required
                  value={productForm.name}
                  onChange={(e) => setProductForm({ ...productForm, name: e.target.value })}
                  placeholder="e.g. Laptop Lenovo IdeaPad 3"
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs focus:border-indigo-500 focus:outline-none"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-bold text-slate-300 mb-1">
                    Price (USD) <span className="text-rose-400">*</span>
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    min="0.01"
                    required
                    value={productForm.price}
                    onChange={(e) =>
                      setProductForm({ ...productForm, price: parseFloat(e.target.value) || 0 })
                    }
                    className="w-full px-3 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs font-mono focus:border-indigo-500 focus:outline-none"
                  />
                </div>
                {!editingProduct && <div>
                  <label className="block text-xs font-bold text-slate-300 mb-1">
                    Initial Stock <span className="text-rose-400">*</span>
                  </label>
                  <input
                    type="number"
                    min="0"
                    required
                    value={productForm.initialStock}
                    onChange={(e) =>
                      setProductForm({ ...productForm, initialStock: parseInt(e.target.value, 10) || 0 })
                    }
                    className="w-full px-3 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs font-mono focus:border-indigo-500 focus:outline-none"
                  />
                </div>}
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Category
                </label>
                <select
                  value={productForm.category}
                  onChange={(e) => setProductForm({ ...productForm, category: e.target.value })}
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-slate-200 text-xs focus:border-indigo-500 focus:outline-none"
                >
                  <option value="Computers">Computers & Laptops</option>
                  <option value="Displays">Monitors & Displays</option>
                  <option value="Peripherals">Keyboards & Mice</option>
                  <option value="Audio">Headphones & Audio</option>
                  <option value="Components">GPU & PC Components</option>
                  <option value="Networking">Networking & Routers</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-2">Product Image</label>
                <div className="flex flex-wrap items-center gap-3 mb-3">
                  <button
                    type="button"
                    onClick={() => productImageInputRef.current?.click()}
                    disabled={isCompressingImage}
                    className="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-indigo-400/50 bg-indigo-600 px-4 py-2.5 text-xs font-bold text-white shadow-lg shadow-indigo-900/30 transition hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-300 disabled:cursor-wait disabled:opacity-60"
                  >
                    <ImageIcon className="w-4 h-4" />
                    {isCompressingImage ? 'Preparing image...' : 'Choose image from computer'}
                  </button>
                  <span className="min-w-0 truncate text-[11px] text-slate-400">
                    {selectedImageName || 'JPEG, PNG, or WebP · up to 15 MB'}
                  </span>
                  {selectedImageName && (
                    <button
                      type="button"
                      onClick={() => {
                        setSelectedImageName('');
                        const fallbackUrl = previousProductImageUrl.current || '';
                        previousProductImageUrl.current = null;
                        setProductForm((current) => ({ ...current, imageUrl: fallbackUrl }));
                      }}
                      className="text-[11px] text-slate-400 underline underline-offset-2 hover:text-white"
                    >
                      Remove selected image
                    </button>
                  )}
                  <input
                    ref={productImageInputRef}
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    className="hidden"
                    disabled={isCompressingImage}
                    onChange={async (event) => {
                      const file = event.currentTarget.files?.[0];
                      event.currentTarget.value = '';
                      if (!file) return;
                      setIsCompressingImage(true);
                      try {
                        const compressedImage = await compressProductImage(file);
                        if (!productForm.imageUrl.startsWith('data:image/')) {
                          previousProductImageUrl.current = productForm.imageUrl;
                        }
                        setProductForm((current) => ({ ...current, imageUrl: compressedImage }));
                        setSelectedImageName(`${file.name} · optimized`);
                      } catch (error) {
                        showToast('Image Upload Failed', error instanceof Error ? error.message : 'Could not prepare this image.', 'system');
                      } finally {
                        setIsCompressingImage(false);
                      }
                    }}
                  />
                </div>
                <label className="mb-1 block text-[11px] font-semibold text-slate-400">
                  Or paste an image URL
                </label>
                <input
                  type="text"
                  inputMode="url"
                  pattern="https?://.+"
                  disabled={isCompressingImage}
                  value={productForm.imageUrl.startsWith('data:image/') ? '' : productForm.imageUrl}
                  onChange={(e) => {
                    setSelectedImageName('');
                    previousProductImageUrl.current = null;
                    setProductForm({ ...productForm, imageUrl: e.target.value });
                  }}
                  placeholder="https://images.unsplash.com/..."
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs focus:border-indigo-500 focus:outline-none"
                />
              </div>

              {/* Photo Preview */}
              {productForm.imageUrl && (
                <div className="relative aspect-[16/9] rounded-xl overflow-hidden bg-slate-950 border border-slate-800">
                  <img
                    src={productForm.imageUrl}
                    alt="Preview"
                    className="w-full h-full object-cover"
                    onError={(e) => {
                      (e.target as HTMLImageElement).src =
                        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400';
                    }}
                  />
                  <span className="absolute bottom-2 left-2 px-2 py-0.5 rounded bg-slate-900/80 text-[10px] text-slate-300">
                    Photo Preview
                  </span>
                </div>
              )}

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Description
                </label>
                <textarea
                  rows={2}
                  value={productForm.description}
                  onChange={(e) => setProductForm({ ...productForm, description: e.target.value })}
                  placeholder="Technical specifications, features, warranty..."
                  className="w-full px-3.5 py-2 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs focus:border-indigo-500 focus:outline-none"
                />
              </div>

              <button
                type="submit"
                disabled={isSubmittingProduct || isCompressingImage}
                className="w-full py-3 px-4 rounded-xl bg-gradient-to-r from-indigo-600 to-violet-600 hover:from-indigo-500 hover:to-violet-500 disabled:opacity-50 text-white font-bold text-xs shadow-lg shadow-indigo-500/25 flex items-center justify-center gap-2 transition active:scale-95"
              >
                {editingProduct ? <Edit2 className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
                {isCompressingImage ? 'Optimizing image...' : isSubmittingProduct ? 'Saving to Database...' : editingProduct ? 'Save Product Changes' : 'Create Product & Allocate Stock'}
              </button>
              {editingProduct && (
                <button type="button" onClick={resetProductForm} className="w-full py-2 text-xs text-slate-400 hover:text-white">Cancel editing</button>
              )}
            </form>
          </div>

          {/* Existing Products Catalog Table */}
          <div className="lg:col-span-2 glass-card p-6 rounded-2xl border border-slate-800 space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div>
                <h3 className="text-lg font-bold text-white">Active Product Catalog</h3>
                <p className="text-xs text-slate-400">
                  Authoritative catalog served by Spring Boot products-service
                </p>
              </div>

              <div className="relative w-full sm:w-64">
                <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  value={productSearch}
                  onChange={(e) => setProductSearch(e.target.value)}
                  placeholder="Filter products..."
                  className="w-full pl-9 pr-3 py-1.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs focus:outline-none focus:border-indigo-500"
                />
              </div>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs">
                <thead>
                  <tr className="border-b border-slate-800 text-slate-400 font-semibold uppercase tracking-wider">
                    <th className="pb-3">Product</th>
                    <th className="pb-3">SKU</th>
                    <th className="pb-3">Category</th>
                    <th className="pb-3 text-right">Price</th>
                    <th className="pb-3 text-right">Stock</th>
                    <th className="pb-3 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 font-medium">
                  {paginatedProducts.map((p) => (
                    <tr key={p.sku} className="hover:bg-slate-800/30">
                      <td className="py-3 pr-2">
                        <div className="flex items-center gap-2.5">
                          <img
                            src={p.imageUrl || 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=100'}
                            alt={p.name}
                            className="w-8 h-8 rounded-lg object-cover border border-slate-800"
                          />
                          <span className="font-bold text-white line-clamp-1">{p.name}</span>
                        </div>
                      </td>
                      <td className="py-3 pr-2 font-mono text-indigo-400">{p.sku}</td>
                      <td className="py-3 pr-2 text-slate-400">{p.category || 'General'}</td>
                      <td className="py-3 pr-2 text-right font-bold text-white">
                        {formatPrice(p.price)}
                      </td>
                      <td className="py-3 pr-2 text-right font-mono">
                        <span
                          className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                            (p.quantity ?? 10) > 0
                              ? 'bg-emerald-500/10 text-emerald-400'
                              : 'bg-rose-500/10 text-rose-400'
                          }`}
                        >
                          {p.quantity ?? 10} units
                        </span>
                      </td>
                      <td className="py-3 pl-2 text-right">
                        <div className="flex items-center justify-end gap-1.5">
                          {p.id && (
                            <button
                              onClick={() => beginProductEdit(p)}
                              title="Edit Product"
                              className="p-1.5 rounded-lg text-indigo-400 hover:text-indigo-300 hover:bg-indigo-950/30 border border-indigo-900/40 transition"
                            >
                              <Edit2 className="w-3.5 h-3.5" />
                            </button>
                          )}
                          <button
                            onClick={() => setSelectedQRProduct(p)}
                            title="Generate QR Barcode Label"
                            className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-800 transition"
                          >
                            <QrCode className="w-3.5 h-3.5" />
                          </button>
                          {p.id && (
                            <button
                              onClick={() => handleDeleteProduct(p.id!, p.name)}
                              title="Delete Product"
                              className="p-1.5 rounded-lg text-rose-400 hover:text-rose-300 hover:bg-rose-950/30 border border-rose-900/40 transition"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Products Pagination Toolbar */}
            {filteredProducts.length > 0 && (
              <div className="pt-3 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-slate-400">
                <div className="flex items-center gap-2">
                  <span>
                    Showing {(productsPage - 1) * productsPageSize + 1} to{' '}
                    {Math.min(productsPage * productsPageSize, filteredProducts.length)} of{' '}
                    {filteredProducts.length}
                  </span>
                  <div className="flex items-center gap-1 ml-2">
                    <span className="text-slate-500">Rows:</span>
                    {[5, 10, 25, 50].map((size) => (
                      <button
                        key={size}
                        onClick={() => {
                          setProductsPageSize(size);
                          setProductsPage(1);
                        }}
                        className={`px-2 py-0.5 rounded font-mono text-[11px] ${
                          productsPageSize === size
                            ? 'bg-indigo-600 text-white'
                            : 'bg-slate-900 text-slate-400 hover:text-white'
                        }`}
                      >
                        {size}
                      </button>
                    ))}
                  </div>
                </div>

                {productsTotalPages > 1 && (
                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => setProductsPage((p) => Math.max(1, p - 1))}
                      disabled={productsPage === 1}
                      className="p-1.5 rounded-lg bg-slate-900 border border-slate-800 disabled:opacity-40"
                    >
                      <ChevronLeft className="w-3.5 h-3.5" />
                    </button>
                    <span className="font-mono px-2">
                      {productsPage} / {productsTotalPages}
                    </span>
                    <button
                      onClick={() => setProductsPage((p) => Math.min(productsTotalPages, p + 1))}
                      disabled={productsPage === productsTotalPages}
                      className="p-1.5 rounded-lg bg-slate-900 border border-slate-800 disabled:opacity-40"
                    >
                      <ChevronRight className="w-3.5 h-3.5" />
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ================= TAB 2: INVENTORY & STOCK ALLOCATIONS ================= */}
      {activeTab === 'inventory' && (
        <div className="space-y-6">
          {/* Quick Allocation Bar */}
          <div className="glass-card p-6 rounded-2xl border border-slate-800">
            <h3 className="text-base font-bold text-white mb-1">Set Inventory Stock Level</h3>
            <p className="text-xs text-slate-400 mb-4">
              Allocate or override physical stock count for any registered SKU in inventory-service
            </p>

            <form onSubmit={handleSaveInventory} className="flex flex-col sm:flex-row gap-3 items-end">
              <div className="flex-1 w-full">
                <label className="block text-xs font-semibold text-slate-400 mb-1">Target SKU</label>
                <input
                  type="text"
                  required
                  value={inventoryForm.sku}
                  onChange={(e) =>
                    setInventoryForm({ ...inventoryForm, sku: e.target.value.toUpperCase() })
                  }
                  placeholder="e.g. LAPTOP-PRO"
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs font-mono focus:border-indigo-500 focus:outline-none"
                />
              </div>

              <div className="w-full sm:w-48">
                <label className="block text-xs font-semibold text-slate-400 mb-1">Quantity (Units)</label>
                <input
                  type="number"
                  min="0"
                  required
                  value={inventoryForm.quantity}
                  onChange={(e) =>
                    setInventoryForm({ ...inventoryForm, quantity: parseInt(e.target.value, 10) || 0 })
                  }
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs font-mono focus:border-indigo-500 focus:outline-none"
                />
              </div>

              <button
                type="submit"
                disabled={isSubmittingInventory}
                className="w-full sm:w-auto px-5 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-xs font-bold transition flex items-center justify-center gap-2"
              >
                <Package className="w-4 h-4" />
                {isSubmittingInventory ? 'Saving...' : 'Set Stock'}
              </button>
            </form>
          </div>

          {/* Real-time Inventory Watchdog Table with 1-Click Restock buttons */}
          <div className="glass-card p-6 rounded-2xl border border-slate-800">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
              <div>
                <h3 className="text-lg font-bold text-white flex items-center gap-2">
                  <Package className="w-5 h-5 text-indigo-400" />
                  Real-Time Stock Watchdog & 1-Click Restock
                </h3>
                <p className="text-xs text-slate-400">
                  Instant inventory adjustments powered by REST endpoints on inventory-service:8001
                </p>
              </div>

              <div className="relative w-full sm:w-64">
                <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  value={inventorySearch}
                  onChange={(e) => setInventorySearch(e.target.value)}
                  placeholder="Filter inventory by SKU..."
                  className="w-full pl-9 pr-3 py-1.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs focus:outline-none focus:border-indigo-500"
                />
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {paginatedInventory.map((item) => {
                const isOut = item.quantity === 0 || !item.isInStock;
                const isLow = item.quantity > 0 && item.quantity < 10;

                return (
                  <div
                    key={item.sku}
                    className={`p-4 rounded-2xl border transition-all ${
                      isOut
                        ? 'bg-rose-950/20 border-rose-900/40'
                        : isLow
                        ? 'bg-amber-950/20 border-amber-900/40'
                        : 'bg-slate-950/60 border-slate-800'
                    }`}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <span className="font-mono text-xs font-bold text-white">{item.sku}</span>
                      <span
                        className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                          isOut
                            ? 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                            : isLow
                            ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                            : 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                        }`}
                      >
                        {isOut ? 'OUT OF STOCK' : isLow ? 'LOW STOCK' : 'IN STOCK'}
                      </span>
                    </div>

                    <div className="flex items-baseline justify-between mb-3">
                      <span className="text-3xl font-black text-white">{item.quantity}</span>
                      <span className="text-xs text-slate-400">units available</span>
                    </div>

                    {/* 1-Click Quick Restock Buttons */}
                    <div className="flex items-center gap-1.5 pt-2 border-t border-slate-800/80">
                      <span className="text-[10px] text-slate-400 font-bold uppercase tracking-wider mr-1">
                        Restock:
                      </span>
                      <button
                        onClick={() => handleQuickRestock(item.sku, item.quantity, -1)}
                        className="flex-1 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-mono font-bold transition"
                        title="Deduct 1 unit"
                      >
                        -1
                      </button>
                      <button
                        onClick={() => handleQuickRestock(item.sku, item.quantity, 1)}
                        className="flex-1 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-mono font-bold transition"
                        title="Add 1 unit"
                      >
                        +1
                      </button>
                      <button
                        onClick={() => handleQuickRestock(item.sku, item.quantity, 10)}
                        className="flex-1 py-1 rounded-lg bg-indigo-600/30 hover:bg-indigo-600 text-indigo-300 hover:text-white text-xs font-mono font-bold border border-indigo-500/30 transition"
                        title="Add 10 units"
                      >
                        +10
                      </button>
                      <button
                        onClick={() => handleQuickRestock(item.sku, item.quantity, 50)}
                        className="flex-1 py-1 rounded-lg bg-emerald-600/30 hover:bg-emerald-600 text-emerald-300 hover:text-white text-xs font-mono font-bold border border-emerald-500/30 transition"
                        title="Add 50 units"
                      >
                        +50
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Inventory Pagination Toolbar */}
            {filteredInventory.length > 0 && (
              <div className="pt-4 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-slate-400 mt-4">
                <div className="flex items-center gap-2">
                  <span>
                    Showing {(inventoryPage - 1) * inventoryPageSize + 1} to{' '}
                    {Math.min(inventoryPage * inventoryPageSize, filteredInventory.length)} of{' '}
                    {filteredInventory.length} items
                  </span>
                  <div className="flex items-center gap-1 ml-2">
                    <span className="text-slate-500">Per page:</span>
                    {[6, 12, 24, 48].map((size) => (
                      <button
                        key={size}
                        onClick={() => {
                          setInventoryPageSize(size);
                          setInventoryPage(1);
                        }}
                        className={`px-2 py-0.5 rounded font-mono text-[11px] ${
                          inventoryPageSize === size
                            ? 'bg-indigo-600 text-white'
                            : 'bg-slate-900 text-slate-400 hover:text-white'
                        }`}
                      >
                        {size}
                      </button>
                    ))}
                  </div>
                </div>

                {inventoryTotalPages > 1 && (
                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => setInventoryPage((p) => Math.max(1, p - 1))}
                      disabled={inventoryPage === 1}
                      className="p-1.5 rounded-lg bg-slate-900 border border-slate-800 disabled:opacity-40"
                    >
                      <ChevronLeft className="w-3.5 h-3.5" />
                    </button>
                    <span className="font-mono px-2">
                      {inventoryPage} / {inventoryTotalPages}
                    </span>
                    <button
                      onClick={() => setInventoryPage((p) => Math.min(inventoryTotalPages, p + 1))}
                      disabled={inventoryPage === inventoryTotalPages}
                      className="p-1.5 rounded-lg bg-slate-900 border border-slate-800 disabled:opacity-40"
                    >
                      <ChevronRight className="w-3.5 h-3.5" />
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* ================= TAB 3: ORDERS OVERSIGHT & CANCELLATION ================= */}
      {activeTab === 'orders' && (
        <div className="glass-card p-6 rounded-2xl border border-slate-800 space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div>
              <h3 className="text-lg font-bold text-white">All Orders & Distributed Sagas</h3>
              <p className="text-xs text-slate-400">
                Cancel orders to trigger automatic stock compensation rollback across Kafka
              </p>
            </div>

            <div className="relative w-full sm:w-64">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={orderSearch}
                onChange={(e) => setOrderSearch(e.target.value)}
                placeholder="Filter by Order # or customer..."
                className="w-full pl-9 pr-3 py-1.5 rounded-xl bg-slate-950 border border-slate-800 text-white text-xs focus:outline-none focus:border-indigo-500"
              />
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead>
                <tr className="border-b border-slate-800 text-slate-400 font-semibold uppercase tracking-wider">
                  <th className="pb-3">Order #</th>
                  <th className="pb-3">Customer</th>
                  <th className="pb-3">Status</th>
                  <th className="pb-3">Items & Quantity</th>
                  <th className="pb-3 text-right">Total Amount</th>
                  <th className="pb-3 text-right">Admin Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 font-medium">
                {paginatedOrders.map((ord) => {
                  const statusPresentation = getOrderStatusPresentation(ord.orderStatus);
                  return (
                    <tr key={ord.id} className="hover:bg-slate-800/30">
                      <td className="py-3 pr-2 font-mono font-bold text-white">
                        {ord.orderNumber}
                      </td>
                      <td className="py-3 pr-2 text-slate-300">
                        {ord.customerName || ord.username || 'Anonymous'}
                      </td>
                      <td className="py-3 pr-2">
                        <span
                          className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                            statusPresentation.tone === 'emerald'
                              ? 'bg-emerald-500/10 text-emerald-400'
                              : statusPresentation.tone === 'blue'
                              ? 'bg-blue-500/10 text-blue-400'
                              : statusPresentation.tone === 'rose'
                              ? 'bg-rose-500/10 text-rose-400'
                              : statusPresentation.tone === 'amber'
                              ? 'bg-amber-500/10 text-amber-400'
                              : 'bg-slate-500/10 text-slate-400'
                          }`}
                        >
                          {statusPresentation.label}
                        </span>
                      </td>
                      <td className="py-3 pr-2">
                        <div className="flex flex-wrap gap-1">
                          {ord.orderItems?.map((it, idx) => (
                            <span
                              key={idx}
                              className="px-1.5 py-0.5 rounded bg-slate-800 text-[10px] font-mono text-slate-300"
                            >
                              {it.quantity}x {it.sku}
                            </span>
                          ))}
                        </div>
                      </td>
                      <td className="py-3 pr-2 text-right font-bold text-indigo-400">
                        {formatPrice(ord.totalAmount || 0)}
                      </td>
                      <td className="py-3 pl-2 text-right">
                        <div className="flex flex-wrap items-center justify-end gap-1.5">
                          {ord.orderStatus === 'PLACED' && (
                            <>
                              <button
                                onClick={() => handleAdminCancelOrder(ord.id, ord.orderNumber)}
                                disabled={cancellingOrderId === ord.id || updatingOrderId === ord.id}
                                className="px-2.5 py-1 rounded-lg bg-rose-600/20 hover:bg-rose-600 text-rose-300 hover:text-white border border-rose-500/30 text-[11px] font-bold transition flex items-center gap-1 disabled:opacity-50"
                              >
                                <Ban className="w-3 h-3" /> Cancel
                              </button>
                              <button
                                onClick={() => handleOrderFulfillment(ord.id, ord.orderNumber, 'ship')}
                                disabled={updatingOrderId === ord.id || cancellingOrderId === ord.id}
                                className="px-2.5 py-1 rounded-lg bg-blue-600/20 hover:bg-blue-600 text-blue-300 hover:text-white border border-blue-500/30 text-[11px] font-bold transition flex items-center gap-1 disabled:opacity-50"
                              >
                                <Truck className="w-3 h-3" /> {updatingOrderId === ord.id ? 'Saving...' : 'Dispatch · In Transit'}
                              </button>
                            </>
                          )}
                          {ord.orderStatus === 'SHIPPED' && (
                            <button
                              onClick={() => handleOrderFulfillment(ord.id, ord.orderNumber, 'deliver')}
                              disabled={updatingOrderId === ord.id}
                              className="px-2.5 py-1 rounded-lg bg-emerald-600/20 hover:bg-emerald-600 text-emerald-300 hover:text-white border border-emerald-500/30 text-[11px] font-bold transition flex items-center gap-1 disabled:opacity-50"
                            >
                              <Package className="w-3 h-3" /> {updatingOrderId === ord.id ? 'Saving...' : 'Mark Delivered'}
                            </button>
                          )}
                          {ord.orderStatus === 'DELIVERED' && <span className="text-[11px] text-emerald-400">Fulfilled</span>}
                          {ord.orderStatus === 'CANCELLED' && <span className="text-[11px] text-slate-500">Cancelled</span>}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {/* Orders Pagination Toolbar */}
          {filteredOrders.length > 0 && (
            <div className="pt-3 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-slate-400">
              <div className="flex items-center gap-2">
                <span>
                  Showing {(ordersPage - 1) * ordersPageSize + 1} to{' '}
                  {Math.min(ordersPage * ordersPageSize, filteredOrders.length)} of{' '}
                  {filteredOrders.length} orders
                </span>
                <div className="flex items-center gap-1 ml-2">
                  <span className="text-slate-500">Rows:</span>
                  {[5, 10, 25, 50].map((size) => (
                    <button
                      key={size}
                      onClick={() => {
                        setOrdersPageSize(size);
                        setOrdersPage(1);
                      }}
                      className={`px-2 py-0.5 rounded font-mono text-[11px] ${
                        ordersPageSize === size
                          ? 'bg-indigo-600 text-white'
                          : 'bg-slate-900 text-slate-400 hover:text-white'
                      }`}
                    >
                      {size}
                    </button>
                  ))}
                </div>
              </div>

              {ordersTotalPages > 1 && (
                <div className="flex items-center gap-1.5">
                  <button
                    onClick={() => setOrdersPage((p) => Math.max(1, p - 1))}
                    disabled={ordersPage === 1}
                    className="p-1.5 rounded-lg bg-slate-900 border border-slate-800 disabled:opacity-40"
                  >
                    <ChevronLeft className="w-3.5 h-3.5" />
                  </button>
                  <span className="font-mono px-2">
                    {ordersPage} / {ordersTotalPages}
                  </span>
                  <button
                    onClick={() => setOrdersPage((p) => Math.min(ordersTotalPages, p + 1))}
                    disabled={ordersPage === ordersTotalPages}
                    className="p-1.5 rounded-lg bg-slate-900 border border-slate-800 disabled:opacity-40"
                  >
                    <ChevronRight className="w-3.5 h-3.5" />
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* QR Code Label Modal */}
      {selectedQRProduct && (
        <ProductQRModal
          product={selectedQRProduct}
          onClose={() => setSelectedQRProduct(null)}
        />
      )}
    </div>
  );
};
