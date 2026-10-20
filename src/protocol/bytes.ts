/** Buffer only within an explicit budget; cancel an oversized producer. */
export async function readBounded(
  stream: ReadableStream<Uint8Array> | null,
  maximum: number,
): Promise<Uint8Array> {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const item = await reader.read();
      if (item.done) break;
      size += item.value.byteLength;
      if (size > maximum) {
        await reader.cancel("Input exceeds limit");
        throw new Error("Input exceeds limit");
      }
      chunks.push(item.value);
    }
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(size);
  let position = 0;
  for (const chunk of chunks) {
    result.set(chunk, position);
    position += chunk.byteLength;
  }
  return result;
}

export const sha256 = (value: string): Promise<string> =>
  sha256Bytes(new TextEncoder().encode(value));

export async function sha256Bytes(value: ArrayBuffer | Uint8Array): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", value as BufferSource);
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Keep the bounded prefix available even when a process is stopped or its stream fails. */
export function captureOutput(stream: ReadableStream<Uint8Array> | null, maximum: number) {
  const buffer = new Uint8Array(maximum);
  let size = 0;
  const done = (async () => {
    if (!stream) return;
    const reader = stream.getReader();
    try {
      for (;;) {
        const item = await reader.read();
        if (item.done) return;
        const retained = item.value.subarray(0, maximum - size);
        buffer.set(retained, size);
        size += retained.byteLength;
        if (retained.byteLength !== item.value.byteLength) {
          await reader.cancel("Output limit reached");
          throw new Error("Output limit reached");
        }
      }
    } finally {
      reader.releaseLock();
    }
  })();
  return { done, text: () => new TextDecoder().decode(buffer.subarray(0, size)) };
}
