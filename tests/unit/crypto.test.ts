import { describe, expect, test } from "bun:test";
import { generateKeyPairSync, sign } from "node:crypto";
import { hashPassword, sha256, verifyPassword, verifyToken } from "../../server/lib/crypto/index";

const { privateKey, publicKey } = generateKeyPairSync("ed25519");
const pem = publicKey.export({ type: "spki", format: "pem" }).toString();

function token(exp: number, key = privateKey) {
  const head = Buffer.from('{"alg":"EdDSA"}').toString("base64url");
  const body = Buffer.from(JSON.stringify({ cc: "AAAA-BBBB", exp })).toString("base64url");
  return `${head}.${body}.${sign(null, Buffer.from(`${head}.${body}`), key).toString("base64url")}`;
}

describe("verifyToken", () => {
  const now = 1_700_000_000_000;
  const exp = now / 1000 + 100;
  test("accepts a valid token", () => {
    expect(JSON.parse(verifyToken(token(exp), pem, 0, now)).cc).toBe("AAAA-BBBB");
  });
  test("rejects an expired token unless grace covers it", () => {
    expect(verifyToken(token(exp), pem, 0, now + 200_000)).toBe("");
    expect(verifyToken(token(exp), pem, 3600, now + 200_000)).not.toBe("");
  });
  test("rejects a token signed by another key and malformed input", () => {
    const other = generateKeyPairSync("ed25519").privateKey;
    expect(verifyToken(token(exp, other), pem, 0, now)).toBe("");
    expect(verifyToken("nope", pem, 0, now)).toBe("");
    expect(verifyToken(token(exp), "not a key", 0, now)).toBe("");
  });
});

describe("passwords", () => {
  test("round trip, wrong password, malformed hash", () => {
    const h = hashPassword("hemmelig");
    expect(verifyPassword("hemmelig", h)).toBe(true);
    expect(verifyPassword("forkert", h)).toBe(false);
    expect(verifyPassword("hemmelig", "plain")).toBe(false);
    expect(hashPassword("hemmelig")).not.toBe(h);
  });
});

test("sha256 is the standard hex digest", () => {
  expect(sha256("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});
