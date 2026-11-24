/**
 * Contract between the native shell (iOS/Android), the rule packs in /rules,
 * and the engine. Mirror any change here in:
 *   - rules/schema/rule-pack.schema.json
 *   - ios/Packages/RewindCore/Sources/RewindCore/{RulePack,PlatformSettings,BridgeEvent}.swift
 */

/** Bump when the engine gains a capability that rule packs may depend on. */
export const ENGINE_VERSION = 1;

export type FeatureId = string;
export type ModeId = string; // "normal" | keys of RulePack.modes

// ---------------------------------------------------------------------------
// Settings (owned by native, passed in config)
// ---------------------------------------------------------------------------

export interface PlatformSettings {
  /** "normal" or a key of RulePack.modes, e.g. "dmsOnly", "savedOnly". */
  mode: ModeId;
  /** Feature toggles keyed by RulePack.features keys. Missing → feature default. */
  features: Record<FeatureId, boolean>;
  grayscale: boolean;
  postCounter: boolean;
}

export interface EngineConfig {
  platform: string;
  /** Hostnames the engine may act on (from native's hardcoded allowlist). Elsewhere it stays inert. */
  hosts?: string[];
  settings: PlatformSettings;
  rules: RulePack;
  /** Known account handle (for templated mode homes such as "/{username}/saved/"). */
  username?: string;
  /** Outline hidden elements instead of hiding them; emit ruleHit events. */
  debug?: boolean;
  /** Apply rules marked `verified: false` for network filtering. */
  experimental?: boolean;
}

// ---------------------------------------------------------------------------
// Rule packs (declarative data; may be refreshed from GitHub; never code)
// ---------------------------------------------------------------------------

export interface RulePack {
  schemaVersion: 1;
  platform: string;
  /** Monotonic integer; higher wins when choosing bundled vs refreshed. */
  revision: number;
  minEngineVersion: number;
  startPath: string;
  /** Routes that are always reachable (login, 2FA, account recovery). Regex on pathname. */
  alwaysAllowRoutes?: string[];
  features: Record<FeatureId, FeatureDef>;
  modes?: Record<ModeId, ModeDef>;
  counter?: CounterDef;
  identity?: IdentityDef;
}

export type FeatureGroup = "content" | "ads";

export interface FeatureDef {
  title: string;
  description?: string;
  group: FeatureGroup;
  default: boolean;
  /** false → shown as "coming soon" and never applied. Default true. */
  available?: boolean;
  rules: RuleSet;
}

export interface RuleSet {
  /** Selectors hidden with `display:none !important`. Engine sets html[data-sr-path] for route scoping. */
  css?: string[];
  dom?: DomRule[];
  routes?: RouteRule[];
  network?: NetworkRule[];
}

export type DomRule = HideClosestRule | HideIfTextRule | HideAllButFirstRule;

/**
 * Every DOM rule may carry `when`: a selector tested against <html>. The rule
 * applies only while it matches, e.g. `html[data-sr-path^="/reel/"]` to scope a
 * rule to a route. Elements a rule hid are shown again once `when` stops matching.
 */
interface Conditional {
  when?: string;
}

/** Find `match`, hide its nearest ancestor matching `closest`. */
export interface HideClosestRule extends Conditional {
  type: "hideClosest";
  match: string;
  closest: string;
}

/** Hide `container` elements containing a text node whose trimmed value equals one of `text`. */
export interface HideIfTextRule extends Conditional {
  type: "hideIfText";
  container: string;
  text: string[];
  /** "exact" (default): whole text node equals. "prefix": text node starts with. */
  match?: "exact" | "prefix";
  /** Only consider text inside descendants of the container matching this selector (e.g. "header"). */
  within?: string;
}

/** Hide every element matching `selector` except the first in document order (e.g. "one reel, no scrolling on"). */
export interface HideAllButFirstRule extends Conditional {
  type: "hideAllButFirst";
  selector: string;
}

export interface RouteRule {
  /** Regex tested against location.pathname. */
  pattern: string;
  action: "block" | "redirect";
  /** Redirect target path. May use $1.. capture groups. */
  to?: string;
}

export interface NetworkRule {
  /** Regex tested against the absolute request URL. */
  url: string;
  /** Remove array elements (objects) matching this predicate, anywhere in the JSON. */
  removeWhere: Predicate;
  /** Network rules are dangerous when wrong (they remove real content). Unverified → experimental only. */
  verified?: boolean;
}

export type Predicate =
  | { anyOf: Predicate[] }
  | { allOf: Predicate[] }
  | { not: Predicate }
  | FieldPredicate;

export interface FieldPredicate {
  /** Dot path inside the candidate object, e.g. "node.product_type". */
  path: string;
  exists?: boolean;
  equals?: string | number | boolean | null;
  in?: Array<string | number | boolean | null>;
}

export interface ModeDef {
  title: string;
  description?: string;
  /** Path to land on; may contain "{username}". */
  home: string;
  /** Regex list on pathname; anything else redirects to home. Home itself is always allowed. */
  allowRoutes: string[];
  rules?: RuleSet;
}

export interface CounterDef {
  /** Selector for one countable post. */
  item: string;
  /** How to derive a stable key for de-duplication. */
  key: { selector: string; attr: string; pattern?: string };
  minVisibleRatio?: number; // default 0.5
  minVisibleMs?: number; // default 1000
}

export interface IdentityDef {
  /**
   * Optional anchors (selectors). When given, the search is limited to their lowest
   * common ancestor, e.g. the nav bar containing both the Home and Inbox links.
   */
  scope?: string[];
  /** Candidate elements; the first whose attribute matches `pattern` wins. */
  selector: string;
  attr: string;
  /** Regex with one capture group for the username. */
  pattern: string;
}

// ---------------------------------------------------------------------------
// Events to native (webkit.messageHandlers.socialRewind in the isolated world / SocialRewindAndroid).
// Native must treat these as untrusted input.
// ---------------------------------------------------------------------------

export type BridgeEvent =
  | { type: "ready"; engineVersion: number; rulesRevision: number }
  | { type: "postViewed"; key: string; sessionCount: number }
  | { type: "routeBlocked"; path: string; reason: string; redirectedTo?: string }
  | { type: "ruleHit"; ruleId: string }
  | { type: "identity"; username: string }
  | { type: "error"; message: string };
