// Tests for the Cloudflare Worker, "APNS Worker.json" in the repo root.
// Run: ./Worker\ Tests/run.sh
//
// Everything Cloudflare and Apple provide is faked here: KV (with operation
// counts, so quota use is tested too), fetch (so APNs answers can be scripted),
// and the clock (so any Pacific time, weekday or DST change can be set).
import assert from "node:assert/strict";

const RealDate = Date;
let fakeNow = RealDate.now();
class FakeDate extends RealDate {
  constructor(...args) { if (args.length === 0) super(fakeNow); else super(...args); }
  static now() { return fakeNow; }
}
globalThis.Date = FakeDate;

/** Epoch ms for a Pacific wall-clock time, DST-aware. */
function pacific(y, mo, d, h, mi, s = 0) {
  for (const off of [7, 8]) {
    const t = RealDate.UTC(y, mo - 1, d, h + off, mi, s);
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Los_Angeles", year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", hour12: false,
    }).formatToParts(new RealDate(t));
    const g = k => Number(parts.find(p => p.type === k).value) % (k === "hour" ? 24 : 1e9);
    if (g("year") === y && g("month") === mo && g("day") === d && g("hour") === h && g("minute") === mi) return t;
  }
  throw new Error("no such Pacific time");
}
const setClock = (...a) => { fakeNow = pacific(...a); };

// ── KV mock ──────────────────────────────────────────────────────────────────
class MockKV {
  constructor() { this.data = new Map(); this.ops = { get: 0, put: 0, list: 0, delete: 0 }; this.putKeys = []; }
  async get(key, type) {
    this.ops.get++;
    const e = this.data.get(key);
    if (!e) return null;
    if (e.exp && e.exp <= Date.now() / 1000) { this.data.delete(key); return null; }
    return type === "json" ? JSON.parse(e.value) : e.value;
  }
  async put(key, value, opts = {}) {
    this.ops.put++;
    this.putKeys.push(key);
    if (typeof value !== "string") throw new Error("non-string put");
    if (opts.metadata && JSON.stringify(opts.metadata).length > 1024) throw new Error("metadata too big");
    this.data.set(key, {
      value, metadata: opts.metadata ?? null,
      exp: opts.expirationTtl ? Math.floor(Date.now() / 1000) + opts.expirationTtl : null,
    });
  }
  async delete(key) { this.ops.delete++; this.data.delete(key); }
  async list({ prefix = "", limit = 1000, cursor } = {}) {
    this.ops.list++;
    const names = [...this.data.keys()].filter(k => k.startsWith(prefix)).sort();
    const start = cursor ? Number(cursor) : 0;
    const slice = names.slice(start, start + limit);
    const complete = start + limit >= names.length;
    return {
      keys: slice.map(name => ({ name, metadata: this.data.get(name).metadata ?? undefined, expiration: this.data.get(name).exp ?? undefined })),
      list_complete: complete,
      ...(complete ? {} : { cursor: String(start + limit) }),
    };
  }
  total() { return Object.values(this.ops).reduce((a, b) => a + b, 0); }
  resetOps() { this.ops = { get: 0, put: 0, list: 0, delete: 0 }; this.putKeys = []; }
}

// ── fetch mock ───────────────────────────────────────────────────────────────
let calls = [];
let responder = () => ({ status: 200, body: "" });
globalThis.fetch = async (url, init) => {
  const headers = Object.fromEntries(Object.entries(init.headers).map(([k, v]) => [k.toLowerCase(), v]));
  const call = { url, headers, body: JSON.parse(init.body) };
  calls.push(call);
  const r = responder(call);
  return new Response(r.body, { status: r.status, headers: { "apns-id": "id-" + calls.length, "apns-request-id": "req-" + calls.length } });
};

// ── env, key ─────────────────────────────────────────────────────────────────
const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", kp.privateKey)).toString("base64");
const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join("\n")}\n-----END PRIVATE KEY-----`;
const SECRET = "test-secret";
function makeEnv(extra = {}) {
  return {
    TOKENS: new MockKV(), CLIENT_SECRET: SECRET,
    APNS_KEY_ID: "KEYID12345", APNS_TEAM_ID: "TEAM123456", APNS_BUNDLE_ID: "com.lasalleyakima.lhslife",
    APNS_PRIVATE_KEY: pem, ...extra,
  };
}

const worker = (await import(process.env.WORKER_MODULE)).default;   // set by run.sh

async function req(env, method, path, { body, auth = SECRET, raw } = {}) {
  const headers = {};
  if (auth) headers.authorization = `Bearer ${auth}`;
  const r = new Request(`https://w.example${path}`, {
    method, headers, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
  const resp = await worker.fetch(r, env);
  const text = await resp.text();
  let data = text; try { data = JSON.parse(text); } catch {}
  return { status: resp.status, data, text };
}
async function cron(env) {
  const p = [];
  const before = env.TOKENS.total(), fetchBefore = calls.length;
  await worker.scheduled({}, env, { waitUntil: x => p.push(x) });
  await Promise.all(p);
  return { subrequests: env.TOKENS.total() - before + calls.length - fetchBefore, fetches: calls.slice(fetchBefore) };
}
const quiet = fn => async (...a) => { const l = console.log, e = console.error; console.log = () => {}; console.error = () => {}; try { return await fn(...a); } finally { console.log = l; console.error = e; } };
const runCron = quiet(cron);

let passed = 0, failed = 0;
async function test(name, fn) {
  calls = []; responder = () => ({ status: 200, body: "" });
  try { await quiet(fn)(); passed++; console.log(`  ok  ${name}`); }
  catch (e) { failed++; console.log(`  FAIL ${name}\n       ${e.stack.split("\n").slice(0, 8).join("\n       ")}`); }
}

const REG = [480, 535, 540, 595, 600, 655, 660, 715, 750, 805, 810, 865, 870, 925];   // 8:00 … 15:25
const LATE = [570, 625, 630, 685, 690, 715, 750, 805, 810, 865, 870, 925];            // late start
const broadcastCalls = cs => cs.filter(c => c.url.includes("/4/broadcasts/"));

