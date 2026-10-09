-- =====================================================================
-- flights.lua  --  Flight Bag page "Last flights" (GPS Homer)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/flights.lua
-- Where the model was when the telemetry ended, as text and as a map QR code
-- to scan with a phone. The roller steps through the logged flights.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

local QR_PATH  = "/SCRIPTS/GPSHOMER/qr.lua"
local QR_QUIET = 4   -- modules of light margin the scanner needs on each side

return function(ctx)
  local ui = ctx.ui
  local core
  for _, app in ipairs(ctx.apps) do
    if app.folder == "GPSHOMER" then core = app.core end
  end

  local flights = core and core.readFlights() or {}
  local idx = 1
  local qr            -- encoder module, false when it failed to load
  local qrUrl, qrRuns -- runs of the current symbol (rebuilding per frame is far too slow)

  local function qrModule()
    if qr == nil then
      local chunk = loadScript(QR_PATH)
      local ok, mod = false, nil
      if chunk then ok, mod = pcall(chunk) end
      qr = (ok and type(mod) == "table") and mod or false
    end
    return qr
  end

  local function runsFor(entry)
    local url = core.mapUrl(entry.lat, entry.lon)
    if qrUrl ~= url then
      qrUrl = url
      local mod  = qrModule()
      local code = mod and mod.encode(url)
      qrRuns     = code and mod.runs(code) or false
    end
    return qrRuns
  end

  local function drawCode(entry, x0, y0, box)
    local mod  = qrModule()
    local runs = mod and runsFor(entry)
    if not runs then
      lcd.drawText(x0, y0, "No QR code", COLOR_THEME_DISABLED)
      return
    end
    local scale = math.max(1, math.floor(box / (mod.SIZE + 2 * QR_QUIET)))
    local side  = (mod.SIZE + 2 * QR_QUIET) * scale
    local qx, qy = x0 + box - side, y0
    lcd.drawFilledRectangle(qx, qy, side, side, lcd.RGB(255, 255, 255))
    local dark = lcd.RGB(0, 0, 0)
    local ox, oy = qx + QR_QUIET * scale, qy + QR_QUIET * scale
    for _, run in ipairs(runs) do
      lcd.drawFilledRectangle(ox + (run[2] - 1) * scale, oy + (run[1] - 1) * scale,
                              run[3] * scale, scale, dark)
    end
  end

  local P = {}

  function P.draw()
    ui.drawHeader("LAST FLIGHTS")
    local COL1, PAD = ui.COL1, ui.PAD
    local n = #flights
    if n == 0 then
      lcd.drawText(COL1, ui.bodyY(1), "No flight logged yet.", COLOR_THEME_PRIMARY1)
      lcd.drawText(COL1, ui.bodyY(2), "A position is stored when the", COLOR_THEME_DISABLED)
      lcd.drawText(COL1, ui.bodyY(3), "telemetry ends after a flight.", COLOR_THEME_DISABLED)
      ui.drawButtonBar({ "Back" }, 1, 1)
      return
    end
    local entry = flights[idx]
    local box   = math.min(ui.barTopY() - ui.bodyY(1), math.floor(LCD_W * 0.46))
    local qrX   = LCD_W - PAD - box
    drawCode(entry, qrX, ui.bodyY(1), box)

    local stamp = entry.date
    if entry.time ~= "" then stamp = (stamp == "" and entry.time) or (stamp .. "  " .. entry.time) end
    if stamp == "" then stamp = "no clock" end
    local counter = idx .. " / " .. n
    lcd.drawText(COL1, ui.bodyY(1), counter, COLOR_THEME_PRIMARY1 + BOLD)
    if n > 1 then
      -- Key hint beside the counter, dropped when it would run into the QR code.
      local hintX = COL1 + lcd.sizeText(counter) + PAD * 2
      local hintW = lcd.sizeText("ROLLER") + 8 + lcd.sizeText("older / newer")
      if hintX + hintW <= qrX - PAD then ui.drawKeyChip(hintX, ui.bodyY(1), "ROLLER", "older / newer") end
    end
    lcd.drawText(COL1, ui.bodyY(2), stamp, COLOR_THEME_PRIMARY1)
    if entry.model ~= "" then lcd.drawText(COL1, ui.bodyY(3), entry.model, COLOR_THEME_PRIMARY1) end
    -- LAT / LON labels, the values on one edge
    local vx = COL1 + math.max(lcd.sizeText("LAT "), lcd.sizeText("LON "))
    lcd.drawText(COL1, ui.bodyY(4), "LAT ", COLOR_THEME_DISABLED)
    lcd.drawText(vx, ui.bodyY(4), core.formatCoord(entry.lat), COLOR_THEME_PRIMARY1)
    lcd.drawText(COL1, ui.bodyY(5), "LON ", COLOR_THEME_DISABLED)
    lcd.drawText(vx, ui.bodyY(5), core.formatCoord(entry.lon), COLOR_THEME_PRIMARY1)
    ui.drawButtonBar({ "Back" }, 1, 1)
  end

  -- Returns true to close the page.
  function P.handle(e)
    if ui.isNext(e) and idx < #flights then idx = idx + 1
    elseif ui.isPrev(e) and idx > 1 then idx = idx - 1
    elseif ui.isExit(e) or ui.isEnter(e) then return true end
    return false
  end

  return P
end
