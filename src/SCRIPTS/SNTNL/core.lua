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

-- ---------------------------------------------------------------------
-- Tunable parameters, shared by both variants. The widget must read thresholds
-- (e.g. RQLY_THRESHOLD) from here, never hard-code them, or the display drifts
-- from the audio warning.
-- ---------------------------------------------------------------------
M.PARAMS = {
  WARN_OFFSET_DB     = 10,     -- Offset (dBm) added on top of the sensitivity limit
  RQLY_THRESHOLD     = 42,     -- Lower RQly bound in % for stage 2
  DEBOUNCE_MS        = 2000,   -- Debounce time in ms (activation and deactivation)
  REPEAT_MS          = 5000,   -- Sound repeat interval in ms
  LINK_LOSS_GRACE_MS = 250,    -- Tolerate a telemetry gap this long before resetting the
                               -- warning state (see evaluate); well under the ~1 s ELRS failsafe.
  CFG_ERR_GRACE_MS   = 10000,  -- Grace period before the cfg-error sound is first played
  CFG_ERR_REPEAT_MS  = 30000,  -- Cfg-error sound repeat interval in ms
  HAPTIC             = false,  -- Vibrate alongside the warning sound (opt-in)
  HAPTIC_STRENGTH    = 2,      -- Pulse-length tier: 1 = soft, 2 = normal, 3 = strong
}

-- playHaptic pulse length per strength tier. Stage 2 (critical) fires a second
-- pulse to feel clearly stronger than Stage 1.
M.HAPTIC_DUR = { [1] = 15, [2] = 30, [3] = 50 }

-- Sound files. Absolute paths bypass EdgeTX's per-language resolution so the
-- same files play regardless of the radio's language setting.
M.SOUNDS = {
  stage1 = "/SOUNDS/en/SCRIPTS/SNTNL/stage1.wav",
  stage2 = "/SOUNDS/en/SCRIPTS/SNTNL/stage2.wav",
  cfgerr = "/SOUNDS/en/SCRIPTS/SNTNL/cfgerr.wav",
}

-- ---------------------------------------------------------------------
-- Optional configuration overlay. The Tools-Script (/SCRIPTS/TOOLS/SNTNL.lua)
-- writes /SCRIPTS/SNTNL/config.lua; both variants pick it up here, so there is
-- no second place that reads the user's thresholds/sounds. The file is OPTIONAL:
-- without it (or with a broken one) the hard-coded defaults above stay in force.
-- ---------------------------------------------------------------------
local CONFIG_PATH           = "/SCRIPTS/SNTNL/config.lua"
local CONFIG_SCHEMA_VERSION = 1

-- Editable ranges -- the SINGLE source of truth, also read by the Tools-Script
-- so the on-radio editor and the runtime clamp can never drift apart.
M.LIMITS = {
  WARN_OFFSET_DB  = { min = 10, max = 30 },   -- Stage 1 dB offset over the sens. limit
  RQLY_THRESHOLD  = { min = 30, max = 70 },   -- Stage 2 RQly % bound
  HAPTIC_STRENGTH = { min = 1,  max = 3 },    -- Haptic pulse-length tier
}

-- Snapshot of the hard-coded defaults, used as the per-field fallback when a
-- config omits a value (or sets "Default" = nil for a sound). Taken before any
-- override runs, so applyConfigOverrides is idempotent regardless of call order.
local DEFAULTS = {
  warnOffsetDb   = M.PARAMS.WARN_OFFSET_DB,
  rqlyThreshold  = M.PARAMS.RQLY_THRESHOLD,
  haptic         = M.PARAMS.HAPTIC,
  hapticStrength = M.PARAMS.HAPTIC_STRENGTH,
  stage1Sound    = M.SOUNDS.stage1,
  stage2Sound    = M.SOUNDS.stage2,
}

-- Clamp helper: n into [lo, hi]; non-numbers fall back to `fallback`.
local function clampNum(n, lo, hi, fallback)
  if type(n) ~= "number" then return fallback end
  if n < lo then return lo elseif n > hi then return hi end
  return n
end

-- Apply a parsed config table over PARAMS/SOUNDS (pure: no file I/O, so it is
-- directly unit-testable). Clamps the thresholds to M.LIMITS so even a corrupt
-- config can never set an unsafe value; a nil sound means "use the default".
function M.applyConfigOverrides(cfg)
  cfg = cfg or {}
  local L = M.LIMITS
  M.PARAMS.WARN_OFFSET_DB = clampNum(cfg.warnOffsetDb,
    L.WARN_OFFSET_DB.min, L.WARN_OFFSET_DB.max, DEFAULTS.warnOffsetDb)
  M.PARAMS.RQLY_THRESHOLD = clampNum(cfg.rqlyThreshold,
    L.RQLY_THRESHOLD.min, L.RQLY_THRESHOLD.max, DEFAULTS.rqlyThreshold)
  M.PARAMS.HAPTIC = (cfg.haptic == true)   -- only an explicit true enables it
  M.PARAMS.HAPTIC_STRENGTH = clampNum(cfg.hapticStrength,
    L.HAPTIC_STRENGTH.min, L.HAPTIC_STRENGTH.max, DEFAULTS.hapticStrength)
  local snd = cfg.sounds or {}
  M.SOUNDS.stage1 = snd.stage1 or DEFAULTS.stage1Sound
  M.SOUNDS.stage2 = snd.stage2 or DEFAULTS.stage2Sound
