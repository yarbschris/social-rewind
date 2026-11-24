// Validate every rules/*.json against the rule-pack schema. Exit 1 on failure.
import Ajv from "ajv/dist/2020.js";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const rulesDir = new URL("../../rules/", import.meta.url).pathname;
const schema = JSON.parse(readFileSync(join(rulesDir, "schema/rule-pack.schema.json"), "utf8"));
const validate = new Ajv({ allErrors: true, strict: true, allowUnionTypes: true }).compile(schema);

let failed = false;
for (const file of readdirSync(rulesDir).filter((f) => f.endsWith(".json"))) {
  const pack = JSON.parse(readFileSync(join(rulesDir, file), "utf8"));
  if (validate(pack)) {
    console.log(`ok   ${file} (revision ${pack.revision})`);
  } else {
    failed = true;
    console.error(`FAIL ${file}`);
    for (const e of validate.errors) console.error(`  ${e.instancePath} ${e.message}`);
  }
}
process.exit(failed ? 1 : 0);
