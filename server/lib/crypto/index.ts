import {
  createHash,
  createPublicKey,
  randomBytes,
  scryptSync,
  timingSafeEqual,
  verify,
} from "node:crypto";

declare function exports(name: string, fn: (...args: never[]) => unknown): void;

const SCRYPT = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

/** Claims of a valid EdDSA token as a JSON string, or "" when the signature or expiry fails. */
export function verifyToken(
  token: string,
  publicKeyPem: string,
  allowExpiredSeconds = 0,
  nowMs = Date.now()
): string {
  const [head, body, sig] = String(token).split(".");
  if (!head || !body || !sig) return "";
  try {
    const key = createPublicKey(publicKeyPem);
    if (!verify(null, Buffer.from(`${head}.${body}`), key, Buffer.from(sig, "base64url")))
      return "";
    const claims = JSON.parse(Buffer.from(body, "base64url").toString());
    if (typeof claims.exp !== "number") return "";
    if (claims.exp * 1000 + allowExpiredSeconds * 1000 < nowMs) return "";
    return JSON.stringify(claims);
  } catch {
    return "";
  }
}

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

export function installCrypto(): void {
  exports("Sha256", sha256 as never);
  exports("VerifyToken", verifyToken as never);
  exports("HashPassword", hashPassword as never);
  exports("VerifyPassword", verifyPassword as never);
  exports("RandomToken", randomToken as never);
}
