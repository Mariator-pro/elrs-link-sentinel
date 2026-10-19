-- =====================================================================
-- settings_model.lua  --  Values of a Flight Bag topic page (no drawing)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/settings_model.lua
-- Gathers the manifest fields of every app for one topic (ctx.id) into one
-- list of rows: the shared fields once on top, then a block per app. Alerts
-- adds the sound rows. save() writes each app through its core. Used by both
-- Flight Bag tools (settings.lua, LVGL/settings.lua).
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

local SND_DEFAULT = 2

-- Sorted *.wav names in `folder` (no trailing slash), without the `skip` names and
-- dot files (macOS "._name.wav" companions). pcall: dir() raises when the folder
-- is missing. Free string functions: EdgeTX has no string methods.
local function listWavs(folder, skip)
  local files = {}
  pcall(function()
    for fname in dir(folder) do
      if type(fname) == "string" and string.match(string.lower(fname), "%.wav$")
         and string.sub(fname, 1, 1) ~= "." and not (skip and skip[fname]) then
        files[#files + 1] = fname
      end
    end
  end)
  table.sort(files, function(a, b) return string.lower(a) < string.lower(b) end)
  return files
end

-- Vibration preview for a Play button: `pulses` pulses at the given strength.
local function testHaptic(on, strength, dur, pulses)
  if not on or not playHaptic or not dur then return end
  local d = dur[strength] or dur[2]
  for i = 1, pulses or 1 do
    playHaptic(d, (i < (pulses or 1)) and d or 0)
  end
end

return function(ctx)
  local id = ctx.id
  local M = {
    rows    = {},      -- { kind = "shared"|"head"|"fix"|"field"|"sound", ... }
    touched = false,   -- a value changed since the page opened
  }
  local blocks = {}   -- per app: { app, man, core, cfg, err, v = values, snd = sounds }
  local shared = {}   -- key -> { field, blocks, value (nil = mixed) }
  local sharedOrder = {}

  local function copySounds(cfg)
    local s = {}
    for k, v in pairs(cfg.sounds or {}) do s[k] = v end
    return s
  end

  local function pageFields(man)
    local out = {}
    for _, f in ipairs(man.fields or {}) do
      if f.page == id then out[#out + 1] = f end
    end
    return out
  end

  local function hasContent(b)
    return #pageFields(b.man) > 0 or (id == "alerts" and b.core.SOUND_KEYS and #b.core.SOUND_KEYS > 0)
  end

  local function nameOf(b) return b.man.name or b.app.folder end

  -- Current value of field key in a block (a shared value overrides once chosen).
  local function valueOf(b, key)
    local s = shared[key]
    if s and s.blocks[b] and s.value ~= nil then return s.value end
    return b.v[key]
  end

  -- All current values of a block, for unit functions and check().
  local function valuesOf(b)
    local v = {}
    for k, x in pairs(b.v) do v[k] = x end
    for key, s in pairs(shared) do
      if s.blocks[b] and s.value ~= nil then v[key] = s.value end
    end
    return v
  end

  local function unitOf(b, f)
    if type(f.unit) == "function" then
      local ok, u = pcall(f.unit, valuesOf(b))
      return ok and u or nil
    end
    return f.unit
  end

  local function formatValue(b, f, val)
    if val == nil then return "Mixed" end
    if f.type == "bool" then return val and "On" or "Off" end
    if f.type == "choice" then
      for i, c in ipairs(f.choices or {}) do
        if c == val then return (f.labels and f.labels[i]) or tostring(c) end
      end
      return tostring(val)
    end
    if f.off ~= nil and val == f.off then return "Off" end
    local u = unitOf(b, f)
    return (f.prefix or "") .. tostring(val) .. (u and (" " .. u) or "")
  end

  -- A block a row belongs to; a shared row stands for any of its blocks.
  local function blockOf(r)
    if r.kind == "shared" then return next(shared[r.key].blocks) end
    return r.block
  end

  -- ---------------------------------------------------------------------------
  -- Rows
  -- ---------------------------------------------------------------------------

  local function build()
    blocks, shared, sharedOrder = {}, {}, {}
    for _, app in ipairs(ctx.apps) do
      local b = { app = app, man = app.man, core = app.core, cfg = app.cfg, err = app.err }
      if hasContent(b) then
        b.v, b.snd = {}, {}
        if b.cfg then
          for _, f in ipairs(b.man.fields or {}) do b.v[f.key] = b.cfg[f.key] end
          b.snd = copySounds(b.cfg)
        end
        blocks[#blocks + 1] = b
      end
    end
    -- Shared fields of this page: one entry per key, value nil while they differ.
    for _, b in ipairs(blocks) do
      if b.cfg then
        for _, f in ipairs(pageFields(b.man)) do
          if f.shared then
            local s = shared[f.key]
            if not s then
              s = { field = f, blocks = {}, first = true }
              shared[f.key] = s
              sharedOrder[#sharedOrder + 1] = f.key
            end
            s.blocks[b] = true
            local v = b.cfg[f.key]
            if s.first then s.value, s.first = v, false
            elseif s.value ~= v then s.value = nil end
          end
        end
      end
    end
  end

  -- Rows in display order. `off` rows (Strength while vibration is off, sound
  -- rows while Sounds is off) stay visible, greyed out and not selectable.
  function M.layout()
    local rows = {}
    local function add(r) rows[#rows + 1] = r end
    for _, key in ipairs(sharedOrder) do
      add({ kind = "shared", key = key, field = shared[key].field })
    end
    for _, b in ipairs(blocks) do
      add({ kind = "head", text = nameOf(b), top = #rows > 0 })
      if b.err == "missing" then
        add({ kind = "fix", block = b, text = "No settings file yet", button = "Create" })
      elseif b.err then
        add({ kind = "fix", block = b, text = "Settings file damaged", button = "Reset" })
      else
        for _, f in ipairs(pageFields(b.man)) do
          if not f.shared then add({ kind = "field", block = b, field = f }) end
        end
        if id == "alerts" then
          for _, key in ipairs(b.core.SOUND_KEYS or {}) do
            local m = (b.man.sounds or {})[key] or {}
            add({ kind = "sound", block = b, key = key, label = m.label or key, hint = m.hint })
          end
        end
      end
    end
    M.rows = rows
    M.refreshOff()
  end

  -- Re-evaluates the `off` flags after a value change.
  function M.refreshOff()
    for _, r in ipairs(M.rows) do
      if r.kind == "shared" and r.key == "hapticStrength" then
        r.off = shared.haptic ~= nil and shared.haptic.value == false
      elseif r.kind == "sound" then
        r.off = valueOf(r.block, "audio") == false
      end
    end
  end

  -- ---------------------------------------------------------------------------
  -- Values
  -- ---------------------------------------------------------------------------

  function M.getValue(r)
    if r.kind == "shared" then return shared[r.key].value end
    return valueOf(r.block, r.field.key)
  end

  -- Sets a value while it is being edited (no change recorded yet).
  function M.setRaw(r, val)
    if r.kind == "shared" then shared[r.key].value = val else r.block.v[r.field.key] = val end
  end

  -- Only a different value counts as a change: EdgeTX's toggle reports its
  -- unchanged value again on RTN.
  function M.setValue(r, val)
    if val ~= M.getValue(r) then M.touched = true end
    M.setRaw(r, val)
    M.refreshOff()   -- Strength follows Vibration, the sound rows follow Sounds
  end

  -- Shown value text; second result true while a shared value differs per app.
  function M.rowValue(r)
    local val = M.getValue(r)
    return formatValue(blockOf(r), r.field, val), r.kind == "shared" and val == nil
  end

  -- Value text of any value of the row's field (for number displays).
  function M.format(r, val) return formatValue(blockOf(r), r.field, val) end

  -- Hint of a row with %v filled in, or nil.
  function M.hintOf(r)
    if not r then return nil end
    if r.kind == "shared" and shared[r.key].value == nil then
      return "Set differently per script, choose again"
    end
    local h = r.hint or (r.field and r.field.hint)
    if not h then return nil end
    if r.field then
      local text = formatValue(blockOf(r), r.field, M.getValue(r))
      h = string.gsub(h, "%%v", (string.gsub(text, "%%", "%%%%")))
    end
    return h
  end

  -- Labels of a choice field and the index of the row's value (1 when none matches).
  function M.choiceLabels(f)
    local labels = {}
    for i, c in ipairs(f.choices) do labels[i] = (f.labels and f.labels[i]) or tostring(c) end
    return labels
  end

  function M.choiceIndex(r)
    local val = M.getValue(r)
    for i, c in ipairs(r.field.choices) do if c == val then return i end end
    return 1
  end

  -- ---------------------------------------------------------------------------
  -- Sounds
  -- ---------------------------------------------------------------------------

  -- Sound options of a block: Off, Default, then the user's files.
  function M.soundOptions(b)
    if b.opts then return b.opts end
    local core, skip = b.core, {}
    for _, name in pairs(core.SOUND_DEFAULTS or {}) do skip[name] = true end
    local opts = { { label = "Off", name = false }, { label = "Default", name = nil } }
    for _, fname in ipairs(listWavs(string.gsub(core.SOUND_DIR, "/$", ""), skip)) do
      opts[#opts + 1] = { label = fname, name = fname }
    end
    b.opts = opts
    return opts
  end

  function M.soundLabels(b)
    local labels = {}
    for i, o in ipairs(M.soundOptions(b)) do labels[i] = o.label end
    return labels
  end

  function M.soundIndex(r)
    local v = r.block.snd[r.key]
    if v == false then return 1 end
    if type(v) == "string" then
      for i, o in ipairs(M.soundOptions(r.block)) do if o.name == v then return i end end
    end
    return SND_DEFAULT
  end

  function M.setSound(r, i)
    if i ~= M.soundIndex(r) then M.touched = true end
    r.block.snd[r.key] = M.soundOptions(r.block)[i].name
  end

  function M.isMuted(r) return r.block.snd[r.key] == false end

  -- Plays the row's sound with the app's vibration pulses.
  function M.playTest(r)
    local b = r.block
    local v = b.snd[r.key]
    if v == false then return end
    if type(v) ~= "string" then v = b.core.SOUND_DEFAULTS[r.key] end
    if not v then return end
    playFile(b.core.SOUND_DIR .. v)
    local strength = valueOf(b, "hapticStrength") or 2
    testHaptic(valueOf(b, "haptic") == true, strength, b.core.HAPTIC_DUR, (b.core.HAPTIC_PULSES or {})[r.key])
  end

  -- ---------------------------------------------------------------------------
  -- Files
  -- ---------------------------------------------------------------------------

  -- Writes factory settings for a fix row; true on success. Idempotent.
  function M.fixWrite(r)
    return r.block.core.saveConfig(r.block.core.defaultConfig())
  end

  -- Re-reads one app after its file was created or reset.
  function M.reload(r)
    local b = r.block
    b.app.cfg, b.app.err = b.core.loadConfig()
    build()
    M.layout()
  end

  -- Writes every app; returns a list of problems (empty when all are saved).
  function M.save()
    local problems = {}
    for _, b in ipairs(blocks) do
      if b.cfg then
        local v = valuesOf(b)
        local msg = b.man.check and b.man.check(v)
        if msg then
          problems[#problems + 1] = nameOf(b) .. ": " .. msg
        else
          local cfg = b.cfg
          for _, f in ipairs(b.man.fields or {}) do
            local s = shared[f.key]
            if s and s.blocks[b] then
              if s.value ~= nil then cfg[f.key] = s.value end   -- mixed stays per app
            elseif v[f.key] ~= nil then
              cfg[f.key] = v[f.key]
            end
          end
          cfg.sounds = cfg.sounds or {}
          for _, key in ipairs(b.core.SOUND_KEYS or {}) do cfg.sounds[key] = b.snd[key] end
          if not b.core.saveConfig(cfg) then
            problems[#problems + 1] = nameOf(b) .. ": save failed, check SD card"
          end
        end
      end
    end
    return problems
  end

  build()
  M.layout()
  return M
end
