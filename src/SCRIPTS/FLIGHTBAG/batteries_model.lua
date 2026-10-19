-- =====================================================================
-- batteries_model.lua  --  Battery profiles of Lipo Nanny (no drawing)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/batteries_model.lua
-- Profile list, the edited profile (name, manufacturer, chemistry, capacity,
-- cells, Low/Critical overrides), its packs (cycles, wear, purchase date,
-- add / archive) and the steps of saving and deleting. Used by both Flight
-- Bag tools (batteries.lua, LVGL/batteries.lua).
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

local TEXT_MAX = { mfr = 10, name = 30 }   -- manufacturer / profile-name char caps
local MAX_PACKS = 20

-- Optional purchase date ("YYYY-MM", absent = unset), edited as a month count so
-- the wheel rolls month -> year.
local Buy = {
  MIN = 2010 * 12,
  MAX = 2099 * 12 + 11,
  toMonths = function(s)
    local y, m = string.match(s or "", "(%d+)-(%d+)")
    y, m = tonumber(y), tonumber(m)
    return (y and m) and (y * 12 + (m - 1)) or nil
  end,
  fromMonths = function(n) return string.format("%04d-%02d", math.floor(n / 12), n % 12 + 1) end,
  today = function()
    local dt = getDateTime and getDateTime()
    return (dt and dt.year) and string.format("%04d-%02d", dt.year, dt.mon) or "2024-01"
  end,
}

