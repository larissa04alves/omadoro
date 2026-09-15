.pragma library

// The pomodoro reducer: transliteration of src/state.rs + phase.rs + config.rs
// + render.rs from the Rust CLI this plugin replaces. Zero Qt, zero
// Quickshell — the whole file runs under node (test/model.test.js). The
// Service.qml owns the clock, the files, the windows and every side effect;
// this file only decides what should happen.

// Phase = "work" | "short_break" | "long_break"
//   The three strings are the Rust disk format (Phase::key), kept on purpose:
//   an old state.json is readable without migration code.

// Clock =
//   | { state: "running", endsAt: number }      // epoch-ms instant the phase ends
//   | { state: "paused",  remainingMs: number }  // what is left, frozen
//
//   Exactly one field is meaningful at a time, and the tag says which. There
//   is no `end = 0` sentinel, no "stale remaining". `running` is derived
//   (`clock.state === "running"`), never stored.

// Timer = {
//   version: 1,
//   phase: Phase,
//   clock: Clock,
//   completedWork: number,   // focuses COMPLETED (skipped ones don't count)
//   seenAt: number           // last instant observed; only feeds the gap check
// }

// Config = {
//   work, short, long: number   (minutes, 1..1440)
//   longEvery: number           (>= 1)
//   autoStartNext: boolean
//   sound: string                // path; "" = system default sound
// }

// Event =
//   | { kind: "tick" }               // the clock moved
//   | { kind: "toggle" }             // pause/resume
//   | { kind: "start" }              // begin if stopped (idempotent)
//   | { kind: "skip" }               // skip the phase; does NOT count a focus
//   | { kind: "restart" }            // current phase back to full time
//   | { kind: "reset" }              // cycle from zero
//   | { kind: "config", next: Config }

// Effect =
//   | { kind: "persist", reason: "user" | "phase" | "beat" | "repair" }
//   | { kind: "notify",  title, body, glyph, urgency }
//   | { kind: "sound",   file }
//
//   Effects are DATA. The reducer decides what happens; Service.qml is the
//   only thing that runs them. A node test asserts on notifications with no Qt.

// Step = { timer: Timer, effects: Effect[] }
// View = { mmss, progress, phase, phaseLabel, running, tooltip, cycleDone, cycleTotal }

var GAP_MS = 120000
var PERSIST_EVERY_MS = 30000
var MAX_REMAINING_MS = 24 * 3600 * 1000
var EVENTS = ["tick", "toggle", "start", "skip", "restart", "reset", "config"]
var DEFAULT_SOUND = "/usr/share/sounds/freedesktop/stereo/complete.oga"
var GLYPH_WORK = "󰔟"
var GLYPH_BREAK = "󰅶"
var MAX_LABEL = 40

var VALID_PHASES = ["work", "short_break", "long_break"]

// Next phase, by fase, as a table rather than a switch — model-the-domain: the
// long-break cadence lives entirely inside the "work" row.
var TRANSITIONS = {
  work: function(completedWork, longEvery) {
    // The `completedWork > 0` guard exists because 0 is a multiple of any n:
    // without it, skipping the very first focus would grant a long break free.
    return (longEvery > 0 && completedWork > 0 && completedWork % longEvery === 0)
      ? "long_break"
      : "short_break"
  },
  short_break: function() { return "work" },
  long_break: function() { return "work" }
}

// ---- Untrusted text (ported from the chime plugin). Only the sound path
// reaches an argv from Model.js; phase labels here are always our own
// constants, not user input.
// Control characters and bidi/zero-width format code points become spaces
// (checked by code point, not a regex literal, so this file never has to
// carry raw control bytes or escape sequences that a formatter could mangle).
function stripControlAndFormatChars(s) {
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    var isControl = c <= 0x1f || (c >= 0x7f && c <= 0x9f)
    var isFormat = (c >= 0x200b && c <= 0x200f) || c === 0x2028 || c === 0x2029 ||
      (c >= 0x202a && c <= 0x202e) || (c >= 0x2066 && c <= 0x2069)
    out += (isControl || isFormat) ? " " : s.charAt(i)
  }
  return out
}

function plainLabel(value, limit) {
  var cap = Number(limit) > 0 ? Number(limit) : MAX_LABEL
  var s = String(value === undefined || value === null ? "" : value)
  if (s.length > cap * 4) s = s.slice(0, cap * 4)
  s = stripControlAndFormatChars(s)
  s = s.replace(/</g, "‹").replace(/>/g, "›")
  s = s.replace(/\s+/g, " ").replace(/^ | $/g, "")
  return s.length > cap ? s.slice(0, cap - 1).replace(/ $/, "") + "…" : s
}

