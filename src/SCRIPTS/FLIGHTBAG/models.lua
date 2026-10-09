-- =====================================================================
-- models.lua  --  Flight Bag page "Models" (Lipo Nanny, Wingman)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/models.lua
-- Per-model setup: list, model editor (cells, parallel packs), battery
-- assignment, the per-model sensor mapping (all Lipo Nanny) and Wingman's
-- module switches. Saves through the core of each app.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

-- Sensor rows; `desc` is the help for the focused field (what it does, values).
local SENSOR_FIELDS = {
  { key = "voltage",  label = "Voltage", desc = {
      "Whole-pack voltage (V). Sets SoC % and",
      "warnings. 4S full ~16.8V, empty ~14.0V." } },
  { key = "current",  label = "Current", desc = {
      "Live current draw (A). Feeds the",
      "remaining-time estimate, e.g. 0-120A." } },
  { key = "capacity", label = "Capacity", desc = {
      "Consumed mAh, counts UP from 0 (or %,",
      "see Capacity unit). Main warn trigger." } },
  -- Not a sensor name: how the Capacity sensor reports (nil = mAh used, "pct").
  { key = "capacityUnit", label = "Capacity unit",
    unit = { "mAh used (default)", "% remaining" }, desc = {
      "Only if the FC sends remaining %.",
      "FC capacity must equal the pack's mAh." } },
}
local SENSOR_BACK = #SENSOR_FIELDS + 1

-- Wingman's module switches: label and help for the focused row. Off also
-- stops that module's alerts in Wingman.
local MODULES = {
  lipo = { label = "Battery", desc = {
      "Battery column, pack selection and",
      "Lipo Nanny alerts. Off: none of them." } },
  link = { label = "Link", desc = {
      "Link column and Link Sentinel alerts.",
      "Off: no link values, no link alerts." } },
  gps  = { label = "GPS", desc = {
      "GPS column, search page and GPS Homer",
      "alerts. Off: no GPS values or alerts." } },
}

