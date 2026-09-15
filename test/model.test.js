// Model.js under node: the file has no Qt in it, so it loads into a bare
// context and every top-level function becomes a property of that context.
//
//   node test/model.test.js
//
// The first 28 tests below are the port of `cargo test` from state.rs,
// phase.rs and config.rs — same name as the Rust test, same invariant. A few
// (waybar_json_has_fields, eww_json_has_fields, glyph_extremes, set_*,
// roundtrip_serde) test the same idea through the JS shape: the design
// replaced Config::set/waybar_json/eww_json/glyph_for with
// normalizeConfig/view, so that is what they exercise now. Everything after
// "extra tests, not in cargo" is new: the union shape, effect ordering, and
// the old state.json restore path.

const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma.*$/m, "")
const M = {}
vm.createContext(M)
vm.runInContext(source, M)

// Values built inside the vm context carry that context's Array/Object
// prototype, which deepStrictEqual treats as a different type. Compare plain JSON.
function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
    console.log("ok - " + name)
  } catch (error) {
    console.error("FAIL " + name)
    console.error(error && error.stack ? error.stack : error)
    process.exitCode = 1
  }
}

// The Rust tests count time in whole seconds (State::tick(now: u64, ...)).
// Model.js works in milliseconds, so every ported test multiplies its
// original Rust values by S — GAP_MS/PERSIST_EVERY_MS/MAX_REMAINING_MS are
// themselves exactly 1000x the Rust GAP_SECS/PERSIST_EVERY/MAX_REMAINING, so
// this preserves every pass/fail boundary from the original test unchanged.
const S = 1000

function cfg(overrides) {
  return M.normalizeConfig(overrides || {})
}

function toggleAt(timer, c, now) { return M.step(timer, { kind: "toggle" }, c, now).timer }
function restartAt(timer, c, now) { return M.step(timer, { kind: "restart" }, c, now).timer }
function skipAt(timer, c, now) { return M.step(timer, { kind: "skip" }, c, now).timer }
function resetAt(timer, c) { return M.step(timer, { kind: "reset" }, c, 0).timer }
function tickAt(timer, c, now) { return M.step(timer, { kind: "tick" }, c, now) }

// ---- Ported from cargo test (28), by name -----------------------------

test("remaining_running_vs_paused", () => {
  const c = cfg()
  let s = M.initialTimer(c) // 25min, pausado
  assert.strictEqual(M.remainingMs(s, 1000 * S), 25 * 60 * S)
  s = toggleAt(s, c, 1000 * S) // inicia em now=1000 -> end=1000+1500
  assert.strictEqual(s.clock.endsAt, (1000 + 1500) * S)
  assert.strictEqual(M.remainingMs(s, 1000 * S), 1500 * S)
  assert.strictEqual(M.remainingMs(s, 1100 * S), 1400 * S)
})

test("remaining_clamps_at_zero", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0)
  assert.strictEqual(M.remainingMs(s, 999999 * S), 0)
})

test("toggle_preserves_remaining_when_pausing", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0) // rodando, end=1500
  s = toggleAt(s, c, 100 * S) // pausa em now=100 -> remaining=1400
  assert.strictEqual(s.clock.state, "paused")
  assert.strictEqual(s.clock.remainingMs, 1400 * S)
})

test("restart_resets_current_phase", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0)
  s = restartAt(s, c, 500 * S)
  assert.strictEqual(M.remainingMs(s, 500 * S), 1500 * S)
})

test("tick_transitions_once_at_zero", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0) // foco rodando, end=1500

  let r = tickAt(s, c, 1499 * S)
  assert.strictEqual(r.effects.some(e => e.kind === "notify"), false)
  s = r.timer

  r = tickAt(s, c, 1500 * S)
  assert.strictEqual(r.effects.some(e => e.kind === "notify"), true)
  s = r.timer
  assert.strictEqual(s.phase, "short_break")
  assert.strictEqual(s.completedWork, 1)
  // auto_start_next=false por padrão -> pausado, não re-dispara
  assert.strictEqual(s.clock.state, "paused")

  r = tickAt(s, c, 2000 * S)
  assert.strictEqual(r.effects.length, 0)
  assert.strictEqual(r.timer, s)
})