// ── /bells ───────────────────────────────────────────────────────────────────
console.log("/bells");
await test("auth required (none, wrong, basic-right)", async () => {
  setClock(2026, 10, 19, 7, 0);
  const env = makeEnv();
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: REG }, auth: null })).status, 401);
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: REG }, auth: "nope" })).status, 401);
  assert.equal(env.TOKENS.ops.put, 0);
  const basic = new Request("https://w.example/bells", { method: "POST", headers: { authorization: "Basic " + btoa("x:" + SECRET) }, body: JSON.stringify({ day: "2026-10-19", minutes: REG }) });
  assert.equal((await worker.fetch(basic, env)).status, 200);
});
await test("validation", async () => {
  setClock(2026, 10, 19, 7, 0);
  const env = makeEnv();
  const bad = async (body, raw) => (await req(env, "POST", "/bells", { body, raw })).status;
  assert.equal(await bad(undefined, "{nope"), 400);
  assert.equal(await bad(null), 400);
  assert.equal(await bad({ day: "2026-10-18", minutes: REG }), 400);          // yesterday
  assert.equal(await bad({ day: "2026-10-21", minutes: REG }), 400);          // day after tomorrow
  assert.equal(await bad({ day: "10/19/2026", minutes: REG }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: [] }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: "480" }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: [480.5] }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: ["480"] }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: [299] }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: [1201] }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: Array.from({ length: 41 }, (_, i) => 400 + i) }), 400);
  assert.equal(await bad({ day: "2026-10-19", minutes: Array.from({ length: 81 }, () => 480) }), 400);
  assert.equal(env.TOKENS.ops.put, 0, "no writes on bad input");
  assert.equal(await bad({ day: "2026-10-19", minutes: [300, 1200] }), 200);   // boundaries
  assert.equal(await bad({ day: "2026-10-20", minutes: REG }), 200);           // tomorrow
  assert.equal(await bad({ day: "2026-10-19", minutes: Array.from({ length: 40 }, (_, i) => 400 + i) }), 200);
  assert.equal(await bad({ day: "2026-10-19", minutes: [...Array.from({ length: 40 }, (_, i) => 400 + i), 400, 401] }), 200); // 42 raw, 40 distinct
});
await test("tomorrow is computed in Pacific (11:30 PM PDT is already the 20th in UTC)", async () => {
  setClock(2026, 10, 19, 23, 30);
  const env = makeEnv();
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: REG } })).status, 200);
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-20", minutes: REG } })).status, 200);
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-21", minutes: REG } })).status, 400);
});
await test("same schedule from two phones → ONE write; dedupe + sort; no device data", async () => {
  setClock(2026, 10, 19, 7, 0);
  const env = makeEnv();
  const a = await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: REG, environment: "production" } });
  const b = await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: [...REG].reverse().concat([480, 925]), environment: "sandbox", deviceId: "should-be-ignored" } });
  assert.deepEqual(a.data, { status: "ok" }); assert.deepEqual(b.data, { status: "ok" });
  assert.equal(env.TOKENS.ops.put, 1);
  const keys = [...env.TOKENS.data.keys()];
  assert.equal(keys.length, 1);
  assert.match(keys[0], /^bells:2026-10-19:[0-9a-f]{12}$/);
  const e = env.TOKENS.data.get(keys[0]);
  assert.deepEqual(JSON.parse(e.value), REG);
  assert.deepEqual(e.metadata, { m: REG });
  assert.ok(e.exp > Date.now() / 1000 + 2.9 * 86400 && e.exp < Date.now() / 1000 + 3.1 * 86400, "ttl ~3 days");
  assert.ok(!e.value.includes("ignored") && !JSON.stringify(e.metadata).includes("ignored"));
  assert.equal(env.TOKENS.ops.list, 1, "list only for the new schedule");
});
await test("cap of 30 schedules per day → 429; known schedule still 200", async () => {
  setClock(2026, 10, 19, 7, 0);
  const env = makeEnv();
  for (let i = 0; i < 30; i++) assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: [480 + i, 900] } })).status, 200);
  const r = await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: [700, 900] } });
  assert.equal(r.status, 429); assert.equal(r.data.status, "too_many_schedules");
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: [480, 900] } })).status, 200);
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-20", minutes: [700, 900] } })).status, 200, "other day unaffected");
  assert.equal(env.TOKENS.ops.put, 31);
});

// ── cron broadcast ───────────────────────────────────────────────────────────
console.log("cron broadcast");
async function dayWith(schedules, day = [2026, 10, 19]) {
  setClock(...day, 6, 30);
  const env = makeEnv();
  const iso = `${day[0]}-${String(day[1]).padStart(2, "0")}-${String(day[2]).padStart(2, "0")}`;
  for (const s of schedules) await req(env, "POST", "/bells", { body: { day: iso, minutes: s } });
  return { env, iso };
}

await test("union across two schedules (from the odd-minute listing)", async () => {
  const { env, iso } = await dayWith([REG, LATE]);
  setClock(2026, 10, 19, 7, 1);
  await runCron(env);
  const rec = JSON.parse(env.TOKENS.data.get(`broadcast:${iso}`).value);
  assert.deepEqual(rec.bells, [...new Set([...REG, ...LATE])].sort((a, b) => a - b));
  assert.equal(rec.schedules, 2);
  assert.equal(calls.length, 0, "no push before first bell");
});

