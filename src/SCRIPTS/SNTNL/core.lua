-- =====================================================================
-- core.lua  --  Shared core for the ELRS Link Sentinel.
-- =====================================================================
-- SD card path: /SCRIPTS/SNTNL/core.lua
--
-- Single source of truth used by BOTH variants (must be copied along with
-- whichever one is installed):
--   * the function script  /SCRIPTS/FUNCTIONS/sntnl.lua  (audio only)
--   * the widget           /WIDGETS/SNTNL/main.lua       (audio + display)
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License version 2 as
-- published by the Free Software Foundation.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along
-- with this program; if not, write to the Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
-- =====================================================================

local M = {}
-- Single source of the version: the settings tool reads VERSION, API and
-- CONFIG_PATH as text from the head of this file (keep them near the top).
M.VERSION = "3.0.0"
M.API     = { 1, 0 }
M.CONFIG_PATH = "/SCRIPTS/SNTNL/config.lua"
-- API is the interface version for scripts that load this core: { breaking, additive }.
-- Adding an exported function or field bumps the second number; changing or
-- removing one bumps the first and resets the second. Fixes and internal
-- changes leave it alone. A loader accepts the same first and at least its second.

-- ---------------------------------------------------------------------------
-- Tunable parameters, shared by both variants. The widget must read thresholds
-- (e.g. RQLY_THRESHOLD) from here, never hard-code them, or the display drifts
-- from the audio warning.
-- ---------------------------------------------------------------------------
M.PARAMS = {
  WARN_OFFSET_DB     = 10,     -- Offset (dBm) added on top of the sensitivity limit
  RQLY_THRESHOLD     = 42,     -- Lower RQly bound in % for stage 2
  DEBOUNCE_MS        = 2000,   -- Debounce time in ms (activation and deactivation)
  REPEAT_MS          = 5000,   -- Sound repeat interval in ms
  LINK_LOSS_GRACE_MS = 1500,   -- Tolerate a telemetry gap this long before resetting the
                               -- warning state (see evaluate). Also the widget's hold before
                               -- it shows NO LINK, so tone and tile never disagree.
  CFG_ERR_GRACE_MS   = 10000,  -- Grace period before the cfg-error sound is first played
  CFG_ERR_REPEAT_MS  = 30000,  -- Cfg-error sound repeat interval in ms
  AUDIO              = true,   -- Play announcements at all (false = every sound off)
  HAPTIC             = false,  -- Vibrate alongside the warning sound (opt-in)
  HAPTIC_STRENGTH    = 2,      -- Pulse-length tier: 1 = soft, 2 = normal, 3 = strong
}

-- LQ colour level for displays: 0 (green) at/above LQ_OK_PCT, 1 (yellow) down to
-- RQLY_THRESHOLD, 2 (red) below. Only green->yellow is display-only; the red end
-- ties to the stage 2 threshold, so it follows the config.
M.LQ_OK_PCT = 70
-- Preflight check of the link: the warning stage as status text and level.
-- A mode without a known sensitivity limit (sensLimit 0) cannot be judged:
-- MODE UNKNOWN, a warning (never met). sensLimit nil counts as known.
local LINK_STATUS = { [0] = "LINK OK", [1] = "LINK WARNING", [2] = "LINK CRITICAL" }
function M.preflight(stage, sensLimit)
  if sensLimit == 0 then return { text = "MODE UNKNOWN", level = 1 } end
  stage = stage or 0
  return { text = LINK_STATUS[stage] or LINK_STATUS[0], level = stage }
end

function M.lqLevel(rqly)
  if rqly >= M.LQ_OK_PCT then return 0 end
  return (rqly >= M.PARAMS.RQLY_THRESHOLD) and 1 or 2
end

-- playHaptic pulse length per strength tier, and pulses per warning: Stage 2
-- (critical) fires twice to feel clearly stronger than Stage 1.
M.HAPTIC_DUR    = { [1] = 15, [2] = 30, [3] = 50 }
M.HAPTIC_PULSES = { stage1 = 1, stage2 = 2 }

-- Warning sounds. The config stores only a file name from SOUND_DIR; the
-- absolute path bypasses EdgeTX's per-language resolution so the same files
-- play regardless of the radio's language setting.
M.SOUND_DIR      = "/SOUNDS/en/SCRIPTS/SNTNL/"
M.SOUND_KEYS     = { "stage1", "stage2", "lost", "conn", "rec" }
M.SOUND_DEFAULTS = { stage1 = "stage1.wav", stage2 = "stage2.wav", lost = "linklost.wav",
                     conn = "linkconn.wav", rec = "linkrec.wav" }
-- Full paths that play (false = muted), overlaid from the config.
M.SOUNDS = {
  stage1 = M.SOUND_DIR .. "stage1.wav",
  stage2 = M.SOUND_DIR .. "stage2.wav",
  lost   = false,
  conn   = false,
  rec    = false,
  cfgerr = M.SOUND_DIR .. "cfgerr.wav",
}
-- Sounds that are off until picked: a missing config entry means Off, so the
-- settings tool's "Default" is written out as the file name (see saveConfig).
local SOUND_DEFAULT_OFF = { lost = true, conn = true, rec = true }

-- ---------------------------------------------------------------------------
-- Optional configuration overlay. The settings tool (/SCRIPTS/TOOLS/FLIGHTBAG.lua)
-- writes /SCRIPTS/SNTNL/config.lua; both variants pick it up here, so there is
-- no second place that reads the user's thresholds/sounds. The file is OPTIONAL:
-- without it (or with a broken one) the hard-coded defaults above stay in force.
-- ---------------------------------------------------------------------------
M.CONFIG_SCHEMA_VERSION = 1

