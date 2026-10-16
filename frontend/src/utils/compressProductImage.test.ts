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
});