await test("bell minute: one update per channel, right host/path/headers/payload; no double send", async () => {
  const { env } = await dayWith([REG, LATE]);
  setClock(2026, 10, 19, 7, 59); assert.equal((await runCron(env)).fetches.length, 0);
  setClock(2026, 10, 19, 8, 0, 3);
  const run = await runCron(env);
  const b = broadcastCalls(run.fetches);
  assert.equal(b.length, 2);
  const byHost = Object.fromEntries(b.map(c => [new URL(c.url).host, c]));
  const prod = byHost["api.push.apple.com"], sand = byHost["api.sandbox.push.apple.com"];
  assert.ok(prod && sand);
  for (const c of [prod, sand]) {
    assert.equal(new URL(c.url).pathname, "/4/broadcasts/apps/com.lasalleyakima.lhslife");
    assert.equal(c.headers["apns-push-type"], "liveactivity");
    assert.equal(c.headers["apns-priority"], "10");
    assert.equal(c.headers["apns-expiration"], "0");
    assert.equal(c.headers["apns-topic"], undefined);
    assert.match(c.headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    assert.equal(c.body.aps.event, "update");
    assert.deepEqual(c.body.aps["content-state"], { slotStartMinutes: 480, isEnded: false });
    assert.ok(Math.abs(c.body.aps.timestamp - Math.floor(Date.now() / 1000)) <= 1);
    assert.equal(c.body.aps.alert, undefined);
  }
  assert.equal(prod.headers["apns-channel-id"], "JJ+34svREfEAAGpsYJ+BOQ==");
  assert.equal(sand.headers["apns-channel-id"], "oikr1cvOEfEAAPYv+t4beg==");
  setClock(2026, 10, 19, 8, 1); assert.equal(broadcastCalls((await runCron(env)).fetches).length, 0, "8:01 no resend");
  setClock(2026, 10, 19, 8, 2); assert.equal(broadcastCalls((await runCron(env)).fetches).length, 0, "8:02 no resend");
  setClock(2026, 10, 19, 8, 55);
  const r = broadcastCalls((await runCron(env)).fetches);
  assert.equal(r.length, 2); assert.equal(r[0].body.aps["content-state"].slotStartMinutes, 535);
});

await test("catch-up: bell sent up to 2 minutes late, not 3", async () => {
  const { env } = await dayWith([REG]);
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  setClock(2026, 10, 19, 8, 2);   // missed 8:00 and 8:01 runs
  const b = broadcastCalls((await runCron(env)).fetches);
  assert.equal(b.length, 2); assert.equal(b[0].body.aps["content-state"].slotStartMinutes, 480);
  setClock(2026, 10, 19, 8, 58);  // missed 8:55..8:57
  assert.equal(broadcastCalls((await runCron(env)).fetches).length, 0, "3 minutes late is too late");
});

await test("several bells due at once → only the latest sent, all marked", async () => {
  const { env, iso } = await dayWith([[480, 481, 600]]);
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  setClock(2026, 10, 19, 8, 1);
  const b = broadcastCalls((await runCron(env)).fetches);
  assert.equal(b.length, 2); assert.equal(b[0].body.aps["content-state"].slotStartMinutes, 481);
  const rec = JSON.parse(env.TOKENS.data.get(`broadcast:${iso}`).value);
  assert.ok(rec.sent.includes(480) && rec.sent.includes(481));
  setClock(2026, 10, 19, 8, 2); assert.equal(broadcastCalls((await runCron(env)).fetches).length, 0);
});

await test("end: sent once at the last bell (replaces that bell's update), never again", async () => {
  const { env, iso } = await dayWith([REG, LATE]);
  setClock(2026, 10, 19, 15, 23); await runCron(env);
  setClock(2026, 10, 19, 15, 25);
  const b = broadcastCalls((await runCron(env)).fetches);
  assert.equal(b.length, 2);
  for (const c of b) {
    assert.equal(c.body.aps.event, "end");
    assert.equal(c.body.aps["content-state"].isEnded, true);
    assert.equal(c.body.aps["content-state"].slotStartMinutes, 925);
    assert.equal(c.body.aps["dismissal-date"], Math.floor(Date.now() / 1000) - 60);
  }
  for (const [h, m] of [[15, 26], [15, 27], [16, 0], [16, 59]]) {
    setClock(2026, 10, 19, h, m); assert.equal(broadcastCalls((await runCron(env)).fetches).length, 0, `${h}:${m}`);
  }
  const rec = JSON.parse(env.TOKENS.data.get(`broadcast:${iso}`).value);
  assert.ok(rec.sent.includes("end") && rec.sent.includes(925));
});

await test("end catches up when the Worker first runs after the last bell", async () => {
  const { env } = await dayWith([REG]);
  setClock(2026, 10, 19, 16, 1);
  const b = broadcastCalls((await runCron(env)).fetches);
  assert.equal(b.length, 2); assert.equal(b[0].body.aps.event, "end");
});

await test("a schedule running past 5 PM: no early end; earlier bells still sent", async () => {
  const { env, iso } = await dayWith([REG, [600, 1050]]);
  setClock(2026, 10, 19, 15, 23); await runCron(env);
  let n = 0;
  for (let m = 25; m < 60; m++) { setClock(2026, 10, 19, 15, m); n += broadcastCalls((await runCron(env)).fetches).filter(c => c.body.aps.event === "end").length; }
  for (let m = 0; m < 60; m++) { setClock(2026, 10, 19, 16, m); n += broadcastCalls((await runCron(env)).fetches).filter(c => c.body.aps.event === "end").length; }
  assert.equal(n, 0);
  const rec = JSON.parse(env.TOKENS.data.get(`broadcast:${iso}`).value);
  assert.ok(rec.sent.includes(925));
  setClock(2026, 10, 19, 16, 30);
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /broadcast: ok, last 15:25\n/);
});

await test("after the day's end, the cron stops listing schedules", async () => {
  const { env } = await dayWith([REG]);
  setClock(2026, 10, 19, 15, 23); await runCron(env);
  setClock(2026, 10, 19, 15, 25); await runCron(env);             // end goes out
  env.TOKENS.resetOps();
  for (let t = 15 * 60 + 26; t < 17 * 60; t++) { setClock(2026, 10, 19, Math.floor(t / 60), t % 60); await runCron(env); }
  assert.equal(env.TOKENS.ops.list, 0);
  assert.equal(env.TOKENS.ops.put, 0);
});