-- Editable ranges, keyed like the config -- the SINGLE source of truth, also read
-- by the settings tool so the editor and the runtime clamp can never drift apart.
M.LIMITS = {
  warnOffsetDb   = { min = 10, max = 30, step = 1 },   -- Stage 1 dB offset over the sens. limit
  rqlyThreshold  = { min = 30, max = 70, step = 1 },   -- Stage 2 RQly % bound
  hapticStrength = { min = 1,  max = 3,  step = 1 },   -- Haptic pulse-length tier
}

-- Snapshot of the hard-coded defaults, keyed like the config, used as the
-- per-field fallback when a config omits a value. Taken before any override
-- runs, so applyConfigOverrides is idempotent regardless of call order. The
-- settings tool reads the TRUE factory defaults from here (PARAMS and SOUNDS
-- are already config-overlaid by then).
M.DEFAULTS = {
  warnOffsetDb   = M.PARAMS.WARN_OFFSET_DB,
  rqlyThreshold  = M.PARAMS.RQLY_THRESHOLD,
  audio          = M.PARAMS.AUDIO,
  haptic         = M.PARAMS.HAPTIC,
  hapticStrength = M.PARAMS.HAPTIC_STRENGTH,
}
local DEFAULTS = M.DEFAULTS

-- Clamp helper: n into [lo, hi]; non-numbers fall back to `fallback`.
local function clampNum(n, lo, hi, fallback)
  if type(n) ~= "number" then return fallback end
  if n < lo then return lo elseif n > hi then return hi end
  return n
end

-- Boolean helper: a plain `or` would swallow an explicit false, so anything
-- that is not a real boolean falls back instead.
local function boolOr(v, fallback)
  if type(v) == "boolean" then return v end
  return fallback
end

-- True unless fstat positively says the file is gone. fstat is absent on the
-- desktop and pcall-guarded, so "unknown" keeps the custom name (no regression).
local function soundFileExists(name)
  if not fstat then return true end
  local ok, info = pcall(fstat, M.SOUND_DIR .. name)
  return not ok or info ~= nil
end

-- Sound override helper: a string is a custom file name (an older full path is
-- cut to its name; dropped to the default when the file no longer exists on the
-- card, so the warning still sounds), `false` means the user muted this event,
-- and anything else (nil / garbage) falls back to the default (nil) so a corrupt
-- config can never reach playFile with junk.
local function soundOr(v)
  if type(v) == "string" then
    local name = string.match(v, "[^/]+$")
    if name and soundFileExists(name) then return name end
    return nil
  end
  if v == false then return false end
  return nil
end

-- Normalise a parsed config table into a copy (never touches PARAMS; the only
-- I/O is one fstat per custom sound): thresholds clamped to M.LIMITS, wrong
-- types replaced by the factory default, a sound is a file name, false (muted)
-- or nil (default). Unknown entries are kept as they are, so a setting written
-- by a newer version survives a save through this one. The ONE place that
-- decides what a config value means -- the runtime overlay and the settings
-- tool both go through here, so they can never disagree on a hand-edited file.
function M.normalizeConfig(cfg)
  local out = {}
  if type(cfg) == "table" then for k, v in pairs(cfg) do out[k] = v end end
  local L = M.LIMITS
  out.warnOffsetDb   = clampNum(out.warnOffsetDb,
                         L.warnOffsetDb.min, L.warnOffsetDb.max, DEFAULTS.warnOffsetDb)
  out.rqlyThreshold  = clampNum(out.rqlyThreshold,
                         L.rqlyThreshold.min, L.rqlyThreshold.max, DEFAULTS.rqlyThreshold)
  out.audio          = boolOr(out.audio, DEFAULTS.audio)
  out.haptic         = boolOr(out.haptic, DEFAULTS.haptic)
  out.hapticStrength = clampNum(out.hapticStrength,
                         L.hapticStrength.min, L.hapticStrength.max, DEFAULTS.hapticStrength)
  local snd, sounds = (type(out.sounds) == "table") and out.sounds or {}, {}
  for k, v in pairs(snd) do sounds[k] = v end
  for _, k in ipairs(M.SOUND_KEYS) do
    sounds[k] = soundOr(snd[k])
    if sounds[k] == nil and SOUND_DEFAULT_OFF[k] then sounds[k] = false end
  end
  out.sounds = sounds
  if type(out.generation) ~= "number" then out.generation = 0 end
  return out
end

-- Apply a parsed config table over PARAMS/SOUNDS (pure: no file I/O beyond
-- normalizeConfig, so it is directly unit-testable). A nil sound means "use the
-- default".
function M.applyConfigOverrides(cfg)
  local n = M.normalizeConfig(cfg)
  M.PARAMS.WARN_OFFSET_DB  = n.warnOffsetDb
  M.PARAMS.RQLY_THRESHOLD  = n.rqlyThreshold
  M.PARAMS.AUDIO           = n.audio
  M.PARAMS.HAPTIC          = n.haptic
  M.PARAMS.HAPTIC_STRENGTH = n.hapticStrength
  for _, k in ipairs(M.SOUND_KEYS) do
    local v = n.sounds[k]
    if v == nil then v = M.SOUND_DEFAULTS[k] end
    M.SOUNDS[k] = v and (M.SOUND_DIR .. v)
  end
end

-- ---------------------------------------------------------------------------
-- Config file: load, save, defaults, reset, reload. Written by the settings
-- tool; the file is OPTIONAL, without it (or with a broken one) the hard-coded
-- defaults stay in force.
-- ---------------------------------------------------------------------------

