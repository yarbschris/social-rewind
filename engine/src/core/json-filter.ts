import type { Predicate } from "./types";

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

function get(obj: unknown, path: string): { found: boolean; value: unknown } {
  let cur: unknown = obj;
  for (const key of path.split(".")) {
    if (cur === null || typeof cur !== "object" || !(key in (cur as object))) return { found: false, value: undefined };
    cur = (cur as Record<string, unknown>)[key];
  }
  return { found: true, value: cur };
}

export function matches(obj: unknown, p: Predicate): boolean {
  if ("anyOf" in p) return p.anyOf.some((q) => matches(obj, q));
  if ("allOf" in p) return p.allOf.every((q) => matches(obj, q));
  if ("not" in p) return !matches(obj, p.not);
  const { found, value } = get(obj, p.path);
  // `exists: true` means present and not null; `exists: false` means absent or null.
  if (p.exists !== undefined && p.exists !== (found && value !== null)) return false;
  if (p.equals !== undefined && !(found && value === p.equals)) return false;
  if (p.in !== undefined && !(found && p.in.includes(value as never))) return false;
  return true;
}

/**
 * Remove every array element (that is an object) matching any predicate, at any depth.
 * Mutates and returns `root`. Returns the number of removed items.
 */
export function filterJson(root: unknown, predicates: Predicate[]): number {
  let removed = 0;
  const visit = (node: Json): void => {
    if (Array.isArray(node)) {
      for (let i = node.length - 1; i >= 0; i--) {
        const item = node[i]!;
        if (item !== null && typeof item === "object" && !Array.isArray(item) && predicates.some((p) => matches(item, p))) {
          node.splice(i, 1);
          removed++;
        } else {
          visit(item);
        }
      }
    } else if (node !== null && typeof node === "object") {
      for (const key of Object.keys(node)) visit(node[key]!);
    }
  };
  visit(root as Json);
  return removed;
}

const XSSI_PREFIXES = ["for (;;);", ")]}'\n", ")]}'"];

// Integers above 2^53 (Instagram media/user pks) lose precision through
// JSON.parse/stringify. Before parsing, wrap long integer literals (outside
// strings) in a marker string; after stringifying, unwrap them byte-for-byte.
const BIG_MARK = "\\u0000SRBIG:";
const BIG_RESTORE = /"\\u0000SRBIG:(-?\d+)"/g;

export function protectBigInts(text: string): string {
  let out = "";
  let last = 0;
  let inString = false;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (inString) {
      if (c === 92 /* \ */) i++;
      else if (c === 34 /* " */) inString = false;
      continue;
    }
    if (c === 34) {
      inString = true;
      continue;
    }
    const isStart = c === 45 /* - */ || (c >= 48 && c <= 57);
    if (!isStart) continue;
    let j = i + 1;
    while (j < text.length && text.charCodeAt(j) >= 48 && text.charCodeAt(j) <= 57) j++;
    const next = text[j];
    const token = text.slice(i, j);
    const digits = token.startsWith("-") ? token.length - 1 : token.length;
    if (digits >= 16 && next !== "." && next !== "e" && next !== "E") {
      out += text.slice(last, i) + `"${BIG_MARK}${token}"`;
      last = j;
    }
    i = j - 1;
  }
  return last === 0 ? text : out + text.slice(last);
}

export function restoreBigInts(text: string): string {
  return text.replace(BIG_RESTORE, "$1");
}

/**
 * Filter a response body. Handles XSSI prefixes and newline-delimited JSON
 * (streamed/deferred GraphQL). Returns null if nothing changed or the body
 * isn't JSON, so callers can pass the original through untouched.
 */
export function filterBody(text: string, predicates: Predicate[]): { text: string; removed: number } | null {
  if (predicates.length === 0) return null;
  let prefix = "";
  let body = text;
  for (const p of XSSI_PREFIXES) {
    if (body.startsWith(p)) {
      prefix = p;
      body = body.slice(p.length);
      break;
    }
  }

  // Our marker could collide with a payload that already contains it; don't risk it.
  if (body.includes("\\u0000SRBIG:")) return null;

  const tryOne = (chunk: string): { out: string; removed: number } | null => {
    let parsed: Json;
    try {
      parsed = JSON.parse(protectBigInts(chunk)) as Json;
    } catch {
      return null;
    }
    const removed = filterJson(parsed, predicates);
    return { out: removed ? restoreBigInts(JSON.stringify(parsed)) : chunk, removed };
  };

  const whole = tryOne(body);
  if (whole) return whole.removed ? { text: prefix + whole.out, removed: whole.removed } : null;

  // Newline-delimited JSON
  const lines = body.split("\n");
  let total = 0;
  let anyJson = false;
  const outLines = lines.map((line) => {
    if (!line.trim()) return line;
    const r = tryOne(line);
    if (!r) return line;
    anyJson = true;
    total += r.removed;
    return r.out;
  });
  if (!anyJson || total === 0) return null;
  return { text: prefix + outLines.join("\n"), removed: total };
}
