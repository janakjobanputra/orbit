// Run with: node --test site-worker.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import worker, { validUsage, validCrash } from "./site-worker.js";

const usage = { version: "1.1.5", os: "15", arch: "arm64", eventsView: "day", menuBarStyle: "classic", textSize: "standard", eventDensity: "compact", calendars: "1-3" };
const crash = { version: "1.1.5", build: "202611061134", os: "15", arch: "arm64", signal: 11, callStack: "{}" };

function fakeDB() {
  const runs = [];
  return { runs, prepare: (sql) => ({ bind: (...args) => ({ run: async () => runs.push({ sql, args }) }) }) };
}
const post = (path, body) => new Request(`https://try-orbit.app${path}`, { method: "POST", body: typeof body === "string" ? body : JSON.stringify(body) });

test("a valid usage report is counted, not stored as its own row", async () => {
  const DB = fakeDB();
  const response = await worker.fetch(post("/api/usage", usage), { DB });
  assert.equal(response.status, 204);
  assert.match(DB.runs[0].sql, /ON CONFLICT/);
  assert.match(DB.runs[0].sql, /reports \+ 1/);
});

test("a usage report with an unknown value or free text is refused", async () => {
  assert.equal(validUsage(usage), true);
  assert.equal(validUsage({ ...usage, eventsView: "Lunch with Sam" }), false);
  assert.equal(validUsage({ ...usage, version: "<script>" }), false);
  const DB = fakeDB();
  assert.equal((await worker.fetch(post("/api/usage", { ...usage, arch: "z80" }), { DB })).status, 400);
  assert.equal(DB.runs.length, 0);
});

test("extra fields in a usage report are never stored", async () => {
  const DB = fakeDB();
  await worker.fetch(post("/api/usage", { ...usage, email: "someone@example.com" }), { DB });
  assert.ok(!JSON.stringify(DB.runs[0].args).includes("example.com"));
});

test("the sender's address is never stored", async () => {
  const DB = fakeDB();
  const request = new Request("https://try-orbit.app/api/crash", { method: "POST", body: JSON.stringify(crash), headers: { "CF-Connecting-IP": "203.0.113.9" } });
  await worker.fetch(request, { DB });
  assert.equal(DB.runs.length, 1);
  assert.ok(!JSON.stringify(DB.runs[0].args).includes("203.0.113.9"));
});

test("crash reports are checked and stored", async () => {
  assert.equal(validCrash(crash), true);
  assert.equal(validCrash({ ...crash, callStack: "" }), false);
  assert.equal(validCrash({ ...crash, signal: "eleven" }), false);
  const DB = fakeDB();
  assert.equal((await worker.fetch(post("/api/crash", crash), { DB })).status, 204);
  assert.equal(DB.runs.length, 1);
});

test("bad bodies, oversized bodies and other methods are refused", async () => {
  const DB = fakeDB();
  assert.equal((await worker.fetch(post("/api/usage", "not json"), { DB })).status, 400);
  assert.equal((await worker.fetch(post("/api/crash", "x".repeat(300 * 1024)), { DB })).status, 400);
  assert.equal((await worker.fetch(new Request("https://try-orbit.app/api/usage"), { DB })).status, 405);
  assert.equal(DB.runs.length, 0);
});

test("with no database attached, reports are turned away rather than crashing the site", async () => {
  assert.equal((await worker.fetch(post("/api/usage", usage), {})).status, 503);
});
