-- =====================================================================
-- manifest.lua  --  Link Sentinel as seen by the Flight Bag settings tool
-- =====================================================================
-- SD card path: /SCRIPTS/SNTNL/manifest.lua
-- Loaded only by the settings tool. Fields, sounds, resets and files by id;
-- their texts come from lang/<code>.lua (lang: "en" when left out). Ranges,
-- defaults, sound slots and the config file live in core.lua.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(core, lang)
  local L, D = core.LIMITS, core.DEFAULTS
  local T = core.texts(lang)
  local man = {
    name    = "Link Sentinel",
    author  = "Mariator-pro",
    license = "GPL-2.0",
    url     = "github.com/Mariator-pro/elrs-link-sentinel",
    -- ids never change once released: other programs recognise an entry by it
    paths = {
      { id = "core",   path = "/SCRIPTS/SNTNL/core.lua" },
      { id = "config", path = core.CONFIG_PATH },
      { id = "widget", path = "/WIDGETS/SNTNL/main.lua" },
      { id = "func",   path = "/SCRIPTS/FUNCTIONS/sntnl.lua" },
      { id = "sounds", path = core.SOUND_DIR },
    },

    fields = {
      { key = "warnOffsetDb", page = "warnings",
        min = L.warnOffsetDb.min, max = L.warnOffsetDb.max, step = L.warnOffsetDb.step,
        default = D.warnOffsetDb, prefix = "+", unit = "dB" },
      { key = "rqlyThreshold", page = "warnings",
        min = L.rqlyThreshold.min, max = L.rqlyThreshold.max, step = L.rqlyThreshold.step,
        default = D.rqlyThreshold, unit = "%" },
      { key = "audio", page = "alerts", shared = true, type = "bool", default = D.audio },
      { key = "haptic", page = "alerts", shared = true, type = "bool", default = D.haptic },
      { key = "hapticStrength", page = "alerts", shared = true,
        type = "choice", choices = { 1, 2, 3 }, default = D.hapticStrength },
      { key = "language", page = "display", shared = true,
        type = "choice", choices = core.LANGUAGES, default = D.language },
    },

    -- Rows on the Alerts page, in core.SOUND_KEYS order
    sounds = {},

    resets = {
      { id = "settings", run = core.resetSettings },
    },
  }

  -- The texts, in the shape the settings tool reads: a file as { label, path },
  -- a field's label, hint (%v: its value) and labels of its choices.
  for _, p in ipairs(man.paths) do p[1], p[2] = T("files", p.id) or p.id, p.path end
  for _, f in ipairs(man.fields) do
    f.label = T("fields", f.key, "label") or f.key
    local hint = T("fields", f.key, "hint")
    if hint then f.hint = string.gsub(hint, "{v}", "%%v") end
    if f.choices then
      f.labels = {}
      for i, c in ipairs(f.choices) do f.labels[i] = T("fields", f.key, "choices", c) or tostring(c) end
    end
  end
  for _, key in ipairs(core.SOUND_KEYS) do
    man.sounds[key] = { label = T("sounds", key, "label") or key, hint = T("sounds", key, "hint") }
  end
  for _, r in ipairs(man.resets) do
    r.label = T("resets", r.id, "label") or r.id
    r.ask, r.desc = T("resets", r.id, "ask"), T("resets", r.id, "desc")
  end
  return man
end
