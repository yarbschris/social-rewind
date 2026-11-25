import type { ActiveRules } from "./compile";
import type { DomRule, HideClosestRule, HideIfTextRule } from "./types";
import { send } from "./bridge";

export const HIDDEN_ATTR = "data-sr-hidden";
export const PATH_ATTR = "data-sr-path";
export const COLLAPSE_ATTR = "data-sr-collapse";
const STYLE_ID = "social-rewind-style";

export interface DomOptions {
  debug: boolean;
  grayscale: boolean;
}

export interface DomHandle {
  /** Re-render CSS, un-hide elements whose rule is no longer active, and re-scan. */
  refresh(opts: DomOptions): void;
  setPath(path: string): void;
  /** Re-evaluate route-scoped (`when`) rules after the path changed. */
  pathChanged(): void;
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
  // Debug: label each outlined element with the rule that matched it.
  const label =
    "font: 600 10px/1.2 ui-monospace, monospace !important; color: #fff !important; background: #e0245e !important;" +
    " padding: 1px 3px !important; display: inline-block !important; opacity: 1 !important;";
  const lines: string[] = [];
  // One rule per selector: a single invalid selector in a list would void the whole list.
  for (const { id, rule } of rules.css) {
    if (!isValidSelector(rule)) {
      onError(`invalid selector: ${rule}`);
      continue;
    }
    lines.push(`${rule} { ${hide} }`);
    if (opts.debug && isValidSelector(`${rule}::before`)) lines.push(`${rule}::before { content: "SR ${id}" !important; ${label} }`);
  }
  lines.push(`[${HIDDEN_ATTR}] { ${hide} }`);
  // Collapsed: still in the layout (so "load more" observers fire as it passes), but 0px and inert.
  if (!opts.debug) {
    lines.push(
      `[${HIDDEN_ATTR}][${COLLAPSE_ATTR}] { display: block !important; height: 0 !important; min-height: 0 !important;` +
        " overflow: hidden !important; margin: 0 !important; padding: 0 !important; border: 0 !important;" +
        " opacity: 0 !important; pointer-events: none !important; }",
    );
  }
  if (opts.debug) lines.push(`[${HIDDEN_ATTR}]::before { content: "SR " attr(${HIDDEN_ATTR}) !important; ${label} }`);
  if (opts.grayscale) lines.push("html { filter: grayscale(1) !important; }");
  return lines.join("\n");
}

type TextRule = { id: string; rule: HideIfTextRule };

function textNodeMatches(t: string, rule: HideIfTextRule): boolean {
  const mode = rule.match ?? "exact";
  return rule.text.some((want) => (mode === "exact" ? t === want : t.startsWith(want)));
}

/** One text walk per scope; returns the first rule that matches. */
function matchText(container: Element, group: TextRule[]): TextRule | null {
  const scopes = new Map<string, TextRule[]>(); // "" = whole container
  for (const r of group) {
    const key = r.rule.within ?? "";
    scopes.set(key, [...(scopes.get(key) ?? []), r]);
  }
  for (const [scope, rules] of scopes) {
    let roots: Element[] = [container];
    if (scope) {
      try {
        roots = [...container.querySelectorAll(scope)];
      } catch {
        continue;
      }
    }
    for (const root of roots) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const t = n.nodeValue?.trim();
        if (!t) continue;
        for (const r of rules) if (textNodeMatches(t, r.rule)) return r;
      }
    }
  }
  return null;
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

/** Climb from `el` while the parent has no other element child. Stops below <main>, <body> and <html>. */
function outermostWrapper(el: Element): Element {
  let w = el;
  for (let p = w.parentElement; p && p.childElementCount === 1 && !p.matches("main, body, html"); p = p.parentElement) w = p;
  return w;
}

/** The largest ancestor of `el` (or `el` itself) that doesn't contain `keep`. Never <body>/<html>. */
function branchOf(el: Element, keep: Element): Element {
  let b = el;
  for (let p = b.parentElement; p && p !== document.body && p !== document.documentElement && !p.contains(keep); p = p.parentElement) b = p;
  return b;
}

