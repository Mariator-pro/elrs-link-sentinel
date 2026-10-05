-- =====================================================================
-- ui.lua  --  Shared building blocks of the Flight Bag settings tool
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/ui.lua
-- Header, rows, buttons, scrolling, the picker and dialog popups and the
-- save-with-retry helper. Loaded once by /SCRIPTS/TOOLS/FLIGHTBAG.lua and
-- handed to every page; the popups live here so any page can open them.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License version 2 as
-- published by the Free Software Foundation.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along
-- with this program; if not, write to the Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
-- =====================================================================

local U = {}

U.PAD  = 6
-- Row pitch. The screen-height fraction is only a load-time fallback (sizeText is
-- not valid until a frame runs); measure() raises it to the real font height on
-- the first frame, so rows and buttons never overlap. Read U.LINE at draw time.
U.LINE = math.max(18, math.floor(LCD_H / 13))
U.COL1 = U.PAD * 2                    -- label / entry column
U.COL2 = math.floor(LCD_W * 0.42)     -- value column of two-column rows
local PAD = U.PAD

function U.measure()
  if U.measured then return end
  local _, fh = lcd.sizeText("Mg")
  local _, bh = lcd.sizeText("Mg", BOLD)
  if fh and fh > 0 then U.LINE = math.max(U.LINE, fh + 8, (bh or 0) + 4) end
  U.measured = true
end

-- ---------------------------------------------------------------------------
-- Events (virtual keys)
-- ---------------------------------------------------------------------------

function U.isNext(e)  return e == EVT_VIRTUAL_NEXT or e == EVT_VIRTUAL_INC end
function U.isPrev(e)  return e == EVT_VIRTUAL_PREV or e == EVT_VIRTUAL_DEC end
function U.isEnter(e) return e == EVT_VIRTUAL_ENTER end
function U.isExit(e)  return e == EVT_VIRTUAL_EXIT end
-- MDL key (EVT_VIRTUAL_MENU); `or -1` so a firmware without it never matches nil.
local EVT_MENU = EVT_VIRTUAL_MENU or -1
function U.isMenu(e)  return e == EVT_MENU end

-- Moves a 1-based cursor within [1, count], clamped (no wrap).
function U.moveCursor(cur, e, count)
  if U.isNext(e) and cur < count then return cur + 1 end
  if U.isPrev(e) and cur > 1     then return cur - 1 end
  return cur
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

function U.headerH() return U.LINE + PAD end

function U.drawHeader(title)
  local h = U.headerH()
  lcd.drawFilledRectangle(0, 0, LCD_W, h, COLOR_THEME_SECONDARY1)
  local _, th = lcd.sizeText("Mg", BOLD)
  lcd.drawText(PAD, math.floor((h - th) / 2), title, COLOR_THEME_PRIMARY2 + BOLD)
end

function U.bodyY(row) return U.LINE + PAD * 2 + (row - 1) * U.LINE end

-- Navigation/action row at COL1: `folder` prefixes "> " and bolds it (opens a
-- sub-page), `disabled` dims it, the cursor row is drawn INVERS.
function U.drawNavRow(row, text, selected, opts)
  opts = opts or {}
  local flags = opts.disabled and COLOR_THEME_DISABLED or COLOR_THEME_PRIMARY1
  if opts.folder then text = "> " .. text; flags = flags + BOLD end
  if selected then flags = flags + INVERS end
  lcd.drawText(U.COL1, U.bodyY(row), text, flags)
end

-- Triangles drawn from stacked 1 px bars (no triangle primitive). (x, y) is the top-left.
U.ARROW_W   = 11
local ARROW_H   = math.ceil(U.ARROW_W / 2)
U.ARROW_GAP = 5
function U.drawDownArrow(x, y, color)
  for i = 0, ARROW_H - 1 do
    lcd.drawFilledRectangle(x + i, y + i, U.ARROW_W - 2 * i, 1, color)
  end
end
function U.drawRightArrow(x, y, color)
  for i = 0, ARROW_H - 1 do
    lcd.drawFilledRectangle(x + i, y + i, 1, U.ARROW_W - 2 * i, color)
  end
end

