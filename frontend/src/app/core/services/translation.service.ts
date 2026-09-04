import { Injectable, signal } from '@angular/core';

export type Language = 'en' | 'es';

@Injectable({
  providedIn: 'root'
})
export class TranslationService {
  private readonly LANG_KEY = 'ecom_selected_language';
  readonly currentLang = signal<Language>(this.getInitialLanguage());

  private readonly translations: Record<Language, Record<string, string>> = {
    en: {
      // Navbar & Header
      'NAV.TITLE': 'MicroStore',
      'NAV.PRODUCTS': 'Catalog',
      'NAV.ORDERS': 'My Orders',
      'NAV.STATUS': 'System Health',
      'NAV.ADMIN': 'Admin Dashboard',
      'NAV.CART': 'Shopping Cart',
      'NAV.SCAN_QR': 'Scan QR',
      'NAV.ONLINE': 'Online',
      'NAV.LOGIN': 'Keycloak Auth',
      'NAV.LOGOUT': 'Sign Out',
      'NAV.LANGUAGE': 'Language',
      'NAV.NOTIFICATIONS': 'System Notifications',
      'NAV.MARK_ALL_READ': 'Mark all as read',
      'NAV.NO_NOTIF': 'No recent notifications.',
      'NAV.THEME_DARK': 'Enterprise Dark',
      'NAV.THEME_LIGHT': 'Modern Light',
      'NAV.THEME_CYBER': 'Cyberpunk OLED',

      // Footer
      'FOOTER.TITLE': 'MicroStore',
      'FOOTER.COPY': 'Enterprise Microservices Architecture with Spring Boot 3.4, Keycloak 26 & Angular 21',
      'FOOTER.CONNECTED': 'Connected to Spring Cloud API Gateway (Port 8080)',

      // Product Catalog
      'PRODUCTS.CATALOG_BADGE': 'CATALOG 2026',
      'PRODUCTS.LIVE_SYNC': 'Live Sync',
      'PRODUCTS.TITLE': 'Enterprise Product Catalog',
      'PRODUCTS.SUBTITLE': 'Ultra-low latency microservices storefront with real-time inventory verification and instant search',
      'PRODUCTS.SEARCH_PLACEHOLDER': 'Search products by name, SKU, or specs...',
      'PRODUCTS.SUGGESTIONS': 'Suggestions',
      'PRODUCTS.RECENT_SEARCHES': 'Recent Searches:',
      'PRODUCTS.CLEAR': 'Clear',
      'PRODUCTS.GUEST_WELCOME': 'Welcome to MicroStore:',
      'PRODUCTS.GUEST_DESC': 'You are browsing in guest mode. Sign in via Keycloak IAM to place orders, check live inventory allocations, and access personalized order history.',
      'PRODUCTS.FILTER_ALL': 'All Items',
      'PRODUCTS.FILTER_IN_STOCK': 'In Stock Only',
      'PRODUCTS.FILTER_OUT_STOCK': 'Out of Stock',
      'PRODUCTS.SORT_LABEL': 'Sort by:',
      'PRODUCTS.SORT_RECENT': 'Recently Added',
      'PRODUCTS.SORT_PRICE_ASC': 'Price: Low to High',
      'PRODUCTS.SORT_PRICE_DESC': 'Price: High to Low',
      'PRODUCTS.SORT_NAME_ASC': 'Name: A to Z',
      'PRODUCTS.SORT_NAME_DESC': 'Name: Z to A',
      'PRODUCTS.PRICE_TIERS': 'Price Range:',
      'PRODUCTS.PRICE_ALL': 'All Prices',
      'PRODUCTS.PRICE_TIER1': 'Under $1,000',
      'PRODUCTS.PRICE_TIER2': '$1,000 - $5,000',
      'PRODUCTS.PRICE_TIER3': 'Over $5,000',
      'PRODUCTS.ACTIVE_FILTERS': 'Active filters applied:',
      'PRODUCTS.CLEAR_ALL_FILTERS': 'Clear all filters',
      'PRODUCTS.SHOWING_PAGE': 'Showing',
      'PRODUCTS.OF': 'of',
      'PRODUCTS.PRODUCTS_COUNT': 'products',
      'PRODUCTS.PAGE': 'Page',
      'PRODUCTS.PREV': '‹ Prev',
      'PRODUCTS.NEXT': 'Next ›',
      'PRODUCTS.IN_STOCK': 'In Stock',
      'PRODUCTS.OUT_OF_STOCK': 'Out of Stock',
      'PRODUCTS.CHECKING_STOCK': 'Checking...',
      'PRODUCTS.NOT_VERIFIED': 'Not verified',
      'PRODUCTS.PRICE': 'Price',
      'PRODUCTS.ADD_TO_CART': 'Add to Cart',
      'PRODUCTS.SIGN_IN_BUY': 'Sign in to Buy',
      'PRODUCTS.SHOW_QR': 'QR Code',
      'PRODUCTS.QUICK_VIEW': 'Quick View',
      'PRODUCTS.NO_PRODUCTS': 'No products matched your criteria.',
      'PRODUCTS.NO_PRODUCTS_DESC': 'Try adjusting your search query, clearing filter chips, or expanding your price range.',

      // Order Lifecycle & History
      'ORDERS.TITLE': 'Order History & Tracking',
      'ORDERS.SUBTITLE': 'Real-time lifecycle tracking, distributed saga validation, and 1-click repurchase',
      'ORDERS.TAB_ALL': 'All Orders',
      'ORDERS.TAB_PROCESSING': 'Processing',
      'ORDERS.TAB_SHIPPED': 'Shipped',
      'ORDERS.TAB_DELIVERED': 'Delivered',
      'ORDERS.TAB_CANCELLED': 'Cancelled',
      'ORDERS.ORDER_NUMBER': 'Order #',
      'ORDERS.CANCEL_BTN': 'Cancel Order',
      'ORDERS.REORDER_BTN': 'Re-Order Items',
      'ORDERS.RECEIPT_BTN': 'View Receipt & QR',
      'ORDERS.STATUS': 'Status',
      'ORDERS.TOTAL': 'Total Amount',
      'ORDERS.ITEMS': 'Order Items',
      'ORDERS.EMPTY_STATE': 'No orders found in this category.',
      'ORDERS.EMPTY_SUBTITLE': 'Your completed checkouts and Saga transactions will appear here.',
      'ORDERS.SHOWING': 'Showing',

      // Scanner Modal
      'SCANNER.TITLE': 'Universal QR & Barcode Scanner',
      'SCANNER.SUBTITLE': 'Camera • Image File • USB & Bluetooth Laser Readers',
      'SCANNER.TAB_CAMERA': 'Camera Scanner',
      'SCANNER.TAB_FILE': 'Upload Image',
      'SCANNER.TAB_HARDWARE': 'USB / Bluetooth HID',
      'SCANNER.CAMERA_HINT': 'Point your camera at a Product SKU or Order QR code',
      'SCANNER.FILE_DROPZONE': 'Click or drag & drop a QR code image here',
      'SCANNER.HARDWARE_READY': 'Hardware Scanner Active & Listening',
      'SCANNER.HARDWARE_DESC': 'Pull the trigger on your USB or Bluetooth scanner anywhere in the app to instantly decode codes.',
      'SCANNER.MANUAL_PLACEHOLDER': 'Or type SKU / Code manually and press Enter...',
      'SCANNER.SWITCH_CAM': 'Switch Camera',
      'SCANNER.TORCH_ON': 'Flash On',
      'SCANNER.TORCH_OFF': 'Flash Off',
      'SCANNER.CLOSE': 'Close Scanner',
      'SCANNER.SUCCESS': 'Code Scanned Successfully!',

      // QR Generator & Receipt
      'QR_GEN.TITLE': 'Digital QR Code',
      'QR_GEN.PRINT': 'Print QR Label',
      'QR_GEN.CLOSE': 'Close',
      'RECEIPT.TITLE': 'Purchase Receipt',
      'RECEIPT.DISPATCH_QR': 'Dispatch & Pickup Verification QR',

      // Cart Drawer
      'CART.TITLE': 'Shopping Cart',
      'CART.EMPTY': 'Your cart is empty',
      'CART.EMPTY_DESC': 'Scan a product SKU with laser/camera or browse catalog to start register.',
      'CART.SUBTOTAL': 'Subtotal',
      'CART.EST_TOTAL': 'Estimated Total',
      'CART.CLEAR': 'Clear Cart',
      'CART.CHECKOUT': 'Proceed to Checkout',
      'CART.SCAN_BTN': 'Scan SKU',

      // Checkout Stepper
      'CHECKOUT.TITLE': 'Secure Checkout & Payment',
      'CHECKOUT.SUBTITLE': 'End-to-End Saga Transaction Orchestrated via Spring Cloud Gateway & Kafka',
      'CHECKOUT.STEP_CART': 'Review Cart',
      'CHECKOUT.STEP_PAYMENT': 'Payment Details',
      'CHECKOUT.STEP_CONFIRM': 'Order Confirmation',
      'CHECKOUT.CARD_HOLDER': 'CARDHOLDER NAME',
      'CHECKOUT.CARD_NUMBER': 'CARD NUMBER',
      'CHECKOUT.EXPIRES': 'EXPIRES',
      'CHECKOUT.CVV': 'CVV',
      'CHECKOUT.PAY_BTN': 'Pay & Place Order',
      'CHECKOUT.PROCESSING': 'Processing Saga Order...',
      'CHECKOUT.SUCCESS_TITLE': 'Order Successfully Placed!',
      'CHECKOUT.SUCCESS_DESC': 'Your order has been validated against Inventory and published to Kafka.',
      'CHECKOUT.VIEW_RECEIPT': 'View Digital Receipt & QR',

      // System Status (Public / Subtle)
      'STATUS.TITLE': 'System Status',
      'STATUS.SUBTITLE': 'Real-time operational health and availability of all platform services',
      'STATUS.ALL_OPERATIONAL': 'All Systems Operational',
      'STATUS.DEGRADED': 'Degraded Performance',
      'STATUS.REFRESH': 'Refresh Status',
      'STATUS.CHECKING': 'Checking...',
      'STATUS.AVAILABILITY': 'Platform Availability',
      'STATUS.LATENCY': 'Response Time',
      'STATUS.SERVICES_ONLINE': 'Services Online',
      'STATUS.OPTIMAL': 'Optimal',
      'STATUS.OPERATIONAL': 'Operational',
      'STATUS.UNREACHABLE': 'Degraded',
      'STATUS.SERVICES_TITLE': 'Core Platform Services',
      'STATUS.PING': 'Check',
      'STATUS.ALL_NODES': 'active services'
    },
    es: {
      // Navbar & Header
      'NAV.TITLE': 'MicroStore',
      'NAV.PRODUCTS': 'Catálogo',
      'NAV.ORDERS': 'Mis Pedidos',
      'NAV.STATUS': 'Salud del Sistema',
      'NAV.ADMIN': 'Panel de Administración',
      'NAV.CART': 'Carrito de Compras',
      'NAV.SCAN_QR': 'Escanear QR',
      'NAV.ONLINE': 'En Línea',
      'NAV.LOGIN': 'Acceso Keycloak',
      'NAV.LOGOUT': 'Cerrar Sesión',
      'NAV.LANGUAGE': 'Idioma',
      'NAV.NOTIFICATIONS': 'Notificaciones del Sistema',
      'NAV.MARK_ALL_READ': 'Marcar todo como leído',
      'NAV.NO_NOTIF': 'No hay notificaciones recientes.',
      'NAV.THEME_DARK': 'Oscuro Empresarial',
      'NAV.THEME_LIGHT': 'Claro Moderno',
      'NAV.THEME_CYBER': 'Cyberpunk OLED',

      // Footer
      'FOOTER.TITLE': 'MicroStore',
      'FOOTER.COPY': 'Arquitectura Empresarial de Microservicios con Spring Boot 3.4, Keycloak 26 y Angular 21',
      'FOOTER.CONNECTED': 'Conectado a Spring Cloud API Gateway (Puerto 8080)',

      // Product Catalog
      'PRODUCTS.CATALOG_BADGE': 'CATÁLOGO 2026',
      'PRODUCTS.LIVE_SYNC': 'Sincronización en Vivo',
      'PRODUCTS.TITLE': 'Catálogo Empresarial de Productos',
      'PRODUCTS.SUBTITLE': 'Tienda de ultra-baja latencia con verificación de stock en tiempo real y búsqueda instantánea',
      'PRODUCTS.SEARCH_PLACEHOLDER': 'Buscar productos por nombre, SKU o especificaciones...',
      'PRODUCTS.SUGGESTIONS': 'Sugerencias',
      'PRODUCTS.RECENT_SEARCHES': 'Búsquedas Recientes:',
      'PRODUCTS.CLEAR': 'Limpiar',
      'PRODUCTS.GUEST_WELCOME': 'Bienvenido a MicroStore:',
      'PRODUCTS.GUEST_DESC': 'Estás navegando en modo invitado. Inicia sesión con Keycloak para realizar pedidos, validar inventario en vivo y ver tu historial.',
      'PRODUCTS.FILTER_ALL': 'Todos los Artículos',
      'PRODUCTS.FILTER_IN_STOCK': 'Solo en Stock',
      'PRODUCTS.FILTER_OUT_STOCK': 'Agotados',
      'PRODUCTS.SORT_LABEL': 'Ordenar por:',
      'PRODUCTS.SORT_RECENT': 'Agregados Recientemente',
      'PRODUCTS.SORT_PRICE_ASC': 'Precio: Menor a Mayor',
      'PRODUCTS.SORT_PRICE_DESC': 'Precio: Mayor a Menor',
      'PRODUCTS.SORT_NAME_ASC': 'Nombre: A a la Z',
      'PRODUCTS.SORT_NAME_DESC': 'Nombre: Z a la A',
      'PRODUCTS.PRICE_TIERS': 'Rango de Precios:',
      'PRODUCTS.PRICE_ALL': 'Todos los Precios',
      'PRODUCTS.PRICE_TIER1': 'Menos de $1,000',
      'PRODUCTS.PRICE_TIER2': '$1,000 - $5,000',
      'PRODUCTS.PRICE_TIER3': 'Más de $5,000',
      'PRODUCTS.ACTIVE_FILTERS': 'Filtros aplicados:',
      'PRODUCTS.CLEAR_ALL_FILTERS': 'Limpiar todos los filtros',
      'PRODUCTS.SHOWING_PAGE': 'Mostrando',
      'PRODUCTS.OF': 'de',
      'PRODUCTS.PRODUCTS_COUNT': 'productos',
      'PRODUCTS.PAGE': 'Página',
      'PRODUCTS.PREV': '‹ Anterior',
      'PRODUCTS.NEXT': 'Siguiente ›',
      'PRODUCTS.IN_STOCK': 'En Stock',
      'PRODUCTS.OUT_OF_STOCK': 'Agotado',
      'PRODUCTS.CHECKING_STOCK': 'Verificando...',
      'PRODUCTS.NOT_VERIFIED': 'No verificado',
      'PRODUCTS.PRICE': 'Precio',
      'PRODUCTS.ADD_TO_CART': 'Agregar al Carrito',
      'PRODUCTS.SIGN_IN_BUY': 'Iniciar Sesión para Comprar',
      'PRODUCTS.SHOW_QR': 'Código QR',
      'PRODUCTS.QUICK_VIEW': 'Vista Rápida',
      'PRODUCTS.NO_PRODUCTS': 'No se encontraron productos con esos criterios.',
      'PRODUCTS.NO_PRODUCTS_DESC': 'Intenta ajustar tu búsqueda, limpiar los filtros o ampliar el rango de precios.',

      // Order Lifecycle & History
      'ORDERS.TITLE': 'Historial de Pedidos y Rastreo',
      'ORDERS.SUBTITLE': 'Seguimiento en tiempo real, validación distribuida Saga y re-compra en 1 clic',
      'ORDERS.TAB_ALL': 'Todos los Pedidos',
      'ORDERS.TAB_PROCESSING': 'En Proceso',
      'ORDERS.TAB_SHIPPED': 'Enviados',
      'ORDERS.TAB_DELIVERED': 'Entregados',
      'ORDERS.TAB_CANCELLED': 'Cancelados',
      'ORDERS.ORDER_NUMBER': 'Pedido #',
      'ORDERS.CANCEL_BTN': 'Cancelar Pedido',
      'ORDERS.REORDER_BTN': 'Re-ordenar Artículos',
      'ORDERS.RECEIPT_BTN': 'Ver Recibo y QR',
      'ORDERS.STATUS': 'Estado',
      'ORDERS.TOTAL': 'Monto Total',
      'ORDERS.ITEMS': 'Artículos del Pedido',
      'ORDERS.EMPTY_STATE': 'No hay pedidos en esta categoría.',
      'ORDERS.EMPTY_SUBTITLE': 'Tus compras y transacciones Saga aparecerán aquí.',
      'ORDERS.SHOWING': 'Mostrando',

      // Scanner Modal
      'SCANNER.TITLE': 'Escáner Universal de QR y Códigos de Barra',
      'SCANNER.SUBTITLE': 'Cámara • Archivo de Imagen • Lectores Láser USB y Bluetooth',
      'SCANNER.TAB_CAMERA': 'Cámara en Vivo',
      'SCANNER.TAB_FILE': 'Subir Imagen',
      'SCANNER.TAB_HARDWARE': 'Lector USB / Bluetooth',
      'SCANNER.CAMERA_HINT': 'Apunta la cámara al código QR de un producto o pedido',
      'SCANNER.FILE_DROPZONE': 'Haz clic o arrastra una imagen con código QR aquí',
      'SCANNER.HARDWARE_READY': 'Lector Físico Activo y Escuchando',
      'SCANNER.HARDWARE_DESC': 'Dispara el gatillo de tu lector USB o Bluetooth en cualquier lugar de la app para decodificar automáticamente.',
      'SCANNER.MANUAL_PLACEHOLDER': 'O escribe el SKU / Código y presiona Enter...',
      'SCANNER.SWITCH_CAM': 'Cambiar Cámara',
      'SCANNER.TORCH_ON': 'Encender Flash',
      'SCANNER.TORCH_OFF': 'Apagar Flash',
      'SCANNER.CLOSE': 'Cerrar Escáner',
      'SCANNER.SUCCESS': '¡Código Escaneado con Éxito!',

      // QR Generator & Receipt
      'QR_GEN.TITLE': 'Código QR Digital',
      'QR_GEN.PRINT': 'Imprimir Etiqueta',
      'QR_GEN.CLOSE': 'Cerrar',
      'RECEIPT.TITLE': 'Comprobante de Compra',
      'RECEIPT.DISPATCH_QR': 'QR de Verificación para Despacho y Entrega',

      // Cart Drawer
      'CART.TITLE': 'Carrito de Compras',
      'CART.EMPTY': 'Tu carrito está vacío',
      'CART.EMPTY_DESC': 'Escanea un SKU con láser/cámara o explora el catálogo para comenzar a cobrar.',
      'CART.SUBTOTAL': 'Subtotal',
      'CART.EST_TOTAL': 'Total Estimado',
      'CART.CLEAR': 'Vaciar Carrito',
      'CART.CHECKOUT': 'Proceder al Pago',
      'CART.SCAN_BTN': 'Escanear SKU',

      // Checkout Stepper
      'CHECKOUT.TITLE': 'Pago Seguro y Creación de Pedido',
      'CHECKOUT.SUBTITLE': 'Transacción Saga de extremo a extremo orquestada con Spring Cloud Gateway y Kafka',
      'CHECKOUT.STEP_CART': 'Revisar Carrito',
      'CHECKOUT.STEP_PAYMENT': 'Datos de Pago',
      'CHECKOUT.STEP_CONFIRM': 'Confirmación de Pedido',
      'CHECKOUT.CARD_HOLDER': 'NOMBRE DEL TITULAR',
      'CHECKOUT.CARD_NUMBER': 'NÚMERO DE TARJETA',
      'CHECKOUT.EXPIRES': 'VENCIMIENTO',
      'CHECKOUT.CVV': 'CVV',
      'CHECKOUT.PAY_BTN': 'Pagar y Crear Pedido',
      'CHECKOUT.PROCESSING': 'Procesando Pedido Saga...',
      'CHECKOUT.SUCCESS_TITLE': '¡Pedido Creado con Éxito!',
      'CHECKOUT.SUCCESS_DESC': 'Tu pedido fue validado en Inventario y publicado en Kafka.',
      'CHECKOUT.VIEW_RECEIPT': 'Ver Recibo Digital y QR',

      // System Status (Public / Subtle)
      'STATUS.TITLE': 'Estado del Sistema',
      'STATUS.SUBTITLE': 'Monitoreo en tiempo real de la disponibilidad operativa de todos nuestros servicios',
      'STATUS.ALL_OPERATIONAL': 'Todos los Sistemas Operacionales',
      'STATUS.DEGRADED': 'Rendimiento Degradado',
      'STATUS.REFRESH': 'Actualizar Estado',
      'STATUS.CHECKING': 'Verificando...',
      'STATUS.AVAILABILITY': 'Disponibilidad Global',
      'STATUS.LATENCY': 'Tiempo de Respuesta',
      'STATUS.SERVICES_ONLINE': 'Servicios en Línea',
      'STATUS.OPTIMAL': 'Óptimo',
      'STATUS.OPERATIONAL': 'Operacional',
      'STATUS.UNREACHABLE': 'Degradado',
      'STATUS.SERVICES_TITLE': 'Servicios Principales de la Plataforma',
      'STATUS.PING': 'Verificar',
      'STATUS.ALL_NODES': 'servicios activos'
    }
  };

  private getInitialLanguage(): Language {
    return 'en';
  }

  setLanguage(lang: Language): void {
    this.currentLang.set('en');
  }

  toggleLanguage(): void {
    this.setLanguage('en');
  }

  translate(key: string): string {
    return this.translations['en']?.[key] || key;
  }
}
