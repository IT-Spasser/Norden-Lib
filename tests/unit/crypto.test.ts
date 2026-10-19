import { describe, expect, test } from "bun:test";
import { hashPassword, hmacSha256, sha256, verifyPassword } from "../../server/lib/crypto/index";

describe("passwords", () => {
  test("round trip, wrong password, malformed hash", () => {
    const h = hashPassword("hemmelig");
    expect(verifyPassword("hemmelig", h)).toBe(true);
    expect(verifyPassword("forkert", h)).toBe(false);
    expect(verifyPassword("hemmelig", "plain")).toBe(false);
    expect(h.startsWith("scrypt$32768$8$3$")).toBe(true);
    expect(hashPassword("hemmelig")).not.toBe(h);
  });
});

test("sha256 is the standard hex digest", () => {
  expect(sha256("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

test("hmacSha256 matches the RFC 4231 test case 2", () => {
  expect(hmacSha256("Jefe", "what do ya want for nothing?")).toBe(
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
  );
});

test("a stored hash cannot choose a cost that exhausts memory, and malformed hashes are refused", () => {
  expect(verifyPassword("x", "scrypt$1048576$16$16$AAAA$AAAA")).toBe(false);
  expect(verifyPassword("x", "scrypt$1000$8$1$AAAA$AAAA")).toBe(false);
  expect(verifyPassword("x", "scrypt$16384$8$1$$")).toBe(false);
  expect(verifyPassword("x", "scrypt$16384$8$1$AAAA")).toBe(false);
});
