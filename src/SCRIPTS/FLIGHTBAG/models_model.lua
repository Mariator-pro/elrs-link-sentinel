-- =====================================================================
-- models_model.lua  --  Per-model setup of Lipo Nanny and Wingman (no drawing)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/models_model.lua
-- Model list, the edited model (cells, parallel packs, battery assignment,
-- sensor mapping, Wingman's module switches), the steps of saving and
-- deleting, and the model's "SD Logs" special function. Used by both Flight
-- Bag tools (models.lua, LVGL/models.lua).
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

-- Sensor rows; `desc` is the help for the row (what it does, values).
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

-- Wingman's module switches: label and help. Off also stops that module's
-- alerts in Wingman.
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

-- Telemetry sensors each app's core sets for the flight log (its LOG_SENSORS),
-- with the Wingman module that drives it. Named here so the page needs no core.
local LOG_SENSORS_API = 1   -- cores write them from interface 1.1 on
local LOG_SENSORS = {
  { folder = "LIPONY",   mod = "lipo", names = { "LNst", "LNpk" } },
  { folder = "SNTNL",    mod = "link", names = { "LSst" } },
  { folder = "GPSHOMER", mod = "gps",  names = { "GHst" } },
}

-- "SD Logs" special function: EdgeTX function type, interval limits in 0.1 s.
local FUNC_LOGS = 18
local MAX_SF = 64
local LOG_INTERVAL = { min = 1, max = 50, default = 5 }

return function(ctx)
  local lib = ctx.lib
  local app, wapp
  for _, a in ipairs(ctx.apps) do
    if a.folder == "LIPONY" then app = a elseif a.folder == "WINGMAN" then wapp = a end
  end
  local core = app and app.core
  local cfg  = app and app.cfg
  local wcore = wapp and wapp.core
  local wcfg  = wapp and wapp.cfg   -- nil: Wingman missing or its file damaged
  local DEFAULT_SENSORS = core and core.DEFAULT_SENSORS

  local M = {
    SENSOR_FIELDS = SENSOR_FIELDS,
    MODULES = MODULES,
    LIMITS = core and core.LIMITS,
    -- Lipo Nanny installed but its file unusable: the page only says so.
    broken = app ~= nil and cfg == nil,
    model = nil,   -- the edited model: { filename, cells, parallel, batteryIds, sensors, mods }
  }
  local orig, inLipo   -- the model as opened; it had a Lipo Nanny entry

  function M.moduleKeys() return wcore.MODULES end
  function M.name(k) return lib.modelName(k) end
  function M.batteries(n) return n .. (n == 1 and " battery" or " batteries") end

  local function profileById(id)
    for _, b in ipairs(cfg.batteries) do if b.id == id then return b end end
    return nil
  end

  local function known(k)
    return k ~= nil and ((cfg and cfg.models[k]) or (wcfg and wcfg.models[k])) ~= nil
  end

  local function idsEqual(a, b)
    if #a ~= #b then return false end
    local set = {}
    for _, id in ipairs(a) do set[id] = true end
    for _, id in ipairs(b) do if not set[id] then return false end end
    return true
  end

  local function sensorsEqual(a, b)
    for _, f in ipairs(SENSOR_FIELDS) do
      if ((a and a[f.key]) or "") ~= ((b and b[f.key]) or "") then return false end
    end
    return true
  end

  local function copyMods(m)
    local c = {}
    for k, v in pairs(m) do c[k] = v end
    return c
  end

  -- ---------------------------------------------------------------------------
  -- List
  -- ---------------------------------------------------------------------------

  -- Configured model keys (in any app), active model first, then alphabetically;
  -- the active model; true when the active model can be added.
  function M.list()
    local active = lib.activeModel()
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
    return keys, active, active ~= nil and not known(active)
  end

  -- ---------------------------------------------------------------------------
  -- Model editor
  -- ---------------------------------------------------------------------------

  -- Opens a model for editing; nil adds the active model.
  function M.open(key)
    local active = lib.activeModel()
    M.isNew = not known(key)
    key = key or active
    local m = cfg and cfg.models[key]
    inLipo = m ~= nil
    m = m or {}
    local DEFAULTS = core and core.DEFAULTS
    local mod = { filename = key, cells = m.cells or (DEFAULTS and DEFAULTS.cells), parallel = m.parallel == true,
                  batteryIds = {}, sensors = {} }
    for _, id in ipairs(m.batteryIds or {}) do mod.batteryIds[#mod.batteryIds + 1] = id end
    for _, f in ipairs(SENSOR_FIELDS) do mod.sensors[f.key] = (m.sensors or {})[f.key] end
    if wcfg then mod.mods = wcore.modules(wcfg, key) end
    M.model, M.isActive = mod, key == active
    orig = { cells = mod.cells, parallel = mod.parallel, batteryIds = {}, sensors = {},
             mods = mod.mods and copyMods(mod.mods) }
    for _, id in ipairs(mod.batteryIds) do orig.batteryIds[#orig.batteryIds + 1] = id end
    for _, f in ipairs(SENSOR_FIELDS) do orig.sensors[f.key] = mod.sensors[f.key] end
  end

  -- Editor rows of the installed apps; Lipo Nanny's first.
  function M.rows()
    local r = cfg and { "cells", "parallel", "batteries", "sensors" } or {}
    if wcfg then r[#r + 1] = "modules" end
    r[#r + 1] = "logs"
    return r
  end

  -- Editor row number of a row id.
  function M.rowIndex(id)
    for i, r in ipairs(M.rows()) do if r == id then return i end end
    return 1
  end

  local function lipoDirty()
    local m = M.model
    return m.cells ~= orig.cells or m.parallel ~= orig.parallel
        or not idsEqual(m.batteryIds, orig.batteryIds)
        or not sensorsEqual(m.sensors, orig.sensors)
  end

  local function modsDirty()
    if not M.model.mods then return false end
    for k, v in pairs(M.model.mods) do if orig.mods[k] ~= v then return true end end
    return false
  end

  function M.dirty() return lipoDirty() or modsDirty() end

  function M.sensorsAreCustom(s)
    if not s then return false end
    for _, f in ipairs(SENSOR_FIELDS) do
      local v = s[f.key]
      if v and v ~= "" and v ~= DEFAULT_SENSORS[f.key] then return true end
    end
    return false
  end

  -- The switched-on modules: "Battery, Link, GPS", "Battery, Link", "None".
  function M.modsText()
    local on = {}
    for _, k in ipairs(wcore.MODULES) do
      if M.model.mods[k] then on[#on + 1] = MODULES[k].label end
    end
    return #on > 0 and table.concat(on, ", ") or "None"
  end

  -- ---------------------------------------------------------------------------
  -- Saving and deleting. A save runs these steps, asking between them:
  -- otherCells() > 0 -> dropOtherCells(); smallProfiles() > 0 -> dropSmallProfiles();
  -- parallelInvalid() stops it; commit() then the writes it names.
  -- ---------------------------------------------------------------------------

  -- Assigned profiles with another cell count (unassigned on save).
  function M.otherCells()
    local n = 0
    for _, id in ipairs(M.model.batteryIds) do
      local p = profileById(id)
      if p and p.cells ~= M.model.cells then n = n + 1 end
    end
    return n
  end

  function M.dropOtherCells()
    local kept = {}
    for _, id in ipairs(M.model.batteryIds) do
      local p = profileById(id)
      if p and p.cells == M.model.cells then kept[#kept + 1] = id end
    end
    M.model.batteryIds = kept
  end

  -- In parallel mode: assigned profiles with fewer than 2 packs (unassigned on save).
  function M.smallProfiles()
    if not M.model.parallel then return 0 end
    local n = 0
    for _, id in ipairs(M.model.batteryIds) do
      local p = profileById(id)
      if p and #(p.instances or {}) < 2 then n = n + 1 end
    end
    return n
  end

  function M.dropSmallProfiles()
    local kept = {}
    for _, id in ipairs(M.model.batteryIds) do
      local p = profileById(id)
      if not (p and #(p.instances or {}) < 2) then kept[#kept + 1] = id end
    end
    M.model.batteryIds = kept
  end

  -- Parallel needs at least one assigned profile of the model's cells with 2+ packs.
  function M.parallelInvalid()
    local m = M.model
    if not m.parallel then return false end
    for _, id in ipairs(m.batteryIds) do
      local p = profileById(id)
      if p and p.cells == m.cells and #(p.instances or {}) >= 2 then return false end
    end
    return true
  end

  -- Puts the model into the configs; returns which files to write (lipo, wing).
  -- Lipo Nanny's entry is written unless the model has none and Wingman's
  -- Battery module is off (nothing to set up then).
  function M.commit()
    local m = M.model
    local lipo = cfg ~= nil and (inLipo or lipoDirty() or not m.mods or m.mods.lipo)
    local wing = modsDirty()
    if wing then wcore.setModules(wcfg, m.filename, m.mods) end
    if not lipo then return false, wing end
    local entry = { cells = m.cells, parallel = m.parallel, batteryIds = m.batteryIds }
    -- Only sensors that differ from the CRSF default are stored.
    if M.sensorsAreCustom(m.sensors) then
      entry.sensors = {}
      for _, f in ipairs(SENSOR_FIELDS) do
        local v = m.sensors[f.key]
        if v and v ~= "" and v ~= DEFAULT_SENSORS[f.key] then entry.sensors[f.key] = v end
      end
    end
    -- Unknown model entries (from a newer version) ride along untouched.
    for k, v in pairs(cfg.models[m.filename] or {}) do
      if entry[k] == nil and k ~= "sensors" then entry[k] = v end
    end
    cfg.models[m.filename] = entry
    return true, wing
  end

  -- Removes the model from both configs; returns which files to write.
  function M.delete()
    local f = M.model.filename
    local lipo, wing = cfg ~= nil and cfg.models[f] ~= nil, wcfg ~= nil and wcfg.models[f] ~= nil
    if lipo then cfg.models[f] = nil end
    if wing then wcfg.models[f] = nil end
    return lipo, wing
  end

  -- Writes; true on success. Idempotent.
  function M.writeLipo() return core.saveConfig(cfg) end
  function M.writeWing() return wcore.saveConfig(wcfg) end

  -- ---------------------------------------------------------------------------
  -- Battery assignment (profiles of the model's cell count)
  -- ---------------------------------------------------------------------------

  -- { id, name, checked, selectable }, checked ones first, then by name.
  function M.assignItems()
    local matching, checked = {}, {}
    for _, b in ipairs(cfg.batteries) do
      if b.cells == M.model.cells then matching[#matching + 1] = b end
    end
    for _, id in ipairs(M.model.batteryIds) do checked[id] = true end
    table.sort(matching, function(a, b)
      local ca, cb = checked[a.id] == true, checked[b.id] == true
      if ca ~= cb then return ca end
      return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    local items = {}
    for _, b in ipairs(matching) do
      items[#items + 1] = { id = b.id, name = b.name, checked = checked[b.id] == true,
        selectable = (not M.model.parallel) or #(b.instances or {}) >= 2 }
    end
    return items
  end

  function M.applyAssign(items)
    local ids = {}
    for _, it in ipairs(items) do if it.checked then ids[#ids + 1] = it.id end end
    M.model.batteryIds = ids
  end

  -- ---------------------------------------------------------------------------
  -- Sensor mapping. The active model picks from its live sensors; another model
  -- shows its stored names read-only. Option 1 is the CRSF default (nil).
  -- ---------------------------------------------------------------------------

  local sensorOpts

  -- Sensor names of the ACTIVE model (model.getSensor only sees that one), in
  -- slot order; slots can be sparse, so the whole range is scanned.
  function M.openSensors()
    sensorOpts = { false }
    if not M.isActive then return end
    local seen = {}
    for i = 0, 63 do
      local ok, s = pcall(model.getSensor, i)
      if ok and type(s) == "table" and s.name and s.name ~= "" and not seen[s.name] then
        seen[s.name] = true
        sensorOpts[#sensorOpts + 1] = s.name
      end
    end
  end

  function M.sensorValue(f)
    local v = M.model.sensors[f.key]
    if f.unit then return f.unit[v == "pct" and 2 or 1] end
    if v and v ~= "" then return v end
    return DEFAULT_SENSORS[f.key] .. " (default)"
  end

  -- Choice labels of a sensor row and the index of its value.
  function M.sensorChoices(f)
    if f.unit then return f.unit, M.model.sensors[f.key] == "pct" and 2 or 1 end
    local labels, cur = { DEFAULT_SENSORS[f.key] .. " (default)" }, 1
    for i = 2, #sensorOpts do
      labels[i] = sensorOpts[i]
      if sensorOpts[i] == M.model.sensors[f.key] then cur = i end
    end
    return labels, cur
  end

  function M.setSensor(f, i)
    if f.unit then M.model.sensors[f.key] = (i == 2) and "pct" or nil
    else M.model.sensors[f.key] = (i > 1) and sensorOpts[i] or nil end
  end

  function M.sensorsResetShown() return M.isActive and M.sensorsAreCustom(M.model.sensors) end
  function M.resetSensors() M.model.sensors = {} end

  -- ---------------------------------------------------------------------------
  -- SD logs: the active model's "SD Logs" special function, changed right away
  -- (EdgeTX saves the model itself). Any such function counts, set up here or
  -- by hand; the first one is the one shown and changed.
  -- ---------------------------------------------------------------------------

  M.LOG_INTERVAL = LOG_INTERVAL

  -- Switch index of "ON" (always on): right after the 64 logical switches.
  local function onSwitch()
    local l1 = getSwitchIndex and getSwitchIndex("L01")
    return l1 and l1 + 64 or nil
  end

  -- Slot and fields of the model's first SD Logs function with a switch, else
  -- of the first one without (EdgeTX never runs it; Apply gives it a trigger
  -- instead of adding a second one), or nil.
  local function scanLogs()
    if not (model and model.getCustomFunction) then return nil end
    local bareSlot, bareCf
    for i = 0, MAX_SF - 1 do
      local ok, cf = pcall(model.getCustomFunction, i)
      if ok and type(cf) == "table" and cf.func == FUNC_LOGS then
        if (cf.switch or 0) ~= 0 then return i, cf end
        if not bareSlot then bareSlot, bareCf = i, cf end
      end
    end
    return bareSlot, bareCf
  end

  local function triggerOf(cf) return (cf.switch or 0) ~= 0 and cf.switch or nil end

  -- Cached per opened model (the editor row draws every frame); set up,
  -- Apply and Remove read it again.
  local logsFor, logsSlot, logsCf
  local function findLogs()
    if logsFor ~= M.model then
      logsSlot, logsCf = scanLogs()
      logsFor = M.model
    end
    return logsSlot, logsCf
  end
  local function rereadLogs() logsFor = nil end

  -- First slot never used: no switch, no function, no value or file name.
  local function freeSlot()
    for i = 0, MAX_SF - 1 do
      local ok, cf = pcall(model.getCustomFunction, i)
      if ok and type(cf) == "table" and (cf.switch or 0) == 0 and (cf.func or 0) == 0
         and (cf.value or 0) == 0 and (cf.name or "") == "" then return i end
    end
    return nil
  end

  local function switchName(idx)
    if idx == onSwitch() then return "Always on" end
    local n = getSwitchName and getSwitchName(idx)
    return n or ("#" .. idx)
  end

  local function intervalText(v) return string.format("%.1f s", v / 10) end
  M.intervalText = intervalText

  -- Text of the "SD logs" row: "Off", "No trigger", "SF↓, 0.5 s", "Always on,
  -- 0.5 s"; ", disabled" when the function is switched off in the model.
  function M.logsText()
    if not M.isActive then return "Only for the active model" end
    local _, cf = findLogs()
    if not cf then return "Off" end
    if not triggerOf(cf) then return "No trigger" end
    return switchName(cf.switch) .. ", " .. intervalText(cf.value or 0) .. (cf.active == 0 and ", disabled" or "")
  end

  -- Position symbols EdgeTX appends to a physical switch's name (up, down).
  local POS_UP, POS_DOWN = "\194\130", "\194\131"
  local function endsWith(s, e) return string.sub(s, -#e) == e end

  -- Arm switch choices: positions of the physical switches (EdgeTX's own list,
  -- so any switch order, count or custom switch), then defined logical
  -- switches. { labels }, { switch indexes }.
  local function armChoices()
    local labels, ids = {}, {}
    local on = onSwitch()
    local l1 = on and on - 64
    -- Below the logical switches come physical switches, multi-position pots
    -- and trims; a physical position ends in up or down, or is the middle
    -- ("-") right after an up.
    if l1 and switches then
      local prevUp
      for idx, n in switches(1, l1 - 1) do
        local up = endsWith(n, POS_UP)
        if up or endsWith(n, POS_DOWN) or (prevUp == idx - 1 and endsWith(n, "-")) then
          labels[#labels + 1] = n; ids[#ids + 1] = idx
        end
        prevUp = up and idx or nil
      end
    end
    if l1 and model.getLogicalSwitch then
      for i = 0, 63 do
        local ok, ls = pcall(model.getLogicalSwitch, i)
        if ok and type(ls) == "table" and (ls.func or 0) ~= 0 then
          labels[#labels + 1] = getSwitchName(l1 + i) or ("L" .. (i + 1)); ids[#ids + 1] = l1 + i
        end
      end
    end
    return labels, ids
  end

  -- Draft of the SD LOGS page: { exists, disabled (switched off in the model),
  -- noTrigger (the model's function has no switch), always (Always on instead
  -- of the arm switch), switch (arm switch, nil: not chosen yet; kept while
  -- Always on is chosen), interval }. An interval set by hand outside the
  -- page's range stays until it is changed; 0 (EdgeTX logs nothing) gets the
  -- default.
  function M.openLogs()
    rereadLogs()
    local _, cf = findLogs()
    local v = cf and cf.value or 0
    local trig = cf and triggerOf(cf)
    local always = trig ~= nil and trig == onSwitch()
    local arm = nil
    if not always then arm = trig end
    M.logs = { exists = cf ~= nil, disabled = cf ~= nil and cf.active == 0,
               noTrigger = cf ~= nil and not trig, always = always, switch = arm,
               interval = v > 0 and v or LOG_INTERVAL.default }
  end

  -- Switch the draft writes: Always on or the arm switch (nil: none yet).
  local function draftSwitch()
    if M.logs.always then return onSwitch() end
    return M.logs.switch
  end

  M.LOG_MODES = { "Armed", "Always on" }

  -- Index of the draft's kind in LOG_MODES.
  function M.logsMode() return M.logs.always and 2 or 1 end

  function M.setLogsMode(i) M.logs.always = i == 2 end

  -- Arm switch text of the draft.
  function M.logsArm()
    local s = M.logs.switch
    if not s then return "Choose arm switch" end
    return switchName(s)
  end

  -- A switch set in EdgeTX that the list has no entry for (inverted switch,
  -- flight mode, ...) heads the list, so confirming keeps it.
  function M.logsArmChoices()
    local labels, ids = armChoices()
    local s, cur = M.logs.switch, nil
    for i, id in ipairs(ids) do if id == s then cur = i end end
    if s and not cur then
      table.insert(labels, 1, switchName(s)); table.insert(ids, 1, s)
    end
    return labels, cur or 1, ids
  end

  function M.setLogsArm(id) M.logs.switch = id end

  -- True when the draft differs from the model's function.
  function M.logsDirty()
    local _, cf = findLogs()
    if not cf then return draftSwitch() ~= nil or M.logs.interval ~= LOG_INTERVAL.default end
    return draftSwitch() ~= triggerOf(cf) or M.logs.interval ~= cf.value
  end

  -- One step within the page's range (a longer interval set by hand comes
  -- back into it).
  function M.stepLogsInterval(d)
    M.logs.interval = math.max(LOG_INTERVAL.min, math.min(LOG_INTERVAL.max, M.logs.interval + d))
  end

  -- Writes the draft into the model: the existing function's slot, else a free
  -- one, switched on. Returns true, or nil and "switch" / "full".
  function M.applyLogs()
    local d = M.logs
    local sw = draftSwitch()
    if not sw then return nil, "switch" end
    local slot = findLogs() or freeSlot()
    if not slot then return nil, "full" end
    model.setCustomFunction(slot, { switch = sw, func = FUNC_LOGS, value = d.interval,
                                    mode = 0, param = 0, active = 1 })
    rereadLogs()
    d.exists, d.disabled, d.noTrigger = true, false, false
    return true
  end

  -- Clears the model's SD Logs function.
  function M.removeLogs()
    local slot = findLogs()
    if slot then model.setCustomFunction(slot, { switch = 0, func = 0 }) end
    rereadLogs()
    M.logs.exists, M.logs.disabled, M.logs.noTrigger = false, false, false
  end

  -- Log sensors of the installed apps (ctx.allApps: every app, not only this
  -- page's) that Wingman shows for this model (all when Wingman is missing):
  -- found, total. 0, 0 without such apps. An older core writes none, so it
  -- does not count.
  function M.logSensors()
    local installed = {}
    for _, a in ipairs(ctx.allApps or ctx.apps) do
      if a.ok and (a.apiMinor or 0) >= LOG_SENSORS_API then installed[a.folder] = true end
    end
    local mods = M.model and M.model.mods
    local found, total = 0, 0
    for _, s in ipairs(LOG_SENSORS) do
      if installed[s.folder] and not (mods and mods[s.mod] == false) then
        for _, n in ipairs(s.names) do
          total = total + 1
          local ok, info = pcall(getFieldInfo, n)
          if ok and info then found = found + 1 end
        end
      end
    end
    return found, total
  end

  return M
end