function pad2(value) {
  var n = Math.floor(Math.abs(Number(value) || 0))
  return (n < 10 ? "0" : "") + n
}

function clampInt(value, min, max, fallback) {
  var n = Number(value)
  if (value === undefined || value === null || value === "" || !isFinite(n)) return fallback
  n = Math.round(n)
  return Math.max(min, Math.min(max, n))
}

function toBool(value, fallback) {
  if (value === undefined || value === null) return fallback
  if (typeof value === "boolean") return value
  var s = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (s === "true" || s === "1" || s === "yes" || s === "on") return true
  if (s === "false" || s === "0" || s === "no" || s === "off") return false
  return fallback
}

function pick(raw, camelKey, snakeKey) {
  if (raw[camelKey] !== undefined) return raw[camelKey]
  if (snakeKey && raw[snakeKey] !== undefined) return raw[snakeKey]
  return undefined
}

function finiteNonNegative(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? n : fallback
}

// ---- Boundary: everything from disk or shell.json passes through here and
// comes out as a domain type. After this the rest of the file trusts the types.

function normalizeConfig(raw) {
  var r = raw && typeof raw === "object" ? raw : {}
  return {
    work: clampInt(pick(r, "work"), 1, 1440, 25),
    short: clampInt(pick(r, "short"), 1, 1440, 5),
    long: clampInt(pick(r, "long"), 1, 1440, 15),
    longEvery: clampInt(pick(r, "longEvery", "long_every"), 1, 1000000, 4),
    autoStartNext: toBool(pick(r, "autoStartNext", "auto_start_next"), false),
    sound: typeof r.sound === "string" ? r.sound : ""
  }
}

function normalizePhase(value) {
  return VALID_PHASES.indexOf(value) !== -1 ? value : null
}

function normalizeClock(raw) {
  if (!raw || typeof raw !== "object") return null
  if (raw.state === "running") {
    var endsAt = Number(raw.endsAt)
    if (!isFinite(endsAt)) return null
    return { state: "running", endsAt: endsAt }
  }
  if (raw.state === "paused") {
    var remainingMs = Number(raw.remainingMs)
    if (!isFinite(remainingMs) || remainingMs < 0) return null
    return { state: "paused", remainingMs: Math.min(remainingMs, MAX_REMAINING_MS) }
  }
  return null
}

// Accepts either our own Timer shape, or the Rust state.json this plugin
// inherits from (`{phase, running, end (epoch s), remaining (s),
// completed_work, last_tick}`). Anything that isn't one of those two shapes
// becomes a fresh timer rather than a crash or a half-built object.
function normalizeTimer(raw, config) {
  if (!raw || typeof raw !== "object") return initialTimer(config)
  var phase = normalizePhase(raw.phase)
  if (!phase) return initialTimer(config)

  if (raw.clock && typeof raw.clock === "object") {
    var clock = normalizeClock(raw.clock)
    if (!clock) return initialTimer(config)
    return {
      version: 1,
      phase: phase,
      clock: clock,
      completedWork: Math.max(0, Math.round(Number(raw.completedWork) || 0)),
      seenAt: finiteNonNegative(raw.seenAt, 0)
    }
  }

  if (raw.running !== undefined) {
    var running = !!raw.running
    var completedWork = Math.max(0, Math.round(Number(raw.completed_work) || 0))
    var seenAt = finiteNonNegative(raw.last_tick, 0) * 1000
    var oldClock
    if (running) {
      oldClock = { state: "running", endsAt: finiteNonNegative(raw.end, 0) * 1000 }
    } else {
      var remainingSecs = Number(raw.remaining)
      var remainingMs = isFinite(remainingSecs) && remainingSecs >= 0
        ? remainingSecs * 1000
        : phaseDurationMs(phase, config)
      oldClock = { state: "paused", remainingMs: Math.min(remainingMs, MAX_REMAINING_MS) }
    }
    return { version: 1, phase: phase, clock: oldClock, completedWork: completedWork, seenAt: seenAt }
  }

  return initialTimer(config)
}

function initialTimer(config) {
  return {
    version: 1,
    phase: "work",
    clock: { state: "paused", remainingMs: phaseDurationMs("work", config) },
    completedWork: 0,
    seenAt: 0
  }
}

// ---- Pure, total, no effects

function phaseDurationMs(phase, config) {
  var minutes = phase === "work" ? config.work : phase === "short_break" ? config.short : config.long
  return minutes * 60000
}

function remainingMs(timer, now) {
  if (timer.clock.state === "running") {
    return Math.max(0, timer.clock.endsAt - now)
  }
  return timer.clock.remainingMs
}

function progress(timer, config, now) {
  var total = phaseDurationMs(timer.phase, config)
  if (total === 0) return 0
  return Math.max(0, Math.min(1, remainingMs(timer, now) / total))
}

