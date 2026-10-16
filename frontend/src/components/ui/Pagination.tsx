import React from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';

export interface PaginationProps {
  currentPage: number;
  totalPages: number;
  pageSize: number;
  totalItems: number;
  pageSizeOptions?: number[];
  itemLabel?: string;
  onPageChange: (page: number | ((prev: number) => number)) => void;
  onPageSizeChange: (size: number) => void;
}

export const Pagination: React.FC<PaginationProps> = ({
  currentPage,
  totalPages,
  pageSize,
  totalItems,
  pageSizeOptions = [8, 12, 24, 48],
  itemLabel = 'items',
  onPageChange,
  onPageSizeChange,
}) => {
  const startItem = totalItems === 0 ? 0 : (currentPage - 1) * pageSize + 1;
  const endItem = Math.min(currentPage * pageSize, totalItems);

  return (
    <div className="glass-card p-4 rounded-2xl border border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-4">
      <div className="flex flex-wrap items-center gap-3 text-xs text-slate-400">
        <span>
          Showing <strong className="text-white">{startItem}</strong> to{' '}
          <strong className="text-white">{endItem}</strong> of{' '}
          <strong className="text-white">{totalItems}</strong> {itemLabel}
        </span>
        <div className="flex items-center gap-1.5 ml-1">
          <span className="text-slate-500">Per page:</span>
          {pageSizeOptions.map((size) => (
            <button
              key={size}
              onClick={() => {
                onPageSizeChange(size);
                onPageChange(1);
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
            onClick={() => onPageChange((p) => Math.max(1, p - 1))}
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
                onClick={() => onPageChange(p)}
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
            onClick={() => onPageChange((p) => Math.min(totalPages, p + 1))}
            disabled={currentPage === totalPages}
            className="p-2 rounded-xl bg-slate-900 border border-slate-800 text-slate-300 hover:text-white disabled:opacity-40 transition"
            title="Next Page"
          >
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>
      )}
    </div>
  );
};