await test("production failure → retried next minute; end gives up after 3 tries", async () => {
  const { env, iso } = await dayWith([REG]);
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  responder = c => c.url.includes("api.push.apple.com") ? { status: 500, body: '{"reason":"InternalServerError"}' } : { status: 200, body: "" };
  setClock(2026, 10, 19, 8, 0); assert.equal(broadcastCalls((await runCron(env)).fetches).length, 2);
  let rec = JSON.parse(env.TOKENS.data.get(`broadcast:${iso}`).value);
  assert.ok(!rec.sent.includes(480)); assert.equal(rec.last.production.status, 500); assert.equal(rec.last.production.reason, "InternalServerError");
  responder = () => ({ status: 200, body: "" });
  setClock(2026, 10, 19, 8, 1); assert.equal(broadcastCalls((await runCron(env)).fetches).length, 2);
  rec = JSON.parse(env.TOKENS.data.get(`broadcast:${iso}`).value);
  assert.ok(rec.sent.includes(480));
  // end failing forever
  responder = () => ({ status: 403, body: '{"reason":"InvalidProviderToken"}' });
  let n = 0;
  for (let m = 25; m < 40; m++) { setClock(2026, 10, 19, 15, m); n += broadcastCalls((await runCron(env)).fetches).length; }
  assert.equal(n, 6, "3 end attempts × 2 channels");
});

await test("missing APNs config: recorded as failure", async () => {
  const { env, iso } = await dayWith([REG]);
  delete env.APNS_KEY_ID;
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  setClock(2026, 10, 19, 8, 0); const r = await runCron(env);
  assert.equal(r.fetches.length, 0);
  const rec = JSON.parse(env.TOKENS.data.get(`broadcast:${iso}`).value);
  assert.match(rec.last.production.reason, /APNs config missing: APNS_KEY_ID/);
});

await test("weekend and outside 6 AM–5 PM: nothing", async () => {
  const { env } = await dayWith([REG], [2026, 10, 24]);   // Saturday
  setClock(2026, 10, 24, 8, 0); const a = await runCron(env);
  assert.equal(a.subrequests, 0);
  const { env: env2 } = await dayWith([[400, 1100]]);
  setClock(2026, 10, 19, 5, 59); assert.equal((await runCron(env2)).subrequests, 0);
  setClock(2026, 10, 19, 17, 0); assert.equal((await runCron(env2)).subrequests, 0);
});

await test("DST: PST day (Nov 2) — bell at 8:00 PST is minute 480", async () => {
  const { env } = await dayWith([REG], [2026, 11, 2]);
  setClock(2026, 11, 2, 7, 59); await runCron(env);
  assert.equal(new RealDate(fakeNow).getUTCHours(), 15, "7:59 PST = 15:59 UTC");
  setClock(2026, 11, 2, 8, 0);
  const b = broadcastCalls((await runCron(env)).fetches);
  assert.equal(b.length, 2); assert.equal(b[0].body.aps["content-state"].slotStartMinutes, 480);
});

await test("DST: PDT day (Oct 19) — 15:00 UTC is 8:00 PDT (slot 480); 08:00 UTC is 1 AM, nothing", async () => {
  const { env } = await dayWith([REG]);
  fakeNow = RealDate.UTC(2026, 9, 19, 14, 59); await runCron(env);
  fakeNow = RealDate.UTC(2026, 9, 19, 15, 0);
  const b = broadcastCalls((await runCron(env)).fetches);
  assert.equal(b.length, 2); assert.equal(b[0].body.aps["content-state"].slotStartMinutes, 480);
  fakeNow = RealDate.UTC(2026, 9, 20, 8, 0);
  assert.equal((await runCron(env)).subrequests, 0);
});

console.log("diagnostics");
await test("/status.json broadcast section", async () => {
  const { env } = await dayWith([REG, LATE]);
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  setClock(2026, 10, 19, 8, 0, 9); await runCron(env);
  setClock(2026, 10, 19, 8, 1);
  env.TOKENS.resetOps();
  const st = await req(env, "GET", "/status.json");
  assert.equal(st.status, 200);
  assert.equal(env.TOKENS.ops.list, 2, "one list for schedules, one for issues");
  assert.equal(st.data.today, "2026-10-19"); assert.equal(st.data.day, "2026-10-19");
  assert.deepEqual(st.data.days, ["2026-10-19"]);
  assert.match(st.data.health, /^broadcast: /);
  assert.equal(st.data.legacy, undefined, "the per-phone system is gone");
  const b = st.data.broadcast;
  assert.equal(b.schedulesReported, 2);
  assert.deepEqual(b.bells[0], { minute: 480, time: "08:00", status: "sent" });
  assert.equal(b.bells[1].status, "upcoming");
  assert.equal(b.schedules.length, 2);
  assert.equal(b.sends.length, 1);
  assert.equal(b.sends[0].production.text, "200 accepted"); assert.equal(b.sends[0].production.status, 200);
  assert.equal(b.sends[0].delaySeconds, 9);
  assert.equal(b.lastResult.sandbox.text, "200 accepted"); assert.equal(b.lastResult.production.time, "08:00");
  assert.match(b.note, /Push Notifications Console/);
  assert.match(b.note, /Overview → subscriptions/);
  assert.equal((await req(env, "GET", "/status.json", { auth: null })).status, 401);
  assert.equal((await req(env, "GET", "/status.json?day=yesterday")).status, 400);
  globalThis.__status = b;
});

