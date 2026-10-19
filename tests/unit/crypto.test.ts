import { describe, expect, test } from "bun:test";
import { hashPassword, sha256, verifyPassword } from "../../server/lib/crypto/index";

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