export function installDom(getRules: () => ActiveRules, initial: DomOptions, onError: (m: string) => void = () => {}): DomHandle {
  let opts = initial;
  const style = document.createElement("style");
  style.id = STYLE_ID;

  const ensureStyle = () => {
    if (!style.isConnected) (document.head ?? document.documentElement).appendChild(style);
  };

  const hide = (el: Element, id: string, rule: DomRule) => {
    if (el.hasAttribute(HIDDEN_ATTR)) return;
    el.setAttribute(HIDDEN_ATTR, id);
    if (rule.collapse) el.setAttribute(COLLAPSE_ATTR, "");
    // A collapsed post is still "on screen" as far as the site knows: don't let its video play.
    for (const v of el.querySelectorAll("video")) v.pause();
    if (opts.debug) send({ type: "ruleHit", ruleId: id });
  };

  const unhide = (el: Element) => {
    el.removeAttribute(HIDDEN_ATTR);
    el.removeAttribute(COLLAPSE_ATTR);
  };

  // `play` doesn't bubble, so catch it on the way down.
  const onPlay = (e: Event) => {
    const t = e.target;
    if (t instanceof HTMLMediaElement && t.closest(`[${HIDDEN_ATTR}]`)) t.pause();
  };
  document.addEventListener("play", onPlay, true);

  const applyClosest = (root: ParentNode, id: string, rule: HideClosestRule) => {
    for (const m of within(root, rule.match)) {
      const target = m.closest(rule.closest);
      if (target) hide(rule.withWrappers ? outermostWrapper(target) : target, id, rule);
    }
  };

  const containersFor = (root: ParentNode, selector: string): Set<Element> => {
    const set = new Set<Element>(within(root, selector));
    if (root instanceof Element) {
      try {
        const up = root.closest(selector);
        if (up) set.add(up);
      } catch {
        /* invalid selector */
      }
    }
    return set;
  };

  const applies = (rule: DomRule): boolean => {
    if (!rule.when) return true;
    try {
      return document.documentElement.matches(rule.when);
    } catch {
      return false;
    }
  };

  /** Ids of DOM rules that may currently hide elements. */
  const liveIds = (): Set<string> => new Set(getRules().dom.filter((r) => applies(r.rule)).map((r) => r.id));

  const apply = (root: ParentNode) => {
    const groups = new Map<string, TextRule[]>();
    for (const { id, rule } of getRules().dom) {
      if (!applies(rule)) continue;
      if (rule.type === "hideClosest") applyClosest(root, id, rule);
      else if (rule.type === "hideAllButFirst") {
        // Document-wide by nature: "first" only means something globally.
        const [first, ...rest] = within(document, rule.selector);
        for (const m of rest) {
          if (!rule.branch) hide(m, id, rule);
          else if (first && !m.contains(first) && !first.contains(m)) hide(branchOf(m, first), id, rule);
        }
      } else groups.set(rule.container, [...(groups.get(rule.container) ?? []), { id, rule }]);
    }
    for (const [selector, group] of groups) {
      for (const c of containersFor(root, selector)) {
        if (c.hasAttribute(HIDDEN_ATTR)) continue;
        const hit = matchText(c, group);
        if (hit) hide(c, hit.id, hit.rule);
      }
    }
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

  /** Show elements hidden by rules that are no longer enabled, or whose `when` stopped matching. */
  const unhideStale = () => {
    const live = liveIds();
    for (const el of document.querySelectorAll(`[${HIDDEN_ATTR}]`)) {
      if (!live.has(el.getAttribute(HIDDEN_ATTR) ?? "")) unhide(el);
    }
  };

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
      unhideStale();
      apply(document);
    },
    pathChanged() {
      unhideStale();
      apply(document);
    },
    setPath(path) {
      document.documentElement.setAttribute(PATH_ATTR, path);
    },
    apply,
    uninstall() {
      observer.disconnect();
      document.removeEventListener("play", onPlay, true);
      style.remove();
    },
  };
}