return function(ctx)
  local ui = ctx.ui
  local app, wapp
  for _, a in ipairs(ctx.apps) do
    if a.folder == "LIPONY" then app = a elseif a.folder == "WINGMAN" then wapp = a end
  end
  local core = app and app.core
  local cfg  = app and app.cfg
  local wcore = wapp and wapp.core
  local wcfg  = wapp and wapp.cfg   -- nil: Wingman missing or its file damaged
  local LIMITS, DEFAULTS = core and core.LIMITS, core and core.DEFAULTS
  local DEFAULT_SENSORS = core and core.DEFAULT_SENSORS
  local isNext, isPrev, isEnter, isExit = ui.isNext, ui.isPrev, ui.isEnter, ui.isExit

  local S = { screen = "list", cursor = 1 }
  local Screen, Nav = {}, {}

  -- Writes Lipo Nanny's and/or Wingman's file, then onDone.
  local function save(onDone, lipo, wing)
    local function saveWing()
      if wing then ui.withRetry(function() return wcore.saveConfig(wcfg) end, onDone)
      elseif onDone then onDone() end
    end
    if lipo then ui.withRetry(function() return core.saveConfig(cfg) end, saveWing) else saveWing() end
  end

  local function profileById(id)
    for _, b in ipairs(cfg.batteries) do if b.id == id then return b end end
    return nil
  end

  local function known(k)
    return k ~= nil and ((cfg and cfg.models[k]) or (wcfg and wcfg.models[k])) ~= nil
  end

  -- Configured model keys (in any app): active model first, then alphabetically.
  local function modelKeys(active)
    local keys, seen = {}, {}
    for _, c in ipairs({ cfg, wcfg }) do
      for k in pairs(c and c.models or {}) do
        if not seen[k] then seen[k] = true; keys[#keys + 1] = k end
      end
    end
    table.sort(keys, function(a, b)
      if a == active then return true end
      if b == active then return false end
      return string.lower(a) < string.lower(b)
    end)
    return keys
  end

  -- Parallel needs at least one assigned profile of the model's cells with 2+ packs.
  local function parallelInvariantOk(m)
    for _, id in ipairs(m.batteryIds) do
      local p = profileById(id)
      if p and p.cells == m.cells and #(p.instances or {}) >= 2 then return true end
    end
    return false
  end

  local function idsEqual(a, b)
    if #a ~= #b then return false end
    local set = {}
    for _, id in ipairs(a) do set[id] = true end
    for _, id in ipairs(b) do if not set[id] then return false end end
    return true
  end

  -- Sensor names of the ACTIVE model (model.getSensor only sees that one), in
  -- slot order; slots can be sparse, so the whole range is scanned.
  local function modelSensorNames()
    local names, seen = {}, {}
    for i = 0, 63 do
      local ok, s = pcall(model.getSensor, i)
      if ok and type(s) == "table" and s.name and s.name ~= "" and not seen[s.name] then
        seen[s.name] = true
        names[#names + 1] = s.name
      end
    end
    return names
  end

  local function sensorsAreCustom(s)
    if not s then return false end
    for _, f in ipairs(SENSOR_FIELDS) do
      local v = s[f.key]
      if v and v ~= "" and v ~= DEFAULT_SENSORS[f.key] then return true end
    end
    return false
  end

  local function sensorsEqual(a, b)
    for _, f in ipairs(SENSOR_FIELDS) do
      if ((a and a[f.key]) or "") ~= ((b and b[f.key]) or "") then return false end
    end
    return true
  end

  -- ---------------------------------------------------------------------------
  -- Screen: list
  -- ---------------------------------------------------------------------------

  local function listState()
    local active = ui.activeModel()
    local keys   = modelKeys(active)
    local addCurrent = active and not known(active)
    return keys, active, addCurrent
  end

  function Screen.drawList()
    ui.drawHeader("MODELS")
    local keys, active, addCurrent = listState()
    if #keys == 0 and not active then
      lcd.drawText(ui.COL1, ui.bodyY(1), "No models configured.", COLOR_THEME_PRIMARY1)
    else
      local start, last = ui.scrollWindow(S.cursor, #keys, 1)
      local row = 0
      for i = start, last do
        row = row + 1
        local k = keys[i]
        ui.drawNavRow(row, ui.modelName(k) .. (k == active and "   [active]" or ""), S.cursor == i, { folder = true })
      end
      ui.drawScrollbar(LCD_W - ui.PAD - 3, ui.bodyY(1), last - start + 1, start, #keys)
    end
    local actions = { "Back" }
    if addCurrent then actions[2] = "[+] Add current model" end
    ui.drawButtonBar(actions, #keys + 1, S.cursor)
  end

  function Screen.handleList(e)
    local keys, _, addCurrent = listState()
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

  -- Editor rows of the installed apps; Lipo Nanny's first, so Batteries and
  -- Sensors keep the rows 3 and 4.
  local function modelRows()
    local r = cfg and { "cells", "parallel", "batteries", "sensors" } or {}
    if wcfg then r[#r + 1] = "modules" end
    return r
  end

  local function copyMods(m)
    local c = {}
    for k, v in pairs(m) do c[k] = v end
    return c
  end

  function Nav.enterModel(key)
    local active = ui.activeModel()
    S.modelIsNew = not known(key)
    key = key or active
    local m = cfg and cfg.models[key]
    S.inLipo = m ~= nil
    m = m or {}
    S.model = { filename = key, cells = m.cells or (DEFAULTS and DEFAULTS.cells), parallel = m.parallel == true,
                batteryIds = {}, sensors = {} }
    for _, id in ipairs(m.batteryIds or {}) do S.model.batteryIds[#S.model.batteryIds + 1] = id end
    for _, f in ipairs(SENSOR_FIELDS) do S.model.sensors[f.key] = (m.sensors or {})[f.key] end
    if wcfg then S.model.mods = wcore.modules(wcfg, key) end
    S.modelIsActive = S.model.filename == active
    S.modelOrig = { cells = S.model.cells, parallel = S.model.parallel, batteryIds = {}, sensors = {},
                    mods = S.model.mods and copyMods(S.model.mods) }
    for _, id in ipairs(S.model.batteryIds) do S.modelOrig.batteryIds[#S.modelOrig.batteryIds + 1] = id end
    for _, f in ipairs(SENSOR_FIELDS) do S.modelOrig.sensors[f.key] = S.model.sensors[f.key] end
    S.modelCursor, S.modelEditing = 1, false
    S.screen = "model"
  end

  local function lipoDirty()
    return S.model.cells ~= S.modelOrig.cells or S.model.parallel ~= S.modelOrig.parallel
        or not idsEqual(S.model.batteryIds, S.modelOrig.batteryIds)
        or not sensorsEqual(S.model.sensors, S.modelOrig.sensors)
  end

  local function modsDirty()
    if not S.model.mods then return false end
    for k, v in pairs(S.model.mods) do if S.modelOrig.mods[k] ~= v then return true end end
    return false
  end

  local function modelDirty() return lipoDirty() or modsDirty() end

  -- The switched-on modules: "Battery, Link, GPS", "Battery, Link", "None".
  local function modsText(mods)
    local on = {}
    for _, k in ipairs(wcore.MODULES) do
      if mods[k] then on[#on + 1] = MODULES[k].label end
    end
    return #on > 0 and table.concat(on, ", ") or "None"
  end

  function Screen.drawModel()
    ui.drawHeader((S.modelIsNew and "ADD MODEL  " or "EDIT MODEL  ") .. ui.modelName(S.model.filename))
    local rows = modelRows()
    for i, id in ipairs(rows) do
      local sel = S.modelCursor == i
      if id == "cells" then
        ui.drawFieldRow(i, "Cells", S.model.cells .. "S", { selected = sel, editing = S.modelEditing })
      elseif id == "parallel" then
        ui.drawFieldRow(i, "Parallel packs", S.model.parallel and "Yes" or "No", { selected = sel })
      elseif id == "batteries" then
        ui.drawFieldRow(i, "Batteries", #S.model.batteryIds .. " selected", { selected = sel, folder = true })
      elseif id == "sensors" then
        ui.drawFieldRow(i, "Sensors", sensorsAreCustom(S.model.sensors) and "custom" or "default",
                        { selected = sel, folder = true })
      else
        ui.drawFieldRow(i, "Show in Wingman", modsText(S.model.mods), { selected = sel, folder = true })
      end
    end
    ui.drawButtonBar(S.modelIsNew and { "Back", "Save" } or { "Back", "Save", "Delete" }, #rows + 1, S.modelCursor)
  end

  local function leaveModel() S.screen, S.cursor = "list", 1 end

  -- Lipo Nanny's entry is written unless the model has none and Wingman's
  -- Battery module is off (nothing to set up then).
  local function finishModelSave()
    local lipo = cfg ~= nil and (S.inLipo or lipoDirty() or not S.model.mods or S.model.mods.lipo)
    local wing = modsDirty()
    if wing then wcore.setModules(wcfg, S.model.filename, S.model.mods) end
    if not lipo then return save(leaveModel, false, wing) end
    local entry = { cells = S.model.cells, parallel = S.model.parallel, batteryIds = S.model.batteryIds }
    -- Only sensors that differ from the CRSF default are stored.
    if sensorsAreCustom(S.model.sensors) then
      entry.sensors = {}
      for _, f in ipairs(SENSOR_FIELDS) do
        local v = S.model.sensors[f.key]
        if v and v ~= "" and v ~= DEFAULT_SENSORS[f.key] then entry.sensors[f.key] = v end
      end
    end
    -- Unknown model entries (from a newer version) ride along untouched.
    for k, v in pairs(cfg.models[S.model.filename] or {}) do
      if entry[k] == nil and k ~= "sensors" then entry[k] = v end
    end
    cfg.models[S.model.filename] = entry
    save(leaveModel, true, wing)
  end

  local function checkParallelSave()
    if S.model.parallel and not parallelInvariantOk(S.model) then
      ui.openAlert("Parallel mode needs a profile with 2+ packs")
      return
    end
    finishModelSave()
  end

  -- Parallel mode only allows profiles with 2+ packs: unassign the others after
  -- confirmation, before the invariant check.
  local function proceedModelSave()
    if not S.model.parallel then return finishModelSave() end
    local kept, dropped = {}, 0
    for _, id in ipairs(S.model.batteryIds) do
      local p = profileById(id)
      if p and #(p.instances or {}) < 2 then dropped = dropped + 1 else kept[#kept + 1] = id end
    end
    if dropped == 0 then return checkParallelSave() end
    ui.openDialog("Parallel mode unassigns " .. dropped .. " batteries with < 2 packs. Continue?",
                  function() S.model.batteryIds = kept; checkParallelSave() end)
  end

  local function saveModel()
    local invalid = 0
    for _, id in ipairs(S.model.batteryIds) do
      local p = profileById(id)
      if p and p.cells ~= S.model.cells then invalid = invalid + 1 end
    end
    if invalid > 0 then
      ui.openDialog("Changing cells unassigns " .. invalid .. " batteries. Continue?", function()
        local kept = {}
        for _, id in ipairs(S.model.batteryIds) do
          local p = profileById(id)
          if p and p.cells == S.model.cells then kept[#kept + 1] = id end
        end
        S.model.batteryIds = kept
        proceedModelSave()
      end)
    else
      proceedModelSave()
    end
  end

  local function deleteModel()
    ui.openDialog("Delete model config for " .. ui.modelName(S.model.filename) .. "?", function()
      local f = S.model.filename
      local lipo, wing = cfg ~= nil and cfg.models[f] ~= nil, wcfg ~= nil and wcfg.models[f] ~= nil
      if lipo then cfg.models[f] = nil end
      if wing then wcfg.models[f] = nil end
      save(leaveModel, lipo, wing)
    end)
  end

  local function cancelModel()
    if modelDirty() then ui.openDialog("Discard changes?", leaveModel) else leaveModel() end
  end

  function Screen.handleModel(e)
    if S.modelEditing then
      local L = LIMITS.cells
      if isNext(e) then S.model.cells = math.min(L.max, S.model.cells + 1)
      elseif isPrev(e) then S.model.cells = math.max(L.min, S.model.cells - 1)
      elseif isEnter(e) or isExit(e) then S.modelEditing = false end
      return
    end
    local rows = modelRows()
    local n = #rows
    S.modelCursor = ui.moveCursor(S.modelCursor, e, n + (S.modelIsNew and 2 or 3))
    if isEnter(e) then
      local c = S.modelCursor
      local id = rows[c]
      if id == "cells" then S.modelEditing = true
      elseif id == "parallel" then S.model.parallel = not S.model.parallel
      elseif id == "batteries" then Nav.openAssign()
      elseif id == "sensors" then Nav.openSensors()
      elseif id == "modules" then S.modsCursor, S.screen = 1, "modules"
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

  function Nav.openAssign()
    local matching, checked = {}, {}
    for _, b in ipairs(cfg.batteries) do
      if b.cells == S.model.cells then matching[#matching + 1] = b end
    end
    for _, id in ipairs(S.model.batteryIds) do checked[id] = true end
    table.sort(matching, function(a, b)
      local ca, cb = checked[a.id] == true, checked[b.id] == true
      if ca ~= cb then return ca end
      return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    S.assignItems = {}
    for _, b in ipairs(matching) do
      S.assignItems[#S.assignItems + 1] = { id = b.id, name = b.name, checked = checked[b.id] == true,
        selectable = (not S.model.parallel) or #(b.instances or {}) >= 2 }
    end
    S.assignCursor, S.screen = 1, "assign"
  end

  local function applyAssign()
    local ids = {}
    for _, it in ipairs(S.assignItems) do if it.checked then ids[#ids + 1] = it.id end end
    S.model.batteryIds = ids
    S.screen, S.modelCursor = "model", 3
  end

  function Screen.drawAssign()
    ui.drawHeader(S.model.parallel and ("SELECT " .. S.model.cells .. "S PARALLEL PROFILES")
                  or ("SELECT " .. S.model.cells .. "S BATTERIES"))
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
  -- Screen: sensor mapping. The active model picks from its live sensors; another
  -- model shows its stored names read-only. Option 1 is the CRSF default (nil).
  -- ---------------------------------------------------------------------------

  function Nav.openSensors()
    S.sensorOpts = { false }
    if S.modelIsActive then
      for _, n in ipairs(modelSensorNames()) do S.sensorOpts[#S.sensorOpts + 1] = n end
    end
    S.sensorCursor, S.screen = 1, "sensors"
  end

  local function sensorRowValue(f)
    local v = S.model.sensors[f.key]
    if f.unit then return f.unit[v == "pct" and 2 or 1] end
    if v and v ~= "" then return v end
    return DEFAULT_SENSORS[f.key] .. " (default)"
  end

  local function sensorsResetShown() return S.modelIsActive and sensorsAreCustom(S.model.sensors) end

  local function leaveSensors() S.screen, S.modelCursor = "model", 4 end

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
    ui.drawHeader("SENSORS  " .. ui.modelName(S.model.filename))
    local _, smH = lcd.sizeText("Mg", SMLSIZE)
    local pitch  = smH + 4
    local y = ui.bodyY(1)
    for i, f in ipairs(SENSOR_FIELDS) do
      ui.drawFieldRowY(y, f.label, sensorRowValue(f), {
        selected = S.sensorCursor == i, disabled = not S.modelIsActive, popup = S.modelIsActive })
      y = y + ui.LINE
    end
    if S.modelIsActive then
      drawHelp(SENSOR_FIELDS[math.min(S.sensorCursor, #SENSOR_FIELDS)].desc)
    else
      lcd.drawText(ui.COL1, ui.barTopY() - pitch - 4, "Activate this model to edit sensors.",
                   COLOR_THEME_PRIMARY1 + SMLSIZE)
    end
    ui.drawButtonBar(sensorsResetShown() and { "Back", "Reset to CRSF defaults" } or { "Back" },
                     SENSOR_BACK, S.sensorCursor)
  end

  local function openSensorPicker(c)
    local f = SENSOR_FIELDS[c]
    if f.unit then
      ui.openPicker("Capacity unit", f.unit, S.model.sensors[f.key] == "pct" and 2 or 1,
                    function(i) S.model.sensors[f.key] = (i == 2) and "pct" or nil end)
      return
    end
    local labels, cur = { DEFAULT_SENSORS[f.key] .. " (default)" }, 1
    for i = 2, #S.sensorOpts do
      labels[i] = S.sensorOpts[i]
      if S.sensorOpts[i] == S.model.sensors[f.key] then cur = i end
    end
    ui.openPicker(f.label .. " sensor", labels, cur,
                  function(i) S.model.sensors[f.key] = (i > 1) and S.sensorOpts[i] or nil end)
  end

  function Screen.handleSensors(e)
    S.sensorCursor = ui.moveCursor(S.sensorCursor, e, SENSOR_BACK + (sensorsResetShown() and 1 or 0))
    if isEnter(e) then
      local c = S.sensorCursor
      if c < SENSOR_BACK then
        if S.modelIsActive then openSensorPicker(c) end
      elseif c == SENSOR_BACK then
        leaveSensors()
      elseif sensorsResetShown() then
        S.model.sensors, S.sensorCursor = {}, SENSOR_BACK
      end
    elseif isExit(e) then
      leaveSensors()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: Show in Wingman (module switches On/Off), stored with the model's Save
  -- ---------------------------------------------------------------------------

  local function leaveModules()
    local rows = modelRows()
    S.screen, S.modelCursor = "model", #rows
  end

  function Screen.drawModules()
    ui.drawHeader("SHOW IN WINGMAN  " .. ui.modelName(S.model.filename))
    for i, k in ipairs(wcore.MODULES) do
      ui.drawFieldRow(i, MODULES[k].label, S.model.mods[k] and "On" or "Off", { selected = S.modsCursor == i })
    end
    drawHelp(MODULES[wcore.MODULES[math.min(S.modsCursor, #wcore.MODULES)]].desc)
    ui.drawButtonBar({ "Back" }, #wcore.MODULES + 1, S.modsCursor)
  end

  function Screen.handleModules(e)
    local n = #wcore.MODULES
    S.modsCursor = ui.moveCursor(S.modsCursor, e, n + 1)
    if isEnter(e) then
      local k = wcore.MODULES[S.modsCursor]
      if k then S.model.mods[k] = not S.model.mods[k] else leaveModules() end
    elseif isExit(e) then
      leaveModules()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Page
  -- ---------------------------------------------------------------------------

  local P = {}

  function P.draw()
    if app and not cfg then
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
    else Screen.drawList() end
  end

  -- Returns true to close the page.
  function P.handle(e)
    if app and not cfg then return isExit(e) or isEnter(e) end
    if S.screen == "model" then Screen.handleModel(e)
    elseif S.screen == "assign" then Screen.handleAssign(e)
    elseif S.screen == "sensors" then Screen.handleSensors(e)
    elseif S.screen == "modules" then Screen.handleModules(e)
    else return Screen.handleList(e) == true end
    return false
  end

  return P
end
