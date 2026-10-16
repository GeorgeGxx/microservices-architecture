import { describe, expect, it, beforeEach } from 'vitest';
import { LocalStorageCartRepository } from './LocalStorageCartRepository';
import { CartItem } from '../../types';

describe('LocalStorageCartRepository', () => {
  let repo: LocalStorageCartRepository;
  const store: Record<string, string> = {};

  beforeEach(() => {
    repo = new LocalStorageCartRepository();
    // In-memory mock for localStorage in node test environment
    Object.keys(store).forEach((k) => delete store[k]);

    const mockStorage = {
      getItem: (key: string) => store[key] ?? null,
      setItem: (key: string, value: string) => {
        store[key] = value;
      },
      removeItem: (key: string) => {
        delete store[key];
      },
      clear: () => {
        Object.keys(store).forEach((k) => delete store[k]);
      },
    };

    Object.defineProperty(globalThis, 'localStorage', {
      value: mockStorage,
      writable: true,
      configurable: true,
    });
  });

  const sampleItems: CartItem[] = [
    {
      product: {
        id: '1',
        sku: 'LAPTOP-PRO',
        name: 'Laptop Pro',
        price: 999,
      },
      quantity: 1,
    },
  ];

  it('loads empty array when localStorage is empty', () => {
    expect(repo.load()).toEqual([]);
  });

  it('saves and loads cart items properly', () => {
    repo.save(sampleItems);
    const loaded = repo.load();
    expect(loaded).toEqual(sampleItems);
  });

  it('clears stored cart items', () => {
    repo.save(sampleItems);
    expect(repo.load()).toHaveLength(1);
    repo.clear();
    expect(repo.load()).toHaveLength(0);
  });

  it('returns empty array when JSON.parse fails', () => {
    localStorage.setItem('novashop_cart_v2', 'invalid-json-content{');
    expect(repo.load()).toEqual([]);
  });
});
