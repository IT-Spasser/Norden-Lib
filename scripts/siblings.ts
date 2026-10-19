/**
 * Which sibling resources are checked out beside NLib.
 *
 * NLib is published standalone under MIT, and several gates in this directory
 * are estate-wide by design: they exist because NLib is the only repo that can
 * see every sibling. A clone of NLib on its own has none of them, and each of
 * those gates would otherwise either die (`found 0 sibling resource(s)`) or
 * report a pass over nothing.
 *
 * Zero siblings is therefore its own case, distinct from "fewer than expected".
 * A gate reads it as "this check does not apply here" and exits 0 saying so;
 * any non-zero count keeps the gate's existing behaviour, failures included —
 * some-but-too-few is exactly the broken-discovery case those floors were
 * written to catch.
 *
 * One rule in one place rather than a copy per gate, for the same reason
 * `secret-gate-provision.ts` generates the per-resource wiring: four copies of
 * a detection is four chances for one to be the stale one, and a stale gate is
 * silent.
 */

import { existsSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Sibling resource directory names, sorted. A resource is a directory beside
 * NLib named `t<Capital>...` that has an `fxmanifest.lua` — the manifest is
 * what distinguishes a resource from a notes folder or a stray checkout.
 */
export function siblingResources(nlibRoot: string): string[] {
  const siblings = resolve(nlibRoot, "..");
  if (!existsSync(siblings)) return [];
  return readdirSync(siblings, { withFileTypes: true })
    .filter((e) => e.isDirectory() && /^t[A-Z]/.test(e.name) && e.name !== "NLib")
    .map((e) => e.name)
    .filter((name) => existsSync(join(siblings, name, "fxmanifest.lua")))
    .sort();
}

/** True when nothing but NLib is checked out — a standalone public clone. */
export function isStandaloneClone(nlibRoot: string): boolean {
  return siblingResources(nlibRoot).length === 0;
}
