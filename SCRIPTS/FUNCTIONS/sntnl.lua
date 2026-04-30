-- ============================================================
-- elrs-link-sentinel (sntnl.lua)
-- EdgeTX function script that monitors the ELRS radio link.
-- Path on the SD card: /SCRIPTS/FUNCTIONS/sntnl.lua
-- ============================================================

-- Configurable parameters
local WARN_OFFSET_DB = 10     -- Offset (dBm) added on top of the sensitivity limit
local RQLY_THRESHOLD = 42     -- Lower RQly bound in % for stage 2
local DEBOUNCE_MS    = 2000   -- Debounce time in ms
local REPEAT_MS      = 5000   -- Sound repeat interval in ms

-- Sound files
local STAGE1_WAV = "/SCRIPTS/FUNCTIONS/sntnl/stage1.wav"
local STAGE2_WAV = "/SCRIPTS/FUNCTIONS/sntnl/stage2.wav"

-- Sensitivity limits in dBm per RFMD (see elrs_modes.md).
-- Entries with 0 dBm are intentional placeholders and produce a
-- permanent warning -- a hint that this mode still needs to be filled in.
local SENS_LIMIT = {
  -- 900 MHz / Sub-GHz
  [0]   = -123,
  [1]   = -120,
  [2]   = -117,
  [3]   = -112,
  [4]   = 0,
  [5]   = -112,
  [6]   = -111,
  [7]   = -111,
  [8]   = 0,
  [9]   = 0,
  [10]  = -112,
  [11]  = -101,
  -- 2.4 GHz
  [20]  = 0,
  [21]  = -115,
  [22]  = 0,
  [23]  = -112,
  [24]  = -112,
  [25]  = 0,
  [26]  = 0,
  [27]  = -108,
  [28]  = -105,
  [29]  = -105,
  [30]  = -104,
  [31]  = -104,
  [32]  = -104,
  [33]  = -104,
  [34]  = -103,
  [35]  = -103,
  [36]  = -103,
  -- GEMX / Crossband
  [100] = -112,
  [101] = -112,
}

-- Internal state
local currentRFMD   = nil
local warnThreshold = nil

local stage1 = { condSince = 0, active = false, lastPlay = 0 }
local stage2 = { condSince = 0, active = false, lastPlay = 0 }

local function nowMs()
  return getTime() * 10
end

local function resetStage(s)
  s.condSince = 0
  s.active    = false
  s.lastPlay  = 0
end

local function resetAll()
  currentRFMD   = nil
  warnThreshold = nil
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

  local rss1 = getValue("1RSS")
  local rss2 = getValue("2RSS")
  local rqly = getValue("RQly")

  -- Single-antenna receivers (e.g. RP1) report 2RSS as a constant 0.
  -- Treat 0 as "no second antenna" and base the decision on 1RSS only.
  local stage1Cond
  if rss2 ~= 0 then
    stage1Cond = (rss1 <= warnThreshold) and (rss2 <= warnThreshold)
  else
    stage1Cond = (rss1 <= warnThreshold)
  end
  local stage2Cond = stage1Cond and (rqly < RQLY_THRESHOLD)

  debounce(stage1, stage1Cond, now)
  debounce(stage2, stage2Cond, now)

  if stage2.active then
    -- Stage 2 takes precedence. The stage 1 repeat timer is intentionally
    -- not advanced so that stage 1 becomes audible again immediately
    -- once stage 2 ends.
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
