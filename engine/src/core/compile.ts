import type {
  DomRule,
  EngineConfig,
  NetworkRule,
  Predicate,
  RouteRule,
  RulePack,
  RuleSet,
} from "./types";
import { isSafePath } from "./router";

export interface Tagged<T> {
  id: string;
  rule: T;
}

export interface CompiledRoute {
  id: string;
  pattern: RegExp;
  action: "block" | "redirect";
  to?: string;
}

export interface CompiledNetwork {
  id: string;
  url: RegExp;
  removeWhere: Predicate;
}

export interface CompiledMode {
  id: string;
  /** Resolved home path, or null when it needs a username we don't know yet. */
  home: string | null;
  allow: RegExp[];
}

export interface ActiveRules {
  css: Tagged<string>[];
  dom: Tagged<DomRule>[];
  routes: CompiledRoute[];
  network: CompiledNetwork[];
  alwaysAllow: RegExp[];
  mode: CompiledMode | null;
  /** Ids of every active rule, used to un-hide elements when settings change. */
  ids: Set<string>;
}

/** Compile regexes defensively: a bad pattern in a refreshed pack must not crash the engine. */
function re(source: string, onError: (msg: string) => void): RegExp | null {
  try {
    return new RegExp(source);
  } catch {
    onError(`invalid regex: ${source}`);
    return null;
  }
}

export function featureEnabled(pack: RulePack, settings: EngineConfig["settings"], id: string): boolean {
  const def = pack.features[id];
  if (!def || def.available === false) return false;
  return settings.features[id] ?? def.default;
}

export function resolveHome(template: string, username: string | undefined): string | null {
  if (!template.includes("{username}")) return template;
  if (!username) return null;
  return template.replaceAll("{username}", encodeURIComponent(username));
}

export function compile(config: EngineConfig, onError: (msg: string) => void = () => {}): ActiveRules {
  const { rules: pack, settings } = config;
  const out: ActiveRules = {
    css: [],
    dom: [],
    routes: [],
    network: [],
    alwaysAllow: [],
    mode: null,
    ids: new Set(),
  };

  const addSet = (prefix: string, set: RuleSet | undefined) => {
    if (!set) return;
    set.css?.forEach((rule, i) => out.css.push({ id: `${prefix}.css${i}`, rule }));
    set.dom?.forEach((rule, i) => out.dom.push({ id: `${prefix}.dom${i}`, rule }));
    set.routes?.forEach((rule: RouteRule, i) => {
      const pattern = re(rule.pattern, onError);
      if (pattern) out.routes.push({ id: `${prefix}.route${i}`, pattern, action: rule.action, to: rule.to });
    });
    set.network?.forEach((rule: NetworkRule, i) => {
      if (rule.verified === false && !config.experimental) return;
      const url = re(rule.url, onError);
      if (url) out.network.push({ id: `${prefix}.net${i}`, url, removeWhere: rule.removeWhere });
    });
  };

  for (const id of Object.keys(pack.features)) {
    if (featureEnabled(pack, settings, id)) addSet(id, pack.features[id]!.rules);
  }

  const modeDef = settings.mode !== "normal" ? pack.modes?.[settings.mode] : undefined;
  if (modeDef) {
    let home = resolveHome(modeDef.home, config.username);
    if (home !== null && !isSafePath(home)) {
      onError(`unsafe mode home: ${home}`);
      home = null;
    }
    // Mode CSS waits until home is known, so it can't hide the page we're stuck on
    // (e.g. the login form) while the username is unresolved.
    if (home !== null) addSet(`mode:${settings.mode}`, modeDef.rules);
    out.mode = {
      id: `mode:${settings.mode}`,
      home,
      allow: modeDef.allowRoutes.map((p) => re(p, onError)).filter((r): r is RegExp => r !== null),
    };
  }

  out.alwaysAllow = (pack.alwaysAllowRoutes ?? []).map((p) => re(p, onError)).filter((r): r is RegExp => r !== null);

  for (const list of [out.css, out.dom, out.routes, out.network]) for (const r of list) out.ids.add(r.id);
  return out;
}
