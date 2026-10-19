import { createHash, createHmac, randomBytes, scryptSync, timingSafeEqual } from "node:crypto";

declare function exports(name: string, fn: (...args: never[]) => unknown): void;

// OWASP's scrypt guidance: N = 2^15, r = 8, p = 3. The parameters travel inside the stored hash so they can be raised later.
const COST = { N: 32768, r: 8, p: 3 };
const maxmem = (c: { N: number; r: number }) => 128 * c.N * c.r * 2;

/** `scrypt$N$r$p$<salt>$<hash>`. Argon2id is not in Node 22, so scrypt is the memory-hard KDF used. */
export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  const key = scryptSync(password, salt, 32, { ...COST, maxmem: maxmem(COST) });
  return `scrypt$${COST.N}$${COST.r}$${COST.p}$${salt.toString("base64url")}$${key.toString("base64url")}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const parts = String(stored).split("$");
  if (parts[0] !== "scrypt" || parts.length !== 6) return false;
  const [, n, r, p, salt, hash] = parts;
  const cost = { N: Number(n), r: Number(r), p: Number(p) };
  // Never run a cost taken from stored data without a ceiling: a tampered row must not be able to exhaust memory.
  if (
    !(
      cost.N >= 1024 &&
      cost.N <= 2 ** 20 &&
      (cost.N & (cost.N - 1)) === 0 &&
      cost.r >= 1 &&
      cost.r <= 16 &&
      cost.p >= 1 &&
      cost.p <= 16
    )
  )
    return false;
  if (128 * cost.N * cost.r > 256 * 1024 * 1024) return false;
  const want = Buffer.from(hash ?? "", "base64url");
  if (want.length === 0 || !salt) return false;
  const got = scryptSync(password, Buffer.from(salt, "base64url"), want.length, {
    ...cost,
    maxmem: maxmem(cost),
  });
  return got.length === want.length && timingSafeEqual(got, want);
}

export function randomToken(bytes = 32): string {
  return randomBytes(Math.min(Math.max(bytes, 16), 64)).toString("base64url");
}

export function sha256(input: string): string {
  return createHash("sha256").update(String(input)).digest("hex");
}

export function hmacSha256(secret: string, body: string): string {
  return createHmac("sha256", String(secret)).update(String(body)).digest("hex");
}

export function installCrypto(): void {
  exports("HmacSha256", hmacSha256 as never);
  exports("Sha256", sha256 as never);
  exports("HashPassword", hashPassword as never);
  exports("VerifyPassword", verifyPassword as never);
  exports("RandomToken", randomToken as never);
}
