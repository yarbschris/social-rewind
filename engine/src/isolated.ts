/**
 * Isolated-world bundle entry (WKContentWorld "SocialRewind"). Wrapped by native
 * exactly like page.ts. `window` here is the isolated world's global object, so
 * `SocialRewind` is visible to native (evaluateJavaScript in this world), not to the page.
 */
import { startIsolated, type PublicApi } from "./core/engine";
import type { EngineConfig } from "./core/types";

declare const __SR_CONFIG__: EngineConfig | undefined;

declare global {
  interface Window {
    SocialRewind?: PublicApi | null;
  }
}

(() => {
  if (window.top !== window) return;
  if ("SocialRewind" in window) return; // already running
  if (typeof __SR_CONFIG__ === "undefined") return;
  const api = startIsolated(__SR_CONFIG__);
  Object.defineProperty(window, "SocialRewind", { value: api, writable: false, configurable: false });
})();
