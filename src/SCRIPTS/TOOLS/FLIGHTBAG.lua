-- TNS|Flight Bag|TNE
-- =====================================================================
-- FLIGHTBAG.lua  --  One settings tool for all installed scripts
-- =====================================================================
-- SD card path: /SCRIPTS/TOOLS/FLIGHTBAG.lua (pages in /SCRIPTS/FLIGHTBAG/)
-- Start page: topic menu on top, the installed apps (every /SCRIPTS/<NAME>/
-- with a core.lua) as a strip of icons below it. A page gathers the settings
-- of all apps on one topic; each app describes itself in its manifest.lua.
-- Tapping an app opens its About data and resets.
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

local BASE     = "/SCRIPTS/FLIGHTBAG/"
local TITLE    = "Flight Bag"
local API_MAJOR = 1          -- core interface this tool understands: { 1, >= 0 }
local HEAD_MAX = 2048        -- VERSION, API and CONFIG_PATH sit within this many bytes
local FIRST    = "WINGMAN"   -- shown first in the app strip

local ui
do
  local chunk = loadScript(BASE .. "ui.lua")
  local ok, mod = false, nil
  if chunk then ok, mod = pcall(chunk) end
  ui = ok and type(mod) == "table" and mod or nil
end
if not ui then
  local function run(event)
    lcd.clear()
    lcd.drawText(10, 10, "Flight Bag files are missing.", COLOR_THEME_PRIMARY1)
    lcd.drawText(10, 40, "Copy " .. BASE .. " to the SD card again.", COLOR_THEME_PRIMARY1)
    if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then return 1 end
    return 0
  end
  return { run = run }
end

-- Topic pages. `apps` limits a page to these app folders (nil = every app).
local SETTINGS_APPS = { LIPONY = true, SNTNL = true, GPSHOMER = true }
local PAGES = {
  { id = "warnings",  label = "Warnings",     file = "settings.lua",  needs = SETTINGS_APPS },
  { id = "alerts",    label = "Alerts",       file = "settings.lua",  needs = SETTINGS_APPS },
  { id = "batteries", label = "Batteries",    file = "batteries.lua", needs = { LIPONY = true }, only = true },
  { id = "models",    label = "Models",       file = "models.lua",    needs = { LIPONY = true, WINGMAN = true }, only = true },
  { id = "flights",   label = "Last flights", file = "flights.lua",   needs = { GPSHOMER = true }, only = true },
  { id = "display",   label = "Display",      file = "settings.lua",  needs = { WINGMAN = true } },
}

local apps  = {}   -- { folder, version, api, configPath, ok, noConfig, icon, ... }
local menu  = {}   -- PAGES entries with at least one usable app
local cursor = 1   -- menu rows, then apps, then Exit
local page         -- open page: { draw(), handle(e) -> true to close }
local pop          -- open app popup: { app, cursor, buttons }

-- ---------------------------------------------------------------------------
-- Scan
-- ---------------------------------------------------------------------------

local function readHead(path)
  local ok, f = pcall(io.open, path, "r")
  if not ok or not f then return "" end
  local rok, s = pcall(io.read, f, HEAD_MAX)
  pcall(io.close, f)
  return rok and s or ""
end

local function exists(path)
  local ok, st = pcall(fstat, path)
  return ok and st ~= nil
end

-- A leftover /SCRIPTS/TOOLS/<NAME>.lua of an older release would list the app
-- twice in the Tools menu; it goes once the app has a manifest.
local function removeLeftover(folder)
  for _, ext in ipairs({ ".lua", ".luac" }) do
    local p = "/SCRIPTS/TOOLS/" .. folder .. ext
    if exists(p) then pcall(del, p) end
  end
end

