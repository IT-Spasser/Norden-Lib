import { createHash, createHmac, randomBytes, scryptSync, timingSafeEqual } from "node:crypto";

declare function exports(name: string, fn: (...args: never[]) => unknown): void;

const SCRYPT = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

/** `scrypt$<salt>$<hash>`. Argon2id is not in Node 22, so scrypt is the memory-hard KDF used. */
export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  return `scrypt$${salt.toString("base64url")}$${scryptSync(password, salt, 32, SCRYPT).toString("base64url")}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const [scheme, salt, hash] = String(stored).split("$");
  if (scheme !== "scrypt" || !salt || !hash) return false;
  const want = Buffer.from(hash, "base64url");
  const got = scryptSync(password, Buffer.from(salt, "base64url"), want.length, SCRYPT);
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
