-- =====================================================================
-- settings.lua  --  Flight Bag topic page (Warnings, Alerts, Display)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/settings.lua
-- Drawn view of settings_model.lua: one list with the shared fields on top,
-- then a block per app; Back and Save at the bottom.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local ui = ctx.ui
  local TEST_X = math.floor(LCD_W * 0.74)
  local M = loadScript("/SCRIPTS/FLIGHTBAG/settings_model.lua")()(ctx)
  local sel = {}             -- indices of the selectable rows
  local cursor = 1
  local editing, editOrig    -- number field being edited
  local dive                 -- sound row dived into: "snd" | "test"

  -- Selectable rows: not the block heads, not the greyed-out ones.
  local function refresh()
    sel = {}
    for i, r in ipairs(M.rows) do
      if r.kind ~= "head" and not r.off then sel[#sel + 1] = i end
    end
    cursor = math.min(cursor, #sel + 2)
  end
  refresh()

  local function current() return sel[cursor] and M.rows[sel[cursor]] end

  -- ---------------------------------------------------------------------------
  -- Drawing
  -- ---------------------------------------------------------------------------

  local function drawRow(r, y, selected)
    local C = COLOR_THEME_PRIMARY1
    if r.kind == "head" then
      lcd.drawText(ui.COL1, y, r.text, C + BOLD)
    elseif r.kind == "fix" then
      lcd.drawText(ui.COL1, y, r.text, COLOR_THEME_WARNING)
      ui.drawButton(TEST_X, y - 2, r.button, selected)
    elseif r.kind == "sound" then
      local dived = selected and dive
      if r.off then C = COLOR_THEME_DISABLED end
      lcd.drawText(ui.COL1, y, r.label, C + ((selected and not dived) and INVERS or 0))
      local vx  = ui.drawArrowBefore(ui.COL2, y, C)
      lcd.drawText(vx, y, M.soundLabels(r.block)[M.soundIndex(r)], C + ((dived == "snd") and INVERS or 0))
      ui.drawButton(TEST_X, y - 2, "Play", dived == "test", M.isMuted(r) or r.off)
    else
      local text, mixed = M.rowValue(r)
      local isEdit = selected and editing
      ui.drawFieldRowY(y, r.field.label, text, {
        selected = selected, editing = isEdit, disabled = r.off,
        popup = r.field.type == "choice",
        valueFlags = (mixed and not r.off) and COLOR_THEME_WARNING or nil,
      })
    end
  end

  local function draw()
    local rows = M.rows
    ui.drawHeader(string.upper(ctx.title))
    local LINE = ui.LINE
    local _, sh = lcd.sizeText("Mg", SMLSIZE)
    local hint  = M.hintOf(current())
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
    M.setValue(r, val)
    refresh()
  end

  local function startEdit(r)
    local f, val = r.field, M.getValue(r)
    if f.type == "bool" then
      setValue(r, not (val == true))
    elseif f.type == "choice" then
      ui.openPicker(f.label, M.choiceLabels(f), M.choiceIndex(r), function(i) setValue(r, f.choices[i]) end)
    else
      editing, editOrig = true, val
      if val == nil then M.setRaw(r, f.default or f.min) end
    end
  end

  local function stepEdit(r, e)
    local f = r.field
    local val = M.getValue(r)
    local step = f.step or 1
    if ui.isNext(e) then val = math.min(f.max, val + step)
    elseif ui.isPrev(e) then val = math.max(f.min, val - step) end
    M.setRaw(r, val)
    if ui.isEnter(e) then editing = nil; M.touched = true
    elseif ui.isExit(e) then M.setRaw(r, editOrig); editing = nil end
  end

  local function handleSound(r, e)
    if ui.isNext(e) or ui.isPrev(e) then
      dive = (dive == "snd" and not M.isMuted(r)) and "test" or "snd"
    elseif ui.isEnter(e) then
      if dive == "snd" then
        ui.openPicker(r.label .. " sound", M.soundLabels(r.block), M.soundIndex(r),
                      function(i) M.setSound(r, i) end)
      else
        M.playTest(r)
      end
    elseif ui.isExit(e) then
      dive = nil
    end
  end

  local function fixFile(r)
    local function write() return M.fixWrite(r) end
    local function done() M.reload(r); refresh() end
    if r.button == "Create" then
      ui.withRetry(write, done)
    else
      ui.openDialog("Replace the damaged settings file with factory settings?", function()
        ui.withRetry(write, done)
      end)
    end
  end

  -- True when every app is saved; otherwise the problems are shown.
  local function save()
    local problems = M.save()
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
        if M.touched then ui.openDialog("Discard changes?", function() P.close = true end)
        else return true end
      elseif cursor == #sel + 2 then                  -- Save
        if save() then return true end
      elseif r then
        if r.kind == "sound" then dive = "snd"
        elseif r.kind == "fix" then fixFile(r)
        else startEdit(r) end
      end
    elseif ui.isExit(e) then
      if M.touched then ui.openDialog("Discard changes?", function() P.close = true end)
      else return true end
    end
    return P.close == true
  end

  return P
end