-- Popup arrow at (x, y), centred on the row; returns where the value text starts.
function U.drawArrowBefore(x, y, color)
  local _, th = lcd.sizeText("Mg")
  U.drawDownArrow(x, y + math.floor((th - ARROW_H) / 2), color)
  return x + U.ARROW_W + U.ARROW_GAP
end

-- Small filled "i" badge sized to SMLSIZE; returns the x where text should start.
function U.drawInfoBadge(x, y)
  local _, sh = lcd.sizeText("Mg", SMLSIZE)
  local r     = math.floor(sh / 2)
  lcd.drawFilledCircle(x + r, y + r, r, COLOR_THEME_FOCUS)
  local iw = lcd.sizeText("i", SMLSIZE)
  lcd.drawText(x + r - math.floor(iw / 2), y, "i", COLOR_THEME_PRIMARY2 + SMLSIZE)
  return x + 2 * r + U.ARROW_GAP
end

-- Two-column field row at y: label at COL1, value at opts.x or COL2. Only the
-- value is highlighted (INVERS when selected, BLINK+INVERS while editing), except
-- a folder field, where the label inverts. opts.popup adds a down-arrow (picker).
function U.drawFieldRowY(y, label, value, opts)
  opts = opts or {}
  local base   = opts.disabled and COLOR_THEME_DISABLED or COLOR_THEME_PRIMARY1
  local lflags = base
  if opts.folder then label = "> " .. label; lflags = lflags + BOLD end
  if opts.selected and opts.folder then lflags = lflags + INVERS end
  lcd.drawText(U.COL1, y, label, lflags)
  if value ~= nil then
    local vflags = opts.valueFlags or base
    if opts.editing then vflags = vflags + BLINK + INVERS
    elseif opts.selected and not opts.folder then vflags = vflags + INVERS end
    local x  = opts.x or U.COL2
    local vx = opts.popup and U.drawArrowBefore(x, y, base) or x
    lcd.drawText(vx, y, value, vflags)
  end
end

function U.drawFieldRow(row, label, value, opts)
  U.drawFieldRowY(U.bodyY(row), label, value, opts)
end

U.BTN_GAP  = 8
U.BTN_PADX = 6

-- Y of the separator above the bottom button bar (also the bottom of the
-- scrolling content); the buttons sit BTN_GAP below it and above the edge.
function U.barTopY()
  local _, th = lcd.sizeText("Mg")
  return LCD_H - (th + 4) - 2 * U.BTN_GAP
end

-- Scroll window for `n` rows starting at body row `top`, keeping `focus` centred
-- and clamped so neither end shows blank rows. Returns (first, last).
function U.scrollWindow(focus, n, top)
  local maxRows = math.max(1, math.floor((U.barTopY() - U.bodyY(top)) / U.LINE))
  focus = math.max(1, math.min(focus, n))
  local start = math.max(1, math.min(focus - math.floor(maxRows / 2), n - maxRows + 1))
  return start, math.min(n, start + maxRows - 1)
end

-- Track + proportional thumb at column sx (`shown` of `total` rows from `top`).
-- No-op when everything fits.
function U.drawScrollbar(sx, listY, shown, top, total)
  if shown >= total then return end
  local trackH = shown * U.LINE
  lcd.drawFilledRectangle(sx, listY, 3, trackH, COLOR_THEME_PRIMARY3)
  local thumbH = math.max(6, math.floor(trackH * shown / total))
  local thumbY = listY + math.floor(trackH * (top - 1) / total)
  lcd.drawFilledRectangle(sx, thumbY, 3, thumbH, COLOR_THEME_FOCUS)
end

-- One button at (x, y): outlined, filled with the accent colour when focused,
-- greyed and struck through when disabled. Returns its width.
function U.drawButton(x, y, label, focused, disabled)
  local _, th = lcd.sizeText("Mg")
  local w     = lcd.sizeText(label) + 2 * U.BTN_PADX
  if disabled then
    lcd.drawRectangle(x, y, w, th + 4, focused and COLOR_THEME_FOCUS or COLOR_THEME_DISABLED)
    lcd.drawText(x + U.BTN_PADX, y + 2, label, COLOR_THEME_DISABLED)
    lcd.drawFilledRectangle(x + U.BTN_PADX, y + 2 + math.floor(th / 2),
                            w - 2 * U.BTN_PADX, 2, COLOR_THEME_DISABLED)
  elseif focused then
    lcd.drawFilledRectangle(x, y, w, th + 4, COLOR_THEME_FOCUS)
    lcd.drawText(x + U.BTN_PADX, y + 2, label, COLOR_THEME_PRIMARY2)
  else
    lcd.drawRectangle(x, y, w, th + 4, COLOR_THEME_PRIMARY1)
    lcd.drawText(x + U.BTN_PADX, y + 2, label, COLOR_THEME_PRIMARY1)
  end
  return w
