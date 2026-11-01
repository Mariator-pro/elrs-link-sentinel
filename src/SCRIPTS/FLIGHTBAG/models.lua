-- =====================================================================
-- models.lua  --  Flight Bag page "Models" (Lipo Nanny, Wingman)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/models.lua
-- Drawn view of models_model.lua: list, model editor (cells, parallel packs),
-- battery assignment, the per-model sensor mapping, Wingman's module
-- switches and the model's SD logs.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local ui = ctx.ui
  local M = loadScript("/SCRIPTS/FLIGHTBAG/models_model.lua")()(ctx)
  local SENSOR_FIELDS, MODULES = M.SENSOR_FIELDS, M.MODULES
  local SENSOR_BACK = #SENSOR_FIELDS + 1
  local isNext, isPrev, isEnter, isExit = ui.isNext, ui.isPrev, ui.isEnter, ui.isExit

  local S = { screen = "list", cursor = 1 }
  local Screen, Nav = {}, {}

  -- Writes Lipo Nanny's and/or Wingman's file, then onDone.
  local function save(onDone, lipo, wing)
    local function saveWing()
      if wing then ui.withRetry(M.writeWing, onDone)
      elseif onDone then onDone() end
    end
    if lipo then ui.withRetry(M.writeLipo, saveWing) else saveWing() end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: list
  -- ---------------------------------------------------------------------------

  function Screen.drawList()
    ui.drawHeader("MODELS")
    local keys, active, addCurrent = M.list()
    if #keys == 0 and not active then
      lcd.drawText(ui.COL1, ui.bodyY(1), "No models configured.", COLOR_THEME_PRIMARY1)
    else
      local start, last = ui.scrollWindow(S.cursor, #keys, 1)
      local row = 0
      for i = start, last do
        row = row + 1
        local k = keys[i]
        ui.drawNavRow(row, M.name(k) .. (k == active and "   [active]" or ""), S.cursor == i, { folder = true })
      end
      ui.drawScrollbar(LCD_W - ui.PAD - 3, ui.bodyY(1), last - start + 1, start, #keys)
    end
    local actions = { "Back" }
    if addCurrent then actions[2] = "[+] Add current model" end
    ui.drawButtonBar(actions, #keys + 1, S.cursor)
  end

  function Screen.handleList(e)
    local keys, _, addCurrent = M.list()
    S.cursor = ui.moveCursor(S.cursor, e, #keys + 1 + (addCurrent and 1 or 0))
    if isEnter(e) then
      if S.cursor <= #keys then Nav.enterModel(keys[S.cursor])
      elseif S.cursor == #keys + 1 then return true
      elseif addCurrent then Nav.enterModel(nil) end
    elseif isExit(e) then
      return true
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: model editor (Lipo Nanny's rows, Wingman's row, buttons)
  -- ---------------------------------------------------------------------------

  function Nav.enterModel(key)
    M.open(key)
    S.modelCursor, S.modelEditing = 1, false
    S.screen = "model"
  end

  function Screen.drawModel()
    local m = M.model
    ui.drawHeader((M.isNew and "ADD MODEL  " or "EDIT MODEL  ") .. M.name(m.filename))
    local rows = M.rows()
    for i, id in ipairs(rows) do
      local sel = S.modelCursor == i
      if id == "cells" then
        ui.drawFieldRow(i, "Cells", m.cells .. "S", { selected = sel, editing = S.modelEditing })
      elseif id == "parallel" then
        ui.drawFieldRow(i, "Parallel packs", m.parallel and "Yes" or "No", { selected = sel })
      elseif id == "batteries" then
        ui.drawFieldRow(i, "Batteries", #m.batteryIds .. " selected", { selected = sel, folder = true })
      elseif id == "sensors" then
        ui.drawFieldRow(i, "Sensors", M.sensorsAreCustom(m.sensors) and "custom" or "default",
                        { selected = sel, folder = true })
      elseif id == "modules" then
        ui.drawFieldRow(i, "Show in Wingman", M.modsText(), { selected = sel, folder = true })
      else
        ui.drawFieldRow(i, "SD logs", M.logsText(), { selected = sel, folder = M.isActive, disabled = not M.isActive })
      end
    end
    ui.drawButtonBar(M.isNew and { "Back", "Save" } or { "Back", "Save", "Delete" }, #rows + 1, S.modelCursor)
  end

  local function leaveModel() S.screen, S.cursor = "list", 1 end

  local function finishModelSave()
    local lipo, wing = M.commit()
    save(leaveModel, lipo, wing)
  end

  local function checkParallelSave()
    if M.parallelInvalid() then
      ui.openAlert("Parallel mode needs a profile with 2+ packs")
      return
    end
    finishModelSave()
  end

  -- Parallel mode only allows profiles with 2+ packs: unassign the others after
  -- confirmation, before the invariant check.
  local function proceedModelSave()
    local dropped = M.smallProfiles()
    if dropped == 0 then return checkParallelSave() end
    ui.openDialog("Parallel mode unassigns " .. M.batteries(dropped) .. " with < 2 packs. Continue?",
                  function() M.dropSmallProfiles(); checkParallelSave() end)
  end

  local function saveModel()
    local invalid = M.otherCells()
    if invalid > 0 then
      ui.openDialog("Changing cells unassigns " .. M.batteries(invalid) .. ". Continue?", function()
        M.dropOtherCells()
        proceedModelSave()
      end)
    else
      proceedModelSave()
    end
  end

  local function deleteModel()
    ui.openDialog("Delete model config for " .. M.name(M.model.filename) .. "?", function()
      local lipo, wing = M.delete()
      save(leaveModel, lipo, wing)
    end)
  end

  local function cancelModel()
    if M.dirty() then ui.openDialog("Discard changes?", leaveModel) else leaveModel() end
  end

  function Screen.handleModel(e)
    local m = M.model
    if S.modelEditing then
      local L = M.LIMITS.cells
      if isNext(e) then m.cells = math.min(L.max, m.cells + 1)
      elseif isPrev(e) then m.cells = math.max(L.min, m.cells - 1)
      elseif isEnter(e) or isExit(e) then S.modelEditing = false end
      return
    end
    local rows = M.rows()
    local n = #rows
    S.modelCursor = ui.moveCursor(S.modelCursor, e, n + (M.isNew and 2 or 3))
    if isEnter(e) then
      local c = S.modelCursor
      local id = rows[c]
      if id == "cells" then S.modelEditing = true
      elseif id == "parallel" then m.parallel = not m.parallel
      elseif id == "batteries" then S.assignItems, S.assignCursor, S.screen = M.assignItems(), 1, "assign"
      elseif id == "sensors" then M.openSensors(); S.sensorCursor, S.screen = 1, "sensors"
      elseif id == "modules" then S.modsCursor, S.screen = 1, "modules"
      elseif id == "logs" then
        if M.isActive then M.openLogs(); S.logsCursor, S.logsEditing, S.screen = 1, false, "logs" end
      elseif c == n + 1 then cancelModel()
      elseif c == n + 2 then saveModel()
      elseif c == n + 3 then deleteModel() end
    elseif isExit(e) then
      cancelModel()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: battery assignment (profiles of the model's cell count)
  -- ---------------------------------------------------------------------------

  local function applyAssign()
    M.applyAssign(S.assignItems)
    S.screen, S.modelCursor = "model", M.rowIndex("batteries")
  end

  function Screen.drawAssign()
    local m = M.model
    ui.drawHeader(m.parallel and ("SELECT " .. m.cells .. "S PARALLEL PROFILES")
                  or ("SELECT " .. m.cells .. "S BATTERIES"))
    if #S.assignItems == 0 then
      lcd.drawText(ui.COL1, ui.bodyY(1), "No matching profiles.", COLOR_THEME_PRIMARY1)
    end
    local start, last = ui.scrollWindow(S.assignCursor, #S.assignItems, 1)
    local row = 0
    for i = start, last do
      local it = S.assignItems[i]
      row = row + 1
      ui.drawNavRow(row, (it.checked and "[x] " or "[ ] ") .. it.name, S.assignCursor == i,
                    { disabled = not it.selectable })
    end
    ui.drawButtonBar({ "Back" }, #S.assignItems + 1, S.assignCursor)
  end

  function Screen.handleAssign(e)
    S.assignCursor = ui.moveCursor(S.assignCursor, e, #S.assignItems + 1)
    if isEnter(e) then
      local it = S.assignItems[S.assignCursor]
      if it then
        if it.selectable then it.checked = not it.checked end
      else
        applyAssign()
      end
    elseif isExit(e) then
      applyAssign()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: sensor mapping
  -- ---------------------------------------------------------------------------

  local function leaveSensors() S.screen, S.modelCursor = "model", M.rowIndex("sensors") end

  -- Help lines for the focused row, above the button bar.
  local function drawHelp(desc)
    local _, smH = lcd.sizeText("Mg", SMLSIZE)
    local pitch = smH + 4
    local dy = ui.barTopY() - #desc * pitch - 4
    for j, line in ipairs(desc) do
      local ly = dy + (j - 1) * pitch
      local tx = (j == 1) and ui.drawInfoBadge(ui.COL1, ly) or ui.COL1
      lcd.drawText(tx, ly, line, COLOR_THEME_PRIMARY1 + SMLSIZE)
    end
  end

  function Screen.drawSensors()
    ui.drawHeader("SENSORS  " .. M.name(M.model.filename))
    local _, smH = lcd.sizeText("Mg", SMLSIZE)
    local pitch  = smH + 4
    local y = ui.bodyY(1)
    for i, f in ipairs(SENSOR_FIELDS) do
      ui.drawFieldRowY(y, f.label, M.sensorValue(f), {
        selected = S.sensorCursor == i, disabled = not M.isActive, popup = M.isActive })
      y = y + ui.LINE
    end
    if M.isActive then
      drawHelp(SENSOR_FIELDS[math.min(S.sensorCursor, #SENSOR_FIELDS)].desc)
    else
      lcd.drawText(ui.COL1, ui.barTopY() - pitch - 4, "Activate this model to edit sensors.",
                   COLOR_THEME_PRIMARY1 + SMLSIZE)
    end
    ui.drawButtonBar(M.sensorsResetShown() and { "Back", "Reset to CRSF defaults" } or { "Back" },
                     SENSOR_BACK, S.sensorCursor)
  end

  local function openSensorPicker(c)
    local f = SENSOR_FIELDS[c]
    local labels, cur = M.sensorChoices(f)
    ui.openPicker(f.unit and f.label or (f.label .. " sensor"), labels, cur, function(i) M.setSensor(f, i) end)
  end

  function Screen.handleSensors(e)
    S.sensorCursor = ui.moveCursor(S.sensorCursor, e, SENSOR_BACK + (M.sensorsResetShown() and 1 or 0))
    if isEnter(e) then
      local c = S.sensorCursor
      if c < SENSOR_BACK then
        if M.isActive then openSensorPicker(c) end
      elseif c == SENSOR_BACK then
        leaveSensors()
      elseif M.sensorsResetShown() then
        M.resetSensors()
        S.sensorCursor = SENSOR_BACK
      end
    elseif isExit(e) then
      leaveSensors()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: Show in Wingman (module switches On/Off), stored with the model's Save
  -- ---------------------------------------------------------------------------

  local function leaveModules() S.screen, S.modelCursor = "model", M.rowIndex("modules") end

  function Screen.drawModules()
    local keys = M.moduleKeys()
    ui.drawHeader("SHOW IN WINGMAN  " .. M.name(M.model.filename))
    for i, k in ipairs(keys) do
      ui.drawFieldRow(i, MODULES[k].label, M.model.mods[k] and "On" or "Off", { selected = S.modsCursor == i })
    end
    drawHelp(MODULES[keys[math.min(S.modsCursor, #keys)]].desc)
    ui.drawButtonBar({ "Back" }, #keys + 1, S.modsCursor)
  end

  function Screen.handleModules(e)
    local keys = M.moduleKeys()
    S.modsCursor = ui.moveCursor(S.modsCursor, e, #keys + 1)
    if isEnter(e) then
      local k = keys[S.modsCursor]
      if k then M.model.mods[k] = not M.model.mods[k] else leaveModules() end
    elseif isExit(e) then
      leaveModules()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: SD logs (the model's "SD Logs" special function, changed at once)
  -- ---------------------------------------------------------------------------

  local function leaveLogs() S.screen, S.modelCursor = "model", M.rowIndex("logs") end

  -- Log, Arm switch (only for Armed), Interval; the buttons follow.
  local function logsRows() return M.logs.always and 2 or 3 end

  local function logsButtons()
    if M.logs.exists then return { "Back", "Apply", "Remove" } end
    return { "Back", "Set up" }
  end

  function Screen.drawLogs()
    ui.drawHeader("SD LOGS  " .. M.name(M.model.filename))
    local rows = logsRows()
    ui.drawFieldRow(1, "Log", M.LOG_MODES[M.logsMode()], { selected = S.logsCursor == 1, popup = true })
    if rows == 3 then
      ui.drawFieldRow(2, "Arm switch", M.logsArm(), { selected = S.logsCursor == 2, popup = true })
    end
    ui.drawFieldRow(rows, "Interval", M.intervalText(M.logs.interval),
                    { selected = S.logsCursor == rows, editing = S.logsEditing })
    local y = ui.bodyY(rows + 1)
    if M.logs.noTrigger then
      lcd.drawText(ui.COL1, y, "No trigger in the model", COLOR_THEME_WARNING)
      drawHelp({ "Without a switch EdgeTX never logs.", "Choose the arm switch and Apply." })
    elseif M.logs.disabled then
      lcd.drawText(ui.COL1, y, "Disabled in the model", COLOR_THEME_WARNING)
      drawHelp({ "The special function is switched off.", "Apply switches it on again." })
    elseif M.logs.exists then
      local found, total = M.logSensors()
      if total > 0 and found < total then
        lcd.drawText(ui.COL1, y, "Log sensors: " .. found .. " of " .. total .. " found",
                     COLOR_THEME_WARNING)
        drawHelp({ "Open Model > Telemetry and select", "Discover new sensors while the apps run." })
      elseif total > 0 then
        lcd.drawText(ui.COL1, y, "Log sensors: all " .. total .. " found", COLOR_THEME_PRIMARY1)
      end
    else
      drawHelp({ "Armed: one log file per flight.", "Always on: from power-on to power-off." })
    end
    ui.drawButtonBar(logsButtons(), rows + 1, S.logsCursor)
  end

  local function applyLogs()
    local ok, err = M.applyLogs()
    if ok then leaveLogs()
    elseif err == "switch" then ui.openAlert("Choose the arm switch first.")
    else ui.openAlert("No free special function. Remove one in the model.") end
  end

  local function cancelLogs()
    if M.logsDirty() then ui.openDialog("Discard changes?", leaveLogs) else leaveLogs() end
  end

  function Screen.handleLogs(e)
    if S.logsEditing then
      if isNext(e) then M.stepLogsInterval(1)
      elseif isPrev(e) then M.stepLogsInterval(-1)
      elseif isEnter(e) or isExit(e) then S.logsEditing = false end
      return
    end
    local rows = logsRows()
    S.logsCursor = ui.moveCursor(S.logsCursor, e, rows + #logsButtons())
    if isEnter(e) then
      local c = S.logsCursor
      if c == 1 then
        ui.openPicker("Log", M.LOG_MODES, M.logsMode(), function(i) M.setLogsMode(i) end)
      elseif c == rows then S.logsEditing = true
      elseif c == 2 then
        local labels, cur, ids = M.logsArmChoices()
        ui.openPicker("Arm switch", labels, cur, function(i) M.setLogsArm(ids[i]) end)
      elseif c == rows + 1 then cancelLogs()
      elseif c == rows + 2 then applyLogs()
      else
        ui.openDialog("Remove SD logs from this model?", function() M.removeLogs(); leaveLogs() end)
      end
    elseif isExit(e) then
      cancelLogs()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Page
  -- ---------------------------------------------------------------------------

  local P = {}

  function P.draw()
    if M.broken then
      ui.drawHeader("MODELS")
      lcd.drawText(ui.COL1, ui.bodyY(1), "Lipo Nanny has no usable settings file.", COLOR_THEME_WARNING)
      lcd.drawText(ui.COL1, ui.bodyY(2), "Fix it in the Lipo Nanny app (start page).", COLOR_THEME_PRIMARY1)
      ui.drawButtonBar({ "Back" }, 1, 1)
      return
    end
    if S.screen == "model" then Screen.drawModel()
    elseif S.screen == "assign" then Screen.drawAssign()
    elseif S.screen == "sensors" then Screen.drawSensors()
    elseif S.screen == "modules" then Screen.drawModules()
    elseif S.screen == "logs" then Screen.drawLogs()
    else Screen.drawList() end
  end

  -- Returns true to close the page.
  function P.handle(e)
    if M.broken then return isExit(e) or isEnter(e) end
    if S.screen == "model" then Screen.handleModel(e)
    elseif S.screen == "assign" then Screen.handleAssign(e)
    elseif S.screen == "sensors" then Screen.handleSensors(e)
    elseif S.screen == "modules" then Screen.handleModules(e)
    elseif S.screen == "logs" then Screen.handleLogs(e)
    else return Screen.handleList(e) == true end
    return false
  end

  return P
end
