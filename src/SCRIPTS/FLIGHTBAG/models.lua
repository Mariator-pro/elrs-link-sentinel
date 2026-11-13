-- =====================================================================
-- models.lua  --  Flight Bag page "Models" (Lipo Nanny, Wingman)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/models.lua
-- Drawn view of models_model.lua: list, model page, battery page (cells,
-- parallel packs), battery assignment, the per-model sensor mapping, Wingman's
-- module switches and the model's SD logs.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local ui = ctx.ui
  local lib = ctx.lib
  local function t(id, values) return lib.t("ui", id, values) end
  -- Button labels for a list of action ids.
  local function labels(ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = t(id) end
    return out
  end
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
    ui.drawHeader(lib.t("titles", "models"))
    local keys, active, addCurrent = M.list()
    if #keys == 0 and not active then
      lcd.drawText(ui.COL1, ui.bodyY(1), t("noModels"), COLOR_THEME_PRIMARY1)
    else
      local start, last = ui.scrollWindow(S.cursor, #keys, 1)
      local row = 0
      for i = start, last do
        row = row + 1
        local k = keys[i]
        ui.drawNavRow(row, M.name(k) .. (k == active and ("   " .. t("active")) or ""), S.cursor == i, { folder = true })
      end
      ui.drawScrollbar(LCD_W - ui.PAD - 3, ui.bodyY(1), last - start + 1, start, #keys)
    end
    local actions = { t("back") }
    if addCurrent then actions[2] = t("addCurrent") end
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
  -- Screen: model page (Battery, Show in Wingman, SD logs, buttons)
  -- ---------------------------------------------------------------------------

  function Nav.enterModel(key)
    M.open(key)
    S.modelCursor = 1
    S.screen = "model"
  end

  function Screen.drawModel()
    local m = M.model
    ui.drawHeader(t(M.isNew and "titleAddModel" or "titleEditModel", { name = M.name(m.filename) }))
    local rows = M.rows()
    for i, id in ipairs(rows) do
      local sel = S.modelCursor == i
      if id == "battery" then
        ui.drawFieldRow(i, t("battery"), M.batteryText(), { selected = sel, folder = true })
      elseif id == "modules" then
        ui.drawFieldRow(i, t("showInWingman"), M.modsText(), { selected = sel, folder = true })
      else
        ui.drawFieldRow(i, t("sdLogs"), M.logsText(), { selected = sel, folder = M.isActive, disabled = not M.isActive })
      end
    end
    ui.drawButtonBar(labels(M.isNew and { "back", "save" } or { "back", "save", "delete" }), #rows + 1, S.modelCursor)
  end

  local function leaveModel() S.screen, S.cursor = "list", 1 end

  local function finishModelSave()
    local lipo, wing = M.commit()
    save(leaveModel, lipo, wing)
  end

  local function checkParallelSave()
    if M.parallelInvalid() then
      ui.openAlert(lib.t("rules", "parallelNeedsTwo"))
      return
    end
    finishModelSave()
  end

  -- Parallel mode only allows profiles with 2+ packs: unassign the others after
  -- confirmation, before the invariant check.
  local function proceedModelSave()
    local dropped = M.smallProfiles()
    if dropped == 0 then return checkParallelSave() end
    ui.openDialog(t("parallelDrop", { batteries = M.batteries(dropped) }),
                  function() M.dropSmallProfiles(); checkParallelSave() end)
  end

  local function saveModel()
    local invalid = M.otherCells()
    if invalid > 0 then
      ui.openDialog(t("cellsDrop", { batteries = M.batteries(invalid) }), function()
        M.dropOtherCells()
        proceedModelSave()
      end)
    else
      proceedModelSave()
    end
  end

  local function deleteModel()
    ui.openDialog(t("deleteModel", { name = M.name(M.model.filename) }), function()
      local lipo, wing = M.delete()
      save(leaveModel, lipo, wing)
    end)
  end

  local function cancelModel()
    if M.dirty() then ui.openDialog(t("discard"), leaveModel) else leaveModel() end
  end

  function Screen.handleModel(e)
    local rows = M.rows()
    local n = #rows
    S.modelCursor = ui.moveCursor(S.modelCursor, e, n + (M.isNew and 2 or 3))
    if isEnter(e) then
      local c = S.modelCursor
      local id = rows[c]
      if id == "battery" then S.batteryCursor, S.batteryEditing, S.screen = 1, false, "battery"
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
  -- Screen: battery page (Lipo Nanny's rows), stored with the model's Save
  -- ---------------------------------------------------------------------------

  local BATTERY_ROWS = M.BATTERY_ROWS

  local function backToBattery(id)
    for i, r in ipairs(BATTERY_ROWS) do if r == id then S.batteryCursor = i end end
    S.screen = "battery"
  end

  local function leaveBattery() S.screen, S.modelCursor = "model", M.rowIndex("battery") end

  function Screen.drawBattery()
    local m = M.model
    ui.drawHeader(t("titleBattery", { name = M.name(m.filename) }))
    for i, id in ipairs(BATTERY_ROWS) do
      local sel = S.batteryCursor == i
      if id == "cells" then
        ui.drawFieldRow(i, t("cells"), m.cells .. "S", { selected = sel, editing = S.batteryEditing })
      elseif id == "parallel" then
        ui.drawFieldRow(i, t("parallelPacks"), t(m.parallel and "yes" or "no"), { selected = sel })
      elseif id == "batteries" then
        ui.drawFieldRow(i, t("batteries"), t("selected", { n = #m.batteryIds }), { selected = sel, folder = true })
      else
        ui.drawFieldRow(i, t("sensors"), t(M.sensorsAreCustom(m.sensors) and "custom" or "default"),
                        { selected = sel, folder = true })
      end
    end
    ui.drawButtonBar(labels({ "back" }), #BATTERY_ROWS + 1, S.batteryCursor)
  end

  function Screen.handleBattery(e)
    local m = M.model
    if S.batteryEditing then
      local L = M.LIMITS.cells
      if isNext(e) then m.cells = math.min(L.max, m.cells + 1)
      elseif isPrev(e) then m.cells = math.max(L.min, m.cells - 1)
      elseif isEnter(e) or isExit(e) then S.batteryEditing = false end
      return
    end
    S.batteryCursor = ui.moveCursor(S.batteryCursor, e, #BATTERY_ROWS + 1)
    if isEnter(e) then
      local id = BATTERY_ROWS[S.batteryCursor]
      if id == "cells" then S.batteryEditing = true
      elseif id == "parallel" then m.parallel = not m.parallel
      elseif id == "batteries" then S.assignItems, S.assignCursor, S.screen = M.assignItems(), 1, "assign"
      elseif id == "sensors" then M.openSensors(); S.sensorCursor, S.screen = 1, "sensors"
      else leaveBattery() end
    elseif isExit(e) then
      leaveBattery()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: battery assignment (profiles of the model's cell count)
  -- ---------------------------------------------------------------------------

  local function applyAssign()
    M.applyAssign(S.assignItems)
    backToBattery("batteries")
  end

  function Screen.drawAssign()
    local m = M.model
    ui.drawHeader(t(m.parallel and "titleSelectParallel" or "titleSelect", { cells = m.cells }))
    if #S.assignItems == 0 then
      lcd.drawText(ui.COL1, ui.bodyY(1), t("noMatching"), COLOR_THEME_PRIMARY1)
    end
    local start, last = ui.scrollWindow(S.assignCursor, #S.assignItems, 1)
    local row = 0
    for i = start, last do
      local it = S.assignItems[i]
      row = row + 1
      ui.drawNavRow(row, (it.checked and "[x] " or "[ ] ") .. it.name, S.assignCursor == i,
                    { disabled = not it.selectable })
    end
    ui.drawButtonBar(labels({ "back" }), #S.assignItems + 1, S.assignCursor)
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

  local function leaveSensors() backToBattery("sensors") end

  -- Help for the focused row, wrapped to the page width, above the button bar.
  local function drawHelp(text)
    local _, smH = lcd.sizeText("Mg", SMLSIZE)
    local pitch = smH + 4
    local desc = ui.wrapText(text, LCD_W - 2 * ui.COL1 - smH - 4, SMLSIZE)
    local dy = ui.barTopY() - #desc * pitch - 4
    for j, line in ipairs(desc) do
      local ly = dy + (j - 1) * pitch
      local tx = (j == 1) and ui.drawInfoBadge(ui.COL1, ly) or ui.COL1
      lcd.drawText(tx, ly, line, COLOR_THEME_PRIMARY1 + SMLSIZE)
    end
  end

  function Screen.drawSensors()
    ui.drawHeader(t("titleSensors", { name = M.name(M.model.filename) }))
    local _, smH = lcd.sizeText("Mg", SMLSIZE)
    local pitch  = smH + 4
    local y = ui.bodyY(1)
    for i, f in ipairs(SENSOR_FIELDS) do
      ui.drawFieldRowY(y, f.label, M.sensorValue(f), {
        selected = S.sensorCursor == i, disabled = not M.isActive, popup = M.isActive })
      y = y + ui.LINE
    end
    if M.isActive then
      drawHelp(SENSOR_FIELDS[math.min(S.sensorCursor, #SENSOR_FIELDS)].hint)
    else
      lcd.drawText(ui.COL1, ui.barTopY() - pitch - 4, t("activateToEdit"),
                   COLOR_THEME_PRIMARY1 + SMLSIZE)
    end
    ui.drawButtonBar(labels(M.sensorsResetShown() and { "back", "resetSensors" } or { "back" }),
                     SENSOR_BACK, S.sensorCursor)
  end

  local function openSensorPicker(c)
    local f = SENSOR_FIELDS[c]
    local choices, cur = M.sensorChoices(f)
    ui.openPicker(f.unit and f.label or t("sensorPicker", { label = f.label }), choices, cur, function(i) M.setSensor(f, i) end)
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
    ui.drawHeader(t("titleShowInWingman", { name = M.name(M.model.filename) }))
    for i, k in ipairs(keys) do
      ui.drawFieldRow(i, MODULES[k].label, lib.t("rows", M.model.mods[k] and "on" or "off"), { selected = S.modsCursor == i })
    end
    drawHelp(MODULES[keys[math.min(S.modsCursor, #keys)]].hint)
    ui.drawButtonBar(labels({ "back" }), #keys + 1, S.modsCursor)
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
    if M.logs.exists then return labels({ "back", "apply", "remove" }) end
    return labels({ "back", "setUp" })
  end

  function Screen.drawLogs()
    ui.drawHeader(t("titleLogs", { name = M.name(M.model.filename) }))
    local rows = logsRows()
    ui.drawFieldRow(1, t("log"), M.LOG_MODES[M.logsMode()], { selected = S.logsCursor == 1, popup = true })
    if rows == 3 then
      ui.drawFieldRow(2, t("armSwitch"), M.logsArm(), { selected = S.logsCursor == 2, popup = true })
    end
    ui.drawFieldRow(rows, t("interval"), M.intervalText(M.logs.interval),
                    { selected = S.logsCursor == rows, editing = S.logsEditing })
    -- Help line: the selected row's; on the buttons the one of the notice below the rows.
    local c = S.logsCursor
    local help = (c == 1 and "logHint") or (c == rows and "intervalHint") or (c == 2 and "armSwitchHint") or nil
    local y = ui.bodyY(rows + 1)
    if M.logs.noTrigger then
      lcd.drawText(ui.COL1, y, t("noTrigger"), COLOR_THEME_WARNING)
      help = help or "noTriggerHelp"
    elseif M.logs.disabled then
      lcd.drawText(ui.COL1, y, t("disabled"), COLOR_THEME_WARNING)
      help = help or "disabledHelp"
    elseif M.logs.exists then
      local found, total = M.logSensors()
      if total > 0 and found < total then
        lcd.drawText(ui.COL1, y, t("logSensorsSome", { found = found, total = total }), COLOR_THEME_WARNING)
        help = help or "discoverHelp"
      elseif total > 0 then
        lcd.drawText(ui.COL1, y, t("logSensorsAll", { total = total }), COLOR_THEME_PRIMARY1)
      end
    end
    if help then drawHelp(t(help)) end
    ui.drawButtonBar(logsButtons(), rows + 1, S.logsCursor)
  end

  local function applyLogs()
    local ok, err = M.applyLogs()
    if ok then leaveLogs()
    elseif err == "switch" then ui.openAlert(t("chooseArmFirst"))
    else ui.openAlert(t("noFreeSlot")) end
  end

  local function cancelLogs()
    if M.logsDirty() then ui.openDialog(t("discard"), leaveLogs) else leaveLogs() end
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
        ui.openPicker(t("log"), M.LOG_MODES, M.logsMode(), function(i) M.setLogsMode(i) end)
      elseif c == rows then S.logsEditing = true
      elseif c == 2 then
        local choices, cur, ids = M.logsArmChoices()
        ui.openPicker(t("armSwitch"), choices, cur, function(i) M.setLogsArm(ids[i]) end)
      elseif c == rows + 1 then cancelLogs()
      elseif c == rows + 2 then applyLogs()
      else
        ui.openDialog(t("removeLogs"), function() M.removeLogs(); leaveLogs() end)
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
      ui.drawHeader(lib.t("titles", "models"))
      lcd.drawText(ui.COL1, ui.bodyY(1), t("lipoBroken"), COLOR_THEME_WARNING)
      lcd.drawText(ui.COL1, ui.bodyY(2), t("lipoBrokenFix"), COLOR_THEME_PRIMARY1)
      ui.drawButtonBar(labels({ "back" }), 1, 1)
      return
    end
    if S.screen == "model" then Screen.drawModel()
    elseif S.screen == "battery" then Screen.drawBattery()
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
    elseif S.screen == "battery" then Screen.handleBattery(e)
    elseif S.screen == "assign" then Screen.handleAssign(e)
    elseif S.screen == "sensors" then Screen.handleSensors(e)
    elseif S.screen == "modules" then Screen.handleModules(e)
    elseif S.screen == "logs" then Screen.handleLogs(e)
    else return Screen.handleList(e) == true end
    return false
  end

  return P
end
