/**
 * Page-world bundle entry. Native wraps this file as
 *   (function(){ "use strict"; const __SR_CONFIG__ = <json>; <this bundle> })();
 * so the config is a closure variable, never a page-visible global.
 */
import { startPage } from "./core/engine";
import type { EngineConfig } from "./core/types";

declare const __SR_CONFIG__: EngineConfig | undefined;

(() => {
  if (window.top !== window) return; // main frame only
  if (typeof __SR_CONFIG__ === "undefined") return;
  startPage(__SR_CONFIG__);
})();