local function scan()
  local list = {}
  pcall(function()
    for folder in dir("/SCRIPTS") do
      local base = "/SCRIPTS/" .. folder .. "/"
      if folder ~= "TOOLS" and exists(base .. "core.lua") then
        local head = readHead(base .. "core.lua")
        local a, b = string.match(head, "%.API%s*=%s*{%s*(%d+)%s*,%s*(%d+)")
        local app = {
          folder     = folder,
          base       = base,
          version    = string.match(head, '%.VERSION%s*=%s*"([^"]+)"'),
          configPath = string.match(head, '%.CONFIG_PATH%s*=%s*"([^"]+)"'),
          hasManifest = exists(base .. "manifest.lua"),
        }
        if app.hasManifest then   -- display name as text, the manifest is not run here
          app.name = string.match(readHead(base .. "manifest.lua"), 'name%s*=%s*"([^"]+)"')
        end
        app.ok = app.hasManifest and tonumber(a) == API_MAJOR and tonumber(b) ~= nil
        app.noConfig = app.ok and app.configPath ~= nil and not exists(app.configPath)
        list[#list + 1] = app
      end
    end
  end)
  table.sort(list, function(x, y)
    if (x.folder == FIRST) ~= (y.folder == FIRST) then return x.folder == FIRST end
    return x.folder < y.folder
  end)
  for _, app in ipairs(list) do
    if app.ok then removeLeftover(app.folder) end
    local bmp = exists(app.base .. "icon.png") and Bitmap.open(app.base .. "icon.png")
    if bmp and Bitmap.getSize(bmp) > 0 then app.icon = bmp end   -- size 0: missing or broken
  end
  return list
end

local function buildMenu()
  menu = {}
  for _, p in ipairs(PAGES) do
    for _, app in ipairs(apps) do
      if app.ok and p.needs[app.folder] then menu[#menu + 1] = p; break end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Loading an app (core, manifest, config) for a page or the popup
-- ---------------------------------------------------------------------------

local function loadApp(app)
  if app.core then return true end
  local function load(path)
    local chunk = loadScript(path)
    if not chunk then return nil end
    local ok, v = pcall(chunk)
    return ok and v or nil
  end
  local core = load(app.base .. "core.lua")
  local mk   = core and load(app.base .. "manifest.lua")
  local ok, man = false, nil
  if type(core) == "table" and type(mk) == "function" then ok, man = pcall(mk, core) end
  if not ok or type(man) ~= "table" then
    app.loadError = true
    return false
  end
  app.core, app.man = core, man
  if core.loadConfig then
    app.cfg, app.err, app.errDetail = core.loadConfig()
  end
  -- Setup errors of the active model, listed in the popup; app.warn (the icon's
  -- warning sign) outlives the unload.
  app.setupErrs = nil
  if type(core.setupErrors) == "function" then
    local sok, list = pcall(core.setupErrors)
    if sok and type(list) == "table" and #list > 0 then app.setupErrs = list end
  end
  app.warn = app.err ~= nil or app.setupErrs ~= nil
  return true
end

-- Drops the loaded modules so the next page starts from the files again.
local function unloadApps()
  for _, app in ipairs(apps) do
    app.core, app.man, app.cfg, app.err, app.errDetail, app.loadError = nil, nil, nil, nil, nil, nil
    app.setupErrs = nil
    app.noConfig = app.ok and app.configPath ~= nil and not exists(app.configPath)
  end
  collectgarbage()
end

-- Loads each app once for its warning sign (damaged settings, setup errors):
-- at start and after a page or popup closed, which may have fixed the problem.
local function refreshWarnings()
  for _, app in ipairs(apps) do
    if app.ok then loadApp(app); unloadApps() end
  end
end

local function openPage(p)
  local chunk = loadScript(BASE .. p.file)
  local ok, mk = false, nil
  if chunk then ok, mk = pcall(chunk) end
  if not ok or type(mk) ~= "function" then
    ui.openAlert(p.label .. " could not be started. Copy " .. BASE .. " to the SD card again.")
    return
  end
  local list = {}
  for _, app in ipairs(apps) do
    if app.ok and (not p.only or p.needs[app.folder]) and loadApp(app) then
      list[#list + 1] = app
    end
  end
  local pok, pg = pcall(mk, { ui = ui, apps = list, id = p.id, title = p.label })
  if pok and type(pg) == "table" then page = pg else unloadApps() end
end

local function closePage()
  page = nil
  unloadApps()
  refreshWarnings()
end

-- ---------------------------------------------------------------------------
-- App popup: About data, file list and resets
-- ---------------------------------------------------------------------------

local popupButtons

-- Runs a core function that writes a file, reports the result and refreshes
-- the popup (a created or reset file changes its buttons).
local function runWrite(fn)
  local ok, res = pcall(fn)
  if ok and res then
    ui.openAlert("Done.")
  else
    ui.openAlert("Save failed. Check SD card.")
  end
  unloadApps()
  if pop then
    loadApp(pop.app)
    pop.buttons = popupButtons(pop.app)
    pop.cursor  = math.min(pop.cursor, #pop.buttons)
  end
end

popupButtons = function(app)
  local b = {}
  if app.ok and app.man then
    b[#b + 1] = { label = "Files", act = function() ui.openInfoRows(app.man.paths or {}) end }
    local core = app.core
    if app.noConfig then
      b[#b + 1] = { label = "Create", act = function()
        runWrite(function() return core.saveConfig(core.defaultConfig()) end) end }
    elseif app.err then
      b[#b + 1] = { label = "Reset", act = function()
        ui.openDialog("Replace the damaged settings file with factory settings?", function()
          runWrite(function() return core.saveConfig(core.defaultConfig()) end) end) end }
    else
      for _, r in ipairs(app.man.resets or {}) do
        b[#b + 1] = { label = r.label, act = function()
          ui.openDialog(r.ask, function() runWrite(r.run) end) end }
      end
    end
  end
  b[#b + 1] = { label = "Close", act = function() pop = nil; unloadApps(); refreshWarnings() end }
  return b
end

local function openPopup(app)
  if app.ok then loadApp(app) end
  pop = { app = app }
  pop.buttons = popupButtons(app)
  pop.cursor  = #pop.buttons
end

-- Popup text: { text, warn } per line; warnings in the theme's warning colour.
local function popupLines(app)
  local lines = {}
  local function add(t, warn) lines[#lines + 1] = { t, warn } end
  local name = app.man and app.man.name or app.folder
  add(name .. (app.version and ("  v" .. app.version) or ""))
  add("(c) Mariator-pro   GPL-2.0")
  if app.man and app.man.url then add(app.man.url) end
  if not app.ok or app.loadError then
    add("Update needed: this version does not work", true)
    add("with this Flight Bag.", true)
  elseif app.noConfig then
    add("No settings file yet.", true)
  elseif app.err then
    add("Settings file damaged (" .. tostring(app.err) .. ").", true)
  elseif app.setupErrs then
    for _, e in ipairs(app.setupErrs) do add(e, true) end
  end
  return lines
end

local function drawPopup()
  local app, LINE, PAD = pop.app, ui.LINE, ui.PAD
  local lines = popupLines(app)
  local w = LCD_W - 4 * PAD
  local _, th = lcd.sizeText("Mg")
  local btnH = th + 4
  -- Buttons wrap into rows that fit the box.
  local rows, x = { {} }, 0
  for i, b in ipairs(pop.buttons) do
    local bw = lcd.sizeText(b.label) + 2 * ui.BTN_PADX
    if x > 0 and x + bw > w - 2 * PAD then rows[#rows + 1] = {}; x = 0 end
    local r = rows[#rows]
    r[#r + 1] = { i = i, w = bw, label = b.label }
    x = x + bw + PAD
  end
  local h = #lines * LINE + #rows * (btnH + PAD) + 3 * PAD
  local bx, by = 2 * PAD, math.floor((LCD_H - h) / 2)
  ui.dimScreen()
  lcd.drawFilledRectangle(bx + 3, by + 3, w, h, COLOR_THEME_PRIMARY1)
  lcd.drawFilledRectangle(bx, by, w, h, COLOR_THEME_SECONDARY3)
  lcd.drawRectangle(bx, by, w, h, COLOR_THEME_SECONDARY1)
  for i, l in ipairs(lines) do
    local flags = l[2] and COLOR_THEME_WARNING or (COLOR_THEME_PRIMARY1 + (i == 1 and BOLD or 0))
    lcd.drawText(bx + PAD, by + PAD + (i - 1) * LINE, l[1], flags)
  end
  local y = by + 2 * PAD + #lines * LINE
  for _, r in ipairs(rows) do
    local cx = bx + PAD
    for _, b in ipairs(r) do
      ui.drawButton(cx, y, b.label, pop.cursor == b.i)
      cx = cx + b.w + PAD
    end
    y = y + btnH + PAD
  end
end

local function handlePopup(e)
  local n = #pop.buttons
  if ui.isNext(e) then pop.cursor = pop.cursor % n + 1
  elseif ui.isPrev(e) then pop.cursor = (pop.cursor - 2) % n + 1
  elseif ui.isEnter(e) then pop.buttons[pop.cursor].act()
  elseif ui.isExit(e) then pop = nil; unloadApps(); refreshWarnings() end
end

-- ---------------------------------------------------------------------------
-- Start page
-- ---------------------------------------------------------------------------

local ICON  = 64      -- icon.png size
-- Strip icons: 48 px, on the low 272 px displays 32 px so more menu rows fit.
local SCALE = (LCD_H < 320) and 50 or 75
local strip = {}      -- per app: { x, y, w, h } for touch, set by draw
local exitBox         -- Exit button box, set by draw

local function smallH() local _, h = lcd.sizeText("Mg", SMLSIZE); return h end
local function iconS() return math.floor(ICON * SCALE / 100) end
local FOCUS_PAD = 6   -- focus margin around the selected icon
-- Gap of PAD to both separators, the focus margin around the icon, two text lines.
local function stripH() return iconS() + 2 * smallH() + 2 * FOCUS_PAD + 2 * ui.PAD end
local function stripTop() return ui.barTopY() - stripH() end
-- The last row only needs its text height (plus a small gap), not a full pitch.
local function menuRows()
  local _, th = lcd.sizeText("Mg", BOLD)
  return math.max(1, math.floor((stripTop() - ui.bodyY(1) - th - 4) / ui.LINE) + 1)
end
local function appIndex(i) return #menu + i end
local function exitIndex() return #menu + #apps + 1 end

-- Menu in columns: top to bottom, then the next column, so no entry scrolls.
local function menuCols()
  return math.max(1, math.ceil(#menu / menuRows()))
end
local function colW() return math.floor((LCD_W - 2 * ui.PAD) / menuCols()) end
local function menuXY(i)
  local rows = menuRows()
  local c, r = math.floor((i - 1) / rows), (i - 1) % rows
  return ui.COL1 + c * colW(), ui.bodyY(r + 1)
end

-- Warning sign at an icon corner: triangle with rounded corners in the theme's
-- warning colour and a black "!" (bar and dot), centred on x, y, half the icon
-- high. Rounded: three corner circles, the triangle between their centres and
-- each edge pushed out by the radius.
local function drawMarker(x, y, s)
  local h = math.max(14, math.floor(s / 2))
  local r = math.max(2, math.floor(h / 7))
  local top, base = y - math.floor(h / 2), y + math.floor(h / 2)
  local half = math.floor(h * 0.6)
  local P = { { x, top + 2 * r }, { x - half + 2 * r, base - r }, { x + half - 2 * r, base - r } }
  local col = COLOR_THEME_WARNING
  if lcd.drawFilledTriangle then
    lcd.drawFilledTriangle(P[1][1], P[1][2], P[2][1], P[2][2], P[3][1], P[3][2], col)
    for i = 1, 3 do
      local a, b = P[i], P[i % 3 + 1]
      local dx, dy = b[1] - a[1], b[2] - a[2]
      local len = math.sqrt(dx * dx + dy * dy)
      local nx, ny = math.floor(-dy / len * r + 0.5), math.floor(dx / len * r + 0.5)   -- outward normal
      lcd.drawFilledTriangle(a[1], a[2], b[1], b[2], b[1] + nx, b[2] + ny, col)
      lcd.drawFilledTriangle(a[1], a[2], b[1] + nx, b[2] + ny, a[1] + nx, a[2] + ny, col)
    end
  end
  for _, c in ipairs(P) do lcd.drawFilledCircle(c[1], c[2], r, col) end
  local bw = math.max(2, math.floor(h / 8))
  local ink = lcd.RGB(0, 0, 0)
  lcd.drawFilledRectangle(x - math.floor(bw / 2), top + math.floor(h * 0.32), bw, math.floor(h * 0.36), ink)
  lcd.drawFilledRectangle(x - math.floor(bw / 2), base - math.floor(h * 0.24), bw, bw, ink)
end

local function drawStrip()
  local PAD = ui.PAD
  local top = stripTop()
  local s   = iconS()
  lcd.drawFilledRectangle(PAD, top, LCD_W - 2 * PAD, 1, COLOR_THEME_PRIMARY3)
  -- At least four slots wide, so the names fit; more apps get narrower cells.
  local cellW = math.floor((LCD_W - 2 * PAD) / math.max(4, #apps))
  strip = {}
  for i, app in ipairs(apps) do
    local cx = PAD + (i - 1) * cellW
    local ix = cx + math.floor((cellW - s) / 2)
    local iy = top + PAD + FOCUS_PAD
    if cursor == appIndex(i) then
      -- Same rounding as the icon (about 10 of 64 px), widened by the margin.
      ui.fillRounded(ix - FOCUS_PAD, iy - FOCUS_PAD, s + 2 * FOCUS_PAD, s + 2 * FOCUS_PAD,
                     math.floor(10 * s / ICON + 0.5) + FOCUS_PAD, COLOR_THEME_FOCUS)
    end
    if app.icon then
      lcd.drawBitmap(app.icon, ix, iy, SCALE)
    else
      lcd.drawFilledRectangle(ix, iy, s, s, COLOR_THEME_SECONDARY1)
      local letter = string.sub(app.folder, 1, 1)
      local lw, lh = lcd.sizeText(letter, BOLD)
      lcd.drawText(ix + math.floor((s - lw) / 2), iy + math.floor((s - lh) / 2), letter,
                   COLOR_THEME_PRIMARY2 + BOLD)
    end
    if not app.ok or app.noConfig or app.warn then drawMarker(ix + s - 2, iy + 2, s) end
    local ty = iy + s + FOCUS_PAD
    for _, t in ipairs({ app.name or app.folder, app.version and ("v" .. app.version) or "?" }) do
      -- Too wide for the cell: cut and mark with "..".
      local base = t
      while #base > 1 and lcd.sizeText(t, SMLSIZE) > cellW - 4 do
        base = string.sub(base, 1, -2)
        t = base .. ".."
      end
      local tw = lcd.sizeText(t, SMLSIZE)
      lcd.drawText(cx + math.floor((cellW - tw) / 2), ty, t, COLOR_THEME_PRIMARY1 + SMLSIZE)
      ty = ty + smallH()
    end
    strip[i] = { x = cx, y = top, w = cellW, h = stripH() }
  end
end

local function drawStart()
  ui.drawHeader(TITLE)
  if #apps == 0 then
    local hint = { "No settings found.", "",
                   "Flight Bag shows the settings of",
                   "installed scripts. Copy a script to",
                   "the SD card and open Flight Bag again." }
    for i, s in ipairs(hint) do lcd.drawText(ui.COL1, ui.bodyY(i), s, COLOR_THEME_PRIMARY1) end
  end
  for i, p in ipairs(menu) do
    local x, y = menuXY(i)
    lcd.drawText(x, y, "> " .. p.label, COLOR_THEME_PRIMARY1 + BOLD + (cursor == i and INVERS or 0))
  end
  if #apps > 0 then drawStrip() end
  exitBox = ui.drawButtonBar({ "Exit" }, exitIndex(), cursor)[1]
end

local function hit(b, x, y) return b and x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h end

-- Index under a tap (menu row, app or Exit), or nil.
local function tapIndex(x, y)
  if hit(exitBox, x, y) then return exitIndex() end
  for i, b in ipairs(strip) do if hit(b, x, y) then return appIndex(i) end end
  if y >= ui.bodyY(1) and y < stripTop() then
    local r = math.floor((y - ui.bodyY(1)) / ui.LINE)
    local c = math.floor((x - ui.PAD) / colW())
    local i = c * menuRows() + r + 1
    if r < menuRows() and menu[i] then return i end
  end
end

-- Returns 1 to leave the tool.
local function activate(i)
  if i == exitIndex() then return 1 end
  if i <= #menu then openPage(menu[i])
  elseif apps[i - #menu] then openPopup(apps[i - #menu]) end
  return 0
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

local function init()
  apps = scan()
  refreshWarnings()
  buildMenu()
  cursor = 1
end

local function run(event, touchState)
  ui.measure()
  event = event or 0
  if ui.handleOverlay(event) then
    -- a dialog or picker took the event
  elseif pop then
    handlePopup(event)
  elseif page then
    local ok, done = pcall(page.handle, event, touchState)
    if not ok then ui.openAlert("Error: " .. tostring(done)); closePage()
    elseif done then closePage() end
  else
    if event == EVT_VIRTUAL_EXIT then return 1 end
    cursor = ui.moveCursor(cursor, event, exitIndex())
    local pick
    if event == EVT_VIRTUAL_ENTER then pick = cursor end
    if event == EVT_TOUCH_TAP and touchState then
      pick = tapIndex(touchState.x, touchState.y)
      if pick then cursor = pick end
    end
    if pick and activate(pick) == 1 then return 1 end
  end

  lcd.clear()
  if page then
    local ok, err = pcall(page.draw)
    if not ok then ui.openAlert("Error: " .. tostring(err)); closePage(); lcd.clear(); drawStart() end
  else
    drawStart()
  end
  if pop then drawPopup() end
  ui.drawOverlay()
  return 0
end

return { init = init, run = run }
