-- =====================================================================
-- manifest.lua  --  Link Sentinel as seen by the Flight Bag settings tool
-- =====================================================================
-- SD card path: /SCRIPTS/SNTNL/manifest.lua
-- Loaded only by the settings tool. Labels and hints live here; ranges,
-- defaults, sound slots and the config file live in core.lua.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(core)
  local L, D = core.LIMITS, core.DEFAULTS
  return {
    name  = "Link Sentinel",
    url   = "github.com/Mariator-pro/elrs-link-sentinel",
    paths = {
      { "Core",   "/SCRIPTS/SNTNL/core.lua" },
      { "Config", core.CONFIG_PATH },
      { "Widget", "/WIDGETS/SNTNL/main.lua" },
      { "Func",   "/SCRIPTS/FUNCTIONS/sntnl.lua" },
      { "Sounds", core.SOUND_DIR },
    },

    fields = {
      { key = "warnOffsetDb", page = "warnings", label = "Link quality low",
        min = L.warnOffsetDb.min, max = L.warnOffsetDb.max, step = L.warnOffsetDb.step,
        default = D.warnOffsetDb, prefix = "+", unit = "dB",
        hint = "Early warning %v before the RSSI (1RSS/2RSS) limit" },
      { key = "rqlyThreshold", page = "warnings", label = "Link quality critical",
        min = L.rqlyThreshold.min, max = L.rqlyThreshold.max, step = L.rqlyThreshold.step,
        default = D.rqlyThreshold, unit = "%",
        hint = "Critical alert when RQly drops below %v" },
      { key = "audio", page = "alerts", label = "Sounds", shared = true,
        type = "bool", default = D.audio, hint = "Off silences every announcement, vibration stays" },
      { key = "haptic", page = "alerts", label = "Vibration", shared = true,
        type = "bool", default = D.haptic },
      { key = "hapticStrength", page = "alerts", label = "Strength", shared = true,
        type = "choice", choices = { 1, 2, 3 }, labels = { "Soft", "Normal", "Strong" },
        default = D.hapticStrength },
    },

    -- Rows on the Alerts page, in core.SOUND_KEYS order
    sounds = {
      stage1 = { label = "Link quality low", hint = "Signal close to the limit" },
      stage2 = { label = "Link quality critical", hint = "Signal at the limit and link quality low" },
      lost   = { label = "Link lost", hint = "Link gone in flight (off by default)" },
      conn   = { label = "Link connected", hint = "Link up for a new flight (off by default)" },
      rec    = { label = "Link recovered", hint = "Link back after a loss in flight (off by default)" },
    },

    resets = {
      { label = "Reset settings", ask = "Reset Link Sentinel settings to factory defaults?",
        run = core.resetSettings },
    },
  }
end
