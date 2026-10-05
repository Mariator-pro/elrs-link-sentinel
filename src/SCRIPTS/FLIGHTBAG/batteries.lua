-- =====================================================================
-- batteries.lua  --  Flight Bag page "Batteries" (Lipo Nanny)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/batteries.lua
-- Battery profiles: list, profile editor (name and manufacturer through a
-- character ring), packs (cycles, wear, purchase date, add / archive) and the
-- read-only per-pack statistics. Saves through the Lipo Nanny core.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

local TEXT_MAX = { mfr = 10, name = 30 }   -- manufacturer / profile-name char caps
local MAX_PACKS = 20

-- Character groups for the ring picker; the wheel cycles within one group, MDL
-- jumps to the next group's `first`. Each group ends in a space.
local CHAR_GROUPS = {
  { label = "ABC",  chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ ", first = "A" },
  { label = "abc",  chars = "abcdefghijklmnopqrstuvwxyz ", first = "a" },
  { label = "123#", chars = "0123456789-+.# ",            first = "0" },
}

local function groupOfChar(ch)
  for gi, g in ipairs(CHAR_GROUPS) do
    if string.find(g.chars, ch, 1, true) then return gi end
  end
  return 1
end

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
  local ui = ctx.ui
  local app
  for _, a in ipairs(ctx.apps) do if a.folder == "LIPONY" then app = a end end
  local core = app and app.core
  local cfg  = app and app.cfg
  local LIMITS, DEFAULTS = core and core.LIMITS, core and core.DEFAULTS
  local CHEM_NAMES = core and core.CHEM_NAMES

  local S = { screen = "list", cursor = 1 }
  local Screen, Nav = {}, {}
  local isNext, isPrev, isEnter, isExit = ui.isNext, ui.isPrev, ui.isEnter, ui.isExit

  local PK, SX   -- column anchors (Packs / Statistics)
  do
    local C = ui.COL1
    PK = { id = C, cyc = math.floor(LCD_W * 0.18), wear = math.floor(LCD_W * 0.34),
           buy = math.floor(LCD_W * 0.52), act = math.floor(LCD_W * 0.82) }
    SX = { id = C, cyc = math.floor(LCD_W * 0.13), mah = math.floor(LCD_W * 0.30),
           vmin = math.floor(LCD_W * 0.52), last = math.floor(LCD_W * 0.70) }
  end

  local function save(onDone)
    ui.withRetry(function() return core.saveConfig(cfg) end, onDone)
  end

  -- ---------------------------------------------------------------------------
  -- Profiles: helpers
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

  local function sortedBatteries()
    local out = {}
    for _, b in ipairs(cfg.batteries) do out[#out + 1] = b end
    table.sort(out, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    return out
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
          if bid == pid then out[#out + 1] = ui.modelName(name); break end
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

  -- ---------------------------------------------------------------------------
  -- Screen: list
  -- ---------------------------------------------------------------------------

  function Screen.drawList()
    ui.drawHeader("BATTERIES")
    local items = sortedBatteries()
    if #items == 0 then
      lcd.drawText(ui.COL1, ui.bodyY(1), "No batteries yet - add your first.", COLOR_THEME_PRIMARY1)
    else
      local start, last = ui.scrollWindow(S.cursor, #items, 1)
      local row = 0
      for i = start, last do
        row = row + 1
        ui.drawNavRow(row, items[i].name, S.cursor == i, { folder = true })
      end
      ui.drawScrollbar(LCD_W - ui.PAD - 3, ui.bodyY(1), last - start + 1, start, #items)
    end
    ui.drawButtonBar({ "Back", "[+] Add new" }, #items + 1, S.cursor)
  end

  function Screen.handleList(e)
    local items = sortedBatteries()
    S.cursor = ui.moveCursor(S.cursor, e, #items + 2)
    if isEnter(e) then
      if S.cursor <= #items then Nav.enterProfile(items[S.cursor])
      elseif S.cursor == #items + 1 then return true
      else Nav.enterProfile(nil) end
    elseif isExit(e) then
      return true
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: profile editor
  -- ---------------------------------------------------------------------------
  -- Items: 1 Name, 2 Manufacturer, 3 Chemistry, 4 Capacity, 5 Cells, 6 Packs,
  -- 7 Statistics, 8 Low, 9 Critical, then the bottom-bar buttons from 10.

  function Nav.enterProfile(existing)
    if existing then
      S.prof, S.profOrig, S.profIsNew = copyProfile(existing), copyProfile(existing), false
    else
      S.prof = newProfile()
      S.profOrig, S.profIsNew = copyProfile(S.prof), true
    end
    sortByLabel(S.prof.instances)
    sortByLabel(S.profOrig.instances)
    S.profCursor, S.profEditing, S.capStep = 1, nil, 100
    S.textBuf, S.textCharMode, S.textSnapshot = nil, false, nil
    S.screen = "profile"
  end

  local function refreshAutoName()
    if S.prof.nameAuto then S.prof.name = genName(S.prof) end
  end

  local function buildProfileLines()
    local p, lines = S.prof, {}
    local function field(item, label, value, folder)
      lines[#lines + 1] = { item = item, label = label, value = value, folder = folder }
    end
    field(1, "Name", p.name .. (p.nameAuto and "  (auto)" or ""))
    field(2, "Manufacturer", p.manufacturer ~= "" and p.manufacturer or "-")
    field(3, "Chemistry", p.chemistry)
    field(4, "Capacity", p.capacityMah .. " mAh")
    field(5, "Cells", p.cells .. "S")
    field(6, "Packs", tostring(#p.instances), true)
    field(7, "Statistics", nil, true)
    field(8, "Low", p.warnPct and (p.warnPct .. " %") or (cfg.warnPct .. " % (default)"))
    field(9, "Critical", p.critPct and (p.critPct .. " %") or (cfg.critPct .. " % (default)"))
    return lines
  end

  local function profileActions()
    local acts = { "Back", "Save" }
    if not S.profIsNew then acts[#acts + 1] = "Delete" end
    if not S.prof.nameAuto then acts[#acts + 1] = "Reset name" end
    return acts
  end

  -- --- text editor (Name / Manufacturer) ---

  local function textDoneIndex()
    local n = #S.textBuf
    return n + ((n < S.textMax) and 2 or 1)
  end
  local function textIsAppendSlot() return #S.textBuf < S.textMax and S.textPos == #S.textBuf + 1 end
  local function textIsDone() return S.textPos == textDoneIndex() end
  local function textClearIndex() return textDoneIndex() + 1 end
  local function textIsClear() return S.textPos == textClearIndex() end

  -- Character ring: the active group's characters around a circle, the active one
  -- marked; the centre names the groups (MDL steps through them).
  local function drawCharRing(ch)
    local gi = S.charGroup or groupOfChar(ch)
    local s  = CHAR_GROUPS[gi].chars
    local m  = #s
    local active = string.find(s, ch, 1, true) or 1
    local top, bottom = ui.bodyY(2) - 2, LCD_H - ui.PAD
    lcd.drawFilledRectangle(ui.PAD, top, LCD_W - 2 * ui.PAD, bottom - top, COLOR_THEME_SECONDARY3)
    local _, th = lcd.sizeText("Mg")
    local half  = math.floor(th / 2)
    local cx, cy = math.floor(LCD_W / 2), math.floor((top + bottom) / 2)
    local r  = math.floor((bottom - top) / 2) - half - 6
    for j = 1, m do
      local ang = 2 * math.pi * (j - 1) / m
      local px  = cx + math.floor(r * math.sin(ang))
      local py  = cy - math.floor(r * math.cos(ang))
      local c   = string.sub(s, j, j)
      if c == " " then c = "_" end
      if j == active then lcd.drawFilledCircle(px, py, half + 1, COLOR_THEME_PRIMARY1) end
      lcd.drawText(px, py - half, c, ((j == active) and COLOR_THEME_PRIMARY2 or COLOR_THEME_PRIMARY1) + CENTER)
    end
    local sep, total = " > ", 0
    for i, g in ipairs(CHAR_GROUPS) do
      total = total + lcd.sizeText(g.label) + (i < #CHAR_GROUPS and lcd.sizeText(sep) or 0)
    end
    local gx, gy = cx - math.floor(total / 2), cy - half
    for i, g in ipairs(CHAR_GROUPS) do
      lcd.drawText(gx, gy, g.label, COLOR_THEME_PRIMARY1 + ((i == gi) and INVERS or 0))
      gx = gx + lcd.sizeText(g.label)
      if i < #CHAR_GROUPS then
        lcd.drawText(gx, gy, sep, COLOR_THEME_PRIMARY1)
        gx = gx + lcd.sizeText(sep)
      end
    end
  end

  -- The edited text with the active slot marked; Done and Clear buttons on the
  -- right in position mode. Long text shows a window with "..." markers.
  local function drawEditValue(y)
    local buf, pos, n = S.textBuf, S.textPos, #S.textBuf
    local INV = COLOR_THEME_PRIMARY1 + INVERS
    local toks = {}
    for i = 1, n do
      local c = string.sub(buf, i, i); if c == " " then c = "_" end
      if i == pos and S.textCharMode then toks[#toks + 1] = { s = c, f = INV }
      elseif i == pos then toks[#toks + 1] = { s = "[" .. c .. "]", f = INV }
      else toks[#toks + 1] = { s = c, f = COLOR_THEME_PRIMARY1 } end
    end
    if not S.textCharMode and n < S.textMax and pos == n + 1 then toks[#toks + 1] = { s = "[_]", f = INV } end
    for _, t in ipairs(toks) do t.w = lcd.sizeText(t.s) end
    local rightEdge = LCD_W - ui.PAD
    if not S.textCharMode then
      local clearW = lcd.sizeText("Clear") + 2 * ui.BTN_PADX
      ui.drawButton(rightEdge - clearW, y - 2, "Clear", pos == textClearIndex())
      rightEdge = rightEdge - clearW - ui.PAD
      local doneW = lcd.sizeText("Done") + 2 * ui.BTN_PADX
      ui.drawButton(rightEdge - doneW, y - 2, "Done", pos == textDoneIndex())
      rightEdge = rightEdge - doneW - ui.PAD
    end
    if #toks == 0 then return end
    local availW, dotsW = rightEdge - ui.COL1, lcd.sizeText("...")
    local active = math.min(pos, #toks)
    local function winW(lo, hi)
      local w = 0
      for i = lo, hi do w = w + toks[i].w end
      if lo > 1 then w = w + dotsW end
      if hi < #toks then w = w + dotsW end
      return w
    end
    local lo, hi = active, active
    while true do
      local grew = false
      if lo > 1 and winW(lo - 1, hi) <= availW then lo = lo - 1; grew = true end
      if hi < #toks and winW(lo, hi + 1) <= availW then hi = hi + 1; grew = true end
      if not grew then break end
    end
    local x = ui.COL1
    if lo > 1 then lcd.drawText(x, y, "...", COLOR_THEME_PRIMARY1); x = x + dotsW end
    for i = lo, hi do lcd.drawText(x, y, toks[i].s, toks[i].f); x = x + toks[i].w end
    if hi < #toks then lcd.drawText(x, y, "...", COLOR_THEME_PRIMARY1) end
  end

  local function drawTextEditor()
    ui.drawHeader(S.profEditing == 2 and "EDIT MANUFACTURER" or "EDIT NAME")
    local y = ui.bodyY(1)
    drawEditValue(y)
    if S.textCharMode then
      local ch = (S.textPos > #S.textBuf) and " " or string.sub(S.textBuf, S.textPos, S.textPos)
      drawCharRing(ch)
      ui.drawKeyHint(y, "MDL", "switch group")
    else
      local hx = ui.drawKeyChip(ui.COL1, ui.bodyY(2), "Wheel", "slot") + ui.PAD * 2
      ui.drawKeyChip(hx, ui.bodyY(2), "ENTER", "edit")
    end
  end

  local function charAt(buf, pos)
    if pos > #buf then return " " end
    return string.sub(buf, pos, pos)
  end

  local function setChar(buf, pos, ch)
    if pos > #buf then return buf .. string.rep(" ", pos - #buf - 1) .. ch end
    return string.sub(buf, 1, pos - 1) .. ch .. string.sub(buf, pos + 1)
  end

  local function cycleChar(ch, d)
    local g = CHAR_GROUPS[S.charGroup].chars
    local i = (string.find(g, ch, 1, true) or 1) + d
    if i < 1 then i = #g elseif i > #g then i = 1 end
    return string.sub(g, i, i)
  end

  local function startTextEdit(field)
    S.profEditing  = field
    S.textBuf      = (field == 2) and S.prof.manufacturer or S.prof.name
    S.textMax      = (field == 2) and TEXT_MAX.mfr or TEXT_MAX.name
    S.textPos, S.textCharMode, S.textSnapshot = 1, false, nil
  end

  local function cancelTextEdit()
    S.profEditing, S.textBuf, S.textCharMode, S.textSnapshot = nil, nil, false, nil
  end

  local function commitTextEdit()
    local s = string.gsub(S.textBuf, "%s+$", "")
    if S.profEditing == 2 then
      S.prof.manufacturer = s
      refreshAutoName()
    elseif s == "" then
      S.prof.nameAuto, S.prof.name = true, genName(S.prof)
    else
      S.prof.name, S.prof.nameAuto = s, false
    end
    cancelTextEdit()
  end

  local function handleTextEdit(e)
    if S.textCharMode then
      if isNext(e) then
        S.textBuf = setChar(S.textBuf, S.textPos, cycleChar(charAt(S.textBuf, S.textPos), 1))
      elseif isPrev(e) then
        S.textBuf = setChar(S.textBuf, S.textPos, cycleChar(charAt(S.textBuf, S.textPos), -1))
      elseif ui.isMenu(e) then
        S.charGroup = S.charGroup % #CHAR_GROUPS + 1
        S.textBuf = setChar(S.textBuf, S.textPos, CHAR_GROUPS[S.charGroup].first)
      elseif isEnter(e) then
        S.textSnapshot, S.textCharMode = nil, false
        S.textPos = math.min(S.textPos + 1, textDoneIndex())
      elseif isExit(e) then
        S.textBuf, S.textSnapshot, S.textCharMode = S.textSnapshot, nil, false
        S.textPos = math.min(S.textPos, textDoneIndex())
      end
    else
      if isNext(e) then S.textPos = math.min(S.textPos + 1, textClearIndex())
      elseif isPrev(e) then S.textPos = math.max(1, S.textPos - 1)
      elseif isEnter(e) then
        if textIsClear() then S.textBuf, S.textPos = "", 1
        elseif textIsDone() then commitTextEdit()
        else
          S.textSnapshot = S.textBuf
          if textIsAppendSlot() then
            S.textBuf = setChar(S.textBuf, S.textPos, S.textPos == 1 and "A" or "a")
          end
          S.charGroup = groupOfChar(charAt(S.textBuf, S.textPos))
          S.textCharMode = true
        end
      elseif isExit(e) then
        cancelTextEdit()
      end
    end
  end

  -- --- number / dropdown / optional-number editing ---

  local function adjustNumber(e)
    local item, p = S.profEditing, S.prof
    if item == 3 then
      local idx = 1
      for i, c in ipairs(CHEM_NAMES) do if c == p.chemistry then idx = i end end
      if isNext(e) then idx = idx % #CHEM_NAMES + 1
      elseif isPrev(e) then idx = (idx - 2) % #CHEM_NAMES + 1 end
      p.chemistry = CHEM_NAMES[idx]
      refreshAutoName()
    elseif item == 4 then
      local L = LIMITS.capacityMah
      if ui.isMenu(e) then
        S.capStep = (S.capStep == 10 and 100) or (S.capStep == 100 and 1000) or 10
      elseif isNext(e) then p.capacityMah = math.min(L.max, p.capacityMah + S.capStep)
      elseif isPrev(e) then p.capacityMah = math.max(L.min, p.capacityMah - S.capStep) end
      refreshAutoName()
    elseif item == 5 then
      local L = LIMITS.cells
      if isNext(e) then p.cells = math.min(L.max, p.cells + 1)
      elseif isPrev(e) then p.cells = math.max(L.min, p.cells - 1) end
      refreshAutoName()
    elseif item == 8 or item == 9 then
      local key = (item == 8) and "warnPct" or "critPct"
      local L   = LIMITS[key]
      local cur = p[key] or cfg[key]
      if isNext(e) then cur = math.min(L.max, cur + 1)
      elseif isPrev(e) then cur = math.max(L.min, cur - 1) end
      p[key] = cur
      pinOverrides(p)
      -- Both back on the general values clears the pair ("(default)" again).
      if p.warnPct == cfg.warnPct and p.critPct == cfg.critPct then p.warnPct, p.critPct = nil, nil end
    end
    if isEnter(e) then S.profEditing = nil end
  end

  function Screen.drawProfile()
    if S.profEditing == 1 or S.profEditing == 2 then drawTextEditor(); return end
    ui.drawHeader(S.profIsNew and "ADD BATTERY" or "EDIT BATTERY")
    local lines = buildProfileLines()
    local focus = #lines
    for i, ln in ipairs(lines) do if ln.item == S.profCursor then focus = i break end end
    local start, last = ui.scrollWindow(focus, #lines, 1)
    local editY, editVal
    for i = start, last do
      local ln, row = lines[i], i - start + 1
      ui.drawFieldRow(row, ln.label, ln.value,
                      { selected = ln.item == S.profCursor, editing = S.profEditing == ln.item, folder = ln.folder })
      if ln.item == S.profEditing then editY, editVal = ui.bodyY(row), ln.value end
    end
    ui.drawScrollbar(LCD_W - ui.PAD - 3, ui.bodyY(1), last - start + 1, start, #lines)
    ui.drawButtonBar(profileActions(), 10, S.profCursor)
    if editY and S.profEditing == 4 then
      ui.drawKeyHint(editY, "MDL", "step " .. S.capStep, editVal and (ui.COL2 + lcd.sizeText(editVal)))
    end
  end

  local function gotoList() S.screen, S.cursor = "list", 1 end

  local function validateProfile()
    if S.prof.manufacturer == "" then ui.openAlert("Manufacturer required"); return false end
    if S.prof.warnPct and S.prof.critPct and not (S.prof.warnPct > S.prof.critPct) then
      ui.openAlert("Low must be above Critical"); return false
    end
    return true
  end

  -- Mints ids for new packs and archives packs removed on the Packs page.
  local function reconcileInstances()
    for _, p in ipairs(S.prof.instances) do
      if not p.id then p.id = nextPackId() end
    end
    local kept = {}
    for _, p in ipairs(S.prof.instances) do kept[p.id] = true end
    for _, p in ipairs(S.profOrig.instances) do
      if p.id and not kept[p.id] then archiveInstance(S.profOrig.name, p) end
    end
  end

  local function saveProfile()
    if not validateProfile() then return end
    if S.prof.nameAuto then S.prof.name = genName(S.prof) end
    if S.profIsNew then S.prof.id = nextBatteryId() end
    reconcileInstances()
    local np = copyProfile(S.prof); np.id = S.prof.id
    if S.profIsNew then
      cfg.batteries[#cfg.batteries + 1] = np
    else
      for i, b in ipairs(cfg.batteries) do
        if b.id == S.prof.id then cfg.batteries[i] = np; break end
      end
    end
    save(gotoList)
  end

  local function doDeleteProfile()
    for _, p in ipairs(S.profOrig.instances) do archiveInstance(S.profOrig.name, p) end
    for i, b in ipairs(cfg.batteries) do
      if b.id == S.prof.id then table.remove(cfg.batteries, i); break end
    end
    -- No model keeps pointing at a profile that no longer exists.
    for _, m in pairs(cfg.models or {}) do
      local ids = m.batteryIds or {}
      for i = #ids, 1, -1 do if ids[i] == S.prof.id then table.remove(ids, i) end end
    end
    save(gotoList)
  end

  local function deleteProfile()
    local names = parallelModelsUsing(S.prof.id)
    if #names > 0 then
      ui.openAlert("Used by parallel model(s) " .. table.concat(names, ", ") .. ". Unassign first")
      return
    end
    ui.openDialog("Delete profile and archive all " .. #S.profOrig.instances .. " packs?", doDeleteProfile)
  end

  local function cancelProfile()
    if profilesEqual(S.prof, S.profOrig) then gotoList()
    else ui.openDialog("Discard changes?", gotoList) end
  end

  function Screen.handleProfile(e)
    if S.profEditing == 1 or S.profEditing == 2 then handleTextEdit(e); return end
    if S.profEditing then
      if isExit(e) then S.profEditing = nil else adjustNumber(e) end
      return
    end
    S.profCursor = ui.moveCursor(S.profCursor, e, 9 + #profileActions())
    if isEnter(e) then
      local c = S.profCursor
      if c == 1 or c == 2 then startTextEdit(c)
      elseif c == 3 or c == 4 or c == 5 or c == 8 or c == 9 then S.profEditing = c
      elseif c == 6 then Nav.enterPacks()
      elseif c == 7 then S.statsCursor, S.screen = 1, "stats"
      else
        local act = profileActions()[c - 9]
        if act == "Save" then saveProfile()
        elseif act == "Back" then cancelProfile()
        elseif act == "Delete" then deleteProfile()
        elseif act == "Reset name" then
          S.prof.nameAuto, S.prof.name, S.profCursor = true, genName(S.prof), 1
        end
      end
    elseif isExit(e) then
      cancelProfile()
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: packs (cycles, wear, purchase date, add / archive)
  -- ---------------------------------------------------------------------------

  local PACK_SUBS = { "cycles", "wear", "buydate", "archive" }

  local function packArchiveLocked()
    if #S.prof.instances <= 1 then return "Last pack - delete the profile instead" end
    local names = parallelModelsUsing(S.prof.id)
    if #names > 0 and (#S.prof.instances - 1) < 2 then
      return "Used by parallel model(s) " .. table.concat(names, ", ") .. " - keep 2+ packs"
    end
    return nil
  end

  function Nav.enterPacks()
    S.packsCursor, S.packDive, S.packSub = 1, nil, "cycles"
    S.packEdit = nil
    S.screen = "packs"
  end

  function Screen.drawPacks()
    ui.drawHeader("PACKS - " .. S.prof.name)
    local packs, C = S.prof.instances, COLOR_THEME_PRIMARY1
    local hy = ui.bodyY(1)
    lcd.drawText(PK.id,   hy, "ID",     C + BOLD)
    lcd.drawText(PK.cyc,  hy, "Cycles", C + BOLD)
    lcd.drawText(PK.wear, hy, "Wear",   C + BOLD)
    lcd.drawText(PK.buy,  hy, "Bought", C + BOLD)
    lcd.drawText(PK.act,  hy, "Delete", C + BOLD)
    local n = #packs
    local start, last = ui.scrollWindow(S.packsCursor, n, 2)
    local dispRow = 1
    for i = start, last do
      local p = packs[i]
      dispRow = dispRow + 1
      local y = ui.bodyY(dispRow)
      local dived  = S.packDive == i
      local function cell(x, text, sub)
        local f = C
        if dived and S.packSub == sub then f = f + INVERS + ((S.packEdit == sub) and BLINK or 0) end
        lcd.drawText(x, y, text, f)
      end
      local _, lh = lcd.sizeText("Mg")
      ui.drawRightArrow(PK.id, y + math.floor((lh - ui.ARROW_W) / 2), C)
      lcd.drawText(PK.id + ui.ARROW_W + ui.ARROW_GAP, y, "#" .. p.label,
                   C + ((S.packsCursor == i and not dived) and INVERS or 0))
      cell(PK.cyc,  tostring(p.cycles or 0), "cycles")
      cell(PK.wear, p.wear .. " %",          "wear")
      cell(PK.buy,  p.buyDate or "-",        "buydate")
      ui.drawButton(PK.act, y - 2, "X", dived and S.packSub == "archive")
    end
    ui.drawScrollbar(LCD_W - ui.PAD - 3, ui.bodyY(2), last - start + 1, start, n)
    ui.drawButtonBar({ "Back", "[+] Add pack" }, #packs + 1, S.packsCursor)
  end

  function Screen.handlePacks(e)
    local packs = S.prof.instances
    if S.packEdit then
      local p = packs[S.packDive]
      if S.packEdit == "cycles" then
        if isNext(e) then p.cycles = math.min(9999, (p.cycles or 0) + 1)
        elseif isPrev(e) then p.cycles = math.max(0, (p.cycles or 0) - 1) end
      elseif S.packEdit == "wear" then
        local L = LIMITS.wear
        if isNext(e) then p.wear = math.min(L.max, p.wear + 1)
        elseif isPrev(e) then p.wear = math.max(L.min, p.wear - 1) end
      else
        local cur = Buy.toMonths(p.buyDate) or Buy.MIN
        if isNext(e) then p.buyDate = Buy.fromMonths(math.min(Buy.MAX, cur + 1))
        elseif isPrev(e) then p.buyDate = Buy.fromMonths(math.max(Buy.MIN, cur - 1)) end
      end
      if isEnter(e) or isExit(e) then S.packEdit = nil end
      return
    end
    if S.packDive then
      if isNext(e) or isPrev(e) then
        local idx = 1
        for j, s in ipairs(PACK_SUBS) do if s == S.packSub then idx = j end end
        idx = idx + (isNext(e) and 1 or -1)
        if idx < 1 then idx = #PACK_SUBS elseif idx > #PACK_SUBS then idx = 1 end
        S.packSub = PACK_SUBS[idx]
      elseif isEnter(e) then
        if S.packSub == "archive" then
          local reason = packArchiveLocked()
          if reason then ui.openAlert(reason)
          else
            table.remove(packs, S.packDive)   -- archived for real on profile save
            S.packDive = nil
            S.packsCursor = math.min(S.packsCursor, #packs + 2)
          end
        else
          local p = packs[S.packDive]
          if S.packSub == "buydate" and not p.buyDate then p.buyDate = Buy.today() end
          S.packEdit = S.packSub
        end
      elseif isExit(e) then
        S.packDive = nil
      end
      return
    end
    S.packsCursor = ui.moveCursor(S.packsCursor, e, #packs + 2)
    if isEnter(e) then
      local c = S.packsCursor
      if c <= #packs then S.packDive, S.packSub = c, "cycles"
      elseif c == #packs + 1 then S.screen = "profile"
      elseif #packs >= MAX_PACKS then ui.openAlert("Max " .. MAX_PACKS .. " packs")
      else
        packs[#packs + 1] = { id = nil, label = nextLabel(packs), wear = 0, cycles = 0 }
        sortByLabel(packs)
      end
    elseif isExit(e) then
      S.screen = "profile"
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: statistics (read-only)
  -- ---------------------------------------------------------------------------

  function Screen.drawStats()
    ui.drawHeader("STATISTICS - " .. S.prof.name)
    local packs, C = S.prof.instances, COLOR_THEME_PRIMARY1
    local hy = ui.bodyY(1)
    lcd.drawText(SX.id,   hy, "ID",        C + BOLD)
    lcd.drawText(SX.cyc,  hy, "Cycles",    C + BOLD)
    lcd.drawText(SX.mah,  hy, "Life mAh",  C + BOLD)
    lcd.drawText(SX.vmin, hy, "Vmin",      C + BOLD)
    lcd.drawText(SX.last, hy, "Last used", C + BOLD)
    local n = #packs
    local start, last = ui.scrollWindow(S.statsCursor, n, 2)
    local dispRow = 1
    for i = start, last do
      local p = packs[i]
      dispRow = dispRow + 1
      local y = ui.bodyY(dispRow)
      lcd.drawText(SX.id,   y, "#" .. p.label, C + (S.statsCursor == i and INVERS or 0))
      lcd.drawText(SX.cyc,  y, tostring(p.cycles or 0),   C)
      lcd.drawText(SX.mah,  y, tostring(p.totalMah or 0), C)
      lcd.drawText(SX.vmin, y, p.minVCell and string.format("%.2f", p.minVCell) or "-", C)
      lcd.drawText(SX.last, y, p.lastUsed or "-", C)
    end
    ui.drawScrollbar(LCD_W - ui.PAD - 3, ui.bodyY(2), last - start + 1, start, n)
    ui.drawButtonBar({ "Back" }, n + 1, S.statsCursor)
  end

  function Screen.handleStats(e)
    local n = #S.prof.instances
    S.statsCursor = ui.moveCursor(S.statsCursor, e, n + 1)
    if isExit(e) or (isEnter(e) and S.statsCursor == n + 1) then S.screen = "profile" end
  end

  -- ---------------------------------------------------------------------------
  -- Page
  -- ---------------------------------------------------------------------------

  -- Complete half-set Low/Critical overrides once and persist that; a failed
  -- write is no error here, the next regular save carries it.
  if cfg then
    local changed = false
    for _, b in ipairs(cfg.batteries) do if pinOverrides(b) then changed = true end end
    if changed then core.saveConfig(cfg) end
  end

  local P = {}

  function P.draw()
    if not cfg then
      ui.drawHeader("BATTERIES")
      lcd.drawText(ui.COL1, ui.bodyY(1), "Lipo Nanny has no usable settings file.", COLOR_THEME_WARNING)
      lcd.drawText(ui.COL1, ui.bodyY(2), "Fix it in the Lipo Nanny app (start page).", COLOR_THEME_PRIMARY1)
      ui.drawButtonBar({ "Back" }, 1, 1)
      return
    end
    if S.screen == "profile" then Screen.drawProfile()
    elseif S.screen == "packs" then Screen.drawPacks()
    elseif S.screen == "stats" then Screen.drawStats()
    else Screen.drawList() end
  end

  -- Returns true to close the page.
  function P.handle(e)
    if not cfg then return isExit(e) or isEnter(e) end
    if S.screen == "profile" then Screen.handleProfile(e)
    elseif S.screen == "packs" then Screen.handlePacks(e)
    elseif S.screen == "stats" then Screen.handleStats(e)
    else return Screen.handleList(e) == true end
    return false
  end

  return P
end