test("full_cycle_hits_long_break", () => {
  const c = cfg({ autoStartNext: true }) // encadeia as fases sozinho
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0)
  let longSeen = false
  for (let i = 0; i < 12; i++) {
    const now = s.clock.endsAt // salta para o fim da fase corrente…
    s = Object.assign({}, s, { seenAt: now - S }) // …simulando que o heartbeat ticou até lá
    const r = tickAt(s, c, now)
    s = r.timer
    if (r.effects.some(e => e.kind === "notify") && s.phase === "long_break") {
      longSeen = true
      break
    }
  }
  assert.ok(longSeen, `deveria atingir a pausa longa após ${c.longEvery} focos`)
  assert.strictEqual(s.completedWork, 4)
})

test("skip_advances_and_runs", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = skipAt(s, c, 0)
  assert.strictEqual(s.phase, "short_break")
  assert.strictEqual(s.clock.state, "running")
  assert.strictEqual(M.remainingMs(s, 0), 5 * 60 * S)
  // foco pulado não conta para a cadência da pausa longa
  assert.strictEqual(s.completedWork, 0)
})

test("skipped_work_never_earns_long_break", () => {
  const c = cfg() // long_every = 4
  let s = M.initialTimer(c)
  for (let i = 0; i < 10; i++) {
    s = skipAt(s, c, 1000 * S) // pula tudo, nunca completa um foco
    assert.notStrictEqual(s.phase, "long_break")
  }
  assert.strictEqual(s.completedWork, 0)
})

test("gap_resets_phase_paused_without_transition", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 1000 * S) // rodando, end=2500

  let r = tickAt(s, c, 1030 * S)
  assert.ok(r.effects.length > 0) // heartbeat: seenAt=1030
  s = r.timer

  // "religou o PC" 10h depois: fase cheia, pausada, sem notificação
  r = tickAt(s, c, (1030 + 36000) * S)
  assert.strictEqual(r.effects.some(e => e.kind === "notify"), false)
  assert.ok(r.effects.length > 0)
  assert.strictEqual(r.timer.clock.state, "paused")
  assert.strictEqual(r.timer.clock.remainingMs, 25 * 60 * S)
})

test("short_gap_does_not_reset", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 1000 * S)

  let r = tickAt(s, c, 1030 * S)
  assert.ok(r.effects.length > 0) // seenAt=1030
  s = r.timer

  r = tickAt(s, c, 1090 * S) // 60s de buraco: dentro da tolerância
  assert.strictEqual(r.effects.some(e => e.kind === "notify"), false)
  assert.strictEqual(r.timer.clock.state, "running")
})

test("heartbeat_persists_periodically_not_every_tick", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 1000 * S) // seenAt=1000

  let r = tickAt(s, c, 1001 * S); assert.strictEqual(r.effects.length, 0); s = r.timer
  r = tickAt(s, c, 1029 * S); assert.strictEqual(r.effects.length, 0); s = r.timer
  r = tickAt(s, c, 1030 * S); assert.ok(r.effects.length > 0); s = r.timer // 30s desde o último registro
  r = tickAt(s, c, 1031 * S); assert.strictEqual(r.effects.length, 0)
})

test("paused_state_never_dirties_on_tick", () => {
  const c = cfg()
  const s = M.initialTimer(c)
  const r = tickAt(s, c, 999999 * S)
  assert.strictEqual(r.effects.length, 0)
  assert.strictEqual(r.timer, s)
})

test("absurd_end_resets_phase_paused", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 1000 * S)
  // state.json corrompido: fim daqui a 200h
  s = Object.assign({}, s, { clock: { state: "running", endsAt: (1000 + 200 * 3600) * S } })

  const r = tickAt(s, c, 1001 * S)
  assert.strictEqual(r.effects.some(e => e.kind === "notify"), false)
  assert.ok(r.effects.length > 0)
  assert.strictEqual(r.timer.clock.state, "paused")
  assert.strictEqual(r.timer.clock.remainingMs, 25 * 60 * S)
})

test("reset_returns_to_initial", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = skipAt(s, c, 0)
  s = skipAt(s, c, 0)
  s = resetAt(s, c)
  assert.deepStrictEqual(plain(s), plain(M.initialTimer(c)))
})

test("resync_snaps_paused_full_phase", () => {
  const oldCfg = cfg()
  const newCfg = cfg({ work: 40 })
  const s = M.initialTimer(oldCfg) // foco pausado, 25:00
  const r = M.step(s, { kind: "config", next: newCfg }, oldCfg, 0)
  assert.ok(r.effects.length > 0)
  assert.strictEqual(r.timer.clock.remainingMs, 40 * 60 * S)
})