await test("/status.json bell statuses: missed vs reported-late vs outside; past days", async () => {
  const { env, iso } = await dayWith([[480, 535, 1050]]);       // 17:30 is after the cron's window
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  responder = c => c.url.includes("api.push.apple.com") ? { status: 500, body: '{"reason":"InternalServerError"}' } : { status: 200, body: "" };
  for (const m of [0, 1, 2]) { setClock(2026, 10, 19, 8, m); await runCron(env); }
  responder = () => ({ status: 200, body: "" });
  setClock(2026, 10, 19, 8, 55); await runCron(env);
  // a second schedule shows up at 9:00, with an 8:30 bell nobody could have sent
  setClock(2026, 10, 19, 9, 0);
  await req(env, "POST", "/bells", { body: { day: iso, minutes: [510, 600] } });
  setClock(2026, 10, 19, 9, 1); await runCron(env);
  setClock(2026, 10, 19, 9, 10);
  const st = await req(env, "GET", "/status.json");
  const by = Object.fromEntries(st.data.broadcast.bells.map(x => [x.time, x.status]));
  assert.deepEqual(by, { "08:00": "missed", "08:30": "late", "08:55": "sent", "10:00": "upcoming", "17:30": "outside" });
  assert.equal(st.data.broadcast.sends.filter(s => s.production.status === 500).length, 3);
  // next day: yesterday is offered, and viewed as a finished day
  setClock(2026, 10, 20, 7, 0);
  const next = await req(env, "GET", "/status.json");
  assert.deepEqual(next.data.days, ["2026-10-20", "2026-10-19"]);
  assert.deepEqual(next.data.broadcast.bells, []);
  const past = await req(env, "GET", "/status.json?day=2026-10-19");
  assert.equal(past.data.broadcast.bells.find(x => x.time === "10:00").status, "missed");
});

