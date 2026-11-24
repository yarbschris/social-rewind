import type { ActiveRules } from "./compile";
import type { DomRule } from "./types";
import { send } from "./bridge";

export const HIDDEN_ATTR = "data-sr-hidden";
export const PATH_ATTR = "data-sr-path";
const STYLE_ID = "social-rewind-style";

export interface DomOptions {
  debug: boolean;
  grayscale: boolean;
}

export interface DomHandle {
  /** Re-render CSS, un-hide elements whose rule is no longer active, and re-scan. */
  refresh(opts: DomOptions): void;
  setPath(path: string): void;
  /** Apply DOM rules to a subtree (exposed for tests). */
  apply(root: ParentNode): void;
  uninstall(): void;
}

function isValidSelector(sel: string): boolean {
  try {
    document.createDocumentFragment().querySelector(sel);
    return true;
  } catch {
    return false;
  }
}

export function buildCss(rules: ActiveRules, opts: DomOptions, onError: (m: string) => void = () => {}): string {
  const hide = opts.debug
    ? "outline: 3px dashed #e0245e !important; opacity: 0.35 !important;"
    : "display: none !important;";
  const lines: string[] = [];
  // One rule per selector: a single invalid selector in a list would void the whole list.
  for (const { rule } of rules.css) {
    if (isValidSelector(rule)) lines.push(`${rule} { ${hide} }`);
    else onError(`invalid selector: ${rule}`);
  }
  lines.push(`[${HIDDEN_ATTR}] { ${hide} }`);
  if (opts.grayscale) lines.push("html { filter: grayscale(1) !important; }");
  return lines.join("\n");
}

function textMatches(container: Element, texts: string[], mode: "exact" | "prefix"): boolean {
  const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const t = n.nodeValue?.trim();
    if (!t) continue;
    for (const want of texts) {
      if (mode === "exact" ? t === want : t.startsWith(want)) return true;
    }
  }
  return false;
}

function within(root: ParentNode, selector: string): Element[] {
  const out: Element[] = [];
  try {
    if (root instanceof Element && root.matches(selector)) out.push(root);
    out.push(...root.querySelectorAll(selector));
  } catch {
    // invalid selector: reported at compile/css time
  }
  return out;
}

export function installDom(getRules: () => ActiveRules, initial: DomOptions, onError: (m: string) => void = () => {}): DomHandle {
  let opts = initial;
  const style = document.createElement("style");
  style.id = STYLE_ID;

  const ensureStyle = () => {
    if (!style.isConnected) (document.head ?? document.documentElement).appendChild(style);
  };

  const hide = (el: Element, id: string) => {
    if (el.hasAttribute(HIDDEN_ATTR)) return;
    el.setAttribute(HIDDEN_ATTR, id);
    if (opts.debug) send({ type: "ruleHit", ruleId: id });
  };

  const applyRule = (root: ParentNode, id: string, rule: DomRule) => {
    if (rule.type === "hideClosest") {
      for (const m of within(root, rule.match)) {
        const target = m.closest(rule.closest);
        if (target) hide(target, id);
      }
    } else {
      const containers = new Set<Element>(within(root, rule.container));
      if (root instanceof Element) {
        try {
          const up = root.closest(rule.container);
          if (up) containers.add(up);
        } catch {
          /* invalid selector */
        }
      }
      for (const c of containers) {
        if (!c.hasAttribute(HIDDEN_ATTR) && textMatches(c, rule.text, rule.match ?? "exact")) hide(c, id);
      }
    }
  };

  const apply = (root: ParentNode) => {
    for (const { id, rule } of getRules().dom) applyRule(root, id, rule);
  };

  const observer = new MutationObserver((records) => {
    ensureStyle();
    const targets = new Set<Element>();
    for (const r of records) {
      if (r.type === "characterData") {
        if (r.target.parentElement) targets.add(r.target.parentElement);
        continue;
      }
      for (const n of r.addedNodes) {
        if (n.nodeType === Node.ELEMENT_NODE) targets.add(n as Element);
        else if (n.nodeType === Node.TEXT_NODE && n.parentElement) targets.add(n.parentElement);
      }
    }
    for (const t of targets) if (t.isConnected) apply(t);
  });

  const render = () => {
    style.textContent = buildCss(getRules(), opts, onError);
    ensureStyle();
  };

  render();
  observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => apply(document), { once: true });
  } else {
    apply(document);
  }

  return {
    refresh(next) {
      opts = next;
      render();
      const active = getRules().ids;
      for (const el of document.querySelectorAll(`[${HIDDEN_ATTR}]`)) {
        if (!active.has(el.getAttribute(HIDDEN_ATTR) ?? "")) el.removeAttribute(HIDDEN_ATTR);
      }
      apply(document);
    },
    setPath(path) {
      document.documentElement.setAttribute(PATH_ATTR, path);
    },
    apply,
    uninstall() {
      observer.disconnect();
      style.remove();
    },
  };
}