function nextPhase(phase, completedWork, longEvery) {
  var fn = TRANSITIONS[phase]
  return fn ? fn(completedWork, longEvery) : "work"
}

// Copies a Timer, overriding only what `patch` names — never mutates `timer`,
// and always returns a new object so QML property bindings see a fresh
// reference even when every field's value is unchanged.
function withTimer(timer, patch) {
  var next = {
    version: timer.version,
    phase: timer.phase,
    clock: timer.clock,
    completedWork: timer.completedWork,
    seenAt: timer.seenAt
  }
  for (var k in patch) next[k] = patch[k]
  return next
}

// Advances to the next phase. `startRunning` decides whether it begins
// counting immediately; `countWork` decides whether an ending focus counts
// toward the long-break cadence (true on a natural end, false on skip).
function advance(timer, config, now, startRunning, countWork) {
  var ended = timer.phase
  var completedWork = timer.completedWork
  if (ended === "work" && countWork) completedWork = completedWork + 1
  var started = nextPhase(ended, completedWork, config.longEvery)
  var durationMs = phaseDurationMs(started, config)
  var clock = startRunning
    ? { state: "running", endsAt: now + durationMs }
    : { state: "paused", remainingMs: durationMs }
  var nextTimer = {
    version: 1,
    phase: started,
    clock: clock,
    completedWork: completedWork,
    seenAt: startRunning ? now : 0
  }
  return { timer: nextTimer, transition: { ended: ended, started: started } }
}

function phaseLabel(phase) {
  if (phase === "work") return "Foco"
  if (phase === "short_break") return "Pausa"
  if (phase === "long_break") return "Pausa longa"
  return ""
}

function glyphFor(phase) {
  return phase === "work" ? GLYPH_WORK : GLYPH_BREAK
}

// ---- The reducer. ONE gate for every transition in the system.

function stepTick(timer, config, now) {
  if (timer.clock.state === "paused") {
    // P9: a paused timer ignores the gap. Nothing is running to have missed.
    return { timer: timer, effects: [] }
  }

  var gap = timer.seenAt > 0 && (now - timer.seenAt) > GAP_MS
  var absurd = Math.max(0, timer.clock.endsAt - now) > MAX_REMAINING_MS
  if (gap || absurd) {
    // Suspend/shutdown, or a corrupted state.json: rewind to the full phase,
    // paused. No notify, no sound — the phase didn't end, the machine did.
    var full = phaseDurationMs(timer.phase, config)
    var rewound = withTimer(timer, { clock: { state: "paused", remainingMs: full }, seenAt: 0 })
    return { timer: rewound, effects: [{ kind: "persist", reason: "repair" }] }
  }

  if (now >= timer.clock.endsAt) {
    var result = advance(timer, config, now, config.autoStartNext, true)
    return {
      timer: result.timer,
      effects: [
        // persist FIRST, always: if the shell dies between these, a
        // notification is lost, never duplicated.
        { kind: "persist", reason: "phase" },
        {
          kind: "notify",
          title: phaseLabel(result.transition.ended) + " terminou",
          body: phaseLabel(result.transition.started) + " agora",
          glyph: glyphFor(result.transition.started),
          urgency: "normal"
        },
        { kind: "sound", file: config.sound ? plainLabel(config.sound, 1024) : DEFAULT_SOUND }
      ]
    }
  }

  if (now - timer.seenAt >= PERSIST_EVERY_MS) {
    // Heartbeat: persist the last-seen instant every so often (not every
    // tick), only so the gap check above still works after a restart.
    return { timer: withTimer(timer, { seenAt: now }), effects: [{ kind: "persist", reason: "beat" }] }
  }

  // seenAt is intentionally left as-is here (matching Rust's last_tick):
  // only the heartbeat and phase-advance branches move it forward.
  return { timer: withTimer(timer, {}), effects: [] }
}

function stepToggle(timer, now) {
  if (timer.clock.state === "running") {
    var paused = withTimer(timer, { clock: { state: "paused", remainingMs: remainingMs(timer, now) } })
    return { timer: paused, effects: [{ kind: "persist", reason: "user" }] }
  }
  var running = withTimer(timer, { clock: { state: "running", endsAt: now + timer.clock.remainingMs }, seenAt: now })
  return { timer: running, effects: [{ kind: "persist", reason: "user" }] }
}

function stepStart(timer, now) {
  // Idempotent by construction: clicking the notification action twice, or
  // dispatching "start" on an already-running timer, changes nothing.
  if (timer.clock.state === "running") {
    return { timer: timer, effects: [] }
  }
  var running = withTimer(timer, { clock: { state: "running", endsAt: now + timer.clock.remainingMs }, seenAt: now })
  return { timer: running, effects: [{ kind: "persist", reason: "user" }] }
}