await test("/status is a self-contained HTML dashboard; phone text can't break out of the data block", async () => {
  const { env } = await dayWith([REG]);
  await req(env, "POST", "/report", { body: { deviceId: "d1", kind: "web_load", subject: "</script><img src=x onerror=alert(1)>", detail: "<b>hi</b> " } });
  setClock(2026, 10, 19, 8, 30);
  const r = await worker.fetch(new Request("https://w.example/status", { headers: { authorization: `Bearer ${SECRET}` } }), env);
  assert.equal(r.status, 200);
  assert.match(r.headers.get("content-type"), /text\/html/);
  assert.equal(r.headers.get("cache-control"), "no-store");
  const html = await r.text();
  assert.match(html, /<title>LHS Life APNS Support<\/title>/);
  assert.ok(!html.includes("__STATUS_DATA__"));
  assert.ok(!html.includes("</script><img"), "no tag can close the data block");
  const data = JSON.parse(html.match(/<script id="data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
  assert.equal(data.issues.groups[0].subject, "</script><img src=x onerror=alert(1)>", "survives intact as data");
  assert.equal(data.issues.groups[0].reports.length, 1);
  // Self-contained: no outside scripts, styles, fonts or images.
  assert.ok(!/<script[^>]+src=/i.test(html), "no external script");
  assert.ok(!/<link[^>]+href="https?:/i.test(html), "no external stylesheet or font");
  const hosts = [...new Set([...html.matchAll(/https?:\/\/([a-z0-9.-]+)/gi)].map(m => m[1]))].sort();
  // www.w3.org is the SVG namespace in the favicon: an identifier, never fetched.
  assert.deepEqual(hosts, ["icloud.developer.apple.com", "www.w3.org"], "only a link to Apple's console");
  assert.ok(!/legacyCard|Older versions/.test(html), "no per-phone section");
  assert.equal((await req(env, "GET", "/status", { auth: null })).status, 401);
  const basic = await worker.fetch(new Request("https://w.example/status", { headers: { authorization: "Basic " + btoa("x:" + SECRET) } }), env);
  assert.equal(basic.status, 200);
});

await test("/status.json issues: the whole week with every report", async () => {
  setClock(2026, 10, 19, 9, 0);
  const env = makeEnv();
  await req(env, "POST", "/report", { body: { deviceId: "a", kind: "calendar_fetch", subject: "calendarwiz", detail: "timeout" } });
  await req(env, "POST", "/report", { body: { deviceId: "b", kind: "calendar_fetch", subject: "calendarwiz", detail: "timeout" } });
  setClock(2026, 10, 16, 9, 0);
  await req(env, "POST", "/report", { body: { deviceId: "a", kind: "web_load", subject: "schoology" } });
  setClock(2026, 10, 19, 9, 5);
  const iss = (await req(env, "GET", "/status.json")).data.issues;
  assert.equal(iss.today, "2026-10-19");
  assert.equal(iss.devicesReportingToday, 2); assert.equal(iss.groupsToday, 1);
  assert.equal(iss.groups.length, 2); assert.equal(iss.groups[0].day, "2026-10-19");
  assert.equal(iss.groups[0].reports.length, 2); assert.equal(iss.groups[1].reports[0].deviceId, "a");
});

await test("dashboard sign-in: page, cookie for a year, GET only, tamper/expiry/password change, logout", async () => {
  setClock(2026, 10, 20, 7, 0);
  const env = makeEnv();
  const go = (path, init = {}) => worker.fetch(new Request("https://w.example" + path, init), env);
  const html = { accept: "text/html,application/xhtml+xml" };

  let r = await go("/status", { headers: html });
  assert.equal(r.status, 401); assert.equal(r.headers.get("www-authenticate"), null);
  const page = await r.text();
  assert.match(page, /<form method="post" action="\/login">/);
  assert.match(page, /name="next" value="\/status"/);
  r = await go("/status.json");
  assert.equal(r.status, 401); assert.match(r.headers.get("www-authenticate"), /^Basic /);

  const form = (pw, next) => { const f = new FormData(); f.set("password", pw); if (next) f.set("next", next); return f; };
  r = await go("/login", { method: "POST", body: form("nope", "/status") });
  assert.equal(r.status, 401); assert.match(await r.text(), /isn&#39;t right/);
  assert.equal(r.headers.get("set-cookie"), null);

  r = await go("/login", { method: "POST", body: form(SECRET, "/status?day=2026-10-19") });
  assert.equal(r.status, 303); assert.equal(r.headers.get("location"), "/status?day=2026-10-19");
  const setCookie = r.headers.get("set-cookie");
  assert.match(setCookie, /^__Host-lhs_session=\d+\.[0-9a-f]{64}; Path=\/; Max-Age=31536000; HttpOnly; Secure; SameSite=Strict$/);
  const cookie = setCookie.split(";")[0];

  assert.equal((await go("/status", { headers: { ...html, cookie } })).status, 200);
  assert.equal((await go("/status.json", { headers: { cookie } })).status, 200);
  // …but never what the app does.
  assert.equal((await go("/bells", { method: "POST", headers: { cookie }, body: JSON.stringify({ day: "2026-10-20", minutes: [480] }) })).status, 401);
  assert.equal((await go("/report", { method: "POST", headers: { cookie }, body: "{}" })).status, 401);

  const [name, value] = cookie.split("=");
  const [exp, sig] = value.split(".");
  assert.equal((await go("/status.json", { headers: { cookie: `${name}=${Number(exp) + 1}.${sig}` } })).status, 401);
  assert.equal((await go("/status.json", { headers: { cookie: `${name}=${exp}.${sig.replace(/^./, c => c === "a" ? "b" : "a")}` } })).status, 401);
  fakeNow += 366 * 86400 * 1000;
  assert.equal((await go("/status.json", { headers: { cookie } })).status, 401, "expired after a year");
  fakeNow -= 366 * 86400 * 1000;
  env.CLIENT_SECRET = "rotated";      // no DASHBOARD_PASSWORD here, so this IS the dashboard password
  assert.equal((await go("/status.json", { headers: { cookie } })).status, 401, "new password signs everyone out");
  env.CLIENT_SECRET = SECRET;
  assert.equal((await go("/status.json", { headers: { cookie } })).status, 200);

  for (const next of ["//evil.example/x", "https://evil.example", "/login", "\\\\evil", "/status\r\nx: y"]) {
    r = await go("/login", { method: "POST", body: form(SECRET, next) });
    assert.equal(r.headers.get("location"), "/status", next);
  }
  r = await go("/login?next=/status"); assert.equal(r.status, 200);
  r = await go("/logout");
  assert.equal(r.status, 303); assert.match(r.headers.get("set-cookie"), /^__Host-lhs_session=; .*Max-Age=0/);

  // From a link in another app the dashboard bounces once; a route that DOES
  // something never accepts the cookie from another site.
  r = await go("/status", { headers: { ...html, "sec-fetch-site": "cross-site" } });
  assert.match(await r.text(), /location\.replace\(location\.href\)/);
  r = await go("/test-broadcast?env=production&end=1&confirm=yes", { headers: { ...html, "sec-fetch-site": "cross-site", cookie } });
  assert.equal(r.status, 401); assert.match(await r.text(), /<form method="post"/);
  assert.equal(calls.length, 0, "nothing was sent to Apple");
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-20", minutes: [480, 535] } })).status, 200);
});

await test("DASHBOARD_PASSWORD: app and dashboard keys never open each other's doors", async () => {
  setClock(2026, 10, 20, 7, 0);
  const DASH = "dash-pw";
  const env = makeEnv({ DASHBOARD_PASSWORD: DASH });
  const go = (path, init = {}) => worker.fetch(new Request("https://w.example" + path, init), env);
  const basic = pw => ({ authorization: "Basic " + btoa("x:" + pw) });

  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-20", minutes: [480, 535] } })).status, 200);
  assert.equal((await req(env, "POST", "/report", { body: { deviceId: "d", kind: "web_load", subject: "x" } })).status, 200);
  for (const path of ["/status", "/status.json", "/test-broadcast"]) {
    assert.equal((await req(env, "GET", path)).status, 401, `app secret must not open ${path}`);
  }
  assert.equal((await req(env, "GET", "/status.json", { auth: DASH })).status, 200);
  assert.equal((await go("/status.json", { headers: basic(DASH) })).status, 200);
  assert.equal((await go("/status.json", { headers: { "x-lhs-auth": DASH } })).status, 200);
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-20", minutes: [480] }, auth: DASH })).status, 401);
  assert.equal((await req(env, "POST", "/report", { body: { deviceId: "d", kind: "x" }, auth: DASH })).status, 401);

  const form = pw => { const f = new FormData(); f.set("password", pw); f.set("next", "/status"); return f; };
  assert.equal((await go("/login", { method: "POST", body: form(SECRET) })).status, 401);
  const r = await go("/login", { method: "POST", body: form(DASH) });
  assert.equal(r.status, 303);
  const cookie = r.headers.get("set-cookie").split(";")[0];
  const st = await go("/status.json", { headers: { cookie } });
  assert.equal(st.status, 200); assert.equal((await st.json()).separatePassword, true);
  env.CLIENT_SECRET = "new-app-secret";
  assert.equal((await go("/status.json", { headers: { cookie } })).status, 200, "app secret change leaves browsers signed in");
  env.DASHBOARD_PASSWORD = "new-dash";
  assert.equal((await go("/status.json", { headers: { cookie } })).status, 401, "dashboard password change signs them out");
});

await test("without DASHBOARD_PASSWORD the app secret stands in, and the dashboard says so", async () => {
  setClock(2026, 10, 20, 7, 0);
  const env = makeEnv();
  const st = await req(env, "GET", "/status.json");
  assert.equal(st.status, 200); assert.equal(st.data.separatePassword, false);
  const html = await (await worker.fetch(new Request("https://w.example/status", { headers: { authorization: `Bearer ${SECRET}` } }), env)).text();
  assert.match(html, /function passwordNotice\(\)/);
  delete env.CLIENT_SECRET;
  assert.equal((await req(env, "GET", "/status.json")).status, 503);
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-20", minutes: [480] } })).status, 503);
});

await test("the per-phone system is gone: /register and /unregister answer 410, nothing is stored", async () => {
  setClock(2026, 10, 27, 7, 30);
  const env = makeEnv();
  const reg = await req(env, "POST", "/register", { body: { deviceId: "old-phone", pushToken: "tok", transitions: [480], endMinutes: 900, appVersion: "1.2.0 (2)" } });
  assert.equal(reg.status, 410); assert.equal(reg.data.status, "gone"); assert.match(reg.data.message, /Update the app/);
  assert.equal((await req(env, "DELETE", "/unregister", { body: { deviceId: "old-phone" } })).status, 410);
  assert.equal((await req(env, "POST", "/register", { body: {}, auth: null })).status, 401, "still behind the app secret");
  assert.equal(env.TOKENS.ops.put, 0);
  // The old diagnostics are gone too: they fall through to the plain name.
  for (const path of ["/purge?confirm=yes", "/rebuild", "/test-push"]) {
    const r = await req(env, "GET", path);
    assert.equal(r.text, "LHS Life APNS Support", path);
  }
  assert.equal(env.TOKENS.ops.put + env.TOKENS.ops.delete, 0);
});

await test("partial reports are the same schedule: no write, merged, not counted toward the cap", async () => {
  setClock(2026, 10, 22, 9, 0);
  const env = makeEnv();
  const THU = [550, 640, 645, 675, 705, 710, 800, 805, 900];      // 9:10 … 3:00
  for (const from of [0, 2, 3, 5, 7]) {
    assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-22", minutes: THU.slice(from) } })).status, 200);
  }
  assert.equal(env.TOKENS.ops.put, 1, "only the first report is written; the rest are part of it");
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-22", minutes: THU } })).status, 200);
  const st = await req(env, "GET", "/status.json?day=2026-10-22");
  assert.equal(st.data.broadcast.schedulesReported, 1);
  assert.deepEqual(st.data.broadcast.schedules[0].bells, THU);
  assert.deepEqual(st.data.broadcast.bells.map(b => b.minute), THU, "union unchanged");
  env.TOKENS.resetOps();
  await req(env, "POST", "/bells", { body: { day: "2026-10-22", minutes: THU.filter(m => m !== 705 && m !== 710) } });
  assert.equal(env.TOKENS.ops.put, 0, "a period turned off is a subset too");
  await req(env, "POST", "/bells", { body: { day: "2026-10-22", minutes: [480, 900] } });
  assert.equal((await req(env, "GET", "/status.json?day=2026-10-22")).data.broadcast.schedulesReported, 2);
});

await test("the cap counts distinct schedules, not partial copies", async () => {
  setClock(2026, 10, 22, 7, 0);
  const env = makeEnv();
  for (let i = 0; i < 29; i++) await req(env, "POST", "/bells", { body: { day: "2026-10-22", minutes: [480 + i, 1000] } });
  const raw = async m => env.TOKENS.put(`bells:2026-10-22:raw${m.length}`, JSON.stringify(m), { metadata: { m } });
  await raw([700, 1000]);
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-22", minutes: [650, 700, 1000] } })).status, 200, "absorbs its partial copy");
  assert.equal((await req(env, "POST", "/bells", { body: { day: "2026-10-22", minutes: [400, 1000] } })).status, 429, "a 31st distinct schedule is refused");
});

await test("/health when every bell was reported late: never 'waiting' after the first bell", async () => {
  setClock(2026, 10, 19, 6, 30);
  const env = makeEnv();
  setClock(2026, 10, 19, 8, 48);
  await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: [480, 535, 540] } });
  setClock(2026, 10, 19, 8, 49); await runCron(env);
  setClock(2026, 10, 19, 8, 52);
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /broadcast: ok, nothing to judge yet/);
  for (const m of [55, 56, 57, 58, 59]) { setClock(2026, 10, 19, 8, m); await runCron(env); }
  setClock(2026, 10, 19, 9, 0); await runCron(env);
  setClock(2026, 10, 19, 16, 0);
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /broadcast: ok, last 09:00 \(day ended\)/);
  const rec = JSON.parse(env.TOKENS.data.get("broadcast:2026-10-19").value);
  delete rec.seen; await env.TOKENS.put("broadcast:2026-10-19", JSON.stringify(rec));
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /\(day ended\)/);
});