end

-- Bottom action bar; `firstItem` is the cursor index of labels[1]. Returns the
-- button boxes { x, y, w, h } for touch.
function U.drawButtonBar(labels, firstItem, cursor)
  local sepY = U.barTopY()
  local btnY = sepY + U.BTN_GAP
  local _, th = lcd.sizeText("Mg")
  lcd.drawFilledRectangle(PAD, sepY, LCD_W - 2 * PAD, 1, COLOR_THEME_PRIMARY3)
  local x, boxes = PAD, {}
  for i, label in ipairs(labels) do
    local w = U.drawButton(x, btnY, label, cursor == firstItem + i - 1)
    boxes[i] = { x = x, y = btnY, w = w, h = th + 4 }
    x = x + w + PAD
  end
  return boxes
end

-- Blue chip with a key name plus its action at (x, y); returns the next x.
function U.drawKeyChip(x, y, key, action)
  local kw, kh = lcd.sizeText(key)
  lcd.drawFilledRectangle(x, y - 1, kw + 4, kh + 2, COLOR_THEME_FOCUS)
  lcd.drawText(x + 2, y, key, COLOR_THEME_PRIMARY2)
  lcd.drawText(x + kw + 8, y, action, COLOR_THEME_PRIMARY1)
  return x + kw + 8 + lcd.sizeText(action)
end

-- Right-aligned key chip, skipped when it would overlap the value ending at valueRight.
function U.drawKeyHint(y, key, action, valueRight)
  local x = LCD_W - PAD - (lcd.sizeText(key) + 8 + lcd.sizeText(action))
  if valueRight and valueRight + PAD > x then return end
  U.drawKeyChip(x, y, key, action)
end

-- One-line hint with the info badge, pinned just above the button bar.
function U.drawHint(text)
  local _, sh = lcd.sizeText("Mg", SMLSIZE)
  local y = U.barTopY() - sh - 4
  lcd.drawText(U.drawInfoBadge(U.COL1, y), y, text, COLOR_THEME_PRIMARY1 + SMLSIZE)
end

-- Filled rectangle with rounded corners: no such primitive in the Lua API, so two
-- overlapping bars plus four corner circles.
function U.fillRounded(x, y, w, h, r, color)
  lcd.drawFilledRectangle(x + r, y, w - 2 * r, h, color)
  lcd.drawFilledRectangle(x, y + r, w, h - 2 * r, color)
  for _, c in ipairs({ { x + r, y + r }, { x + w - r - 1, y + r },
                       { x + r, y + h - r - 1 }, { x + w - r - 1, y + h - r - 1 } }) do
    lcd.drawFilledCircle(c[1], c[2], r, color)
  end
end

-- Full-screen shade behind a popup (opacity 0 = solid, 15 = invisible).
function U.dimScreen()
  lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, lcd.RGB(0, 0, 0), 9)
end

