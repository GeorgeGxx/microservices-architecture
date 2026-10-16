import { describe, expect, it, vi, beforeEach } from 'vitest';
import { compressProductImage } from './compressProductImage';

describe('compressProductImage utility', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('rejects unsupported image file types', async () => {
    const file = new File(['dummy'], 'image.gif', { type: 'image/gif' });
    await expect(compressProductImage(file)).rejects.toThrow('Choose a JPEG, PNG, or WebP image.');
  });

  it('rejects images exceeding 15MB', async () => {
    const file = new File([''], 'large.png', { type: 'image/png' });
    Object.defineProperty(file, 'size', { value: 16 * 1024 * 1024 });
    await expect(compressProductImage(file)).rejects.toThrow('Choose an image that is 15 MB or smaller.');
  });

  it('throws descriptive error if createImageBitmap fails', async () => {
    const file = new File(['corrupt data'], 'photo.jpg', { type: 'image/jpeg' });
    (globalThis as any).createImageBitmap = vi.fn().mockRejectedValue(new Error('Corrupt'));
    await expect(compressProductImage(file)).rejects.toThrow('This image could not be opened. Try another JPEG, PNG, or WebP file.');
  });

  it('compresses image successfully and returns base64 data URL', async () => {
    const file = new File(['valid'], 'photo.png', { type: 'image/png' });
    const mockBitmap = {
      width: 1200,
      height: 800,
      close: vi.fn(),
    };
    (globalThis as any).createImageBitmap = vi.fn().mockResolvedValue(mockBitmap);

    const mockCanvas = {
      width: 0,
      height: 0,
      getContext: vi.fn().mockReturnValue({
        drawImage: vi.fn(),
      }),
      toBlob: vi.fn((cb, type) => {
        cb(new Blob(['compressed-image-data'], { type: type || 'image/webp' }));
      }),
    };

    (globalThis as any).document = {
      createElement: vi.fn().mockReturnValue(mockCanvas),
    };

    (globalThis as any).FileReader = class {
      result = 'data:image/webp;base64,mockedbase64content';
      onload: (() => void) | null = null;
      onerror: (() => void) | null = null;
      readAsDataURL() {
        this.onload?.();
      }
    };

    const result = await compressProductImage(file);
    expect(result).toBe('data:image/webp;base64,mockedbase64content');
    expect(mockBitmap.close).toHaveBeenCalled();
  });

  it('throws if 2d canvas context is unavailable', async () => {
    const file = new File(['valid'], 'photo.png', { type: 'image/png' });
    const mockBitmap = { width: 100, height: 100, close: vi.fn() };
    (globalThis as any).createImageBitmap = vi.fn().mockResolvedValue(mockBitmap);

    const mockCanvas = {
      width: 0,
      height: 0,
      getContext: vi.fn().mockReturnValue(null),
    };
    (globalThis as any).document = { createElement: vi.fn().mockReturnValue(mockCanvas) };

    await expect(compressProductImage(file)).rejects.toThrow('Image compression is not available in this browser.');
    expect(mockBitmap.close).toHaveBeenCalled();
  });

  it('falls back to png when webp is not generated', async () => {
    const file = new File(['valid'], 'photo.png', { type: 'image/png' });
    const mockBitmap = { width: 400, height: 400, close: vi.fn() };
    (globalThis as any).createImageBitmap = vi.fn().mockResolvedValue(mockBitmap);

    let callCount = 0;
    const mockCanvas = {
      width: 0,
      height: 0,
      getContext: vi.fn().mockReturnValue({ drawImage: vi.fn() }),
      toBlob: vi.fn((cb) => {
        callCount++;
        // First call simulates browser rejecting webp, returning image/png
        cb(new Blob(['fallback'], { type: callCount === 1 ? 'image/other' : 'image/png' }));
      }),
    };
    (globalThis as any).document = { createElement: vi.fn().mockReturnValue(mockCanvas) };

    (globalThis as any).FileReader = class {
      result = 'data:image/png;base64,fallbackpng';
      onload: (() => void) | null = null;
      readAsDataURL() { this.onload?.(); }
    };

    const result = await compressProductImage(file);
    expect(result).toBe('data:image/png;base64,fallbackpng');
  });

  it('throws error when image exceeds maximum allowed size even after lowest tier', async () => {
    const file = new File(['valid'], 'huge.jpg', { type: 'image/jpeg' });
    const mockBitmap = { width: 400, height: 400, close: vi.fn() };
    (globalThis as any).createImageBitmap = vi.fn().mockResolvedValue(mockBitmap);

    const hugeBlob = new Blob(['x'.repeat(300 * 1024)], { type: 'image/webp' });
    const mockCanvas = {
      width: 0,
      height: 0,
      getContext: vi.fn().mockReturnValue({ drawImage: vi.fn() }),
      toBlob: vi.fn((cb) => cb(hugeBlob)),
    };
    (globalThis as any).document = { createElement: vi.fn().mockReturnValue(mockCanvas) };

    await expect(compressProductImage(file)).rejects.toThrow('The image is still too large after compression. Choose a smaller image.');
    expect(mockBitmap.close).toHaveBeenCalled();
  });
});
