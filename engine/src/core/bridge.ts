import type { BridgeEvent } from "./types";

interface WebkitHost {
  webkit?: { messageHandlers?: { socialRewind?: { postMessage(msg: unknown): void } } };
  SocialRewindAndroid?: { postMessage(json: string): void };
}

type Listener = (event: BridgeEvent) => void;
const testListeners = new Set<Listener>();

/** Send an event to the native shell. Never throws. */
export function send(event: BridgeEvent): void {
  for (const l of testListeners) l(event);
  try {
    const w = globalThis as unknown as WebkitHost;
    if (w.webkit?.messageHandlers?.socialRewind) {
      w.webkit.messageHandlers.socialRewind.postMessage(event);
    } else if (w.SocialRewindAndroid) {
      w.SocialRewindAndroid.postMessage(JSON.stringify(event));
    }
  } catch {
    // Native side unavailable; nothing useful to do.
  }
}

/** Test hook: observe outgoing events. Returns an unsubscribe function. */
export function onSend(listener: Listener): () => void {
  testListeners.add(listener);
  return () => testListeners.delete(listener);
}
