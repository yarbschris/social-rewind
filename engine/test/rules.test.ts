import Ajv from "ajv/dist/2020.js";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { RulePack } from "../src/core/types";
import { RULES_DIR as rulesDir } from "./helpers";

const schema = JSON.parse(readFileSync(join(rulesDir, "schema/rule-pack.schema.json"), "utf8"));
const validate = new Ajv({ allErrors: true, strict: true, allowUnionTypes: true }).compile(schema);
const packs = readdirSync(rulesDir)
  .filter((f) => f.endsWith(".json"))
  .map((f) => [f, JSON.parse(readFileSync(join(rulesDir, f), "utf8")) as RulePack] as const);

describe.each(packs)("rule pack %s", (_file, pack) => {
  it("matches the schema", () => {
    expect(validate(pack), JSON.stringify(validate.errors, null, 2)).toBe(true);
  });

  it("has only valid regexes", () => {
    const regexes = [
      ...(pack.alwaysAllowRoutes ?? []),
      ...Object.values(pack.features).flatMap((f) => [
        ...(f.rules.routes ?? []).map((r) => r.pattern),
        ...(f.rules.network ?? []).map((r) => r.url),
      ]),
      ...Object.values(pack.modes ?? {}).flatMap((m) => m.allowRoutes),
      ...(pack.counter?.routes ?? []),
    ];
    for (const r of regexes) expect(() => new RegExp(r), r).not.toThrow();
  });

  it("never broadens which hosts can load (no host fields at all)", () => {
    expect(JSON.stringify(pack)).not.toMatch(/"(allowedHosts|hosts|scripts?)"\s*:/);
  });
});

describe("schema rejects off-origin paths", () => {
  const base = packs[0]![1];
  it.each(["//evil.example/", "/\\evil.example", "https://evil.example/"])("mode home %j", (home) => {
    const pack = structuredClone(base);
    pack.modes!.dmsOnly!.home = home;
    expect(validate(pack)).toBe(false);
  });
  it("route redirect target", () => {
    const pack = structuredClone(base);
    pack.features.blockReels!.rules.routes![0]!.to = "//evil.example/";
    expect(validate(pack)).toBe(false);
  });
});
