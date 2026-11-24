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

  const tryOne = (chunk: string): { out: string; removed: number } | null => {
    let parsed: Json;
    try {
      parsed = JSON.parse(chunk) as Json;
    } catch {
      return null;
    }
    const removed = filterJson(parsed, predicates);
    return { out: removed ? JSON.stringify(parsed) : chunk, removed };
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
