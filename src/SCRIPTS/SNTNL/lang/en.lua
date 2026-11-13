-- =====================================================================
-- lang/en.lua  --  English texts of Link Sentinel in the Flight Bag tool
-- =====================================================================
-- SD card path: /SCRIPTS/SNTNL/lang/en.lua
-- Every text by area and id; the complete set and the fallback of the
-- other languages. {name} is a placeholder. Plain quotes and dots only:
-- the radio's font has no typographic ones.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return {
  fields = {
    warnOffsetDb   = { label = "Link quality low", hint = "Early warning {v} before the RSSI limit (1RSS/2RSS)" },
    rqlyThreshold  = { label = "Link quality critical", hint = "Critical alert when RQly drops below {v}" },
    audio          = { label = "Sounds", hint = "Off silences every announcement, vibration stays" },
    haptic         = { label = "Vibration" },
    hapticStrength = { label = "Strength", choices = { "Soft", "Normal", "Strong" } },
    language       = { label = "Language", hint = "Language of Flight Bag",
                       choices = { en = "English", de = "Deutsch" } },
  },
  sounds = {
    stage1 = { label = "Link quality low", hint = "Signal close to the limit" },
    stage2 = { label = "Link quality critical", hint = "Signal at the limit and link quality low" },
    lost   = { label = "Link lost", hint = "Link gone in flight (off by default)" },
    conn   = { label = "Link connected", hint = "Link up for a new flight (off by default)" },
    rec    = { label = "Link recovered", hint = "Link back after a loss in flight (off by default)" },
  },
  resets = {
    settings = { label = "Reset settings", ask = "Reset Link Sentinel's settings?",
                 desc = "All Link Sentinel settings go back to their defaults, it stores nothing else. The settings for all apps (Sounds, Vibration, Language) stay." },
  },
  setup = {
    damaged        = "Settings file damaged",
    missingSensors = "Missing sensors: {sensors}",
    checkSensors   = "Check sensors config",
  },
  files = { core = "Core", config = "Config", widget = "Widget", func = "Func", sounds = "Sounds" },
}
