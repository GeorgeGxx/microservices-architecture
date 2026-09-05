export interface ProductImagePreset {
  id: string;
  label: string;
  category: string;
  url: string;
}

export const PRODUCT_IMAGE_PRESETS: ProductImagePreset[] = [
  {
    id: 'laptop',
    label: 'Laptop Pro',
    category: 'Computers',
    url: 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?auto=format&fit=crop&w=800&q=80'
  },
  {
    id: 'keyboard',
    label: 'RGB Keyboard',
    category: 'Peripherals',
    url: 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?auto=format&fit=crop&w=800&q=80'
  },
  {
    id: 'mouse',
    label: 'Gaming Mouse',
    category: 'Peripherals',
    url: 'https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?auto=format&fit=crop&w=800&q=80'
  },
  {
    id: 'monitor',
    label: 'Curved Monitor',
    category: 'Displays',
    url: 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?auto=format&fit=crop&w=800&q=80'
  },
  {
    id: 'headphones',
    label: 'HD Headphones',
    category: 'Audio',
    url: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=800&q=80'
  },
  {
    id: 'gpu',
    label: 'Graphics Card',
    category: 'Hardware',
    url: 'https://images.unsplash.com/photo-1591488320449-011701bb6704?auto=format&fit=crop&w=800&q=80'
  },
  {
    id: 'smartwatch',
    label: 'Smart Watch',
    category: 'Wearables',
    url: 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=800&q=80'
  },
  {
    id: 'server',
    label: 'Cloud Server Rack',
    category: 'Infrastructure',
    url: 'https://images.unsplash.com/photo-1558494949-ef010cbdcc31?auto=format&fit=crop&w=800&q=80'
  }
];

const DEFAULT_FALLBACK = 'https://images.unsplash.com/photo-1550009158-9ebf69173e03?auto=format&fit=crop&w=800&q=80';

export const PRODUCT_CACHE_KEY = 'msa_product_cache';

/**
 * Retrieves a cached product by SKU from localStorage to maintain
 * image consistency across orders, checkout, and inventory views.
 */
export function getCachedProductBySku(sku?: string): { sku: string; name?: string; imageUrl?: string } | null {
  if (!sku || typeof localStorage === 'undefined') return null;
  try {
    const raw = localStorage.getItem(PRODUCT_CACHE_KEY);
    if (!raw) return null;
    const cache = JSON.parse(raw);
    return cache[sku.toUpperCase()] || cache[sku] || null;
  } catch {
    return null;
  }
}

/**
 * Saves a single product into the persistent product cache.
 */
export function cacheProductInStorage(product: { sku: string; name?: string; imageUrl?: string }): void {
  if (!product?.sku || typeof localStorage === 'undefined') return;
  try {
    const raw = localStorage.getItem(PRODUCT_CACHE_KEY);
    const cache = raw ? JSON.parse(raw) : {};
    cache[product.sku.toUpperCase()] = {
      sku: product.sku.toUpperCase(),
      name: product.name,
      imageUrl: product.imageUrl
    };
    localStorage.setItem(PRODUCT_CACHE_KEY, JSON.stringify(cache));
  } catch {}
}

/**
 * Saves multiple products into the persistent product cache.
 */
export function cacheMultipleProductsInStorage(products: Array<{ sku: string; name?: string; imageUrl?: string }>): void {
  if (!Array.isArray(products) || typeof localStorage === 'undefined') return;
  try {
    const raw = localStorage.getItem(PRODUCT_CACHE_KEY);
    const cache = raw ? JSON.parse(raw) : {};
    for (const p of products) {
      if (p?.sku) {
        cache[p.sku.toUpperCase()] = {
          sku: p.sku.toUpperCase(),
          name: p.name,
          imageUrl: p.imageUrl
        };
      }
    }
    localStorage.setItem(PRODUCT_CACHE_KEY, JSON.stringify(cache));
  } catch {}
}

/**
 * Returns the product image URL if valid, or a smart matching fallback based on SKU / Name.
 * Automatically inspects the persistent product cache if imageUrl is missing.
 */
export function getProductImageUrl(product?: { sku?: string; name?: string; imageUrl?: string } | null): string {
  if (!product) return DEFAULT_FALLBACK;
  if (product.imageUrl && product.imageUrl.trim().length > 0) {
    return product.imageUrl.trim();
  }

  // Check persistent catalog cache to retrieve the exact user-uploaded inventory image
  if (product.sku) {
    const cached = getCachedProductBySku(product.sku);
    if (cached?.imageUrl && cached.imageUrl.trim().length > 0) {
      return cached.imageUrl.trim();
    }
    if (!product.name && cached?.name) {
      product = { ...product, name: cached.name };
    }
  }

  const query = `${product.sku || ''} ${product.name || ''}`.toLowerCase();

  if (query.includes('laptop') || query.includes('macbook') || query.includes('notebook')) {
    return PRODUCT_IMAGE_PRESETS[0].url;
  }
  if (query.includes('keyboard') || query.includes('teclado') || query.includes('000001')) {
    return PRODUCT_IMAGE_PRESETS[1].url;
  }
  if (query.includes('mouse') || query.includes('raton') || query.includes('000002')) {
    return PRODUCT_IMAGE_PRESETS[2].url;
  }
  if (query.includes('monitor') || query.includes('display') || query.includes('screen') || query.includes('000003')) {
    return PRODUCT_IMAGE_PRESETS[3].url;
  }
  if (query.includes('headphone') || query.includes('audifono') || query.includes('audio') || query.includes('000004')) {
    return PRODUCT_IMAGE_PRESETS[4].url;
  }
  if (query.includes('gpu') || query.includes('rtx') || query.includes('graphic')) {
    return PRODUCT_IMAGE_PRESETS[5].url;
  }
  if (query.includes('watch') || query.includes('reloj')) {
    return PRODUCT_IMAGE_PRESETS[6].url;
  }
  if (query.includes('server') || query.includes('rack') || query.includes('cloud')) {
    return PRODUCT_IMAGE_PRESETS[7].url;
  }

  return DEFAULT_FALLBACK;
}

/**
 * Reads a local File from user's machine, resizes it in HTML5 Canvas,
 * and outputs an optimized Base64 JPEG/WebP Data URL for local database storage.
 */
export function compressImageFile(file: File, maxDimension: number = 800, quality: number = 0.82): Promise<string> {
  return new Promise((resolve, reject) => {
    if (!file.type.startsWith('image/')) {
      return reject(new Error('Selected file is not an image.'));
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        let width = img.width;
        let height = img.height;

        if (width > height) {
          if (width > maxDimension) {
            height = Math.round((height * maxDimension) / width);
            width = maxDimension;
          }
        } else {
          if (height > maxDimension) {
            width = Math.round((width * maxDimension) / height);
            height = maxDimension;
          }
        }

        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        if (!ctx) {
          return resolve(e.target?.result as string);
        }

        ctx.drawImage(img, 0, 0, width, height);
        const compressedBase64 = canvas.toDataURL('image/jpeg', quality);
        resolve(compressedBase64);
      };

      img.onerror = () => reject(new Error('Failed to decode image.'));
      img.src = e.target?.result as string;
    };

    reader.onerror = () => reject(new Error('Failed to read file from disk.'));
    reader.readAsDataURL(file);
  });
}
