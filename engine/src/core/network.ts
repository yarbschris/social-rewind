import type { ActiveRules } from "./compile";
import type { Predicate } from "./types";
import { filterBody, filterJson } from "./json-filter";

export interface NetworkHandle {
  uninstall(): void;
}

function predicatesFor(url: string, rules: ActiveRules): Predicate[] {
  return rules.network.filter((r) => r.url.test(url)).map((r) => r.removeWhere);
}

function absolute(url: string | URL): string {
  try {
    return new URL(String(url), location.href).href;
  } catch {
    return String(url);
  }
}

const URL_KEY = Symbol("socialRewindUrl");
const CACHE_KEY = Symbol("socialRewindCache");

interface TaggedXhr {
  [URL_KEY]?: string;
  [CACHE_KEY]?: { raw: unknown; out: unknown };
}

/**
 * Wrap fetch and XMLHttpRequest so matching JSON responses are filtered before
 * the page sees them. Any failure passes the original response through.
 */
export function installNetwork(getRules: () => ActiveRules, win: typeof globalThis = globalThis): NetworkHandle {
  const restore: Array<() => void> = [];

  // --- fetch -------------------------------------------------------------
  const origFetch = win.fetch;
  if (typeof origFetch === "function") {
    const wrapped = async function (this: unknown, input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
      const res = await origFetch.call(this ?? win, input, init);
      try {
        const reqUrl = res.url || (input instanceof Request ? input.url : absolute(input as string | URL));
        const preds = predicatesFor(reqUrl, getRules());
        if (preds.length === 0) return res;
        const type = res.headers.get("content-type") ?? "";
        if (type && !/json|javascript|text/i.test(type)) return res;
        const text = await res.clone().text();
        const filtered = filterBody(text, preds);
        if (!filtered) return res;
        const headers = new Headers(res.headers);
        headers.delete("content-length");
        headers.delete("content-encoding");
        const out = new Response(filtered.text, { status: res.status, statusText: res.statusText, headers });
        Object.defineProperty(out, "url", { value: res.url });
        return out;
      } catch {
        return res;
      }
    };
    win.fetch = wrapped as typeof fetch;
    restore.push(() => {
      win.fetch = origFetch;
    });
  }

  // --- XMLHttpRequest ----------------------------------------------------
  const XHR = win.XMLHttpRequest;
  if (typeof XHR === "function") {
    const proto = XHR.prototype;
    const origOpen = proto.open;
    const textDesc = Object.getOwnPropertyDescriptor(proto, "responseText");
    const respDesc = Object.getOwnPropertyDescriptor(proto, "response");

    proto.open = function (this: XMLHttpRequest & TaggedXhr, method: string, url: string | URL, ...rest: unknown[]) {
      this[URL_KEY] = absolute(url);
      delete this[CACHE_KEY];
      return (origOpen as (...a: unknown[]) => void).call(this, method, url, ...rest);
    } as typeof proto.open;

    const filtered = (xhr: XMLHttpRequest & TaggedXhr, raw: unknown, kind: "text" | "json"): unknown => {
      try {
        if (xhr.readyState !== 4 || !xhr[URL_KEY]) return raw;
        const cached = xhr[CACHE_KEY];
        if (cached && cached.raw === raw) return cached.out;
        const preds = predicatesFor(xhr[URL_KEY], getRules());
        let out: unknown = raw;
        if (preds.length) {
          if (kind === "text" && typeof raw === "string") {
            out = filterBody(raw, preds)?.text ?? raw;
          } else if (kind === "json" && raw !== null && typeof raw === "object") {
            filterJson(raw, preds);
          }
        }
        xhr[CACHE_KEY] = { raw, out };
        return out;
      } catch {
        return raw;
      }
    };

    if (textDesc?.get) {
      const get = textDesc.get;
      Object.defineProperty(proto, "responseText", {
        ...textDesc,
        get(this: XMLHttpRequest & TaggedXhr) {
          return filtered(this, get.call(this), "text");
        },
      });
    }
    if (respDesc?.get) {
      const get = respDesc.get;
      Object.defineProperty(proto, "response", {
        ...respDesc,
        get(this: XMLHttpRequest & TaggedXhr) {
          const raw = get.call(this);
          const t = this.responseType;
          if (t === "" || t === "text") return filtered(this, raw, "text");
          if (t === "json") return filtered(this, raw, "json");
          return raw;
        },
      });
    }

    restore.push(() => {
      proto.open = origOpen;
      if (textDesc) Object.defineProperty(proto, "responseText", textDesc);
      if (respDesc) Object.defineProperty(proto, "response", respDesc);
    });
  }

  return {
    uninstall() {
      for (const r of restore.reverse()) r();
    },
  };
}