test("resync_skips_running_or_midphase", () => {
  const oldCfg = cfg()
  const newCfg = cfg({ work: 40 })

  let running = M.initialTimer(oldCfg)
  running = toggleAt(running, oldCfg, 0) // rodando -> não mexe
  let r = M.step(running, { kind: "config", next: newCfg }, oldCfg, 0)
  assert.strictEqual(r.effects.length, 0)
  assert.strictEqual(r.timer, running)

  let mid = M.initialTimer(oldCfg)
  mid = Object.assign({}, mid, { clock: { state: "paused", remainingMs: 600 * S } }) // pausado no meio -> não mexe
  r = M.step(mid, { kind: "config", next: newCfg }, oldCfg, 0)
  assert.strictEqual(r.effects.length, 0)
  assert.strictEqual(r.timer.clock.remainingMs, 600 * S)
})

test("work_then_short_break", () => {
  assert.strictEqual(M.nextPhase("work", 1, 4), "short_break")
  assert.strictEqual(M.nextPhase("work", 2, 4), "short_break")
  assert.strictEqual(M.nextPhase("work", 3, 4), "short_break")
})

test("zero_completed_work_never_long_break", () => {
  // Foco pulado sem nenhum concluído: 0 é múltiplo de 4, mas não merece pausa longa.
  assert.strictEqual(M.nextPhase("work", 0, 4), "short_break")
})

test("long_break_every_n", () => {
  assert.strictEqual(M.nextPhase("work", 4, 4), "long_break")
  assert.strictEqual(M.nextPhase("work", 8, 4), "long_break")
})

test("break_returns_to_work", () => {
  assert.strictEqual(M.nextPhase("short_break", 4, 4), "work")
  assert.strictEqual(M.nextPhase("long_break", 4, 4), "work")
})

test("defaults_25_5_15_4", () => {
  const c = M.normalizeConfig({})
  assert.deepStrictEqual([c.work, c.short, c.long, c.longEvery], [25, 5, 15, 4])
  assert.strictEqual(c.autoStartNext, false)
})

// Config::roundtrip_serde tested serde_json round-tripping the Rust struct.
// There is no Config serializer here (config now lives in shell.json, owned
// by the host) — the equivalent invariant is that normalizeConfig is
// idempotent across a JSON round-trip.
test("roundtrip_serde", () => {
  const c = M.normalizeConfig({ work: 30, short: 8, long: 20, longEvery: 3, autoStartNext: true })
  const back = M.normalizeConfig(JSON.parse(JSON.stringify(c)))
  assert.deepStrictEqual(plain(back), plain(c))
})

// Config::set(key, value) -> Result<(), String> became normalizeConfig(raw),
// which has no error channel: every field always produces a valid Config.
test("set_valid_fields", () => {
  const c = M.normalizeConfig({ work: 40, autoStartNext: true })
  assert.strictEqual(c.work, 40)
  assert.strictEqual(c.autoStartNext, true)
})

test("set_rejects_bad_input", () => {
  assert.strictEqual(M.normalizeConfig({ work: 0 }).work, 1, "clamps to the Rust floor instead of erroring")
  assert.strictEqual(M.normalizeConfig({ work: "abc" }).work, 25, "non-numeric falls back to the default")
  assert.strictEqual(M.normalizeConfig({ work: 1441 }).work, 1440, "clamps to the Rust ceiling")
  assert.strictEqual(M.normalizeConfig({ work: 1440 }).work, 1440)
  assert.strictEqual(M.normalizeConfig({ longEvery: 0 }).longEvery, 1)
  assert.deepStrictEqual(
    plain(M.normalizeConfig({ chaveInexistente: 1 })),
    plain(M.normalizeConfig({})),
    "unknown keys are ignored, not errors"
  )
})

// render.rs's RING_GLYPHS existed because the Waybar module only renders
// text; the ring is now QtQuick.Shapes. What survives from "glyph at the
// extremes" is the notification glyph, which is by phase (foco vs pausa).
test("glyph_extremes", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0)

  let r = tickAt(s, c, 1500 * S) // foco termina -> pausa começa
  let notify = r.effects.find(e => e.kind === "notify")
  assert.strictEqual(notify.glyph, M.GLYPH_BREAK)

  s = M.step(r.timer, { kind: "start" }, c, 1500 * S).timer // retoma a pausa manualmente
  // simula um heartbeat recente logo antes do fim, para não cruzar GAP_MS
  s = Object.assign({}, s, { seenAt: (1500 + 5 * 60) * S - S })
  r = tickAt(s, c, (1500 + 5 * 60) * S) // pausa termina -> foco começa
  notify = r.effects.find(e => e.kind === "notify")
  assert.strictEqual(notify.glyph, M.GLYPH_WORK)
})

