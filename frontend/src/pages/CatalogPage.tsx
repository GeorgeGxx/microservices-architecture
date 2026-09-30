import React, { useState, useMemo, useEffect } from 'react';
import { Product } from '../types';
import { useCurrency } from '../context/CurrencyContext';
import { useWishlist } from '../context/WishlistContext';
import { useAuth } from '../context/AuthContext';
import { ProductCard } from '../components/ui/ProductCard';
import {
  Sparkles,
  SlidersHorizontal,
  CheckCircle,
  AlertCircle,
  ChevronLeft,
  ChevronRight,
  Heart,
  X,
  Tag,
} from 'lucide-react';

interface CatalogPageProps {
  products: Product[];
  isLoading: boolean;
  searchQuery: string;
  onClearSearch: () => void;
  favoritesOnly: boolean;
  onToggleFavorites: () => void;
  onOpenQuickView: (product: Product) => void;
  onOpenQR: (product: Product) => void;
}

export const CatalogPage: React.FC<CatalogPageProps> = ({
  products,
  isLoading,
  searchQuery,
  onClearSearch,
  favoritesOnly,
  onToggleFavorites,
  onOpenQuickView,
  onOpenQR,
}) => {
  const { formatPrice } = useCurrency();
  const { wishlist, isInWishlist } = useWishlist();
  const { user, login } = useAuth();

  const [selectedCategory, setSelectedCategory] = useState<string>('All');
  const [inStockOnly, setInStockOnly] = useState(false);
  const [maxPrice, setMaxPrice] = useState<number>(3000);
  const [sortBy, setSortBy] = useState<'featured' | 'price-asc' | 'price-desc' | 'rating'>('featured');

  // Pagination states
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState(8);

  // Extract unique categories
  const categories = useMemo(() => {
    const set = new Set<string>();
    products.forEach((p) => {
      if (p.category) set.add(p.category);
    });
    return ['All', ...Array.from(set)];
  }, [products]);

  // Reset pagination on filter change
  useEffect(() => {
    setCurrentPage(1);
  }, [searchQuery, favoritesOnly, selectedCategory, inStockOnly, maxPrice, sortBy]);

  // Filter and sort products
  const filteredProducts = useMemo(() => {
    return products
      .filter((p) => {
        const matchesSearch = searchQuery
          ? p.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
            p.sku.toLowerCase().includes(searchQuery.toLowerCase()) ||
            (p.description && p.description.toLowerCase().includes(searchQuery.toLowerCase())) ||
            (p.category && p.category.toLowerCase().includes(searchQuery.toLowerCase()))
          : true;

        const matchesFavorites = favoritesOnly ? isInWishlist(p.sku) : true;

        const matchesCategory =
          selectedCategory === 'All' || p.category === selectedCategory;

        const isInStock =
          p.isInStock !== false && (p.quantity === undefined || p.quantity > 0);
        const matchesStock = inStockOnly ? isInStock : true;

        const matchesPrice = p.price <= maxPrice;

        return matchesSearch && matchesFavorites && matchesCategory && matchesStock && matchesPrice;
      })
      .sort((a, b) => {
        if (sortBy === 'price-asc') return a.price - b.price;
        if (sortBy === 'price-desc') return b.price - a.price;
        if (sortBy === 'rating') return (b.rating || 0) - (a.rating || 0);
        return 0; // featured default
      });
  }, [products, searchQuery, favoritesOnly, selectedCategory, inStockOnly, maxPrice, sortBy, isInWishlist]);

  const totalPages = Math.max(1, Math.ceil(filteredProducts.length / pageSize));
  const paginatedProducts = useMemo(() => {
    const start = (currentPage - 1) * pageSize;
    return filteredProducts.slice(start, start + pageSize);
  }, [filteredProducts, currentPage, pageSize]);

  const hasActiveFilters = Boolean(searchQuery || favoritesOnly || selectedCategory !== 'All' || inStockOnly || maxPrice < 3000);

  return (
    <div className="space-y-8 animate-in fade-in duration-300">
      {/* Hero Banner with Modern Glassmorphism */}
      <div className="relative overflow-hidden rounded-3xl glass-card p-8 md:p-12 border border-slate-800">
        <div className="absolute top-0 right-0 -mt-10 -mr-10 w-96 h-96 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 -mb-10 -ml-10 w-96 h-96 bg-violet-500/10 rounded-full blur-3xl pointer-events-none" />

        <div className="relative z-10 max-w-2xl">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 text-xs font-semibold mb-4">
            <Sparkles className="w-3.5 h-3.5" />
            <span>Spring Boot 4.0.8 & Apollo Federation 2.3 Supergraph</span>
          </div>
          <h1 className="text-3xl md:text-5xl font-extrabold text-white tracking-tight leading-tight mb-4">
            Precision Electronics & Enterprise Catalog
          </h1>
          <p className="text-slate-400 text-sm md:text-base leading-relaxed mb-6">
            Live federated multi-service inventory orchestration with sub-millisecond GC pauses and zero blocking queries.
          </p>
          <div className="flex flex-wrap items-center gap-6 text-xs text-slate-400">
            <div className="flex items-center gap-2">
              <CheckCircle className="w-4 h-4 text-emerald-400" />
              <span>Real-Time Subgraph Sync</span>
            </div>
            <div className="flex items-center gap-2">
              <CheckCircle className="w-4 h-4 text-indigo-400" />
              <span>Strict OTel Distributed Tracing</span>
            </div>
            <div className="flex items-center gap-2">
              <CheckCircle className="w-4 h-4 text-amber-400" />
              <span>Carrier Reference on Orders</span>
            </div>
          </div>
        </div>
      </div>

      {/* Filter and Control Bar (Cleaned, no duplicate search input) */}
      <div className="glass-card p-4 rounded-2xl border border-slate-800 space-y-4">
        <div className="flex flex-col md:flex-row gap-3 items-center justify-between">
          {/* Category Pills & Wishlist Filter */}
          <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none w-full md:w-auto">
            {categories.map((cat) => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-3.5 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition ${
                  selectedCategory === cat && !favoritesOnly
                    ? 'bg-indigo-600 text-white shadow-md shadow-indigo-500/25'
                    : 'bg-slate-950/60 text-slate-400 hover:text-white border border-slate-800/80 hover:border-slate-700'
                }`}
              >
                {cat}
              </button>
            ))}

            {/* Dedicated Wishlist Quick Filter Button */}
            <button
              onClick={() => {
                if (!user) {
                  login();
                } else {
                  onToggleFavorites();
                }
              }}
              title={user ? 'Filter by your saved wishlist' : 'Sign in to access your wishlist'}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap border transition ${
                favoritesOnly
                  ? 'bg-rose-500/20 text-rose-400 border-rose-500/50 shadow-sm'
                  : 'bg-slate-950/60 text-slate-400 hover:text-rose-400 border-slate-800/80 hover:border-slate-700'
              }`}
            >
              <Heart className={`w-3.5 h-3.5 ${favoritesOnly ? 'fill-rose-400 text-rose-400' : ''}`} />
              <span>Wishlist</span>
              {user && wishlist.length > 0 && (
                <span className="ml-1 px-1.5 py-0.2 rounded-full bg-rose-500/30 text-rose-300 font-mono text-[10px]">
                  {wishlist.length}
                </span>
              )}
            </button>
          </div>

          {/* Sort & Quick Toggles */}
          <div className="flex flex-wrap items-center gap-3 w-full md:w-auto justify-end">
            <label className="flex items-center gap-2 text-xs text-slate-400 cursor-pointer bg-slate-950/60 border border-slate-800 px-3 py-2 rounded-xl hover:border-slate-700 transition">
              <input
                type="checkbox"
                checked={inStockOnly}
                onChange={(e) => setInStockOnly(e.target.checked)}
                className="rounded border-slate-700 text-indigo-600 focus:ring-0 cursor-pointer"
              />
              <span>In Stock Only</span>
            </label>

            <div className="flex items-center gap-2 bg-slate-950/60 border border-slate-800 px-3 py-1.5 rounded-xl">
              <SlidersHorizontal className="w-3.5 h-3.5 text-slate-400" />
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as any)}
                className="bg-transparent text-xs text-slate-300 focus:outline-none cursor-pointer"
              >
                <option value="featured">Featured Catalog</option>
                <option value="price-asc">Price: Low to High</option>
                <option value="price-desc">Price: High to Low</option>
                <option value="rating">Top Rated</option>
              </select>
            </div>
          </div>
        </div>

        {/* Active Filter Chips & Clear Action */}
        {hasActiveFilters && (
          <div className="pt-2 border-t border-slate-800/60 flex flex-wrap items-center justify-between gap-2 text-xs">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-slate-500 font-medium">Active filters:</span>

              {searchQuery && (
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-indigo-500/10 border border-indigo-500/30 text-indigo-300">
                  <Tag className="w-3 h-3 text-indigo-400" />
                  <span>Keyword: "{searchQuery}"</span>
                  <button
                    onClick={onClearSearch}
                    className="hover:text-white p-0.5"
                    title="Remove search query"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              )}

              {favoritesOnly && (
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-rose-500/10 border border-rose-500/30 text-rose-300">
                  <Heart className="w-3 h-3 fill-rose-400 text-rose-400" />
                  <span>Favorites Only</span>
                  <button
                    onClick={onToggleFavorites}
                    className="hover:text-white p-0.5"
                    title="Remove favorites filter"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              )}

              {selectedCategory !== 'All' && (
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-800 border border-slate-700 text-slate-300">
                  <span>Category: {selectedCategory}</span>
                  <button
                    onClick={() => setSelectedCategory('All')}
                    className="hover:text-white p-0.5"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              )}

              {inStockOnly && (
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-emerald-500/10 border border-emerald-500/30 text-emerald-300">
                  <span>In Stock Only</span>
                  <button
                    onClick={() => setInStockOnly(false)}
                    className="hover:text-white p-0.5"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              )}
            </div>

            <div className="flex items-center gap-3">
              <span className="text-slate-400 font-mono">
                {filteredProducts.length} {filteredProducts.length === 1 ? 'product' : 'products'} found
              </span>
              <button
                onClick={() => {
                  onClearSearch();
                  setSelectedCategory('All');
                  setInStockOnly(false);
                  if (favoritesOnly) onToggleFavorites();
                }}
                className="text-indigo-400 hover:text-indigo-300 hover:underline"
              >
                Reset all
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Product Grid */}
      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {[...Array(8)].map((_, i) => (
            <div
              key={i}
              className="glass-card rounded-2xl p-4 border border-slate-800 space-y-4 animate-pulse"
            >
              <div className="w-full h-48 bg-slate-800/50 rounded-xl" />
              <div className="h-4 bg-slate-800/50 rounded w-3/4" />
              <div className="h-3 bg-slate-800/50 rounded w-1/2" />
              <div className="h-8 bg-slate-800/50 rounded-xl w-full" />
            </div>
          ))}
        </div>
      ) : filteredProducts.length === 0 ? (
        <div className="text-center py-24 glass-card rounded-3xl border border-slate-800">
          <AlertCircle className="w-12 h-12 text-slate-600 mx-auto mb-3" />
          <h3 className="text-lg font-bold text-slate-300">No matching products found</h3>
          <p className="text-xs text-slate-500 mt-1">
            Try adjusting your search criteria, category filter, or reset your search query.
          </p>
          <button
            onClick={() => {
              onClearSearch();
              setSelectedCategory('All');
              setInStockOnly(false);
              if (favoritesOnly) onToggleFavorites();
            }}
            className="mt-4 px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold rounded-xl transition"
          >
            Reset All Filters
          </button>
        </div>
      ) : (
        <div className="space-y-6">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
            {paginatedProducts.map((product) => (
              <ProductCard
                key={product.sku}
                product={product}
                onOpenQuickView={onOpenQuickView}
                onOpenQR={onOpenQR}
              />
            ))}
          </div>

          {/* Full Pagination Toolbar */}
          {filteredProducts.length > 0 && (
            <div className="glass-card p-4 rounded-2xl border border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-4">
              <div className="flex flex-wrap items-center gap-3 text-xs text-slate-400">
                <span>
                  Showing <strong className="text-white">{(currentPage - 1) * pageSize + 1}</strong> to{' '}
                  <strong className="text-white">
                    {Math.min(currentPage * pageSize, filteredProducts.length)}
                  </strong>{' '}
                  of <strong className="text-white">{filteredProducts.length}</strong> products
                </span>
                <div className="flex items-center gap-1.5 ml-1">
                  <span className="text-slate-500">Per page:</span>
                  {[8, 12, 24, 48].map((size) => (
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
      )}
    </div>
  );
};
export default CatalogPage;
