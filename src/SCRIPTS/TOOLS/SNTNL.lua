-- TNS|Link Sentinel|TNE
-- =====================================================================
-- SNTNL.lua  --  EdgeTX Tools Script for ELRS Link Sentinel configuration
-- =====================================================================
-- SD card path: /SCRIPTS/TOOLS/SNTNL.lua
-- Writes the optional shared config /SCRIPTS/SNTNL/config.lua that core.lua
-- (both the function script and the widget) overlays at runtime. The config is
-- OPTIONAL: without it the hard-coded defaults in core.lua stay in force.
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

local VERSION        = "2.1.0"
local SCHEMA_VERSION = 1
local CORE_PATH      = "/SCRIPTS/SNTNL/core.lua"
local PATHS = {
  config    = "/SCRIPTS/SNTNL/config.lua",
  soundDir  = "/SOUNDS/en/SCRIPTS/SNTNL/",   -- trailing slash: prefix for full paths
  soundList = "/SOUNDS/en/SCRIPTS/SNTNL",    -- no trailing slash: passed to dir()
}

-- ---------------------------------------------------------------------------
-- Shared core module (read-only here): the editable ranges, the threshold
-- defaults and the default sound paths all live in core, so the on-radio editor
-- can never drift from what core actually enforces. Inline fallbacks keep the
-- tool usable if core is missing (it then just writes a config core will clamp).
-- ---------------------------------------------------------------------------
local core
do
  local chunk = loadScript and loadScript(CORE_PATH)
  if chunk then
    local ok, mod = pcall(chunk)
    if ok then core = mod end
  end
end

local LIMITS = (core and core.LIMITS) or {
  WARN_OFFSET_DB = { min = 10, max = 30 },
  RQLY_THRESHOLD = { min = 30, max = 70 },
}
local DEF_OFFSET     = (core and core.PARAMS and core.PARAMS.WARN_OFFSET_DB) or 10
local DEF_RQLY       = (core and core.PARAMS and core.PARAMS.RQLY_THRESHOLD) or 42
-- Haptic feedback: on/off plus a 1..3 strength tier. Defaults and pulse lengths
-- come from core when present so the Test button previews the exact buzz a real
-- warning fires; labels are the user-facing tier names.
local HAPTIC = {
  min       = 1, max = 3,
  default   = (core and core.PARAMS and core.PARAMS.HAPTIC_STRENGTH) or 2,
  defaultOn = (core and core.PARAMS and core.PARAMS.HAPTIC) == true,
  labels    = { "Soft", "Normal", "Strong" },
  dur       = (core and core.HAPTIC_DUR) or { 15, 30, 50 },
}

-- A config's strength, clamped to range and defaulted when missing/garbage.
function HAPTIC.strengthOf(cfg)
  local hs = cfg.hapticStrength
  if type(hs) == "number" and hs >= HAPTIC.min and hs <= HAPTIC.max then return hs end
  return HAPTIC.default
end

-- Buzz alongside a Test preview, mirroring the warning cue: pulses=1 for Stage 1,
-- 2 for Stage 2. Uses the strength currently set in the tool (not the saved
-- config). No-op when haptic is off or playHaptic is absent (desktop / motorless).
function HAPTIC.test(on, strength, pulses)
  if not on or not playHaptic then return end
  local s = strength
  if type(s) ~= "number" or s < HAPTIC.min or s > HAPTIC.max then s = HAPTIC.default end
  local dur = HAPTIC.dur[s]   -- s is clamped to 1..3, so always a valid index
  for i = 1, pulses do
    playHaptic(dur, (i < pulses) and dur or 0)   -- gap between pulses, none after the last
  end
end
PATHS.s1Default  = (core and core.SOUNDS and core.SOUNDS.stage1) or (PATHS.soundDir .. "stage1.wav")
PATHS.s2Default  = (core and core.SOUNDS and core.SOUNDS.stage2) or (PATHS.soundDir .. "stage2.wav")

-- ---------------------------------------------------------------------------
-- Serialization (same table shape core loads) + file write
-- ---------------------------------------------------------------------------

local function quoteString(s)
  s = string.gsub(s, "\\", "\\\\")
  s = string.gsub(s, '"', '\\"')
  s = string.gsub(s, "\n", "\\n")
  return '"' .. s .. '"'
end