end

-- Load the optional config ONCE at module load. The thresholds are ground-config
-- (set in the Tools-Script, not retuned mid-flight), so a one-shot read at
-- init/create is enough -- a change takes effect on the next model select / reboot,
-- with no per-tick file I/O. Fully fault tolerant: a missing or broken file simply
-- leaves the hard-coded defaults in force. Wrapped in pcall, and a silent no-op on
-- desktop (no io / loadfile path) so the unit tests are unaffected.
local function loadConfigOnce()
  local f = io.open(CONFIG_PATH, "r")
  if not f then return end                                 -- no config -> defaults
  f:close()
  local ok, result = pcall(dofile, CONFIG_PATH)
  if not ok or type(result) ~= "table" then return end     -- parse error -> defaults
  if result.schemaVersion ~= CONFIG_SCHEMA_VERSION then return end
  M.applyConfigOverrides(result)
end
pcall(loadConfigOnce)

-- Telemetry sensor names (CRSF/ELRS standard).
M.SENSORS = {
  rssi1 = "1RSS", rssi2 = "2RSS", rqly = "RQly",
  rfmd  = "RFMD", ant  = "ANT",   tpwr = "TPWR", fm = "FM",
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

-- ---------------------------------------------------------------------
-- Time / sensor helpers
-- ---------------------------------------------------------------------
local function nowMs()
  return getTime() * 10
end

-- getValue() returns 0 for undiscovered telemetry sources, which is
-- indistinguishable from a real reading of 0. getFieldInfo() instead returns
-- nil for unknown sources, so we use it for existence checks.
local function sensorExists(name)
  return getFieldInfo(name) ~= nil
end

-- A display-only sensor: its raw value if present, else nil so the widget can
-- show "--" instead of a misleading 0 (TPWR/FM/ANT may simply not exist).
local function readOptional(name)
  if sensorExists(name) then return getValue(name) end
  return nil
end

-- ---------------------------------------------------------------------
-- State (caller-owned)
-- ---------------------------------------------------------------------
function M.newState()
  return {
    currentRFMD   = nil,
    warnThreshold = nil,
    stage1 = { condSince = 0, active = false, lastPlay = 0 },
    stage2 = { condSince = 0, active = false, lastPlay = 0 },
    -- linkLostSince marks when telemetry first went away (0 = link present); drives
    -- the brief-gap grace before resetAll().
    linkLostSince  = 0,
    -- cfgErrSince marks when the missing-sensor situation was first observed
    -- (drives the grace period); cfgErrLastPlay drives the repeat timer.
    cfgErrSince    = 0,
    cfgErrLastPlay = 0,
  }
end

local function resetStage(s)
  s.condSince = 0
  s.active    = false
  s.lastPlay  = 0
end

local function resetAll(state)
  state.currentRFMD    = nil
  state.warnThreshold  = nil
  state.cfgErrSince    = 0
  state.cfgErrLastPlay = 0
  resetStage(state.stage1)
  resetStage(state.stage2)
end

-- ---------------------------------------------------------------------
-- Pure logic
-- ---------------------------------------------------------------------

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

-- ---------------------------------------------------------------------
-- Telemetry reading -- the single place that reads ALL sensors raw.
-- ---------------------------------------------------------------------
function M.readSnapshot()
  local S = M.SENSORS
  return {
    rssiValid = getRSSI() ~= 0,              -- telemetry present at all
    has1RSS   = sensorExists(S.rssi1),       -- mandatory-sensor existence
    hasRQly   = sensorExists(S.rqly),
    hasRFMD   = sensorExists(S.rfmd),
    rfmd      = getValue(S.rfmd),
    rss1      = getValue(S.rssi1),
    rss2      = getValue(S.rssi2),           -- 0 when absent -> treated as single antenna
    rqly      = getValue(S.rqly),
    ant       = readOptional(S.ant),         -- display-only -> nil when absent
    tpwr      = readOptional(S.tpwr),
    fm        = readOptional(S.fm),          -- string sensor
  }
end

-- ---------------------------------------------------------------------
-- Warning state machine (pure: mutates `state`, no I/O). Returns a result
-- table the caller acts on (play flags) and the widget renders.
-- ---------------------------------------------------------------------
function M.evaluate(state, snap, now)
  local result = {}

  -- Telemetry lost -> stay silent (ELRS alarms on a real loss itself). Do NOT reset
  -- immediately: a brief gap must not wipe an active warning, or both stages re-debounce
  -- in parallel on reconnect and flash a spurious OK between WARNING and CRITICAL. Reset
  -- only once the loss persists LINK_LOSS_GRACE_MS (well before the ~1 s ELRS failsafe).
  if not snap.rssiValid then
    if state.linkLostSince == 0 then state.linkLostSince = now end
    if (now - state.linkLostSince) >= M.PARAMS.LINK_LOSS_GRACE_MS then
      resetAll(state)
    end
    result.status = "no_link"
    return result
  end
  state.linkLostSince = 0   -- telemetry present again -> clear the loss timer

  -- 1RSS, RQly and RFMD are mandatory. After a grace period (to tolerate
  -- sensor-discovery delays) flag cfgerr -- the script cannot warn without them.
  if not snap.has1RSS or not snap.hasRQly or not snap.hasRFMD then
    result.status = "cfg_error"
    if state.cfgErrSince == 0 then
      state.cfgErrSince = now
      result.inGrace = true
    elseif (now - state.cfgErrSince) >= M.PARAMS.CFG_ERR_GRACE_MS then
      if state.cfgErrLastPlay == 0
         or (now - state.cfgErrLastPlay) >= M.PARAMS.CFG_ERR_REPEAT_MS then
        result.playCfgErr      = true
        state.cfgErrLastPlay   = now
      end
    else
      result.inGrace = true
    end
    return result
  end
  -- Sensors present -- clear any pending cfg-error timers.
  state.cfgErrSince    = 0
  state.cfgErrLastPlay = 0

  -- Mode -> threshold; recompute only on an actual mode change.
  local rfmd = snap.rfmd
  if rfmd ~= state.currentRFMD then
    state.currentRFMD   = rfmd
    state.warnThreshold = M.thresholdFor(rfmd)
  end
  local sensLimit = M.SENS_LIMIT[rfmd] or 0

  -- Governing RSS: the stronger antenna, or 1RSS when there is no second one
  -- (2RSS == 0, single-antenna receiver). stage 1 fires when even this one is weak.
  local rss1, rss2, rqly = snap.rss1, snap.rss2, snap.rqly
  local dual       = (rss2 ~= nil and rss2 ~= 0)
  local linkRssi   = dual and math.max(rss1, rss2) or rss1
  local stage1Cond = (linkRssi <= state.warnThreshold)
  local stage2Cond = stage1Cond and (rqly < M.PARAMS.RQLY_THRESHOLD)

  local stage2WasActive = state.stage2.active
  M.debounce(state.stage1, stage1Cond, now)
  M.debounce(state.stage2, stage2Cond, now)

  -- Stage 2 just ended while Stage 1 is still active: force an immediate Stage 1
  -- play so the transition critical -> warning has no audible gap.
  if stage2WasActive and not state.stage2.active and state.stage1.active then
    state.stage1.lastPlay = 0
  end

  -- Decide which sound to (re)play. Stage 2 takes precedence over Stage 1.
  if state.stage2.active then
    if state.stage2.lastPlay == 0 or (now - state.stage2.lastPlay) >= M.PARAMS.REPEAT_MS then
      result.playStage2   = true
      state.stage2.lastPlay = now
    end
  elseif state.stage1.active then
    if state.stage1.lastPlay == 0 or (now - state.stage1.lastPlay) >= M.PARAMS.REPEAT_MS then
      result.playStage1   = true
      state.stage1.lastPlay = now
    end
  end

  result.status      = "running"
  result.stage       = state.stage2.active and 2 or (state.stage1.active and 1 or 0)
  result.sensLimit   = sensLimit                 -- raw (no offset) -> widget's rangePct
  result.threshold   = state.warnThreshold       -- sensLimit + offset -> drives the warning
  result.linkRssi    = linkRssi                  -- governing RSS (stronger antenna) -> range bar
  result.modeName    = M.MODE_NAMES[rfmd]        -- nil if unknown (widget falls back to number)
  result.dualAntenna = dual
  return result
end

-- Vibrate alongside a warning. `pulses` = 1 for Stage 1, 2 for the stronger
-- Stage 2. No-op when haptic is off or the build lacks playHaptic (desktop
-- tests), so it never touches the pure logic above.
local function warnHaptic(pulses)
  if not M.PARAMS.HAPTIC or not playHaptic then return end
  local dur = M.HAPTIC_DUR[M.PARAMS.HAPTIC_STRENGTH] or M.HAPTIC_DUR[2]
  for i = 1, pulses do
    playHaptic(dur, (i < pulses) and dur or 0)   -- gap between pulses, none after the last
  end
end

-- ---------------------------------------------------------------------
-- One full cycle: read -> evaluate -> play. Returns the result table plus the
-- raw snapshot for the widget. The function script ignores the return value;
-- the widget derives all display values from it.
-- ---------------------------------------------------------------------
function M.update(state, now)
  now = now or nowMs()
  local snap   = M.readSnapshot()
  local result = M.evaluate(state, snap, now)
  result.snapshot = snap

  if result.playStage2 then
    playFile(M.SOUNDS.stage2)
    warnHaptic(2)
  elseif result.playStage1 then
    playFile(M.SOUNDS.stage1)
    warnHaptic(1)
  end
  if result.playCfgErr then
    playFile(M.SOUNDS.cfgerr)
  end

  return result
end

return M
