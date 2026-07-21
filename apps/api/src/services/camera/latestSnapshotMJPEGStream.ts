const DEFAULT_BOUNDARY = 'levy-home-frame';
const DEFAULT_FRAME_INTERVAL_MS = 200;

type LatestSnapshotMJPEGStreamOptions = {
  boundary?: string;
  frameIntervalMs?: number;
  sleep?: (milliseconds: number) => Promise<void>;
};

export function createLatestSnapshotMJPEGResponse(
  fetchSnapshot: (signal: AbortSignal) => Promise<{ bytes: Uint8Array; contentType: string }>,
  options: LatestSnapshotMJPEGStreamOptions = {},
): Response {
  const boundary = options.boundary ?? DEFAULT_BOUNDARY;
  const frameIntervalMs = options.frameIntervalMs ?? DEFAULT_FRAME_INTERVAL_MS;
  const sleep = options.sleep ?? ((milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
  const abortController = new AbortController();
  let isFirstFrame = true;

  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        if (!isFirstFrame) {
          await sleep(frameIntervalMs);
        }

        const snapshot = await fetchSnapshot(abortController.signal);
        controller.enqueue(multipartFrame(boundary, snapshot.contentType, snapshot.bytes));
        isFirstFrame = false;
      } catch (error) {
        if (abortController.signal.aborted) {
          controller.close();
        } else {
          controller.error(error);
        }
      }
    },
    cancel() {
      abortController.abort();
    },
  }, { highWaterMark: 0 });

  return new Response(body, {
    headers: {
      'Content-Type': `multipart/x-mixed-replace; boundary=${boundary}`,
      'Cache-Control': 'no-store, private',
    },
  });
}

function multipartFrame(boundary: string, contentType: string, bytes: Uint8Array): Uint8Array {
  const header = new TextEncoder().encode(
    `--${boundary}\r\nContent-Type: ${contentType}\r\nContent-Length: ${bytes.byteLength}\r\n\r\n`,
  );
  const trailer = new TextEncoder().encode('\r\n');
  const frame = new Uint8Array(header.byteLength + bytes.byteLength + trailer.byteLength);
  frame.set(header, 0);
  frame.set(bytes, header.byteLength);
  frame.set(trailer, header.byteLength + bytes.byteLength);
  return frame;
}
