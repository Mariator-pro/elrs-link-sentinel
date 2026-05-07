-- ============================================================
-- elrs-link-sentinel (sntnl.lua)
-- EdgeTX function script that monitors the ELRS radio link.
-- Path on the SD card: /SCRIPTS/FUNCTIONS/sntnl.lua
-- ============================================================

-- Configurable parameters
local WARN_OFFSET_DB    = 10     -- Offset (dBm) added on top of the sensitivity limit (default: 10)
local RQLY_THRESHOLD    = 42     -- Lower RQly bound in % for stage 2 (default: 42)
local DEBOUNCE_MS       = 2000   -- Debounce time in ms (default: 2000)
local REPEAT_MS         = 5000   -- Sound repeat interval in ms (default: 5000)
local CFG_ERR_GRACE_MS  = 10000  -- Grace period before the cfg-error sound is played (default: 10000)
local CFG_ERR_REPEAT_MS = 30000  -- Cfg-error sound repeat interval in ms (default: 30000)

-- Sound files. Absolute paths bypass EdgeTX's per-language resolution so the
-- same files play regardless of the radio's language setting.
local STAGE1_WAV = "/SOUNDS/en/SCRIPTS/SNTNL/stage1.wav"
local STAGE2_WAV = "/SOUNDS/en/SCRIPTS/SNTNL/stage2.wav"
local CFGERR_WAV = "/SOUNDS/en/SCRIPTS/SNTNL/cfgerr.wav"

-- Sensitivity limits in dBm per RFMD (see elrs_modes.md).
-- Entries with 0 dBm are intentional placeholders and produce a
-- permanent warning -- a hint that this mode still needs to be filled in.
local SENS_LIMIT = {
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

-- Internal state
local currentRFMD   = nil
local warnThreshold = nil

local stage1 = { condSince = 0, active = false, lastPlay = 0 }
local stage2 = { condSince = 0, active = false, lastPlay = 0 }

-- Tracks a misconfiguration: telemetry is up but mandatory sensors (1RSS, RQly)
-- never showed up. cfgErrSince marks when the situation was first observed
-- (used for the grace period); cfgErrLastPlay drives the repeat timer.
local cfgErrSince   = 0
local cfgErrLastPlay = 0

local function nowMs()
  return getTime() * 10
end

-- getValue() returns 0 for undiscovered telemetry sources, which is
-- indistinguishable from a real reading of 0. getFieldInfo() instead returns
-- nil for unknown sources, so we use it for existence checks.
local function sensorExists(name)
  return getFieldInfo(name) ~= nil
end

local function resetStage(s)
  s.condSince = 0
  s.active    = false
  s.lastPlay  = 0
end

local function resetAll()
  currentRFMD    = nil
  warnThreshold  = nil
  cfgErrSince    = 0
  cfgErrLastPlay = 0
  resetStage(stage1)
  resetStage(stage2)
end

local function thresholdFor(rfmd)
  -- Unknown RFMD -> 0 dBm sensitivity -> warning threshold +10 dBm (permanent warning).
  local sens = SENS_LIMIT[rfmd] or 0
  return sens + WARN_OFFSET_DB
end

-- Debounce: DEBOUNCE_MS must elapse between the condition becoming true
-- and active=true, and likewise for the way back to false. condSince holds
-- the start time of the current transition phase; 0 means no phase active.
local function debounce(s, cond, now)
  if cond ~= s.active then
    if s.condSince == 0 then
      s.condSince = now
    elseif now - s.condSince >= DEBOUNCE_MS then
      s.active    = cond
      s.condSince = 0
    end
  else
    s.condSince = 0
  end
end

local function init_func()
  resetAll()
end

local function run_func()
  -- Telemetry lost -> reset all state and stay silent.
  if getRSSI() == 0 then
    resetAll()
    return
  end

  local now = nowMs()

  local rfmd = getValue("RFMD")
  if rfmd ~= currentRFMD then
    currentRFMD   = rfmd
    warnThreshold = thresholdFor(rfmd)
  end

  -- 1RSS and RQly are mandatory. After a grace period (to tolerate sensor-
  -- discovery delays) play cfgerr.wav so the pilot knows the script cannot
  -- warn because of a missing-sensor configuration problem.
  if not sensorExists("1RSS") or not sensorExists("RQly") then
    if cfgErrSince == 0 then
      cfgErrSince = now
    elseif (now - cfgErrSince) >= CFG_ERR_GRACE_MS then
      if cfgErrLastPlay == 0 or (now - cfgErrLastPlay) >= CFG_ERR_REPEAT_MS then
        playFile(CFGERR_WAV)
        cfgErrLastPlay = now
      end
    end
    return
  end
  -- Sensors are present -- clear any pending cfg-error timers.
  cfgErrSince    = 0
  cfgErrLastPlay = 0

  local rss1 = getValue("1RSS")
  local rss2 = getValue("2RSS")
  local rqly = getValue("RQly")

  -- Single-antenna receivers (e.g. Radiomaster RP1) either don't expose 2RSS at
  -- all (sensor never discovered -> nil) or report it as a constant 0. Treat
  -- both as "no second antenna" and base the decision on 1RSS only.
  local stage1Cond
  if rss2 and rss2 ~= 0 then
    stage1Cond = (rss1 <= warnThreshold) and (rss2 <= warnThreshold)
  else
    stage1Cond = (rss1 <= warnThreshold)
  end
  local stage2Cond = stage1Cond and (rqly < RQLY_THRESHOLD)

  local stage2WasActive = stage2.active
  debounce(stage1, stage1Cond, now)
  debounce(stage2, stage2Cond, now)

  -- Stage 2 just ended while Stage 1 is still active: force an immediate
  -- Stage 1 play so the transition critical -> warning has no audible gap,
  -- regardless of how long Stage 2 was active.
  if stage2WasActive and not stage2.active and stage1.active then
    stage1.lastPlay = 0
  end

  if stage2.active then
    -- Stage 2 takes precedence over Stage 1.
    if stage2.lastPlay == 0 or (now - stage2.lastPlay) >= REPEAT_MS then
      playFile(STAGE2_WAV)
      stage2.lastPlay = now
    end
  elseif stage1.active then
    if stage1.lastPlay == 0 or (now - stage1.lastPlay) >= REPEAT_MS then
      playFile(STAGE1_WAV)
      stage1.lastPlay = now
    end
  end
end

return { init = init_func, run = run_func }