return function(ctx)
  local lib = ctx.lib
  local app
  for _, a in ipairs(ctx.apps) do if a.folder == "LIPONY" then app = a end end
  local core = app and app.core
  local cfg  = app and app.cfg
  local LIMITS, DEFAULTS = core and core.LIMITS, core and core.DEFAULTS
  local CHEM_NAMES = core and core.CHEM_NAMES

  local M = {
    TEXT_MAX = TEXT_MAX, MAX_PACKS = MAX_PACKS, Buy = Buy,
    LIMITS = LIMITS, CHEM_NAMES = CHEM_NAMES,
    broken = cfg == nil,   -- Lipo Nanny's file unusable: the page only says so
    prof = nil,            -- the edited profile
  }
  local orig   -- the profile as opened

  -- ---------------------------------------------------------------------------
  -- Helpers
  -- ---------------------------------------------------------------------------

  -- Auto-generated profile name: "<Manufacturer> <S>s <Chemistry> <mAh>mAh".
  local function genName(p)
    local mfr = (p.manufacturer ~= "" and (p.manufacturer .. " ")) or ""
    return mfr .. p.cells .. "s " .. p.chemistry .. " " .. p.capacityMah .. "mAh"
  end

  -- Next "bat_NNN" id, never reused: a counter persisted in the config, floored to
  -- one above every id still present in the library or referenced by a model.
  local function nextBatteryId()
    local function num(id) return tonumber(string.match(tostring(id or ""), "^bat_(%d+)$")) or 0 end
    local n = cfg.nextBatteryId or 1
    for _, b in ipairs(cfg.batteries) do n = math.max(n, num(b.id) + 1) end
    for _, m in pairs(cfg.models or {}) do
      for _, mid in ipairs(m.batteryIds or {}) do n = math.max(n, num(mid) + 1) end
    end
    cfg.nextBatteryId = n + 1
    return string.format("bat_%03d", n)
  end

  -- Next "pack_NNNN" id: a rising counter persisted in the config, never reused,
  -- so each physical pack keeps its statistics for its lifetime.
  local function nextPackId()
    local n = cfg.nextPackId or 1
    cfg.nextPackId = n + 1
    return string.format("pack_%04d", n)
  end

  -- Smallest free display number: a new pack fills the gap of an archived one.
  local function nextLabel(instances)
    local used = {}
    for _, p in ipairs(instances or {}) do used[p.label or 0] = true end
    local n = 1
    while used[n] do n = n + 1 end
    return n
  end

  local function sortByLabel(instances)
    table.sort(instances, function(a, b) return (a.label or 0) < (b.label or 0) end)
  end

  local function newProfile()
    local p = { manufacturer = "", name = "", nameAuto = true, chemistry = CHEM_NAMES[1],
                capacityMah = DEFAULTS.capacityMah, cells = DEFAULTS.cells,
                instances = { { id = nil, label = 1, wear = 0, cycles = 0 } } }
    p.name = genName(p)
    return p
  end

  local function copyInstances(src)
    local out = {}
    for i, p in ipairs(src or {}) do
      out[i] = { id = p.id, label = p.label, wear = p.wear or 0, cycles = p.cycles or 0,
                 totalMah = p.totalMah, lastUsed = p.lastUsed, minVCell = p.minVCell,
                 buyDate = p.buyDate }
    end
    return out
  end

  -- Low/Critical overrides come as a pair: once either is set, both are stored
  -- (the missing one at its current general value). Returns true if changed.
  local function pinOverrides(p)
    if p.warnPct == nil and p.critPct == nil then return false end
    local changed = false
    if p.warnPct == nil then p.warnPct = cfg.warnPct; changed = true end
    if p.critPct == nil then p.critPct = cfg.critPct; changed = true end
    return changed
  end

  local function copyProfile(src)
    local p = { id = src.id, manufacturer = src.manufacturer or "", name = src.name or "",
                nameAuto = src.nameAuto ~= false, chemistry = src.chemistry or CHEM_NAMES[1],
                capacityMah = src.capacityMah or DEFAULTS.capacityMah,
                cells = src.cells or DEFAULTS.cells,
                warnPct = src.warnPct, critPct = src.critPct,
                instances = copyInstances(src.instances) }
    -- Unknown profile entries (from a newer version) ride along untouched.
    for k, v in pairs(src) do if p[k] == nil and k ~= "instances" then p[k] = v end end
    pinOverrides(p)
    return p
  end

  local function instancesEqual(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
      if a[i].id ~= b[i].id or a[i].label ~= b[i].label
         or (a[i].wear or 0) ~= (b[i].wear or 0) or (a[i].cycles or 0) ~= (b[i].cycles or 0)
         or a[i].buyDate ~= b[i].buyDate then
        return false
      end
    end
    return true
  end

  local function profilesEqual(a, b)
    return a.manufacturer == b.manufacturer and a.name == b.name and a.nameAuto == b.nameAuto
       and a.chemistry == b.chemistry and a.capacityMah == b.capacityMah and a.cells == b.cells
       and a.warnPct == b.warnPct and a.critPct == b.critPct
       and instancesEqual(a.instances, b.instances)
  end

  -- Names of parallel models this profile is assigned to.
  local function parallelModelsUsing(pid)
    local out = {}
    for name, m in pairs(cfg.models or {}) do
      if m.parallel == true and m.batteryIds then
        for _, bid in ipairs(m.batteryIds) do
          if bid == pid then out[#out + 1] = lib.modelName(name); break end
        end
      end
    end
    table.sort(out)
    return out
  end

  -- Retires one pack into config.archive, keyed by its pack id.
  local function archiveInstance(profileName, inst)
    if not inst or not inst.id then return end
    cfg.archive[inst.id] = { name = profileName, cycles = inst.cycles or 0,
                             totalMah = inst.totalMah or 0, lastUsed = inst.lastUsed,
                             minVCell = inst.minVCell, buyDate = inst.buyDate }
  end

  local function refreshAutoName()
    if M.prof.nameAuto then M.prof.name = genName(M.prof) end
  end

  -- ---------------------------------------------------------------------------
  -- List and profile
  -- ---------------------------------------------------------------------------

  function M.sorted()
    local out = {}
    for _, b in ipairs(cfg.batteries) do out[#out + 1] = b end
    table.sort(out, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    return out
  end

  -- Opens a profile for editing; nil starts a new one.
  function M.open(existing)
    if existing then
      M.prof, orig, M.isNew = copyProfile(existing), copyProfile(existing), false
    else
      M.prof = newProfile()
      orig, M.isNew = copyProfile(M.prof), true
    end
    sortByLabel(M.prof.instances)
    sortByLabel(orig.instances)
  end

  function M.dirty() return not profilesEqual(M.prof, orig) end
  function M.packsBefore() return #orig.instances end

  -- The question before deleting the profile, for both views.
  function M.deleteQuestion()
    local n = M.packsBefore()
    if n == 1 then return "Delete profile and archive its pack?" end
    return "Delete profile and archive all " .. n .. " packs?"
  end

  -- Name (field 1) or manufacturer (field 2) as typed; trailing spaces go. An
  -- empty name returns to the generated one.
  function M.setText(field, s)
    s = string.gsub(s, "%s+$", "")
    local p = M.prof
    if field == 2 then
      p.manufacturer = s
      refreshAutoName()
    elseif s == "" then
      p.nameAuto, p.name = true, genName(p)
    else
      p.name, p.nameAuto = s, false
    end
  end

  function M.resetName() M.prof.nameAuto, M.prof.name = true, genName(M.prof) end

  function M.chemIndex()
    for i, c in ipairs(CHEM_NAMES) do if c == M.prof.chemistry then return i end end
    return 1
  end
  function M.setChemistry(i) M.prof.chemistry = CHEM_NAMES[i]; refreshAutoName() end

  local function clamp(v, L) return math.max(L.min, math.min(L.max, v)) end
  function M.setCapacity(v) M.prof.capacityMah = clamp(v, LIMITS.capacityMah); refreshAutoName() end
  function M.setCells(v) M.prof.cells = clamp(v, LIMITS.cells); refreshAutoName() end

  -- Battery low ("warnPct") / critical ("critPct"): the override or the general value.
  function M.pct(key) return M.prof[key] or cfg[key] end
  function M.pctText(key)
    local p = M.prof
    return p[key] and (p[key] .. " %") or (cfg[key] .. " % (default)")
  end
  function M.setPct(key, v)
    local p = M.prof
    p[key] = clamp(v, LIMITS[key])
    pinOverrides(p)
    -- Both back on the general values clears the pair ("(default)" again).
    if p.warnPct == cfg.warnPct and p.critPct == cfg.critPct then p.warnPct, p.critPct = nil, nil end
  end

  -- ---------------------------------------------------------------------------
  -- Packs
  -- ---------------------------------------------------------------------------

  -- Why the pack can't be archived, or nil.
  function M.archiveLocked()
    if #M.prof.instances <= 1 then return "Last pack - delete the profile instead" end
    local names = parallelModelsUsing(M.prof.id)
    if #names > 0 and (#M.prof.instances - 1) < 2 then
      return "Used by parallel model(s) " .. table.concat(names, ", ") .. " - keep 2+ packs"
    end
    return nil
  end

  -- Removes pack i (archived for real on profile save).
  function M.removePack(i) table.remove(M.prof.instances, i) end

  -- Adds a pack; returns a message when the profile is full.
  function M.addPack()
    local packs = M.prof.instances
    if #packs >= MAX_PACKS then return "Max " .. MAX_PACKS .. " packs" end
    packs[#packs + 1] = { id = nil, label = nextLabel(packs), wear = 0, cycles = 0 }
    sortByLabel(packs)
  end

  function M.setCycles(p, v) p.cycles = math.max(0, math.min(9999, v)) end
  function M.setWear(p, v) p.wear = clamp(v, LIMITS.wear) end
  function M.setBuy(p, months) p.buyDate = Buy.fromMonths(math.max(Buy.MIN, math.min(Buy.MAX, months))) end

  -- ---------------------------------------------------------------------------
  -- Saving and deleting
  -- ---------------------------------------------------------------------------

  -- Why the profile can't be saved, or nil.
  function M.invalid()
    local p = M.prof
    if p.manufacturer == "" then return "Manufacturer required" end
    if p.warnPct and p.critPct and not (p.warnPct > p.critPct) then
      return "Battery low must be above Battery critical"
    end
    return nil
  end

  -- Puts the profile into the config (ids minted, removed packs archived).
  function M.commit()
    local p = M.prof
    if p.nameAuto then p.name = genName(p) end
    if M.isNew then p.id = nextBatteryId() end
    for _, inst in ipairs(p.instances) do
      if not inst.id then inst.id = nextPackId() end
    end
    local kept = {}
    for _, inst in ipairs(p.instances) do kept[inst.id] = true end
    for _, inst in ipairs(orig.instances) do
      if inst.id and not kept[inst.id] then archiveInstance(orig.name, inst) end
    end
    local np = copyProfile(p); np.id = p.id
    if M.isNew then
      cfg.batteries[#cfg.batteries + 1] = np
    else
      for i, b in ipairs(cfg.batteries) do
        if b.id == p.id then cfg.batteries[i] = np; break end
      end
    end
  end

  -- Why the profile can't be deleted, or nil.
  function M.deleteBlocked()
    local names = parallelModelsUsing(M.prof.id)
    if #names > 0 then return "Used by parallel model(s) " .. table.concat(names, ", ") .. ". Unassign first" end
    return nil
  end

  -- Removes the profile, archives its packs and unassigns it from every model.
  function M.delete()
    for _, inst in ipairs(orig.instances) do archiveInstance(orig.name, inst) end
    for i, b in ipairs(cfg.batteries) do
      if b.id == M.prof.id then table.remove(cfg.batteries, i); break end
    end
    for _, m in pairs(cfg.models or {}) do
      local ids = m.batteryIds or {}
      for i = #ids, 1, -1 do if ids[i] == M.prof.id then table.remove(ids, i) end end
    end
  end

  -- Writes Lipo Nanny's file; true on success. Idempotent.
  function M.write() return core.saveConfig(cfg) end

  -- Complete half-set Low/Critical overrides once and persist that; a failed
  -- write is no error here, the next regular save carries it.
  if cfg then
    local changed = false
    for _, b in ipairs(cfg.batteries) do if pinOverrides(b) then changed = true end end
    if changed then core.saveConfig(cfg) end
  end

  return M
end