await test("/health: idle, waiting, ok, FAILED, weekend; open and non-sensitive", async () => {
  setClock(2026, 10, 19, 9, 0);
  let env = makeEnv();
  let h = await req(env, "GET", "/health", { auth: null });
  assert.equal(h.status, 200); assert.match(h.text, /^OK\nauth: configured\nbroadcast: idle \(no bells reported today\)\n$/);
  ({ env } = await dayWith([REG]));
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /broadcast: ok, waiting for first bell 08:00/);
  setClock(2026, 10, 19, 8, 0); await runCron(env);
  setClock(2026, 10, 19, 8, 30);
  h = await req(env, "GET", "/health", { auth: null });
  assert.match(h.text, /broadcast: ok, last 08:00\n/);
  globalThis.__healthOk = h.text;
  // 8:55 fails on production
  responder = c => c.url.includes("api.push.apple.com") ? { status: 403, body: '{"reason":"InvalidProviderToken"}' } : { status: 200, body: "" };
  for (const m of [55, 56, 57]) { setClock(2026, 10, 19, 8, m); await runCron(env); }
  setClock(2026, 10, 19, 8, 56);
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /broadcast: ok, last 08:00/, "within grace");
  setClock(2026, 10, 19, 8, 58);
  h = await req(env, "GET", "/health", { auth: null });
  assert.match(h.text, /broadcast: FAILED, 08:55 not delivered \(production: 403 InvalidProviderToken\)/);
  globalThis.__healthFail = h.text;
  assert.ok(!h.text.includes("JJ+34") && !h.text.includes(SECRET));
  // sandbox-only failure stays ok but says so
  responder = c => c.url.includes("sandbox") ? { status: 400, body: '{"reason":"BadChannelId"}' } : { status: 200, body: "" };
  setClock(2026, 10, 19, 9, 0); await runCron(env);
  setClock(2026, 10, 19, 9, 10);
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /broadcast: ok, last 09:00 \(sandbox: 400 BadChannelId\)/);
  setClock(2026, 10, 24, 10, 0);
  assert.match((await req(env, "GET", "/health", { auth: null })).text, /broadcast: idle \(weekend\)/);
  const noSecret = makeEnv({ CLIENT_SECRET: undefined });
  assert.match((await req(noSecret, "GET", "/health", { auth: null })).text, /auth: NOT CONFIGURED/);
});

