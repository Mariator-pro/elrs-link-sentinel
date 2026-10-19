-- =====================================================================
-- batteries.lua  --  Flight Bag page "Batteries" (Lipo Nanny)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/batteries.lua
-- Drawn view of batteries_model.lua: list, profile editor (name and
-- manufacturer through a character ring), packs (cycles, wear, purchase date,
-- add / archive) and the read-only per-pack statistics.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

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

return function(ctx)
  local ui = ctx.ui
  local M = loadScript("/SCRIPTS/FLIGHTBAG/batteries_model.lua")()(ctx)
  local TEXT_MAX, Buy = M.TEXT_MAX, M.Buy

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
    ui.withRetry(M.write, onDone)
  end

  -- ---------------------------------------------------------------------------
  -- Screen: list
  -- ---------------------------------------------------------------------------

  function Screen.drawList()
    ui.drawHeader("BATTERIES")
    local items = M.sorted()
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
    local items = M.sorted()
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
    M.open(existing)
    S.profCursor, S.profEditing, S.capStep = 1, nil, 100
    S.textBuf, S.textCharMode, S.textSnapshot = nil, false, nil
    S.screen = "profile"
  end

  local function buildProfileLines()
    local p, lines = M.prof, {}
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
    field(8, "Battery low", M.pctText("warnPct"))
    field(9, "Battery critical", M.pctText("critPct"))
    return lines
  end

  local function profileActions()
    local acts = { "Back", "Save" }
    if not M.isNew then acts[#acts + 1] = "Delete" end
    if not M.prof.nameAuto then acts[#acts + 1] = "Reset name" end
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
    S.textBuf      = (field == 2) and M.prof.manufacturer or M.prof.name
    S.textMax      = (field == 2) and TEXT_MAX.mfr or TEXT_MAX.name
    S.textPos, S.textCharMode, S.textSnapshot = 1, false, nil
  end

  local function cancelTextEdit()
    S.profEditing, S.textBuf, S.textCharMode, S.textSnapshot = nil, nil, false, nil
  end

  local function commitTextEdit()
    M.setText(S.profEditing, S.textBuf)
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
    local item, p = S.profEditing, M.prof
    local d = isNext(e) and 1 or (isPrev(e) and -1 or 0)
    if item == 3 then
      local n = #M.CHEM_NAMES
      M.setChemistry((M.chemIndex() - 1 + d) % n + 1)
    elseif item == 4 then
      if ui.isMenu(e) then
        S.capStep = (S.capStep == 10 and 100) or (S.capStep == 100 and 1000) or 10
      else
        M.setCapacity(p.capacityMah + d * S.capStep)
      end
    elseif item == 5 then
      M.setCells(p.cells + d)
    elseif (item == 8 or item == 9) and d ~= 0 then
      local key = (item == 8) and "warnPct" or "critPct"
      M.setPct(key, M.pct(key) + d)
    end
    if isEnter(e) then S.profEditing = nil end
  end

  function Screen.drawProfile()
    if S.profEditing == 1 or S.profEditing == 2 then drawTextEditor(); return end
    ui.drawHeader(M.isNew and "ADD BATTERY" or "EDIT BATTERY")
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

  local function saveProfile()
    local msg = M.invalid()
    if msg then ui.openAlert(msg); return end
    M.commit()
    save(gotoList)
  end

  local function deleteProfile()
    local msg = M.deleteBlocked()
    if msg then ui.openAlert(msg); return end
    ui.openDialog(M.deleteQuestion(), function()
      M.delete()
      save(gotoList)
    end)
  end

  local function cancelProfile()
    if not M.dirty() then gotoList()
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
          M.resetName()
          S.profCursor = 1
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

  function Nav.enterPacks()
    S.packsCursor, S.packDive, S.packSub = 1, nil, "cycles"
    S.packEdit = nil
    S.screen = "packs"
  end

  function Screen.drawPacks()
    ui.drawHeader("PACKS - " .. M.prof.name)
    local packs, C = M.prof.instances, COLOR_THEME_PRIMARY1
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
    local packs = M.prof.instances
    if S.packEdit then
      local p = packs[S.packDive]
      local d = isNext(e) and 1 or (isPrev(e) and -1 or 0)
      if d ~= 0 then
        if S.packEdit == "cycles" then M.setCycles(p, (p.cycles or 0) + d)
        elseif S.packEdit == "wear" then M.setWear(p, p.wear + d)
        else M.setBuy(p, (Buy.toMonths(p.buyDate) or Buy.MIN) + d) end
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
          local reason = M.archiveLocked()
          if reason then ui.openAlert(reason)
          else
            M.removePack(S.packDive)   -- archived for real on profile save
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
      else
        local msg = M.addPack()
        if msg then ui.openAlert(msg) end
      end
    elseif isExit(e) then
      S.screen = "profile"
    end
  end

  -- ---------------------------------------------------------------------------
  -- Screen: statistics (read-only)
  -- ---------------------------------------------------------------------------

  function Screen.drawStats()
    ui.drawHeader("STATISTICS - " .. M.prof.name)
    local packs, C = M.prof.instances, COLOR_THEME_PRIMARY1
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
    local n = #M.prof.instances
    S.statsCursor = ui.moveCursor(S.statsCursor, e, n + 1)
    if isExit(e) or (isEnter(e) and S.statsCursor == n + 1) then S.screen = "profile" end
  end

  -- ---------------------------------------------------------------------------
  -- Page
  -- ---------------------------------------------------------------------------

  local P = {}

  function P.draw()
    if M.broken then
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
    if M.broken then return isExit(e) or isEnter(e) end
    if S.screen == "profile" then Screen.handleProfile(e)
    elseif S.screen == "packs" then Screen.handlePacks(e)
    elseif S.screen == "stats" then Screen.handleStats(e)
    else return Screen.handleList(e) == true end
    return false
  end

  return P
end
