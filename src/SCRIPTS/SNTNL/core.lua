-- =====================================================================
-- core.lua  --  Shared core for the ELRS Link Sentinel.
-- =====================================================================
-- SD card path: /SCRIPTS/SNTNL/core.lua
--
-- Single source of truth used by BOTH variants (must be copied along with
-- whichever one is installed):
--   * the function script  /SCRIPTS/FUNCTIONS/sntnl.lua  (audio only)
--   * the widget           /WIDGETS/SNTNL/main.lua       (audio + display)
--
-- core owns: the reference tables (from elrs_modes.md), the user parameters,
-- reading ALL telemetry (readSnapshot), the warning state machine (evaluate)
-- and sound playback (update). It does NOT do any display derivation and
-- never calls lcd.* -- that lives entirely in the widget.
--
-- State is caller-owned (newState): a widget can be instantiated multiple
-- times and all instances share this one loaded module, so per-instance state
-- must not live in module locals.
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
-- Configurable parameters. A single source of truth for both variants --
-- the widget must read shared thresholds (e.g. RQLY_THRESHOLD for its LQ
-- bar colour) from here, never hard-code them, or the display would drift
-- from the acoustic warning.
-- ---------------------------------------------------------------------
M.PARAMS = {
  WARN_OFFSET_DB    = 10,     -- Offset (dBm) added on top of the sensitivity limit
  RQLY_THRESHOLD    = 42,     -- Lower RQly bound in % for stage 2
  DEBOUNCE_MS       = 2000,   -- Debounce time in ms (activation and deactivation)
  REPEAT_MS         = 5000,   -- Sound repeat interval in ms
  CFG_ERR_GRACE_MS  = 10000,  -- Grace period before the cfg-error sound is first played
  CFG_ERR_REPEAT_MS = 30000,  -- Cfg-error sound repeat interval in ms
}

-- Sound files. Absolute paths bypass EdgeTX's per-language resolution so the
-- same files play regardless of the radio's language setting.
M.SOUNDS = {
  stage1 = "/SOUNDS/en/SCRIPTS/SNTNL/stage1.wav",
  stage2 = "/SOUNDS/en/SCRIPTS/SNTNL/stage2.wav",
  cfgerr = "/SOUNDS/en/SCRIPTS/SNTNL/cfgerr.wav",
}

-- Telemetry sensor names (CRSF/ELRS standard).
M.SENSORS = {
  rssi1 = "1RSS", rssi2 = "2RSS", rqly = "RQly",
  rfmd  = "RFMD", ant  = "ANT",   tpwr = "TPWR", fm = "FM",
}

-- Sensitivity limits in dBm per RFMD (see elrs_modes.md).
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

-- Human-readable mode names per RFMD (Lua-Name column of elrs_modes.md). Used
-- only for display; the widget reads M.MODE_NAMES[rfmd]. nil for an unknown
-- mode -> the widget falls back to showing the raw RFMD number.
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

  -- Telemetry lost -> reset all state and stay silent. ELRS itself alarms on a
  -- real telemetry loss; this script does not cover that case.
  if not snap.rssiValid then
    resetAll(state)
    result.status = "no_link"
    return result
  end

  -- 1RSS, RQly and RFMD are mandatory. After a grace period (to tolerate
  -- sensor-discovery delays) flag cfgerr so the pilot knows the script cannot
  -- warn because of a missing-sensor configuration problem.
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
  -- (2RSS == 0, e.g. RP1). stage 1 = even this one weak (== "both antennas weak").
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
  elseif result.playStage1 then
    playFile(M.SOUNDS.stage1)
  end
  if result.playCfgErr then
    playFile(M.SOUNDS.cfgerr)
  end

  return result
end

return M
