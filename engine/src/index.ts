/**
 * Social Rewind filter engine: bundle entry point.
 *
 * Injected at document start (page content world) after native defines
 * `window.__SOCIAL_REWIND_CONFIG__`. Exposes `window.SocialRewind` for native
 * to push live setting changes.
 */
import { start, type PublicApi } from "./core/engine";
import type { EngineConfig } from "./core/types";

declare global {
  interface Window {
    __SOCIAL_REWIND_CONFIG__?: EngineConfig;
    SocialRewind?: PublicApi | null;
  }
}

(() => {
  if (window.top !== window) return; // main frame only
  if ("SocialRewind" in window) return; // already running
  const config = window.__SOCIAL_REWIND_CONFIG__;
  if (!config) return;
  const api = start(config);
  Object.defineProperty(window, "SocialRewind", { value: api, writable: false, configurable: false });
})();