local function serialize(value, indent)
  local t = type(value)
  if t == "number" or t == "boolean" then
    return tostring(value)
  elseif t == "string" then
    return quoteString(value)
  elseif t == "table" then
    local nextIndent = indent .. "  "
    local parts      = {}
    local arrayLen   = #value
    for i = 1, arrayLen do
      parts[#parts + 1] = nextIndent .. serialize(value[i], nextIndent)
    end
    for k, v in pairs(value) do
      local isArrayIndex = type(k) == "number" and k >= 1 and k <= arrayLen
                           and math.floor(k) == k
      if not isArrayIndex then
        local keyStr
        if type(k) == "string" then
          keyStr = "[" .. quoteString(k) .. "]"
        else
          keyStr = "[" .. tostring(k) .. "]"
        end
        parts[#parts + 1] = nextIndent .. keyStr .. " = " .. serialize(v, nextIndent)
      end
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
  end
  return "nil"
end

-- Reads a whole file (block reads; "a" format is not on every build), or nil.
local function readFile(path)
  local ok, f = pcall(io.open, path, "r")
  if not ok or not f then return nil end
  local parts = {}
  while true do
    local rok, chunk = pcall(io.read, f, 4096)
    if not rok or not chunk or chunk == "" then break end
    parts[#parts + 1] = chunk
  end
  pcall(io.close, f)
  return table.concat(parts)
end

-- io.open "w" does NOT truncate on some EdgeTX/SD builds, so a shorter write
-- would leave the old tail behind -- pad with trailing newlines (valid after the
-- table) up to the old length. Pcall-wrapped so a full/read-only SD never raises.
local function writeFile(path, content)
  local old = readFile(path)
  if old and #old > #content then
    content = content .. string.rep("\n", #old - #content)
  end
  local ok, f = pcall(io.open, path, "w")
  if not ok or not f then return false end
  local wok = pcall(io.write, f, content)
  pcall(io.close, f)
  return wok == true
end

-- ---------------------------------------------------------------------------
-- Config load / default / save
-- ---------------------------------------------------------------------------

-- Returns (config) on success, or (nil, errKind, detail) where errKind is
-- "missing" | "parse" | "schema".
local function loadConfig()
  local ok, f = pcall(io.open, PATHS.config, "r")
  if not ok or not f then return nil, "missing" end
  pcall(io.close, f)

  local pok, result = pcall(dofile, PATHS.config)
  if not pok then return nil, "parse", tostring(result) end
  if type(result) ~= "table" then return nil, "parse", "not a table" end
  if result.schemaVersion ~= SCHEMA_VERSION then
    return nil, "schema", tostring(result.schemaVersion)
  end
  result.sounds = result.sounds or {}
  return result
end

local function defaultConfig()
  return {
    schemaVersion  = SCHEMA_VERSION,
    warnOffsetDb   = DEF_OFFSET,
    rqlyThreshold  = DEF_RQLY,
    haptic         = HAPTIC.defaultOn,
    hapticStrength = HAPTIC.default,
    sounds         = {},
  }
end

-- Writes the config. core reads it once at load (no reload sentinel needed --
-- a change takes effect on the next model select / reboot). Returns true on success.
local function saveConfig(cfg)
  local content = "-- ELRS Link Sentinel configuration (auto-generated by the Tools-Script).\n"
                  .. "return " .. serialize(cfg, "") .. "\n"
  return writeFile(PATHS.config, content)
end

-- ---------------------------------------------------------------------------
-- Custom warning sounds
-- ---------------------------------------------------------------------------

-- Excluded from the named list -- the two stage defaults are reachable via the
-- "Default" option, and cfgerr is not user-selectable here.
local SOUND_DEFAULT_FILES = { ["stage1.wav"] = true, ["stage2.wav"] = true, ["cfgerr.wav"] = true }

-- Sorted *.wav files in the sound folder (any user-named file shows up). pcall:
-- dir() raises when the folder is missing. string.lower/match as free functions:
-- EdgeTX-Lua has no string methods (fname:lower() would raise on the radio).
-- Names starting with "." are skipped: macOS writes "._name.wav" AppleDouble
-- metadata companions onto FAT/exFAT cards -- those are not playable audio.
local function listSoundFiles()
  local files = {}
  pcall(function()
    for fname in dir(PATHS.soundList) do
      if type(fname) == "string" and string.match(string.lower(fname), "%.wav$")
         and string.sub(fname, 1, 1) ~= "." and not SOUND_DEFAULT_FILES[fname] then
        files[#files + 1] = fname
      end
    end
  end)
  table.sort(files, function(a, b) return string.lower(a) < string.lower(b) end)
  return files
end

-- Picker options { label, path }; index 1 is the default, stored as nil in the
-- config so a deleted file falls back to the bundled default instead of breaking.
local function buildSoundOptions(defaultPath, files)
  local opts = { { label = "Default", path = defaultPath } }
  for _, fname in ipairs(files) do
    opts[#opts + 1] = { label = fname, path = PATHS.soundDir .. fname }
  end
  return opts
end

-- 1-based index of the option matching `path` (nil or no-longer-present -> 1 = Default).
local function soundOptionIndex(opts, path)
  if path then
    for i, o in ipairs(opts) do if o.path == path then return i end end
  end
  return 1
end

-- Config value for a selection: nil for Default, else the chosen file's path.
local function soundConfigValue(opts, idx)
  return (idx > 1) and opts[idx].path or nil
end

-- ---------------------------------------------------------------------------
-- UI state
-- ---------------------------------------------------------------------------

local SCREEN = {
  CONFIG_ERROR = "config_error",
  MAIN         = "main",
  SETTINGS     = "settings",
  ABOUT        = "about",
}

local S = {
  screen    = SCREEN.MAIN,
  cfg       = nil,
  err       = nil,
  errDetail = nil,
  cursor    = 1,
  dialog    = nil,   -- { text, yes, no, onYes } or { rows = {{label,value},...} }
  picker    = nil,
  -- Settings editor working state
  set        = nil,  -- { offset, rqly, s1Idx, s2Idx }
  setEditing = false,
  setField   = nil,  -- "offset" | "rqly"
  setOrig    = nil,
  setDive    = nil,  -- focused row (1 = Stage 1, 2 = Stage 2), or nil at top level
  setSub     = "thr",
}

-- ---------------------------------------------------------------------------
-- Event helpers (virtual keys)
-- ---------------------------------------------------------------------------

local function isNext(e)
  return e == EVT_VIRTUAL_NEXT or e == EVT_VIRTUAL_INC
end
local function isPrev(e)
  return e == EVT_VIRTUAL_PREV or e == EVT_VIRTUAL_DEC
end
local function isEnter(e) return e == EVT_VIRTUAL_ENTER end
local function isExit(e)  return e == EVT_VIRTUAL_EXIT end

-- Moves a 1-based cursor within [1, count], clamped (no wrap).
local function moveCursor(cur, e, count)
  if isNext(e) and cur < count then return cur + 1 end
  if isPrev(e) and cur > 1     then return cur - 1 end
  return cur
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------

local PAD  = 6
-- Row pitch. The screen-height fraction is only a load-time fallback (sizeText is
-- not valid until a frame runs); draw() raises LINE to the real font height on the
-- first frame, so rows and buttons never overlap.
local LINE = math.max(18, math.floor(LCD_H / 13))
local COL1 = PAD * 2                    -- label / entry column

-- Settings table column x-anchors (Warning label / Threshold / Sound / Test).
local ST_WARN, ST_THR, ST_SND, ST_TEST =
  COL1, math.floor(LCD_W * 0.26), math.floor(LCD_W * 0.48), math.floor(LCD_W * 0.74)

local function drawHeader(title)
  local h = LINE + PAD
  lcd.drawFilledRectangle(0, 0, LCD_W, h, COLOR_THEME_SECONDARY1)
  local _, th = lcd.sizeText("Mg")            -- font height; vertically centre the title
  lcd.drawText(PAD, math.floor((h - th) / 2), title, COLOR_THEME_PRIMARY2 + BOLD)
end

local function bodyY(row)
  return LINE + PAD * 2 + (row - 1) * LINE
end

-- Selection inverts the text (no focus bar). A navigation row is a single string
-- at COL1: `folder` prefixes "> " and bolds it (opens a sub-page); the cursor row
-- is drawn INVERS.
local function drawNavRow(row, text, selected, opts)
  opts = opts or {}
  local flags = COLOR_THEME_PRIMARY1
  if opts.folder then text = "> " .. text; flags = flags + BOLD end
  if selected then flags = flags + INVERS end
  lcd.drawText(COL1, bodyY(row), text, flags)
end

-- Downward triangle marking a field that opens a picker popup. Stacked 1px rows.
local ARROW_W   = 11
local ARROW_H   = math.ceil(ARROW_W / 2)
local ARROW_GAP = 5
local function drawDownArrow(x, y, color)
  for i = 0, ARROW_H - 1 do
    lcd.drawFilledRectangle(x + i, y + i, ARROW_W - 2 * i, 1, color)
  end
end

-- Same triangle rotated 90 deg to point right, marking a row that dives into a
-- sub-context (the Stage rows). (x, y) is the top-left.
local function drawRightArrow(x, y, color)
  for i = 0, ARROW_H - 1 do
    lcd.drawFilledRectangle(x + i, y + i, 1, ARROW_W - 2 * i, color)
  end
end

-- Draws the popup arrow at (x, y), vertically centred on the row; returns the x
-- where the value text should start (right of the arrow).
local function drawArrowBefore(x, y, color)
  local _, th = lcd.sizeText("Mg")
  drawDownArrow(x, y + math.floor((th - ARROW_H) / 2), color)
  return x + ARROW_W + ARROW_GAP
end

-- Small "i" badge marking a line as a hint; returns the x where its text starts.
local function drawInfoBadge(x, y)
  local _, sh = lcd.sizeText("Mg", SMLSIZE)
  local r     = math.floor(sh / 2)
  lcd.drawFilledCircle(x + r, y + r, r, COLOR_THEME_FOCUS)
  local iw = lcd.sizeText("i", SMLSIZE)
  lcd.drawText(x + r - math.floor(iw / 2), y, "i", COLOR_THEME_PRIMARY2 + SMLSIZE)
  return x + 2 * r + ARROW_GAP
end

-- Gap (px) between the separator line and the bottom button row.
local BTN_GAP = 8

-- Y of the separator line above the bottom button bar.
local function barTopY()
  local _, th = lcd.sizeText("Mg")
  return LCD_H - (th + 4) - 2 * BTN_GAP
end

-- Draws one button at (x, y): outlined, or filled with the accent colour when
-- focused. Returns its width so callers can lay several out in a row.
local BTN_PADX = 6
local function drawButton(x, y, label, focused)
  local _, th = lcd.sizeText("Mg")
  local w     = lcd.sizeText(label) + 2 * BTN_PADX
  if focused then
    lcd.drawFilledRectangle(x, y, w, th + 4, COLOR_THEME_FOCUS)
    lcd.drawText(x + BTN_PADX, y + 2, label, COLOR_THEME_PRIMARY2)
  else
    lcd.drawRectangle(x, y, w, th + 4, COLOR_THEME_PRIMARY1)
    lcd.drawText(x + BTN_PADX, y + 2, label, COLOR_THEME_PRIMARY1)
  end
  return w
end

-- Bottom action bar; `firstItem` is the cursor index of labels[1].
local function drawButtonBar(labels, firstItem, cursor)
  local sepY = barTopY()
  local btnY = sepY + BTN_GAP
  lcd.drawFilledRectangle(PAD, sepY, LCD_W - 2 * PAD, 1, COLOR_THEME_PRIMARY3)
  local x = PAD
  for i, label in ipairs(labels) do
    local w = drawButton(x, btnY, label, cursor == firstItem + i - 1)
    x = x + w + PAD
  end
end

-- Full-screen shade behind a popup/dialog. opacity 0 = solid, 15 = invisible.
local DIM_OPACITY = 9
local function dimScreen()
  lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, lcd.RGB(0, 0, 0), DIM_OPACITY)
end

-- ---------------------------------------------------------------------------
-- Generic confirm dialog (Yes/No, EXIT cancels)
-- ---------------------------------------------------------------------------

local function openDialog(text, onYes, yesLabel, noLabel)
  S.dialog = { text = text, onYes = onYes, cursor = 2,  -- default to the safe answer
               yes = yesLabel or "Yes", no = noLabel or "No" }
end

-- Two-column info popup from {label, value} pairs; geometry/alignment are
-- computed at draw time (lcd.sizeText). ENTER or EXIT dismisses it.
local function openInfoRows(rows)
  S.dialog = { rows = rows }
end

-- Word-wraps `text` to lines no wider than maxW px, breaking on spaces.
local function wrapText(text, maxW)
  local lines, line = {}, ""
  local i, n = 1, #text
  while i <= n do
    local sp = string.find(text, " ", i, true)
    local word
    if sp then word = string.sub(text, i, sp - 1); i = sp + 1
    else       word = string.sub(text, i);         i = n + 1 end
    local cand = (line == "") and word or (line .. " " .. word)
    if line ~= "" and lcd.sizeText(cand) > maxW then
      lines[#lines + 1] = line
      line = word
    else
      line = cand
    end
  end
  lines[#lines + 1] = line
  return lines
end

-- Two-column popup: every value starts at one fixed x (no space padding -- the
-- column is measured here so it survives the proportional font).
local function drawInfoRows(d)
  local rows = d.rows
  local gap  = PAD * 2
  local labelW, valueW = 0, 0
  for _, it in ipairs(rows) do
    labelW = math.max(labelW, lcd.sizeText(it[1]))
    valueW = math.max(valueW, lcd.sizeText(it[2]))
  end
  local w = math.min(LCD_W - 2 * PAD, labelW + gap + valueW + 2 * PAD)
  local x = math.floor((LCD_W - w) / 2)
  local h = (#rows + 2) * LINE + PAD * 2
  local y = math.floor((LCD_H - h) / 2)
  dimScreen()
  lcd.drawFilledRectangle(x + 3, y + 3, w, h, COLOR_THEME_PRIMARY1)
  lcd.drawFilledRectangle(x, y, w, h, COLOR_THEME_SECONDARY3)
  lcd.drawRectangle(x, y, w, h, COLOR_THEME_SECONDARY1)
  local valX = x + PAD + labelW + gap            -- shared value column
  for i, it in ipairs(rows) do
    local ry = y + PAD + (i - 1) * LINE
    lcd.drawText(x + PAD, ry, it[1], COLOR_THEME_PRIMARY1)
    lcd.drawText(valX,    ry, it[2], COLOR_THEME_PRIMARY1)
  end
  drawButton(x + PAD * 2, y + h - LINE - PAD, "Close", true)
end

local function drawDialog()
  local d = S.dialog
  if d.rows then drawInfoRows(d); return end
  dimScreen()
  local w     = math.floor(LCD_W * 0.8)
  local x     = math.floor((LCD_W - w) / 2)
  local lines = wrapText(d.text, w - 2 * PAD)
  local h     = (#lines + 2) * LINE + PAD * 2
  local y     = math.floor((LCD_H - h) / 2)
  lcd.drawFilledRectangle(x + 3, y + 3, w, h, COLOR_THEME_PRIMARY1)
  lcd.drawFilledRectangle(x, y, w, h, COLOR_THEME_SECONDARY3)
  lcd.drawRectangle(x, y, w, h, COLOR_THEME_SECONDARY1)
  for i, line in ipairs(lines) do
    lcd.drawText(x + PAD, y + PAD + (i - 1) * LINE, line, COLOR_THEME_PRIMARY1)
  end
  local btnY = y + h - LINE - PAD
  drawButton(x + PAD * 2,                 btnY, d.yes, d.cursor == 1)
  drawButton(x + math.floor(w / 2) + PAD, btnY, d.no,  d.cursor == 2)
end

local function handleDialog(e)
  local d = S.dialog
  if d.rows then                     -- single-button info popup
    if isEnter(e) or isExit(e) then S.dialog = nil end
    return
  end
  if isNext(e) or isPrev(e) then
    d.cursor = (d.cursor == 1) and 2 or 1
  elseif isEnter(e) then
    local onYes = d.onYes
    local choseYes = d.cursor == 1
    S.dialog = nil
    if choseYes and onYes then onYes() end
  elseif isExit(e) then
    S.dialog = nil   -- EXIT == the cancelling answer
  end
end

-- ---------------------------------------------------------------------------
-- Generic scrollable picker popup
-- ---------------------------------------------------------------------------

local PICKER_MAX_ROWS = 5

local function pickerEnsureVisible(rows)
  local p = S.picker
  if p.sel < p.top then p.top = p.sel end
  if p.sel > p.top + rows - 1 then p.top = p.sel - rows + 1 end
  if p.top < 1 then p.top = 1 end
end

local function openPicker(title, labels, sel, onPick)
  S.picker = { title = title, labels = labels, sel = sel or 1, top = 1, onPick = onPick }
end

local function pickerRows()
  local _, th  = lcd.sizeText("Mg")
  local maxFit = math.floor((LCD_H - 2 * LINE - th - 2 * PAD) / LINE)
  return math.max(1, math.min(PICKER_MAX_ROWS, #S.picker.labels, maxFit))
end

-- Vertical scrollbar: thumb sized/placed for `visibleRows` of `totalRows`, with
-- `firstIdx` the top row shown.
local function drawScrollbar(sx, y0, visibleRows, firstIdx, totalRows)
  local trackH = visibleRows * LINE
  lcd.drawFilledRectangle(sx, y0, 3, trackH, COLOR_THEME_PRIMARY3)
  local thumbH = math.max(6, math.floor(trackH * visibleRows / totalRows))
  local thumbY = y0 + math.floor(trackH * (firstIdx - 1) / totalRows)
  lcd.drawFilledRectangle(sx, thumbY, 3, thumbH, COLOR_THEME_FOCUS)
end

local PICK_INDENT = 8
local function drawPicker()
  local p     = S.picker
  local n     = #p.labels
  local rows  = pickerRows()
  local _, th = lcd.sizeText("Mg")
  local headH = th + 6
  local w     = math.floor(LCD_W * 0.58)
  local h     = headH + rows * LINE + 4
  local x     = math.floor((LCD_W - w) / 2)
  local y     = math.floor((LCD_H - h) / 2)
  local hasBar = n > rows
  local textY  = math.floor((LINE - th) / 2)

  dimScreen()
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
        local barW = w - (hasBar and 5 or 0)
        lcd.drawFilledRectangle(x, ry, barW, LINE, COLOR_THEME_FOCUS)
        lcd.drawText(x + PICK_INDENT, ry + textY, p.labels[idx], COLOR_THEME_PRIMARY2)
      else
        lcd.drawText(x + PICK_INDENT, ry + textY, p.labels[idx], COLOR_THEME_PRIMARY1)
      end
    end
  end

  if hasBar then drawScrollbar(x + w - 4, listY, rows, p.top, n) end
end

local function handlePicker(e)
  local p = S.picker
  local n = #p.labels
  if isNext(e) or isPrev(e) then
    p.sel = isNext(e) and (p.sel % n + 1) or ((p.sel - 2) % n + 1)
    pickerEnsureVisible(pickerRows())
  elseif isEnter(e) then
    local onPick, sel = p.onPick, p.sel
    S.picker = nil
    if onPick then onPick(sel) end
  elseif isExit(e) then
    S.picker = nil          -- cancel
  end
end

-- Runs a write closure (returns true on success). On failure it shows a
-- Retry / Cancel dialog that re-runs the same closure; on success it calls
-- onDone. The closure must do only the (idempotent) file writes.
local function withRetry(writeFn, onDone)
  if writeFn() then
    if onDone then onDone() end
  else
    openDialog("Save failed -- check SD card.",
               function() withRetry(writeFn, onDone) end, "Retry", "Cancel")
  end
end

-- Overwrites config.lua with factory defaults and clears any parse/schema error.
local function resetConfig(onDone)
  local fresh = defaultConfig()
  withRetry(function() return saveConfig(fresh) end, function()
    S.cfg              = fresh
    S.err, S.errDetail = nil, nil
    if onDone then onDone() end
  end)
end

-- ---------------------------------------------------------------------------
-- Screen: config error
-- ---------------------------------------------------------------------------

local function drawConfigError()
  drawHeader("CONFIG ERROR")
  if S.err == "schema" then
    lcd.drawText(COL1, bodyY(1), "Schema version mismatch", COLOR_THEME_PRIMARY1)
    lcd.drawText(COL1, bodyY(2), "(found " .. tostring(S.errDetail) .. ", expected "
                 .. SCHEMA_VERSION .. ").", COLOR_THEME_PRIMARY1)
  else
    lcd.drawText(COL1, bodyY(1), "Parse error in config.lua", COLOR_THEME_PRIMARY1)
  end
  lcd.drawText(COL1, bodyY(3), "Edit config.lua on PC,", COLOR_THEME_PRIMARY1)
  lcd.drawText(COL1, bodyY(4), "or reset to defaults below.", COLOR_THEME_PRIMARY1)
  drawButtonBar({ "Reset config", "Exit" }, 1, S.cursor)
end

local function handleConfigError(e)
  S.cursor = moveCursor(S.cursor, e, 2)
  if isEnter(e) then
    if S.cursor == 1 then
      openDialog("Reset configuration to defaults?",
                 function() resetConfig(function() S.screen = SCREEN.MAIN; S.cursor = 1 end) end)
    else
      return 1
    end
  elseif isExit(e) then
    return 1
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- Screen: main menu
-- ---------------------------------------------------------------------------

local MAIN_ITEMS = { "Settings", "About" }

local function drawMain()
  drawHeader("LINK SENTINEL - SETUP")
  for i, item in ipairs(MAIN_ITEMS) do
    drawNavRow(i, item, S.cursor == i, { folder = true })
  end
  drawButtonBar({ "Exit" }, #MAIN_ITEMS + 1, S.cursor)
end

local function enterSettings()
  local files   = listSoundFiles()
  S.sndS1Opts   = buildSoundOptions(PATHS.s1Default, files)
  S.sndS2Opts   = buildSoundOptions(PATHS.s2Default, files)
  local snd     = S.cfg.sounds or {}
  S.set = {
    offset  = S.cfg.warnOffsetDb  or DEF_OFFSET,
    rqly    = S.cfg.rqlyThreshold or DEF_RQLY,
    haptic  = (S.cfg.haptic == true),
    hapStr  = HAPTIC.strengthOf(S.cfg),
    s1Idx   = soundOptionIndex(S.sndS1Opts, snd.stage1),
    s2Idx   = soundOptionIndex(S.sndS2Opts, snd.stage2),
  }
  S.setEditing = false
  S.setDive    = nil
  S.setSub     = "thr"
  S.cursor     = 1
  S.screen     = SCREEN.SETTINGS
end

local function handleMain(e)
  S.cursor = moveCursor(S.cursor, e, #MAIN_ITEMS + 1)
  if isEnter(e) then
    if S.cursor > #MAIN_ITEMS then
      return 1                 -- Exit button closes the tool
    end
    local item = MAIN_ITEMS[S.cursor]
    if item == "Settings" then
      enterSettings()
    elseif item == "About" then
      S.screen = SCREEN.ABOUT
      S.cursor = 1
    end
  elseif isExit(e) then
    return 1
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- Screen: About
-- ---------------------------------------------------------------------------

-- Built once (IIFE) so firmware/path assembly adds no top-level locals. `lines`
-- is the compact scrolling list -- its last entry opens the path popup; `paths`
-- is the newline-separated file locations shown there.
local ABOUT = (function()
  local lines = {
    "(c) Mariator-pro   GPL-2.0",
    "SNTNL  v" .. VERSION,
  }
  -- Firmware line only on the radio: getVersion is absent in host/desktop tests.
  if getVersion then
    local ver, radio, _, _, _, osname = getVersion()
    lines[#lines + 1] = (osname or "EdgeTX") .. " " .. tostring(ver)
                        .. " (" .. tostring(radio) .. ")"
  end
  lines[#lines + 1] = "github.com/Mariator-pro/elrs-link-sentinel"
  lines[#lines + 1] = "Schema version: " .. SCHEMA_VERSION
  lines[#lines + 1] = "File locations..."   -- last line: ENTER opens the path popup
  -- {label, path}; labels are padded to a common width at popup time (see handleAbout).
  local pathItems = {
    { "Core:",   CORE_PATH .. (core and "" or "  (MISSING)") },
    { "Config:", PATHS.config },
    { "Func:",   "/SCRIPTS/FUNCTIONS/sntnl.lua" },
    { "Widget:", "/WIDGETS/SNTNL/main.lua" },
    { "Tool:",   "/SCRIPTS/TOOLS/SNTNL.lua" },
    { "Sounds:", PATHS.soundDir },
  }
  return { lines = lines, pathItems = pathItems }
end)()

-- Scrolling info list; only the final "File locations..." line acts on ENTER.
local function drawAbout()
  drawHeader("ABOUT")
  local n       = #ABOUT.lines
  local maxRows = math.max(1, math.floor((barTopY() - bodyY(1)) / LINE))
  local focus   = math.max(1, math.min(S.cursor, n))
  local start   = math.max(1, math.min(focus - math.floor(maxRows / 2), n - maxRows + 1))
  if start < 1 then start = 1 end
  local row = 0
  for i = start, math.min(n, start + maxRows - 1) do
    row = row + 1
    lcd.drawText(COL1, bodyY(row), ABOUT.lines[i], COLOR_THEME_PRIMARY1 + (S.cursor == i and INVERS or 0))
  end
  if n > maxRows then drawScrollbar(LCD_W - 4, bodyY(1), maxRows, start, n) end
  drawButtonBar({ "Back" }, n + 1, S.cursor)
end

local function handleAbout(e)
  local n = #ABOUT.lines
  S.cursor = moveCursor(S.cursor, e, n + 1)
  if isExit(e) then
    S.screen = SCREEN.MAIN; S.cursor = 2
  elseif isEnter(e) then
    if S.cursor > n then                 -- Back button
      S.screen = SCREEN.MAIN; S.cursor = 2
    elseif S.cursor == n then            -- "File locations..." line
      openInfoRows(ABOUT.pathItems)
    end                                  -- plain info lines: ENTER ignored
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- Screen: Settings editor
-- ---------------------------------------------------------------------------

-- Top-level rows: Stage 1 (1), Stage 2 (2), Haptic on/off (3), Haptic strength (4),
-- reset-config (5), Back (6), Save (7). ENTER on a Stage row dives in; the roller
-- then steps its cells (SET_SUBS) and ENTER edits/opens the picker/plays the focused one.
local SET_ITEMS = 7
local SET_SUBS  = { "thr", "snd", "test" }

-- One Stage row per line: label, threshold (value + how to render it) and the
-- sound option list + selected index. The edit range lives in LIMITS, read
-- directly by the edit handler (see handleSettings).
local function settingsRows()
  return {
    { label = "Stage 1", thr = S.set.offset, prefix = "+", unit = " dB",
      sndOpts = S.sndS1Opts, sndIdx = S.set.s1Idx },
    { label = "Stage 2", thr = S.set.rqly,   prefix = "",  unit = " %",
      sndOpts = S.sndS2Opts, sndIdx = S.set.s2Idx },
  }
end

local function settingsDirty()
  local snd = S.cfg.sounds or {}
  return S.set.offset ~= (S.cfg.warnOffsetDb or DEF_OFFSET)
      or S.set.rqly   ~= (S.cfg.rqlyThreshold or DEF_RQLY)
      or S.set.haptic ~= (S.cfg.haptic == true)
      or S.set.hapStr ~= HAPTIC.strengthOf(S.cfg)
      or soundConfigValue(S.sndS1Opts, S.set.s1Idx) ~= snd.stage1
      or soundConfigValue(S.sndS2Opts, S.set.s2Idx) ~= snd.stage2
end

local function leaveSettings()
  S.screen = SCREEN.MAIN
  S.cursor = 1
end

local function saveSettings()
  S.cfg.warnOffsetDb   = S.set.offset
  S.cfg.rqlyThreshold  = S.set.rqly
  S.cfg.haptic         = S.set.haptic
  S.cfg.hapticStrength = S.set.hapStr
  S.cfg.sounds = S.cfg.sounds or {}
  S.cfg.sounds.stage1 = soundConfigValue(S.sndS1Opts, S.set.s1Idx)
  S.cfg.sounds.stage2 = soundConfigValue(S.sndS2Opts, S.set.s2Idx)
  withRetry(function() return saveConfig(S.cfg) end, leaveSettings)
end

local function cancelSettings()
  if settingsDirty() then
    openDialog("Discard changes?", leaveSettings)
  else
    leaveSettings()
  end
end

-- Draws one Stage row (label + Threshold/Sound/Test cells) honouring the dive/
-- edit state; takes y so the scrolling list can place it anywhere.
local function drawStageRow(r, row, y)
  local dived  = S.setDive == r
  local rowSel = (S.cursor == r) and not dived
  local _, lh  = lcd.sizeText("Mg")
  drawRightArrow(ST_WARN, y + math.floor((lh - ARROW_W) / 2), COLOR_THEME_PRIMARY1)
  lcd.drawText(ST_WARN + ARROW_W + ARROW_GAP, y, row.label,
               COLOR_THEME_PRIMARY1 + (rowSel and INVERS or 0))
  local function cell(x, text, sub, editing)
    local f = COLOR_THEME_PRIMARY1
    if editing then f = f + BLINK + INVERS
    elseif dived and S.setSub == sub then f = f + INVERS end
    lcd.drawText(x, y, text, f)
  end
  cell(ST_THR, row.prefix .. row.thr .. row.unit, "thr",
       dived and S.setSub == "thr" and S.setEditing)
  local sndTextX = drawArrowBefore(ST_SND, y, COLOR_THEME_PRIMARY1)
  cell(sndTextX, row.sndOpts[row.sndIdx].label, "snd", false)   -- sound uses the picker
  drawButton(ST_TEST, y - 2, "Play", dived and S.setSub == "test")
end

-- A "label value" row edited in place like the thresholds: value blinks while
-- editing, inverted when only selected (the Haptic rows).
local function drawChoiceRow(y, label, value, selected, editing)
  lcd.drawText(COL1, y, label, COLOR_THEME_PRIMARY1)
  local f = COLOR_THEME_PRIMARY1
  if editing then f = f + BLINK + INVERS
  elseif selected then f = f + INVERS end
  lcd.drawText(ST_SND, y, value, f)
end

local function drawSettings()
  drawHeader("SETTINGS")
  local sr = settingsRows()

  -- Scrollable content rows; only Back/Save stays fixed below. The context hint
  -- sits under the Stages but only while one is focused -- dropped, not blanked,
  -- so the list never scrolls past an empty gap.
  local showHint = (S.cursor == 1 or S.cursor == 2)   -- dive keeps the cursor on the Stage
  local rows = {
    function(y)
      lcd.drawText(ST_WARN, y, "Warning",   COLOR_THEME_PRIMARY1 + BOLD)
      lcd.drawText(ST_THR,  y, "Threshold", COLOR_THEME_PRIMARY1 + BOLD)
      lcd.drawText(ST_SND,  y, "Sound",     COLOR_THEME_PRIMARY1 + BOLD)
      lcd.drawText(ST_TEST, y, "Test",      COLOR_THEME_PRIMARY1 + BOLD)
    end,
    function(y) drawStageRow(1, sr[1], y) end,
    function(y) drawStageRow(2, sr[2], y) end,
  }
  if showHint then
    rows[#rows + 1] = function(y)
      local hint = (S.cursor == 1)
        and ("Early warning " .. S.set.offset .. " dB before RSSI (1RSS/2RSS) limit")
        or  ("Critical alert when RQly drops below " .. S.set.rqly .. "%")
      lcd.drawText(drawInfoBadge(COL1, y), y, hint, COLOR_THEME_PRIMARY1 + SMLSIZE)
    end
  end
  rows[#rows + 1] = function(y) drawChoiceRow(y, "Haptic feedback", S.set.haptic and "On" or "Off",
                      S.cursor == 3, S.setEditing and S.setField == "haptic") end
  -- Strength only matters once feedback is on, so it is hidden (and skipped in
  -- navigation) while haptic is off.
  if S.set.haptic then
    rows[#rows + 1] = function(y) drawChoiceRow(y, "Haptic strength", HAPTIC.labels[S.set.hapStr] or "Normal",
                        S.cursor == 4, S.setEditing and S.setField == "hapStr") end
  end
  rows[#rows + 1] = function(y) drawButton(PAD, y, "Reset to defaults", S.cursor == 5) end

  -- Viewport: first body row down to the bar separator.
  local top0    = bodyY(1)
  local sepY    = barTopY()
  local nRows   = #rows
  local rowsFit = math.max(1, math.floor((sepY - top0) / LINE))

  -- Content row = cursor + 1 (header is row 1): the hint exists only while a Stage
  -- is focused, always before the Haptic/Reset rows, so those never shift. On the
  -- Back/Save bar show the list bottom. Focus is centred + clamped to stay visible.
  local focus = S.cursor + 1
  if not S.set.haptic and S.cursor >= 4 then focus = focus - 1 end   -- strength row hidden
  focus = (S.cursor <= 5) and focus or nRows
  local start = math.max(1, math.min(focus - math.floor(rowsFit / 2),
                                     nRows - rowsFit + 1))

  for i = 0, rowsFit - 1 do
    local idx = start + i
    if idx <= nRows then rows[idx](top0 + i * LINE) end
  end

  -- Scrollbar when the list overflows the viewport.
  if nRows > rowsFit then drawScrollbar(LCD_W - 4, top0, rowsFit, start, nRows) end

  drawButtonBar({ "Back", "Save" }, 6, S.cursor)
end

local function handleSettings(e)
  if S.setEditing then
    local field = S.setField
    if field == "haptic" then
      if isNext(e) or isPrev(e) then
        S.set.haptic = not S.set.haptic           -- both directions just toggle
      elseif isEnter(e) then
        S.setEditing = false
      elseif isExit(e) then
        S.set.haptic = S.setOrig                   -- cancel edit
        S.setEditing = false
      end
    else
      -- Numeric fields, clamped without wrap: offset/rqly (LIMITS), hapStr (HAPTIC).
      local lo, hi
      if field == "hapStr" then
        lo, hi = HAPTIC.min, HAPTIC.max
      else
        local lim = (field == "offset") and LIMITS.WARN_OFFSET_DB or LIMITS.RQLY_THRESHOLD
        lo, hi = lim.min, lim.max
      end
      if isNext(e) and S.set[field] < hi then
        S.set[field] = S.set[field] + 1
      elseif isPrev(e) and S.set[field] > lo then
        S.set[field] = S.set[field] - 1
      elseif isEnter(e) then
        S.setEditing = false
      elseif isExit(e) then
        S.set[field] = S.setOrig   -- cancel edit
        S.setEditing = false
      end
    end
    return 0
  end

  -- Dived into a Stage row: roller steps Threshold->Sound->Test, ENTER edits/
  -- opens the picker/plays the focused cell, EXIT leaves the row.
  if S.setDive then
    if isNext(e) or isPrev(e) then
      local idx = 1
      for j, s in ipairs(SET_SUBS) do if s == S.setSub then idx = j end end
      idx = idx + (isNext(e) and 1 or -1)
      if idx < 1 then idx = #SET_SUBS elseif idx > #SET_SUBS then idx = 1 end
      S.setSub = SET_SUBS[idx]
    elseif isEnter(e) then
      local isS1 = S.setDive == 1
      if S.setSub == "thr" then
        S.setField   = isS1 and "offset" or "rqly"
        S.setEditing, S.setOrig = true, S.set[S.setField]
      elseif S.setSub == "snd" then
        local field  = isS1 and "s1Idx" or "s2Idx"
        local opts   = isS1 and S.sndS1Opts or S.sndS2Opts
        local labels = {}
        for _, o in ipairs(opts) do labels[#labels + 1] = o.label end
        openPicker(isS1 and "Stage 1 sound" or "Stage 2 sound", labels, S.set[field],
                   function(sel) S.set[field] = sel end)
      else   -- test: preview the row's current sound (and haptic, if enabled)
        playFile(isS1 and S.sndS1Opts[S.set.s1Idx].path
                       or S.sndS2Opts[S.set.s2Idx].path)
        HAPTIC.test(S.set.haptic, S.set.hapStr, isS1 and 1 or 2)
      end
    elseif isExit(e) then
      S.setDive = nil
    end
    return 0
  end

  -- Top-level row navigation.
  S.cursor = moveCursor(S.cursor, e, SET_ITEMS)
  -- Skip the hidden Haptic-strength row (4) when haptic feedback is off.
  if S.cursor == 4 and not S.set.haptic then S.cursor = isNext(e) and 5 or 3 end
  if isEnter(e) then
    if S.cursor == 1 or S.cursor == 2 then
      S.setDive, S.setSub = S.cursor, "thr"   -- dive into the Stage 1 / Stage 2 row
    elseif S.cursor == 3 then
      S.setField, S.setEditing, S.setOrig = "haptic", true, S.set.haptic
    elseif S.cursor == 4 then
      S.setField, S.setEditing, S.setOrig = "hapStr", true, S.set.hapStr
    elseif S.cursor == 5 then
      openDialog("Reset configuration to defaults?",
                 function() resetConfig(function() enterSettings() end) end)
    elseif S.cursor == 6 then
      cancelSettings()   -- Back (discard with confirm if dirty)
    elseif S.cursor == 7 then
      saveSettings()
    end
  elseif isExit(e) then
    cancelSettings()
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function init()
  S.cfg, S.err, S.errDetail = loadConfig()
  S.cursor = 1
  S.dialog = nil
  S.picker = nil
  if S.err == "missing" then
    -- Config is optional: start from in-RAM defaults; Save will create the file.
    S.cfg, S.err, S.errDetail = defaultConfig(), nil, nil
    S.screen = SCREEN.MAIN
  elseif S.err then
    S.screen = SCREEN.CONFIG_ERROR
  else
    S.screen = SCREEN.MAIN
  end
end

-- Handle the event first, then draw -- so one frame reflects the result of the
-- input (no one-frame lag) and a modal dialog renders on top of its screen.
local function handleEvent(event)
  if S.dialog then handleDialog(event); return 0 end
  if S.picker then handlePicker(event); return 0 end
  if S.screen == SCREEN.CONFIG_ERROR then return handleConfigError(event) end
  if S.screen == SCREEN.SETTINGS     then return handleSettings(event)    end
  if S.screen == SCREEN.ABOUT        then return handleAbout(event)       end
  return handleMain(event)
end

local function draw()
  lcd.clear()
  if not S.lineMeasured then            -- correct row pitch to the real font height once
    local _, fh = lcd.sizeText("Mg")
    if fh and fh > 0 then LINE = math.max(LINE, fh + 8) end
    S.lineMeasured = true
  end
  if S.screen == SCREEN.CONFIG_ERROR then
    drawConfigError()
  elseif S.screen == SCREEN.SETTINGS then
    drawSettings()
  elseif S.screen == SCREEN.ABOUT then
    drawAbout()
  else
    drawMain()
  end
  if S.picker then drawPicker() end   -- overlays
  if S.dialog then drawDialog() end   -- overlays
end

local function run(event)
  local ret = handleEvent(event) or 0
  draw()
  return ret
end

return { init = init, run = run }