await test("/test-broadcast: auth, default sandbox, both, end guard, explanations, no KV writes", async () => {
  const { env } = await dayWith([REG]);
  setClock(2026, 10, 19, 7, 59); await runCron(env);
  setClock(2026, 10, 19, 9, 10);
  env.TOKENS.resetOps();
  assert.equal((await req(env, "GET", "/test-broadcast", { auth: null })).status, 401);
  calls = [];
  let r = await req(env, "GET", "/test-broadcast");
  assert.equal(r.status, 200); assert.equal(calls.length, 1);
  assert.equal(new URL(calls[0].url).host, "api.sandbox.push.apple.com");
  assert.equal(r.data.slotStartMinutes, 540, "defaults to most recent bell (9:00)");
  assert.equal(r.data.attempts[0].ok, true);
  calls = [];
  r = await req(env, "GET", "/test-broadcast?env=both&minutes=600");
  assert.equal(calls.length, 2); assert.equal(r.data.bell, "10:00");
  assert.equal((await req(env, "GET", "/test-broadcast?env=production&end=1")).status, 400);
  assert.equal((await req(env, "GET", "/test-broadcast?env=nope")).status, 400);
  assert.equal((await req(env, "GET", "/test-broadcast?minutes=abc")).status, 400);
  calls = [];
  r = await req(env, "GET", "/test-broadcast?env=sandbox&end=1");
  assert.equal(r.status, 200); assert.equal(calls[0].body.aps.event, "end");
  responder = () => ({ status: 400, body: '{"reason":"BadChannelId"}' });
  r = await req(env, "GET", "/test-broadcast?env=production");
  assert.equal(r.data.attempts[0].ok, false); assert.match(r.data.attempts[0].meaning, /does not know this channel/);
  assert.match(r.data.verdict, /refused/);
  responder = () => ({ status: 403, body: '{"reason":"InvalidProviderToken"}' });
  r = await req(env, "GET", "/test-broadcast");
  assert.match(r.data.attempts[0].meaning, /APNS_KEY_ID does not match/);
  assert.equal(env.TOKENS.ops.put, 0, "test-broadcast writes nothing");
  setClock(2027, 6, 7, 11, 0);   // past any cached signing token (earlier tests moved the clock around)
  const broken = makeEnv({ APNS_PRIVATE_KEY: "garbage" });
  r = await req(broken, "GET", "/test-broadcast");
  assert.equal(r.status, 500); assert.equal(r.data.step, "building the APNs token");
  globalThis.__testOk = (await (async () => { responder = () => ({ status: 200, body: "" }); return (await req(env, "GET", "/test-broadcast")).data; })());
});

// ── a whole day's quota ──────────────────────────────────────────────────────
console.log("quota");
await test("full school day: 400 phones, 3 schedules — KV totals", async () => {
  setClock(2026, 10, 19, 6, 0);
  const env = makeEnv();
  const ASSEMBLY = [480, 530, 535, 585, 590, 640, 645, 700, 735, 785, 790, 840, 845, 925];
  const kinds = [REG, LATE, ASSEMBLY];
  env.TOKENS.resetOps();
  // Each phone posts at card start (morning) and again on a relaunch.
  for (let i = 0; i < 400; i++) {
    for (let k = 0; k < 2; k++) await req(env, "POST", "/bells", { body: { day: "2026-10-19", minutes: kinds[i % 3], environment: "production" } });
  }
  const bellOps = { ...env.TOKENS.ops };
  const bellPuts = [...env.TOKENS.putKeys];
  env.TOKENS.resetOps();
  let pushes = 0;
  for (let t = 6 * 60; t < 17 * 60; t++) {
    setClock(2026, 10, 19, Math.floor(t / 60), t % 60);
    pushes += broadcastCalls((await runCron(env)).fetches).length;
  }
  globalThis.__day = { bellOps, bellPuts: bellPuts.length, cronOps: { ...env.TOKENS.ops }, cronPuts: env.TOKENS.putKeys, pushes };
  assert.equal(bellOps.put, 3);
  const union = new Set([...REG, ...LATE, ...ASSEMBLY]).size;
  // updates for every bell except the last (that's "end"): 2 channels each
  assert.equal(pushes, union * 2);
  // Odd minutes from 6:01 to the last bell (15:25), then none: 283 of 1,000.
  // Under half, so Cloudflare's 50% warning stays quiet.
  assert.equal(env.TOKENS.ops.list, (925 - 361) / 2 + 1);
  assert.ok(env.TOKENS.ops.list < 500);
  assert.deepEqual([...new Set(env.TOKENS.putKeys)], ["broadcast:2026-10-19"]);
  assert.equal(env.TOKENS.ops.put, 1 + union, "one write for the union + one per bell (last bell = end)");
});

console.log(`\n${passed} passed, ${failed} failed`);
if (globalThis.__day) {
  const d = globalThis.__day;
  console.log("\nfull day:", JSON.stringify({ bellsRoute: d.bellOps, cron: d.cronOps, broadcastPushes: d.pushes }));
  const counts = {}; for (const k of d.cronPuts) counts[k] = (counts[k] ?? 0) + 1;
  console.log("cron writes by key:", counts);
}
if (globalThis.__healthOk) console.log("\n/health ok:\n" + globalThis.__healthOk + "/health failed:\n" + globalThis.__healthFail);
if (globalThis.__status) console.log("/status broadcast:", JSON.stringify(globalThis.__status, null, 2));
if (globalThis.__testOk) console.log("/test-broadcast:", JSON.stringify(globalThis.__testOk, null, 2));
process.exit(failed ? 1 : 0);