local function quoteString(s)
  s = string.gsub(s, "\\", "\\\\")
  s = string.gsub(s, '"', '\\"')
  s = string.gsub(s, "\n", "\\n")
  return '"' .. s .. '"'
end

-- Lua source for a value; string keys sorted so the file is stable.
local function serialize(value, indent)
  local t = type(value)
  if t == "number" or t == "boolean" then return tostring(value) end
  if t == "string" then return quoteString(value) end
  if t ~= "table" then return "nil" end
  local nextIndent, parts, n = indent .. "  ", {}, #value
  for i = 1, n do parts[#parts + 1] = nextIndent .. serialize(value[i], nextIndent) end
  local keys = {}
  for k in pairs(value) do
    if not (type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k) then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local keyStr = (type(k) == "string") and ("[" .. quoteString(k) .. "]") or ("[" .. tostring(k) .. "]")
    parts[#parts + 1] = nextIndent .. keyStr .. " = " .. serialize(value[k], nextIndent)
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

-- Reads a whole file (block reads; "a" format is not on every build), or nil.
local function readFile(path)
  local ok, f = pcall(io.open, path, "r")
  if not ok or not f then return nil end
  local parts = {}
  while true do
    local rok, chunk = pcall(io.read, f, 4096)
    if not rok or not chunk or chunk == "" then break end
    parts[#parts + 1] = chunk
  end
  pcall(io.close, f)
  return table.concat(parts)
end

-- io.open "w" does NOT truncate on some EdgeTX/SD builds, so a shorter write
-- would leave the old tail behind -- pad with trailing newlines (valid after the
-- table) up to the old length. Pcall-wrapped so a full/read-only SD never raises.
local function writeFile(path, content)
  local old = readFile(path)
  if old and #old > #content then
    content = content .. string.rep("\n", #old - #content)
  end
  local ok, f = pcall(io.open, path, "w")
  if not ok or not f then return false end
  local wok = pcall(io.write, f, content)
  pcall(io.close, f)
  return wok == true
end

-- Returns the normalised config, or nil plus "missing" | "parse" | "schema"
-- (and a detail text). Text only, no .luac (mode "tx"): the radio would prefer
-- a compiled copy with the same 2 s FAT timestamp over a newer file.
function M.loadConfig()
  local ok, f = pcall(io.open, M.CONFIG_PATH, "r")
  if not ok or not f then return nil, "missing" end
  pcall(io.close, f)
  local cok, chunk, err = pcall(loadScript, M.CONFIG_PATH, "tx")
  if not cok or not chunk then return nil, "parse", tostring(err or chunk) end
  local pok, result = pcall(chunk)
  if not pok then return nil, "parse", tostring(result) end
  if type(result) ~= "table" then return nil, "parse", "not a table" end
  if result.schemaVersion ~= M.CONFIG_SCHEMA_VERSION then
    return nil, "schema", tostring(result.schemaVersion)
  end
  return M.normalizeConfig(result)
end

-- Writes the config with a raised generation (the reload sentinel). True on success.
function M.saveConfig(cfg)
  cfg.schemaVersion = M.CONFIG_SCHEMA_VERSION
  cfg.generation    = (cfg.generation or 0) + 1
  if type(cfg.sounds) ~= "table" then cfg.sounds = {} end
  for k in pairs(SOUND_DEFAULT_OFF) do
    if cfg.sounds[k] == nil then cfg.sounds[k] = M.SOUND_DEFAULTS[k] end
  end
  return writeFile(M.CONFIG_PATH, "-- ELRS Link Sentinel configuration (auto-generated).\nreturn "
                                  .. serialize(cfg, "") .. "\n")
end

-- Factory settings as a fresh table.
function M.defaultConfig()
  local cfg = M.normalizeConfig({})
  cfg.schemaVersion = M.CONFIG_SCHEMA_VERSION
  return cfg
end

-- Settings back to factory values. The shared settings (audio, haptic) are kept: they
-- are set once for all scripts in the settings tool. True on success.
function M.resetSettings()
  local cfg = M.loadConfig() or M.defaultConfig()
  local fresh = M.defaultConfig()
  fresh.audio, fresh.haptic, fresh.hapticStrength = cfg.audio, cfg.haptic, cfg.hapticStrength
  fresh.generation = cfg.generation
  return M.saveConfig(fresh)
end

-- Re-reads the config at most every CONFIG_POLL_MS and applies it when its
-- generation changed (or it appeared / went away), so a change made in the
-- settings tool takes effect without a model reload.
local CONFIG_POLL_MS = 5000
local configGen, configPollAt
function M.pollConfig(now)
  now = now or getTime() * 10
  if configPollAt and now - configPollAt < CONFIG_POLL_MS then return end
  configPollAt = now
  local cfg, kind = M.loadConfig()
  -- damaged or wrong version: defaults stay in use, but it is a setup error
  M.configDamaged = (kind == "parse" or kind == "schema")
  local gen = cfg and cfg.generation or false
  if gen ~= configGen then
    configGen = gen
    M.applyConfigOverrides(cfg or {})
  end
end
pcall(M.pollConfig, 0)

-- ---------------------------------------------------------------------------
-- Telemetry sensors + sensitivity limits
-- ---------------------------------------------------------------------------

-- Telemetry sensor names (CRSF/ELRS standard).
M.SENSORS = {
  rssi1 = "1RSS", rssi2 = "2RSS", rqly = "RQly",
  rfmd  = "RFMD", ant  = "ANT",   tpwr = "TPWR", fm = "FM",
  rsnr  = "RSNR",
}

-- Sensitivity limits in dBm per RFMD.
-- Entries with 0 dBm are intentional placeholders and produce a permanent
-- warning -- a hint that this mode still needs to be filled in.
M.SENS_LIMIT = {
  -- 900 MHz / Sub-GHz
  [0]   = -123,  -- 25Hz
  [1]   = -120,  -- 50Hz
  [2]   = -117,  -- 100Hz
  [3]   = -112,  -- 100Hz Full
  [4]   = 0,     -- 150Hz
  [5]   = -112,  -- 200Hz
  [6]   = -111,  -- 200Hz Full
  [7]   = -111,  -- 250Hz
  [8]   = 0,     -- 333Hz Full
  [9]   = 0,     -- 500Hz
  [10]  = -112,  -- D50
  [11]  = -101,  -- K1000 Full
  -- 2.4 GHz
  [20]  = 0,     -- 25Hz
  [21]  = -115,  -- 50Hz
  [22]  = 0,     -- 100Hz
  [23]  = -112,  -- 100Hz Full
  [24]  = -112,  -- 150Hz
  [25]  = 0,     -- 200Hz
  [26]  = 0,     -- 200Hz Full
  [27]  = -108,  -- 250Hz
  [28]  = -105,  -- 333Hz Full
  [29]  = -105,  -- 500Hz
  [30]  = -104,  -- D250
  [31]  = -104,  -- D500
  [32]  = -104,  -- F500
  [33]  = -104,  -- F1000
  [34]  = -103,  -- DK250
  [35]  = -103,  -- DK500
  [36]  = -103,  -- K1000
  -- GEMX / Crossband
  [100] = -112,  -- X100Hz Full
  [101] = -112,  -- X150Hz
}

-- Human-readable mode names per RFMD, display-only. nil for an unknown mode ->
-- the widget falls back to showing the raw RFMD number.
M.MODE_NAMES = {
  -- 900 MHz / Sub-GHz
  [0]   = "25Hz",
  [1]   = "50Hz",
  [2]   = "100Hz",
  [3]   = "100Hz Full",
  [4]   = "150Hz",
  [5]   = "200Hz",
  [6]   = "200Hz Full",
  [7]   = "250Hz",
  [8]   = "333Hz Full",
  [9]   = "500Hz",
  [10]  = "D50",
  [11]  = "K1000 Full",
  -- 2.4 GHz
  [20]  = "25Hz",
  [21]  = "50Hz",
  [22]  = "100Hz",
  [23]  = "100Hz Full",
  [24]  = "150Hz",
  [25]  = "200Hz",
  [26]  = "200Hz Full",
  [27]  = "250Hz",
  [28]  = "333Hz Full",
  [29]  = "500Hz",
  [30]  = "D250",
  [31]  = "D500",
  [32]  = "F500",
  [33]  = "F1000",
  [34]  = "DK250",
  [35]  = "DK500",
  [36]  = "K1000",
  -- GEMX / Crossband
  [100] = "X100Hz Full",
  [101] = "X150Hz",
}

-- ---------------------------------------------------------------------------
-- Time / sensor helpers
-- ---------------------------------------------------------------------------
local function nowMs()
  return getTime() * 10
end

-- getFieldInfo is nil for a sensor that was never discovered; getValue would give 0.
local function sensorExists(name)
  local ok, info = pcall(getFieldInfo, name)
  return ok and info ~= nil
end

-- Existence per sensor, re-checked at most every `interval` (same unit as `now`).
-- names = { key = "SensorName", ... }; returns the cached { key = true/false }.
local function sensorsPresent(state, names, now, interval)
  if state.sensorCheckAt == nil or now - state.sensorCheckAt >= interval then
    state.sensorCheckAt = now
    local has = {}
    for key, name in pairs(names) do has[key] = sensorExists(name) end
    state.sensorsPresent = has
  end
  return state.sensorsPresent
end

-- Value of a present sensor, nil when absent (display shows "--", not a fake 0).
local function readPresent(has, names, key)
  if not has[key] then return nil end
  local ok, v = pcall(getValue, names[key])
  if ok then return v end
  return nil
end

local SENSOR_CHECK_MS = 1000   -- sensor existence is model config, 1 s cache is plenty

-- True while EdgeTX receives telemetry (any protocol).
local function linkUp()
  return getRSSI() ~= 0
end

-- Debounced loss: true once the link has been down for `grace` (same unit as `now`).
-- state.linkLostSince is nil while the link is up.
local function linkLost(state, up, now, grace)
  if up then
    state.linkLostSince = nil
    return false
  end
  state.linkLostSince = state.linkLostSince or now
  return now - state.linkLostSince >= grace
end

-- Disarmed marker in the FM text: Betaflight appends * ! ?, ArduPilot *,
-- INAV sends OK / WAIT / !ERR. "!FS!" (failsafe) is armed despite its "!".
local INAV_DISARMED = { OK = true, WAIT = true, ["!ERR"] = true }
local function fmDisarmed(fm)
  if fm == "!FS!" then return false end
  if INAV_DISARMED[fm] then return true end
  local last = string.sub(fm, -1)
  return last == "*" or last == "!" or last == "?"
end

-- armed, known. Known only once a disarmed marker was seen on this link
-- (state.disarmSeen): some setups never send one, and a text without a marker
-- alone proves nothing. Clear state.disarmSeen when the flight ends.
local function armedFromFM(state, fm)
  if type(fm) ~= "string" or fm == "" then return false, false end
  if fmDisarmed(fm) then
    state.disarmSeen = true
    return false, true
  end
  if not state.disarmSeen then return false, false end
  return true, true
end
M.armedFromFM = armedFromFM

-- Flight phases, word for word the same in every script. They pick the page:
-- WAITING (no link) -> PRE (link up) -> FLIGHT (armed, or the app's preflight
-- check met for PRE_HOLD_T without a break) -> ENDED (link lost LINK_LOSS_T)
-- -> WAITING after ENDED_HOLD_T. No way back from FLIGHT to PRE (a disarm keeps
-- FLIGHT). A loss in PRE goes straight to WAITING (no flight). A loss while
-- armed is a link failure: back within ENDED_HOLD_T, the same flight goes on.
-- Display only: logic that needs the real armed state reads armedFromFM.
-- Times in ms. Returns the phase and an event: "new" (a new flight starts in
-- PRE), "lost" (PRE -> WAITING), "end" (FLIGHT -> ENDED, s.linkFailure tells
-- why), "resume" (link back after a failure) or "over" (ENDED_HOLD_T without
-- link), else nil.
local LINK_LOSS_T, ENDED_HOLD_T, PRE_HOLD_T = 1500, 30000, 15000
local function flightPhase(s, up, armed, ready, now)
  local phase, event = s.phase or "WAITING", nil
  local lost = linkLost(s, up, now, LINK_LOSS_T)
  if up then s.armedBeforeLoss = armed == true end
  if phase == "WAITING" then
    if up then phase, event = "PRE", "new" end
  elseif phase == "ENDED" then
    if up and s.linkFailure then
      phase, event = "FLIGHT", "resume"
    elseif up then
      phase, event = "PRE", "new"
    elseif now - s.endedAt >= ENDED_HOLD_T then
      phase, event = "WAITING", "over"
    end
    if phase ~= "ENDED" then s.linkFailure = nil end
  elseif phase == "FLIGHT" then
    if lost then
      phase, event, s.endedAt, s.linkFailure = "ENDED", "end", now, s.armedBeforeLoss
    end
  elseif lost then
    phase, event = "WAITING", "lost"
  elseif up then
    if not ready then s.readySince = nil elseif not s.readySince then s.readySince = now end
    if armed or (s.readySince and now - s.readySince >= PRE_HOLD_T) then phase = "FLIGHT" end
  end
  if phase ~= "PRE" then s.readySince = nil end
  s.phase = phase
  return phase, event
end
M.flightPhase = flightPhase
M.LINK_LOSS_T, M.ENDED_HOLD_T, M.PRE_HOLD_T = LINK_LOSS_T, ENDED_HOLD_T, PRE_HOLD_T

-- ---------------------------------------------------------------------------
-- State (caller-owned)
-- ---------------------------------------------------------------------------
function M.newState()
  return {
    phase  = "WAITING",   -- flight phase (flightPhase); its link fields live here too
    stage1 = { condSince = 0, active = false },
    stage2 = { condSince = 0, active = false },
    -- announcedStage/lastPlay drive the sound: any CHANGE of the sounding stage
    -- plays immediately, an unchanged stage repeats on REPEAT_MS.
    announcedStage = 0,
    lastPlay       = 0,
    -- linkLostSince marks when telemetry first went away (nil = link present); drives
    -- the brief-gap grace before resetAll().
    linkLostSince  = nil,
    -- cfgErrSince marks when the missing-sensor situation was first observed
    -- (drives the grace period); cfgErrLastPlay drives the repeat timer.
    cfgErrSince    = 0,
    cfgErrLastPlay = 0,
  }
end

local function resetStage(s)
  s.condSince = 0
  s.active    = false
end

-- Resets the WARN state after a sustained link loss. Deliberately leaves the
-- cfgErr timers alone: sensor existence (getFieldInfo) is model config and
-- survives dropouts, so the cfgerr grace must not restart on every loss --
-- evaluate() clears those timers once the sensors are present again.
local function resetAll(state)
  state.announcedStage = 0
  state.lastPlay       = 0
  resetStage(state.stage1)
  resetStage(state.stage2)
end

-- ---------------------------------------------------------------------------
-- Pure logic
-- ---------------------------------------------------------------------------

-- Unknown RFMD -> 0 dBm sensitivity -> warning threshold +WARN_OFFSET_DB
-- (permanent warning).
function M.thresholdFor(rfmd)
  local sens = M.SENS_LIMIT[rfmd] or 0
  return sens + M.PARAMS.WARN_OFFSET_DB
end

-- Debounce: DEBOUNCE_MS must elapse between the condition becoming true and
-- active=true, and likewise on the way back to false. condSince holds the start
-- time of the current transition phase; 0 means no phase active.
function M.debounce(s, cond, now)
  if cond ~= s.active then
    if s.condSince == 0 then
      s.condSince = now
    elseif now - s.condSince >= M.PARAMS.DEBOUNCE_MS then
      s.active    = cond
      s.condSince = 0
    end
  else
    s.condSince = 0
  end
end

-- RANGELIMIT in % (0..100): how far the governing RSS has come towards the
-- mode's raw sensitivity limit (100 = limit reached). nil for a placeholder or
-- unknown mode (sensLimit 0).
function M.rangePct(rss, sensLimit)
  if not sensLimit or sensLimit == 0 then return nil end
  local pct = 100 * (rss + 50) / (sensLimit + 50)
  if pct < 0 then return 0 elseif pct > 100 then return 100 end
  return pct
end

-- TX power headroom from the module's Max Power (mW) and Dynamic setting and
-- the current TPWR: "MAX" (at the maximum, or fixed power), "DYN" (dynamic
-- power below the maximum) or nil (unknown). With DYN also the part of the
-- range bar (percentage points) the bar would shrink by at full power: an
-- uplink RSS gain of 10*log10(Max/TPWR) dB on the mode's scale; nil for an
-- unknown mode.
function M.powerHeadroom(maxMw, dynamic, tpwr, sensLimit)
  if not maxMw or dynamic == nil or not tpwr then return nil end
  if not dynamic or tpwr >= maxMw then return "MAX" end
  if not sensLimit or sensLimit == 0 or tpwr <= 0 then return "DYN" end
  return "DYN", 10 * math.log(maxMw / tpwr, 10) * 100 / (-50 - sensLimit)
end

-- Setup errors that need no telemetry, one text each (the settings tool lists
-- them; a widget only shows that there is one): mandatory sensors not
-- discovered in the model. state as kept by update; without it a fresh one.
local MANDATORY = { "rssi1", "rqly", "rfmd" }
function M.setupErrors(state)
  state = state or M.newState()
  local has = sensorsPresent(state, M.SENSORS, nowMs(), SENSOR_CHECK_MS)
  local out = {}
  if M.configDamaged then out[1] = "Settings file damaged" end   -- defaults in use
  local missing = {}
  for _, k in ipairs(MANDATORY) do
    if not has[k] then missing[#missing + 1] = M.SENSORS[k] end
  end
  if #missing > 0 then
    out[#out + 1] = "Missing sensors: " .. table.concat(missing, ", ")
    out[#out + 1] = "Check sensors config"
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Telemetry reading -- the single place that reads ALL sensors raw.
-- ---------------------------------------------------------------------------
function M.readSnapshot(state, now)
  local S   = M.SENSORS
  local has = sensorsPresent(state, S, now, SENSOR_CHECK_MS)
  return {
    rssiValid = linkUp(),                    -- telemetry present at all
    has1RSS   = has.rssi1,                   -- mandatory-sensor existence
    hasRQly   = has.rqly,
    hasRFMD   = has.rfmd,
    rfmd      = getValue(S.rfmd),
    rss1      = getValue(S.rssi1),
    rss2      = getValue(S.rssi2),           -- 0 when absent -> treated as single antenna
    rqly      = getValue(S.rqly),
    ant       = readPresent(has, S, "ant"),  -- display-only -> nil when absent
    tpwr      = readPresent(has, S, "tpwr"),
    fm        = readPresent(has, S, "fm"),   -- string sensor
    rsnr      = readPresent(has, S, "rsnr"), -- uplink SNR in dB, for scripts that load the core
  }
end

-- ---------------------------------------------------------------------------
-- Warning state machine (pure: mutates `state`, no I/O). Returns a result
-- table the caller acts on (play flags) and the widget renders.
-- ---------------------------------------------------------------------------
function M.evaluate(state, snap, now)
  local result = {}

  -- Flight phase from the link, the armed state and the last cycle's preflight
  -- check. A flight end clears the extremes on the next sample: disarmed or
  -- unknown before the loss, a loss before the flight page, or 30 s without
  -- link (also after a link failure while armed).
  local armed, armedKnown = false, false
  if snap.rssiValid then armed, armedKnown = armedFromFM(state, snap.fm) end
  local phase, event = flightPhase(state, snap.rssiValid, armed, state.preReady, now)
  if event == "lost" or event == "over" or (event == "end" and not state.linkFailure) then
    state.disarmSeen = nil   -- new flight, new proof needed
    state.minsStale  = true  -- flight extremes stay readable until the next link
  end
  result.phase = phase
  -- Link lost tone: once per flight end, when armed or unknown before the loss.
  if snap.rssiValid then state.lostTone = armed or not armedKnown end
  if event == "end" and state.lostTone then result.playLost = true end
  -- Link up for a new flight, or back after a link failure while armed.
  if event == "new" then
    result.playConn = true
    -- re-read Max Power / Dynamic: another model may use other module settings
    state.pwrScan, state.pwrMax, state.pwrDyn = { id = 1 }, nil, nil
  end
  if event == "resume" then result.playRec = true end

  -- Telemetry lost -> stay silent (ELRS alarms on a real loss itself). Do NOT reset
  -- immediately: a brief gap must not wipe an active warning, or both stages re-debounce
  -- in parallel on reconnect and flash a spurious OK between WARNING and CRITICAL. Reset
  -- only once the loss persists LINK_LOSS_GRACE_MS.
  local lost = linkLost(state, snap.rssiValid, now, M.PARAMS.LINK_LOSS_GRACE_MS)
  if not snap.rssiValid then
    if lost then resetAll(state) end
    result.status   = "no_link"
    result.linkLost = lost      -- grace elapsed -> widget shows NO LINK
    result.minRqly, result.minMarginDb = state.minRqly, state.minMarginDb
    result.maxRangePct, result.maxTpwr = state.maxRangePct, state.maxTpwr
    result.maxStage = state.maxStage
    return result
  end

  -- 1RSS, RQly and RFMD are mandatory. After a grace period (to tolerate
  -- sensor-discovery delays) flag cfgerr -- the script cannot warn without them.
  if not snap.has1RSS or not snap.hasRQly or not snap.hasRFMD then
    result.status  = "cfg_error"
    state.preReady = false
    if state.cfgErrSince == 0 then
      state.cfgErrSince = now
    elseif (now - state.cfgErrSince) >= M.PARAMS.CFG_ERR_GRACE_MS then
      if state.cfgErrLastPlay == 0
         or (now - state.cfgErrLastPlay) >= M.PARAMS.CFG_ERR_REPEAT_MS then
        result.playCfgErr    = true
        state.cfgErrLastPlay = now
      end
    end
    return result
  end
  -- Sensors present -- clear any pending cfg-error timers.
  state.cfgErrSince    = 0
  state.cfgErrLastPlay = 0

  -- Recomputed every cycle so a changed offset applies mid-flight.
  local rfmd = snap.rfmd
  local warnThreshold = M.thresholdFor(rfmd)
  local sensLimit = M.SENS_LIMIT[rfmd] or 0

  -- Governing RSS: the stronger antenna, or 1RSS when there is no second one
  -- (2RSS == 0, single-antenna receiver). stage 1 fires when even this one is weak.
  local rss1, rss2, rqly = snap.rss1, snap.rss2, snap.rqly
  local dual       = (rss2 ~= nil and rss2 ~= 0)
  local linkRssi   = dual and math.max(rss1, rss2) or rss1
  local stage1Cond = (linkRssi <= warnThreshold)
  local stage2Cond = stage1Cond and (rqly < M.PARAMS.RQLY_THRESHOLD)

  M.debounce(state.stage1, stage1Cond, now)
  M.debounce(state.stage2, stage2Cond, now)

  -- Decide which sound to (re)play. Any CHANGE of the sounding stage (up,
  -- down, or re-entry) plays immediately; an unchanged stage repeats on
  -- REPEAT_MS. Stage 2 takes precedence over Stage 1.
  local sounding = state.stage2.active and 2 or (state.stage1.active and 1 or 0)
  if sounding ~= state.announcedStage then
    state.announcedStage = sounding
    state.lastPlay       = 0
  end
  if sounding > 0 and
     (state.lastPlay == 0 or (now - state.lastPlay) >= M.PARAMS.REPEAT_MS) then
    if sounding == 2 then result.playStage2 = true else result.playStage1 = true end
    state.lastPlay = now
  end

  -- Flight extremes (the widget's end page, scripts that load the core):
  -- lowest RQly, smallest margin of the governing RSS above the mode's
  -- sensitivity limit (dB, comparable across mode changes), highest RANGELIMIT,
  -- highest TX power (mW, nil without TPWR) and highest warning stage. With FM only while armed;
  -- cleared on the first sample after a flight end (see flightPhase above).
  if state.minsStale then
    state.minRqly, state.minMarginDb, state.minsStale = nil, nil, nil
    state.maxRangePct, state.maxTpwr, state.maxStage = nil, nil, nil
  end
  local rangePct = M.rangePct(linkRssi, sensLimit)
  if armed or not armedKnown then
    if not state.minRqly or rqly < state.minRqly then state.minRqly = rqly end
    if sensLimit ~= 0 then
      local margin = linkRssi - sensLimit
      if not state.minMarginDb or margin < state.minMarginDb then state.minMarginDb = margin end
    end
    if rangePct and (not state.maxRangePct or rangePct > state.maxRangePct) then state.maxRangePct = rangePct end
    if snap.tpwr and (not state.maxTpwr or snap.tpwr > state.maxTpwr) then state.maxTpwr = snap.tpwr end
    if sounding > (state.maxStage or 0) then state.maxStage = sounding end
  end

  state.preReady   = M.preflight(sounding, sensLimit).level == 0   -- preflight check for flightPhase
  result.status    = "running"
  result.stage     = sounding
  result.sensLimit = sensLimit              -- raw (no offset) -> widget's rangePct
  result.linkRssi  = linkRssi               -- governing RSS (stronger antenna) -> range bar
  result.modeName  = M.MODE_NAMES[rfmd]     -- nil if unknown (widget falls back to number)
  result.armed     = armed                  -- false while unknown
  result.rangePct    = rangePct               -- RANGELIMIT now (nil for an unknown mode)
  result.minRqly     = state.minRqly
  result.minMarginDb = state.minMarginDb
  result.maxRangePct = state.maxRangePct
  result.maxTpwr     = state.maxTpwr
  result.maxStage    = state.maxStage            -- highest warning stage of the flight (nil: none)
  result.pwrTag, result.pwrReservePct = M.powerHeadroom(state.pwrMax, state.pwrDyn, snap.tpwr, sensLimit)
  return result
end

-- Vibrate alongside a warning, HAPTIC_PULSES[key] pulses. No-op when haptic
-- is off or the build lacks playHaptic (desktop tests), so it never touches the
-- pure logic above.
local function warnHaptic(key)
  if not M.PARAMS.HAPTIC or not playHaptic then return end
  local dur    = M.HAPTIC_DUR[M.PARAMS.HAPTIC_STRENGTH] or M.HAPTIC_DUR[2]
  local pulses = M.HAPTIC_PULSES[key] or 1
  for i = 1, pulses do
    playHaptic(dur, (i < pulses) and dur or 0)   -- gap between pulses, none after the last
  end
end

-- ---------------------------------------------------------------------------
-- CRSF device info: TX module name + firmware for a display (state.modLine, nil
-- until known), and the module's Max Power / Dynamic setting (state.pwrMax in
-- mW, state.pwrDyn) read from its parameter list after each new link. The
-- caller pops the CRSF queue once per cycle and hands every frame to
-- handleFrame, so other consumers in the same script get them too; pollModule
-- sends the pings and parameter reads. Not part of update(): a script without
-- a display has no use for it.
-- ---------------------------------------------------------------------------
local CRSF_PING, CRSF_DEVICE_INFO = 0x28, 0x29
local CRSF_PARAM_ENTRY, CRSF_PARAM_READ = 0x2B, 0x2C
local ADDR_BROADCAST, ADDR_RADIO  = 0x00, 0xEA
local ADDR_TX_MODULE              = 0xEE   -- the only sender accepted (not FC or receiver)
local DEV_PING_MS                 = 1000
local PARAM_RETRY_MS, PARAM_TRIES = 500, 3 -- no answer: ask again, then skip the parameter
local PARAM_SELECT                = 9      -- text selection, e.g. "10;25;50;100;250"

-- Null-terminated string from byte array `b` at `from`; returns it and the index after the 0.
local function crsfReadString(b, from)
  local out, i = {}, from
  while b[i] and b[i] ~= 0 do
    out[#out + 1] = string.char(b[i])
    i = i + 1
  end
  return table.concat(out), i + 1
end

local function deviceInfo(state, data)
  local name, p = crsfReadString(data, 3)
  -- after the name: serial(4) + hardware(4) + software(4), version in the last three
  -- bytes, then the parameter count
  local maj, min, rev = data[p + 9], data[p + 10], data[p + 11]
  if name ~= "" and maj and min and rev then
    state.modLine = string.format("%s (v%d.%d.%d)", name, maj, min, rev)
    state.paramCount = data[p + 12] or 0
  end
end

-- Parameter entry: field id, chunks still to come, then (over all chunks) parent,
-- type, name, and for a text selection the options and the selected index.
local function paramEntry(state, data)
  local scan = state.pwrScan
  if not scan or data[3] ~= scan.id then return end   -- not ours (e.g. the ELRS tool's)
  local left = data[4] or 0
  if scan.expect and left ~= scan.expect then          -- chunk missed: start the field over
    scan.buf, scan.chunk, scan.expect, scan.sentAt = nil, 0, nil, nil
    return
  end
  scan.buf = scan.buf or {}
  for i = 5, #data do scan.buf[#scan.buf + 1] = data[i] end
  scan.sentAt, scan.tries = nil, 0                     -- answered: next request right away
  if left > 0 then
    scan.chunk, scan.expect = (scan.chunk or 0) + 1, left - 1
    return
  end
  local b = scan.buf
  scan.buf, scan.chunk, scan.expect = nil, 0, nil
  if b[2] and b[2] % 128 == PARAM_SELECT then
    local name, p = crsfReadString(b, 3)
    if name == "Max Power" or name == "Dynamic" then
      local opts, q = crsfReadString(b, p)
      local sel, n = b[q], 0
      for o in string.gmatch(opts .. ";", "([^;]*);") do
        if n == sel then
          if name == "Max Power" then state.pwrMax = tonumber(o) else state.pwrDyn = o ~= "Off" end
        end
        n = n + 1
      end
    end
  end
  scan.id = scan.id + 1
  if state.pwrMax and state.pwrDyn ~= nil then state.pwrScan = nil end
end

function M.handleFrame(state, cmd, data)
  if type(data) ~= "table" or data[2] ~= ADDR_TX_MODULE then return end
  if cmd == CRSF_DEVICE_INFO then deviceInfo(state, data)
  elseif cmd == CRSF_PARAM_ENTRY then paramEntry(state, data) end
end

-- Pings until the module has answered (then EdgeTX keeps polling itself, so a
-- module swap still shows); while a scan runs, reads the parameters one by one.
function M.pollModule(state, now)
  if not crossfireTelemetryPush then return end
  now = now or nowMs()
  if not state.modLine then
    if state.lastDevPing == nil or now - state.lastDevPing >= DEV_PING_MS then
      crossfireTelemetryPush(CRSF_PING, { ADDR_BROADCAST, ADDR_RADIO })
      state.lastDevPing = now
    end
    return
  end
  local scan = state.pwrScan
  if not scan then return end
  if scan.sentAt and now - scan.sentAt < PARAM_RETRY_MS then return end
  if scan.sentAt then
    scan.tries = scan.tries + 1
    if scan.tries >= PARAM_TRIES then
      scan.id, scan.tries, scan.buf, scan.chunk, scan.expect = scan.id + 1, 0, nil, 0, nil
    end
  end
  if scan.id > state.paramCount then state.pwrScan = nil; return end   -- not found: no tag
  -- false: send buffer busy, ask again next cycle
  if crossfireTelemetryPush(CRSF_PARAM_READ, { ADDR_TX_MODULE, ADDR_RADIO, scan.id, scan.chunk or 0 }) ~= false then
    scan.sentAt, scan.tries = now, scan.tries or 0
  end
end

-- Restarts the backlight timeout so a dark display lights up with a warning.
local function wakeDisplay()
  if lcd and lcd.resetBacklightTimeout then lcd.resetBacklightTimeout() end
end

-- ---------------------------------------------------------------------------
-- One full cycle: read -> evaluate -> play. Returns the result table plus the
-- raw snapshot for the widget. The function script ignores the return value;
-- the widget derives all display values from it.
-- ---------------------------------------------------------------------------
function M.update(state, now)
  now = now or nowMs()
  M.pollConfig(now)
  local snap   = M.readSnapshot(state, now)
  local result = M.evaluate(state, snap, now)
  result.snapshot = snap

  -- A muted event (SOUNDS.stageN == false, or all sounds off via AUDIO) skips
  -- playFile but still buzzes: the haptic cue has its own on/off setting.
  local audio = M.PARAMS.AUDIO ~= false
  if result.playStage2 then
    if audio and M.SOUNDS.stage2 then playFile(M.SOUNDS.stage2) end
    warnHaptic("stage2")
    wakeDisplay()
  elseif result.playStage1 then
    if audio and M.SOUNDS.stage1 then playFile(M.SOUNDS.stage1) end
    warnHaptic("stage1")
    wakeDisplay()
  end
  if result.playCfgErr and audio then
    playFile(M.SOUNDS.cfgerr)
  end
  if result.playLost and audio and M.SOUNDS.lost then
    playFile(M.SOUNDS.lost)
  end
  if result.playConn and audio and M.SOUNDS.conn then
    playFile(M.SOUNDS.conn)
  end
  if result.playRec and audio and M.SOUNDS.rec then
    playFile(M.SOUNDS.rec)
  end

  return result
end

return M