test("mmss_formats", () => {
  assert.strictEqual(M.mmss(0), "00:00")
  assert.strictEqual(M.mmss(65 * 1000), "01:05")
  assert.strictEqual(M.mmss(25 * 60 * 1000), "25:00")
  assert.strictEqual(M.mmss(59 * 1000), "00:59")
})

// waybar_json/eww_json became view(): the one formatted read the UI ever sees.
test("waybar_json_has_fields", () => {
  const c = cfg()
  const s = M.initialTimer(c)
  const v = M.view(s, c, 0)
  assert.ok(v.mmss.indexOf("25:00") !== -1, v.mmss)
  assert.strictEqual(v.running, false)
  assert.strictEqual(v.progress, 1)
})

test("eww_json_has_fields", () => {
  const c = cfg()
  const s = M.initialTimer(c)
  const v = M.view(s, c, 0)
  assert.strictEqual(v.phase, "work")
  assert.strictEqual(v.phaseLabel, "Foco")
  assert.strictEqual(v.running, false)
})

// ---- Extra tests, not in cargo -----------------------------------------

test("clock é uma união etiquetada: paused nunca tem endsAt, running nunca tem remainingMs", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  assert.strictEqual(s.clock.state, "paused")
  assert.strictEqual("endsAt" in s.clock, false)
  s = toggleAt(s, c, 0)
  assert.strictEqual(s.clock.state, "running")
  assert.strictEqual("remainingMs" in s.clock, false)
})

test("no fim natural da fase, persist chega antes de notify e de sound", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0)
  const r = tickAt(s, c, 1500 * S)
  assert.deepStrictEqual(plain(r.effects.map(e => e.kind)), ["persist", "notify", "sound"])
  assert.strictEqual(r.effects[0].reason, "phase")
})

test("skip não dispara notificação", () => {
  const c = cfg()
  const s = M.initialTimer(c)
  const r = M.step(s, { kind: "skip" }, c, 0)
  assert.deepStrictEqual(plain(r.effects.map(e => e.kind)), ["persist"])
})

test("start é idempotente quando já rodando", () => {
  const c = cfg()
  let s = M.initialTimer(c)
  s = toggleAt(s, c, 0) // rodando
  const r = M.step(s, { kind: "start" }, c, 500 * S)
  assert.strictEqual(r.timer, s)
  assert.strictEqual(r.effects.length, 0)
})

test("restore lê o state.json antigo do Rust (epoch em segundos)", () => {
  const c = cfg()
  const old = JSON.stringify({ phase: "work", running: true, end: 2500, remaining: 0, completed_work: 2, last_tick: 1000 })
  const r = M.restore(old, c, 1001 * S)
  assert.strictEqual(r.timer.phase, "work")
  assert.strictEqual(r.timer.completedWork, 2)
  assert.strictEqual(r.timer.clock.state, "running")
  assert.strictEqual(r.timer.clock.endsAt, 2500 * S)
})

test("restore com buraco maior que 120s rebobina pausado", () => {
  const c = cfg()
  const old = JSON.stringify({ phase: "work", running: true, end: 2500, remaining: 0, completed_work: 0, last_tick: 1000 })
  const r = M.restore(old, c, (1000 + 300) * S) // 300s de buraco > GAP_SECS
  assert.strictEqual(r.timer.clock.state, "paused")
  assert.strictEqual(r.timer.clock.remainingMs, 25 * 60 * S)
  assert.strictEqual(r.effects.some(e => e.kind === "notify"), false)
  assert.strictEqual(r.effects.some(e => e.kind === "persist" && e.reason === "repair"), true)
})

test("normalizeConfig aceita chaves em snake_case", () => {
  const c = M.normalizeConfig({ long_every: 3, auto_start_next: true })
  assert.strictEqual(c.longEvery, 3)
  assert.strictEqual(c.autoStartNext, true)
})

test("normalizeTimer descarta lixo e cai no timer inicial", () => {
  const c = cfg()
  assert.deepStrictEqual(plain(M.normalizeTimer(null, c)), plain(M.initialTimer(c)))
  assert.deepStrictEqual(plain(M.normalizeTimer({ foo: "bar" }, c)), plain(M.initialTimer(c)))
  assert.deepStrictEqual(plain(M.normalizeTimer({ phase: "nonsense" }, c)), plain(M.initialTimer(c)))
})

if (process.exitCode) {
  console.error(`${passed} passed, some failed`)
} else {
  console.log(`ok - ${passed} tests passed`)
}
