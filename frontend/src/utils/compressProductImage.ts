const MAX_SOURCE_BYTES = 15 * 1024 * 1024;
const MAX_COMPRESSED_IMAGE_BYTES = 256 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

function canvasToBlob(canvas: HTMLCanvasElement, type: string, quality: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error('The selected image could not be compressed.'))),
      type,
      quality
    );
  });
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => typeof reader.result === 'string'
      ? resolve(reader.result)
      : reject(new Error('The compressed image could not be read.'));
    reader.onerror = () => reject(new Error('The compressed image could not be read.'));
    reader.readAsDataURL(blob);
  });
}

export async function compressProductImage(file: File): Promise<string> {
  if (!ALLOWED_IMAGE_TYPES.has(file.type)) {
    throw new Error('Choose a JPEG, PNG, or WebP image.');
  }
  if (file.size > MAX_SOURCE_BYTES) {
    throw new Error('Choose an image that is 15 MB or smaller.');
  }

  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file);
  } catch {
    throw new Error('This image could not be opened. Try another JPEG, PNG, or WebP file.');
  }

  try {
    for (const [maxDimension, quality] of [[800, 0.82], [640, 0.72], [512, 0.62]] as const) {
      const scale = Math.min(1, maxDimension / Math.max(bitmap.width, bitmap.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(bitmap.width * scale));
      canvas.height = Math.max(1, Math.round(bitmap.height * scale));
      const context = canvas.getContext('2d');
      if (!context) throw new Error('Image compression is not available in this browser.');

      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      let blob = await canvasToBlob(canvas, 'image/webp', quality);
      if (blob.type !== 'image/webp') {
        // Older browsers may not encode WebP; preserve PNG transparency when applicable.
        blob = await canvasToBlob(canvas, file.type === 'image/png' ? 'image/png' : 'image/jpeg', quality);
      }
      canvas.width = 0;
      canvas.height = 0;

      if (blob.size <= MAX_COMPRESSED_IMAGE_BYTES) return await blobToDataUrl(blob);
    }
  } finally {
    bitmap.close();
  }

  throw new Error('The image is still too large after compression. Choose a smaller image.');
}
