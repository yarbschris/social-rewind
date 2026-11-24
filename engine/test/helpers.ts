import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { EngineConfig, PlatformSettings, RulePack } from "../src/core/types";

export const RULES_DIR = join(import.meta.dirname, "../../rules");

export function loadPack(platform: string): RulePack {
  return JSON.parse(readFileSync(join(RULES_DIR, `${platform}.json`), "utf8")) as RulePack;
}

export function settings(over: Partial<PlatformSettings> = {}): PlatformSettings {
  return { mode: "normal", features: {}, grayscale: false, postCounter: true, ...over };
}

export function config(over: Partial<EngineConfig> = {}, pack = loadPack("instagram")): EngineConfig {
  return { platform: pack.platform, rules: pack, settings: settings(), ...over };
}

/** Minimal IntersectionObserver stand-in whose entries are driven by the test. */
export class FakeIO {
  static instances: FakeIO[] = [];
  observed = new Set<Element>();
  constructor(public cb: IntersectionObserverCallback) {
    FakeIO.instances.push(this);
  }
  observe(el: Element) {
    this.observed.add(el);
  }
  unobserve(el: Element) {
    this.observed.delete(el);
  }
  disconnect() {
    this.observed.clear();
  }
  takeRecords() {
    return [];
  }
  fire(target: Element, ratio: number) {
    this.cb(
      [{ target, intersectionRatio: ratio, isIntersecting: ratio > 0 } as IntersectionObserverEntry],
      this as unknown as IntersectionObserver,
    );
  }
}