function stepSkip(timer, config, now) {
  // A skipped focus is not a completed one: countWork = false, so nextPhase
  // can never grant a long break for it. No notification either.
  var result = advance(timer, config, now, true, false)
  return { timer: result.timer, effects: [{ kind: "persist", reason: "user" }] }
}

function stepRestart(timer, config, now) {
  var full = phaseDurationMs(timer.phase, config)
  var restarted = timer.clock.state === "running"
    ? withTimer(timer, { clock: { state: "running", endsAt: now + full }, seenAt: now })
    : withTimer(timer, { clock: { state: "paused", remainingMs: full } })
  return { timer: restarted, effects: [{ kind: "persist", reason: "user" }] }
}

function stepReset(config) {
  return { timer: initialTimer(config), effects: [{ kind: "persist", reason: "user" }] }
}

// Resync: only when paused AND still at the full duration of the OLD config
// (`config`, the parameter every step() call receives) — a phase running or
// paused mid-way is left alone; the change lands on the next cycle.
function stepConfig(timer, config, next) {
  if (timer.clock.state === "paused" && timer.clock.remainingMs === phaseDurationMs(timer.phase, config)) {
    var updated = phaseDurationMs(timer.phase, next)
    if (updated !== timer.clock.remainingMs) {
      var resynced = withTimer(timer, { clock: { state: "paused", remainingMs: updated } })
      return { timer: resynced, effects: [{ kind: "persist", reason: "user" }] }
    }
  }
  return { timer: timer, effects: [] }
}

function step(timer, event, config, now) {
  switch (event.kind) {
    case "tick": return stepTick(timer, config, now)
    case "toggle": return stepToggle(timer, now)
    case "start": return stepStart(timer, now)
    case "skip": return stepSkip(timer, config, now)
    case "restart": return stepRestart(timer, config, now)
    case "reset": return stepReset(config)
    case "config": return stepConfig(timer, config, event.next)
    default: return { timer: timer, effects: [] }
  }
}

// ---- Conveniences built on step()

// Restoring is literally a tick with a possibly large gap: the same rule that
// handles suspend handles a shell restart. One code path, both scenarios.
function restore(text, config, now) {
  var raw = null
  var trimmed = text === undefined || text === null ? "" : String(text).replace(/^\s+|\s+$/g, "")
  if (trimmed !== "") {
    try { raw = JSON.parse(trimmed) } catch (e) { raw = null }
  }
  var timer = normalizeTimer(raw, config)
  return step(timer, { kind: "tick" }, config, now)
}

function view(timer, config, now) {
  var running = timer.clock.state === "running"
  var remaining = remainingMs(timer, now)
  var cycleTotal = config.longEvery
  var cycleDone = cycleTotal > 0 ? timer.completedWork % cycleTotal : 0
  var tooltip = phaseLabel(timer.phase) + " — " + (running ? "em andamento" : "pausado") +
    " · " + mmss(remaining) + " restante · " + cycleDone + "/" + cycleTotal + " focos até a pausa longa"
  return {
    mmss: mmss(remaining),
    progress: progress(timer, config, now),
    phase: timer.phase,
    phaseLabel: phaseLabel(timer.phase),
    running: running,
    tooltip: tooltip,
    cycleDone: cycleDone,
    cycleTotal: cycleTotal
  }
}

function serialize(timer) {
  return JSON.stringify(timer, null, 2) + "\n"
}

// "MM:SS" from a duration in milliseconds.
function mmss(ms) {
  var totalSecs = Math.floor(Math.max(0, Number(ms) || 0) / 1000)
  return pad2(Math.floor(totalSecs / 60)) + ":" + pad2(totalSecs % 60)
}

if (typeof module !== "undefined") {
  module.exports = {
    GAP_MS: GAP_MS, PERSIST_EVERY_MS: PERSIST_EVERY_MS, MAX_REMAINING_MS: MAX_REMAINING_MS,
    EVENTS: EVENTS, DEFAULT_SOUND: DEFAULT_SOUND, GLYPH_WORK: GLYPH_WORK, GLYPH_BREAK: GLYPH_BREAK,
    MAX_LABEL: MAX_LABEL, TRANSITIONS: TRANSITIONS,
    plainLabel: plainLabel, pad2: pad2, clampInt: clampInt, toBool: toBool,
    normalizeConfig: normalizeConfig, normalizeTimer: normalizeTimer, initialTimer: initialTimer,
    phaseDurationMs: phaseDurationMs, remainingMs: remainingMs, progress: progress, nextPhase: nextPhase,
    step: step, restore: restore, view: view, serialize: serialize, mmss: mmss, phaseLabel: phaseLabel
  }
}
