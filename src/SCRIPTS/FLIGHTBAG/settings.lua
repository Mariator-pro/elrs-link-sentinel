-- =====================================================================
-- settings.lua  --  Flight Bag topic page (Warnings, Alerts, Display)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/settings.lua
-- Gathers the manifest fields of every app for one topic (ctx.id) into one
-- list: the shared fields once on top, then a block per app. Alerts adds the
-- sound rows. Save writes each changed app through its core.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

local SND_OFF, SND_DEFAULT = 1, 2

return function(ctx)
  local ui, id = ctx.ui, ctx.id
  local TEST_X = math.floor(LCD_W * 0.74)

  local blocks = {}   -- per app: { app, man, core, cfg, err, v = values, snd = sounds }
  local shared = {}   -- key -> { field, blocks, value (nil = mixed), touched }
  local sharedOrder = {}
  local rows, sel = {}, {}   -- display rows; indices of the selectable ones
  local cursor = 1
  local editing, editOrig    -- number field being edited
  local dive                 -- sound row dived into: "snd" | "test"
  local touched = false

  -- ---------------------------------------------------------------------------
  -- Values
  -- ---------------------------------------------------------------------------

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

  -- Sound options of a block: Off, Default, then the user's files.
  local function soundOptions(b)
    if b.opts then return b.opts end
    local core, skip = b.core, {}
    for _, name in pairs(core.SOUND_DEFAULTS or {}) do skip[name] = true end
    local opts = { { label = "Off", name = false }, { label = "Default", name = nil } }
    for _, fname in ipairs(ui.listWavs(string.gsub(core.SOUND_DIR, "/$", ""), skip)) do
      opts[#opts + 1] = { label = fname, name = fname }
    end
    b.opts = opts
    return opts
  end

  local function soundIndex(b, key)
    local v = b.snd[key]
    if v == false then return SND_OFF end
    if type(v) == "string" then
      for i, o in ipairs(soundOptions(b)) do if o.name == v then return i end end
    end
    return SND_DEFAULT
  end

  local function soundPath(b, key)
    local v = b.snd[key]
    if v == false then return nil end
    if type(v) ~= "string" then v = b.core.SOUND_DEFAULTS[key] end
    return v and (b.core.SOUND_DIR .. v)
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

  local function layout()
    rows, sel = {}, {}
    local function add(r)
      rows[#rows + 1] = r
      if r.kind ~= "head" and not r.off then sel[#sel + 1] = #rows end
    end
    for _, key in ipairs(sharedOrder) do
      local s = shared[key]
      -- Strength only matters while vibration is on: greyed out and skipped otherwise.
      local off = key == "hapticStrength" and shared.haptic and shared.haptic.value == false
      add({ kind = "shared", key = key, field = s.field, off = off })
    end
    for _, b in ipairs(blocks) do
      add({ kind = "head", text = b.man.name or b.app.folder, top = #rows > 0 })
      if b.err == "missing" then
        add({ kind = "fix", block = b, text = "No settings file yet", button = "Create" })
      elseif b.err then
        add({ kind = "fix", block = b, text = "Settings file damaged", button = "Reset" })
      else
        for _, f in ipairs(pageFields(b.man)) do
          if not f.shared then add({ kind = "field", block = b, field = f }) end
        end
        if id == "alerts" then
          -- With Sounds (audio) Off the app plays nothing: its sound rows stay
          -- visible but greyed out and are skipped by the cursor.
          local off = valueOf(b, "audio") == false
          for _, key in ipairs(b.core.SOUND_KEYS or {}) do
            local m = (b.man.sounds or {})[key] or {}
            add({ kind = "sound", block = b, key = key, label = m.label or key, hint = m.hint, off = off })
          end
        end
      end
    end
    cursor = math.min(cursor, #sel + 2)
  end

  build()
  layout()

  local function current() return sel[cursor] and rows[sel[cursor]] end

  -- ---------------------------------------------------------------------------
  -- Drawing
  -- ---------------------------------------------------------------------------

  local function rowValue(r)
    if r.kind == "shared" then
      local s = shared[r.key]
      local anyBlock = next(s.blocks)
      return formatValue(anyBlock, r.field, s.value), s.value == nil
    end
    return formatValue(r.block, r.field, valueOf(r.block, r.field.key)), false
  end

  local function drawRow(r, y, selected)
    local C = COLOR_THEME_PRIMARY1
    if r.kind == "head" then
      lcd.drawText(ui.COL1, y, r.text, C + BOLD)
    elseif r.kind == "fix" then
      lcd.drawText(ui.COL1, y, r.text, COLOR_THEME_WARNING)
      ui.drawButton(TEST_X, y - 2, r.button, selected)
    elseif r.kind == "sound" then
      local b = r.block
      local dived = selected and dive
      if r.off then C = COLOR_THEME_DISABLED end
      lcd.drawText(ui.COL1, y, r.label, C + ((selected and not dived) and INVERS or 0))
      local opt = soundOptions(b)[soundIndex(b, r.key)]
      local vx  = ui.drawArrowBefore(ui.COL2, y, C)
      lcd.drawText(vx, y, opt.label, C + ((dived == "snd") and INVERS or 0))
      ui.drawButton(TEST_X, y - 2, "Play", dived == "test", opt.name == false or r.off)
    else
      local text, mixed = rowValue(r)
      local isEdit = selected and editing
      ui.drawFieldRowY(y, r.field.label, text, {
        selected = selected, editing = isEdit, disabled = r.off,
        popup = r.field.type == "choice",
        valueFlags = (mixed and not r.off) and COLOR_THEME_WARNING or nil,
      })
    end
  end

  local function hintOf(r)
    if not r then return nil end
    if r.kind == "shared" and shared[r.key].value == nil then
      return "Set differently per script, choose again"
    end
    local h = r.hint or (r.field and r.field.hint)
    if not h then return nil end
    if r.field then
      local val   -- no and/or: a shared false (Off) must not fall through to valueOf
      if r.kind == "shared" then val = shared[r.key].value else val = valueOf(r.block, r.field.key) end
      local text = formatValue(r.block or next(shared[r.key].blocks), r.field, val)
      h = string.gsub(h, "%%v", (string.gsub(text, "%%", "%%%%")))
    end
    return h
  end

  local function draw()
    ui.drawHeader(string.upper(ctx.title))
    local LINE = ui.LINE
    local _, sh = lcd.sizeText("Mg", SMLSIZE)
    local hint  = hintOf(current())
    local bottom = ui.barTopY() - (hint and (sh + 8) or 0)
    local top0   = ui.bodyY(1)
    local fit    = math.max(1, math.floor((bottom - top0) / LINE))
    if #rows == 0 then
      lcd.drawText(ui.COL1, top0, "Nothing to set here.", COLOR_THEME_PRIMARY1)
    end
    local focus = sel[cursor] or #rows
    local start = math.max(1, math.min(focus - math.floor(fit / 2), #rows - fit + 1))
    for i = 0, fit - 1 do
      local idx = start + i
      if rows[idx] then drawRow(rows[idx], top0 + i * LINE, sel[cursor] == idx) end
    end
    if #rows > fit then ui.drawScrollbar(LCD_W - ui.PAD - 3, top0, fit, start, #rows) end
    if hint then ui.drawHint(hint) end
    ui.drawButtonBar({ "Back", "Save" }, #sel + 1, cursor)
  end

  -- ---------------------------------------------------------------------------
  -- Editing
  -- ---------------------------------------------------------------------------

  local function setValue(r, val)
    if r.kind == "shared" then shared[r.key].value = val
    else r.block.v[r.field.key] = val end
    touched = true
    layout()   -- Strength follows Vibration, the sound rows follow Sounds
  end

  local function getValue(r)
    if r.kind == "shared" then return shared[r.key].value end
    return valueOf(r.block, r.field.key)
  end

  local function startEdit(r)
    local f, val = r.field, getValue(r)
    if f.type == "bool" then
      setValue(r, not (val == true))
    elseif f.type == "choice" then
      local cur = 1
      for i, c in ipairs(f.choices) do if c == val then cur = i end end
      local labels = {}
      for i, c in ipairs(f.choices) do labels[i] = (f.labels and f.labels[i]) or tostring(c) end
      ui.openPicker(f.label, labels, cur, function(i) setValue(r, f.choices[i]) end)
    else
      if val == nil then val = f.default or f.min end
      editing, editOrig = true, getValue(r)
      if r.kind == "shared" then shared[r.key].value = val else r.block.v[f.key] = val end
    end
  end

  local function stepEdit(r, e)
    local f = r.field
    local val = getValue(r)
    local step = f.step or 1
    if ui.isNext(e) then val = math.min(f.max, val + step)
    elseif ui.isPrev(e) then val = math.max(f.min, val - step) end
    if r.kind == "shared" then shared[r.key].value = val else r.block.v[f.key] = val end
    if ui.isEnter(e) then editing = nil; touched = true
    elseif ui.isExit(e) then
      if r.kind == "shared" then shared[r.key].value = editOrig else r.block.v[f.key] = editOrig end
      editing = nil
    end
  end

  local function playTest(r)
    local b = r.block
    local path = soundPath(b, r.key)
    if not path then return end
    playFile(path)
    local on = valueOf(b, "haptic")
    local strength = valueOf(b, "hapticStrength") or 2
    ui.testHaptic(on == true, strength, b.core.HAPTIC_DUR, (b.core.HAPTIC_PULSES or {})[r.key])
  end

  local function handleSound(r, e)
    local b = r.block
    if ui.isNext(e) or ui.isPrev(e) then
      local muted = b.snd[r.key] == false
      dive = (dive == "snd" and not muted) and "test" or "snd"
    elseif ui.isEnter(e) then
      if dive == "snd" then
        local labels = {}
        for i, o in ipairs(soundOptions(b)) do labels[i] = o.label end
        ui.openPicker(r.label .. " sound", labels, soundIndex(b, r.key), function(i)
          b.snd[r.key] = soundOptions(b)[i].name
          touched = true
        end)
      else
        playTest(r)
      end
    elseif ui.isExit(e) then
      dive = nil
    end
  end

  -- Re-reads one app after its file was created or reset.
  local function reloadBlock(b)
    b.app.cfg, b.app.err = b.core.loadConfig()
    build()
    layout()
  end

  local function fixFile(r)
    local b = r.block
    local function write()
      return b.core.saveConfig(b.core.defaultConfig())
    end
    if r.button == "Create" then
      ui.withRetry(write, function() reloadBlock(b) end)
    else
      ui.openDialog("Replace the damaged settings file with factory settings?", function()
        ui.withRetry(write, function() reloadBlock(b) end)
      end)
    end
  end

  -- Writes every app with changes; returns true when all are saved.
  local function save()
    local problems = {}
    for _, b in ipairs(blocks) do
      if b.cfg then
        local v = valuesOf(b)
        local msg = b.man.check and b.man.check(v)
        if msg then
          problems[#problems + 1] = (b.man.name or b.app.folder) .. ": " .. msg
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
            problems[#problems + 1] = (b.man.name or b.app.folder) .. ": save failed, check SD card"
          end
        end
      end
    end
    if #problems > 0 then
      ui.openAlert(table.concat(problems, "\n"))
      return false
    end
    return true
  end

  local P = {}

  function P.draw() draw() end

  -- Returns true to close the page.
  function P.handle(e)
    local r = current()
    if editing and r then stepEdit(r, e); return false end
    if dive and r then handleSound(r, e); return false end
    local count = #sel + 2
    cursor = ui.moveCursor(cursor, e, count)
    if ui.isEnter(e) then
      if cursor == #sel + 1 then                      -- Back
        if touched then ui.openDialog("Discard changes?", function() P.close = true end)
        else return true end
      elseif cursor == #sel + 2 then                  -- Save
        if save() then return true end
      elseif r then
        if r.kind == "sound" then dive = "snd"
        elseif r.kind == "fix" then fixFile(r)
        else startEdit(r) end
      end
    elseif ui.isExit(e) then
      if touched then ui.openDialog("Discard changes?", function() P.close = true end)
      else return true end
    end
    return P.close == true
  end

  return P
end