-- Word wrap to lines no wider than maxW px, breaking on spaces; "\n" forces a break.
function U.wrapText(text, maxW, flags)
  local lines, segStart = {}, 1
  while true do
    local nl  = string.find(text, "\n", segStart, true)
    local seg = string.sub(text, segStart, nl and nl - 1 or #text)
    local line = ""
    for word in string.gmatch(seg, "%S+") do
      local cand = (line == "") and word or (line .. " " .. word)
      if line ~= "" and lcd.sizeText(cand, flags) > maxW then
        lines[#lines + 1] = line
        line = word
      else
        line = cand
      end
    end
    lines[#lines + 1] = line
    if not nl then break end
    segStart = nl + 1
  end
  return lines
end

-- ---------------------------------------------------------------------------
-- Dialogs: confirm (Yes/No), alert (OK), info rows (label/value columns)
-- ---------------------------------------------------------------------------

function U.openDialog(text, onYes, yesLabel, noLabel)
  U.dialog = { text = text, onYes = onYes, cursor = 2,   -- default to the safe answer
               yes = yesLabel or "Yes", no = noLabel or "No" }
end

function U.openAlert(text) U.dialog = { text = text, alert = true } end

function U.openInfoRows(rows) U.dialog = { rows = rows, alert = true } end

local function drawDialog()
  local d = U.dialog
  local LINE = U.LINE
  U.dimScreen()
  local lines, labelW, valueW = nil, 0, 0
  if d.rows then
    for _, r in ipairs(d.rows) do
      labelW = math.max(labelW, lcd.sizeText(r[1]))
      valueW = math.max(valueW, lcd.sizeText(r[2]))
    end
  end
  local w = d.rows and math.min(LCD_W - 2 * PAD, labelW + PAD + valueW + 2 * PAD)
                    or  math.floor(LCD_W * 0.8)
  local x = math.floor((LCD_W - w) / 2)
  if not d.rows then lines = U.wrapText(d.text, w - 2 * PAD) end
  local rowN = d.rows and #d.rows or #lines
  local h    = (rowN + 2) * LINE + PAD * 2
  local y    = math.floor((LCD_H - h) / 2)
  lcd.drawFilledRectangle(x + 3, y + 3, w, h, COLOR_THEME_PRIMARY1)
  lcd.drawFilledRectangle(x, y, w, h, COLOR_THEME_SECONDARY3)
  lcd.drawRectangle(x, y, w, h, COLOR_THEME_SECONDARY1)
  if d.rows then
    local valueX = x + PAD + labelW + PAD
    for i, r in ipairs(d.rows) do
      local ry = y + PAD + (i - 1) * LINE
      lcd.drawText(x + PAD, ry, r[1], COLOR_THEME_PRIMARY1)
      lcd.drawText(valueX,  ry, r[2], COLOR_THEME_PRIMARY1)
    end
  else
    for i, line in ipairs(lines) do
      lcd.drawText(x + PAD, y + PAD + (i - 1) * LINE, line, COLOR_THEME_PRIMARY1)
    end
  end
  local btnY = y + h - LINE - PAD
  if d.alert then
    local okW = lcd.sizeText("OK") + 2 * U.BTN_PADX
    U.drawButton(math.floor((LCD_W - okW) / 2), btnY, "OK", true)
  else
    U.drawButton(x + PAD * 2,                 btnY, d.yes, d.cursor == 1)
    U.drawButton(x + math.floor(w / 2) + PAD, btnY, d.no,  d.cursor == 2)
  end
end

local function handleDialog(e)
  local d = U.dialog
  if d.alert then
    if U.isEnter(e) or U.isExit(e) then U.dialog = nil end
    return
  end
  if U.isNext(e) or U.isPrev(e) then
    d.cursor = (d.cursor == 1) and 2 or 1
  elseif U.isEnter(e) then
    U.dialog = nil
    if d.cursor == 1 and d.onYes then d.onYes() end
  elseif U.isExit(e) then
    U.dialog = nil
  end
end

-- ---------------------------------------------------------------------------
-- Scrollable picker popup: `sel` pre-selected, onPick(idx) on ENTER, EXIT cancels
-- ---------------------------------------------------------------------------

local PICK_ROWS, PICK_INDENT = 5, 8

function U.openPicker(title, labels, sel, onPick)
  U.picker = { title = title, labels = labels, sel = sel or 1, top = 1, onPick = onPick }
end

local function pickerRows()
  local _, hh  = lcd.sizeText("Mg", BOLD)
  local maxFit = math.floor((LCD_H - 2 * U.LINE - hh - 2 * PAD) / U.LINE)
  return math.max(1, math.min(PICK_ROWS, #U.picker.labels, maxFit))
end

local function drawPicker()
  local p     = U.picker
  local LINE  = U.LINE
  local n     = #p.labels
  local rows  = pickerRows()
  local _, th = lcd.sizeText("Mg")
  local _, hh = lcd.sizeText("Mg", BOLD)
  local headH = hh + 6
  local w     = math.floor(LCD_W * 0.58)
  local h     = headH + rows * LINE + 4
  local x     = math.floor((LCD_W - w) / 2)
  local y     = math.floor((LCD_H - h) / 2)
  local textY = math.floor((LINE - th) / 2)
  U.dimScreen()
  lcd.drawFilledRectangle(x + 3, y + 3, w, h, COLOR_THEME_PRIMARY1)
  lcd.drawFilledRectangle(x, y, w, h, COLOR_THEME_SECONDARY3)
  lcd.drawRectangle(x, y, w, h, COLOR_THEME_SECONDARY1)
  lcd.drawFilledRectangle(x, y, w, headH, COLOR_THEME_SECONDARY1)
  lcd.drawText(x + PICK_INDENT, y + 3, p.title, COLOR_THEME_PRIMARY2 + BOLD)
  lcd.drawText(x + w - PICK_INDENT, y + 3, p.sel .. "/" .. n, COLOR_THEME_PRIMARY2 + RIGHT)
  local listY = y + headH
  for i = 0, rows - 1 do
    local idx = p.top + i
    if idx <= n then
      local ry = listY + i * LINE
      if idx == p.sel then
        lcd.drawFilledRectangle(x, ry, w - (n > rows and 5 or 0), LINE, COLOR_THEME_FOCUS)
        lcd.drawText(x + PICK_INDENT, ry + textY, p.labels[idx], COLOR_THEME_PRIMARY2)
      else
        lcd.drawText(x + PICK_INDENT, ry + textY, p.labels[idx], COLOR_THEME_PRIMARY1)
      end
    end
  end
  U.drawScrollbar(x + w - 4, listY, rows, p.top, n)
end

local function handlePicker(e)
  local p = U.picker
  local n = #p.labels
  if U.isNext(e) or U.isPrev(e) then
    p.sel = U.isNext(e) and (p.sel % n + 1) or ((p.sel - 2) % n + 1)
    local rows = pickerRows()
    if p.sel < p.top then p.top = p.sel end
    if p.sel > p.top + rows - 1 then p.top = p.sel - rows + 1 end
  elseif U.isEnter(e) then
    U.picker = nil
    if p.onPick then p.onPick(p.sel) end
  elseif U.isExit(e) then
    U.picker = nil
  end
end

-- True while a popup is open; it takes the event (handled here).
function U.handleOverlay(e)
  if U.dialog then handleDialog(e); return true end
  if U.picker then handlePicker(e); return true end
  return false
end

function U.drawOverlay()
  if U.picker then drawPicker() end
  if U.dialog then drawDialog() end
end

-- Runs a write (returns true on success); on failure a Retry / Cancel dialog
-- re-runs it, on success onDone runs. The write must be idempotent.
function U.withRetry(writeFn, onDone)
  if writeFn() then
    if onDone then onDone() end
  else
    U.openDialog("Save failed. Check SD card.",
                 function() U.withRetry(writeFn, onDone) end, "Retry", "Cancel")
  end
end

-- ---------------------------------------------------------------------------
-- Shared helpers for the pages
-- ---------------------------------------------------------------------------

-- Sorted *.wav names in `dir` (no trailing slash), without the `skip` names and
-- dot files (macOS "._name.wav" companions). pcall: dir() raises when the folder
-- is missing. Free string functions: EdgeTX has no string methods.
function U.listWavs(folder, skip)
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

-- The model's EdgeTX display name, read from the head of /MODELS/<filename>
-- (first `name:` field); falls back to the filename, cached per session.
local modelNames = {}
function U.modelName(filename)
  if not filename then return "?" end
  if modelNames[filename] == nil then
    local name = filename
    local ok, f = pcall(io.open, "/MODELS/" .. filename, "r")
    if ok and f then
      local rok, head = pcall(io.read, f, 512)
      pcall(io.close, f)
      local m = rok and head and string.match(head, 'name:%s*"(.-)"')
      if m and m ~= "" then name = m end
    end
    modelNames[filename] = name
  end
  return modelNames[filename]
end

-- Filename of the active model, or nil.
function U.activeModel()
  local ok, info = pcall(model.getInfo)
  if ok and type(info) == "table" then return info.filename end
  return nil
end

-- Vibration preview for a Test button: `pulses` pulses at the given strength.
function U.testHaptic(on, strength, dur, pulses)
  if not on or not playHaptic or not dur then return end
  local d = dur[strength] or dur[2]
  for i = 1, pulses or 1 do
    playHaptic(d, (i < (pulses or 1)) and d or 0)
  end
end

return U
