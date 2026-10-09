-- =====================================================================
-- main.lua  --  EdgeTX widget for the ELRS Link Sentinel.
-- =====================================================================
-- SD card path: /WIDGETS/SNTNL/main.lua
-- Requires the shared module /SCRIPTS/SNTNL/core.lua on the SD card
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
-- =====================================================================

-- ---------------------------------------------------------------------------
-- Responsive scaling: every pixel constant runs through sx(); positions scale
-- with S, fonts are fixed EdgeTX stages.
-- ---------------------------------------------------------------------------
local REF_W = 480
local S     = (LCD_W or REF_W) / REF_W
local function sx(v) return math.floor(v * S + 0.5) end

-- Slack on the tier thresholds so a zone sitting a pixel or two above a boundary
-- doesn't flip tier on a minor font-metric change.
local TIER_TOL = sx(4)

-- ---------------------------------------------------------------------------
-- Shared core module. Loaded once here (module level) for all instances. If
-- it cannot be loaded, refresh() shows a "Core missing" tile instead.
-- ---------------------------------------------------------------------------
local CORE_PATH = "/SCRIPTS/SNTNL/core.lua"
local core
do
  local chunk = loadScript(CORE_PATH)
  if chunk then
    local ok, mod = pcall(chunk)
    if ok then core = mod end
  end
end

-- Tick throttle so the warning cadence is the same whether driven by the
-- ~20 Hz refresh() or the slower background(); fault counter trips a tile.
local TICK_INTERVAL = 10   -- 0.1 s (getTime units)
local ERROR_LIMIT   = 5

-- Range-bar smoothing steps (see smoothRange).
local RANGE_STEP_SMALL = 1
local RANGE_STEP_BIG   = 4
local RANGE_JUMP       = 8

-- ---------------------------------------------------------------------------
-- Color palettes. Set per frame from the Theme option. Escalation colors are
-- theme-independent.
-- ---------------------------------------------------------------------------
local DARK = {
  transparent = false,
  panel  = lcd.RGB( 18,  20,  18),
  fg     = lcd.RGB(235, 235, 235),
  muted  = lcd.RGB(150, 150, 150),
  track  = lcd.RGB( 55,  58,  55),
  accent = lcd.RGB(124, 210,  48),
}
local LIGHT = {
  transparent = true,
  panel  = nil,
  fg     = lcd.RGB(  0,   0,   0),
  muted  = lcd.RGB( 90,  90,  90),
  track  = lcd.RGB(200, 200, 205),
  accent = lcd.RGB(  1, 152,   8),
}
local WARN_COL = lcd.RGB(255, 180,   0)  -- yellow / Stage 1
local CRIT_COL = lcd.RGB(220,  40,  40)  -- red    / Stage 2
local ON_DARK  = lcd.RGB(245, 245, 245)  -- text on the red status bar

-- Mascot-eye colours, theme-independent (light eyeball, dark rim/pupil).
local EYE_WHITE = lcd.RGB(245, 245, 245)
local EYE_RIM   = lcd.RGB( 20,  20,  20)

-- Active palette. Safe as a module global: refresh() is the only draw
-- path and only one instance runs at a time.
local COLORS = DARK

-- Heading/brand text colour, separate from the stage (OK/warn/crit) colours so the
-- Accent option only repaints the brand, never the state bars/thresholds. Set per
-- frame; default is the palette's accent green (so Light/Dark each keep their green).
local BRAND = DARK.accent

-- Resolve the brand text colour from the Accent option: "Theme" pulls the active
-- EdgeTX theme's focus colour, "Custom" the AccentColor picker value. lcd.getColor
-- normalises either to a real RGB (the picker value may be a theme index, not raw
-- RGB). Falls back to the palette accent (Default) if unavailable.
local function brandColor(opt, customCol)
  if opt == 2 and lcd.getColor then
    local c = lcd.getColor(COLOR_THEME_FOCUS)
    if c then return c end
  elseif opt == 3 and customCol then
    local c = lcd.getColor and lcd.getColor(customCol) or customCol
    if c then return c end
  end
  return COLORS.accent
end

-- ---------------------------------------------------------------------------
-- Text helper: custom color via CUSTOM_COLOR so a raw RGB never collides
-- with the size/attribute bits in the flags. flags = only size / align / BOLD.
-- ---------------------------------------------------------------------------
local function dtext(x, y, text, color, flags)
  lcd.setColor(CUSTOM_COLOR, color)
  lcd.drawText(x, y, text, CUSTOM_COLOR + (flags or 0))
end

-- BOLD is a font-index step, not an attribute: only the standard font has a bold
-- variant; added to any size flag it selects a different size.
local function bold(flag)
  if flag == 0 then return BOLD end
  return 0
end

-- Font stages, largest -> smallest.
local FONT_STEPS = { XXLSIZE, DBLSIZE, MIDSIZE, 0, SMLSIZE }
local SMALLER    = { [XXLSIZE] = DBLSIZE, [DBLSIZE] = MIDSIZE,
                     [MIDSIZE] = 0, [0] = SMLSIZE, [SMLSIZE] = SMLSIZE }

-- Text-metric caches: fonts never change at runtime, so measurements are
-- session-constant. Height depends only on the font, width on font + text.
local FONT_H, TEXT_W = {}, {}
local function fontH(flags)
  flags = flags or 0
  local h = FONT_H[flags]
  if not h then
    h = select(2, lcd.sizeText("0", flags))
    FONT_H[flags] = h
  end
  return h
end
-- Width cache is capped: every new live value (distance, voltage ...) adds an
-- entry, so it starts over once TEXT_W_MAX entries are stored.
local TEXT_W_MAX = 200
local textWCount = 0
local function textW(text, flags)
  flags = flags or 0
  local byFlag = TEXT_W[flags]
  if not byFlag then byFlag = {}; TEXT_W[flags] = byFlag end
  local w = byFlag[text]
  if not w then
    if textWCount >= TEXT_W_MAX then
      TEXT_W, textWCount = {}, 0
      byFlag = {}; TEXT_W[flags] = byFlag
    end
    w = lcd.sizeText(text, flags); byFlag[text] = w
    textWCount = textWCount + 1
  end
  return w
end

-- Largest font whose text fits in maxW x maxH. Dimension big numbers from
-- a fixed reference string so "1%" never gets a bigger font than "100%".
-- maxFont caps the largest step tried (e.g. MIDSIZE for the big percent).
-- withBold measures each step as drawn with bold() applied.
local function fitFont(text, maxW, maxH, maxFont, withBold)
  local capped = not maxFont
  for _, f in ipairs(FONT_STEPS) do
    if f == maxFont then capped = true end
    local m = withBold and (f + bold(f)) or f
    if capped and textW(text, m) <= maxW and (not maxH or fontH(m) <= maxH) then return f end
  end
  return SMLSIZE
end

-- Vertical-center offset for a row, measured against a reference glyph.
local function vcenter(ry, rh, flags)
  return ry + math.floor((rh - fontH(flags or 0)) / 2)
end

-- Muted label followed by its value -- shared by the info rows and captions.
local function drawKV(x, y, label, value)
  dtext(x, y, label, COLORS.muted, SMLSIZE)
  dtext(x + textW(label, SMLSIZE), y, value, COLORS.fg, SMLSIZE)
end

-- Fill color for the current stage: accent -> yellow -> red.
local function stageColor(stage)
  if stage >= 2 then return CRIT_COL end
  if stage >= 1 then return WARN_COL end
  return COLORS.accent
end

-- Colour for the status word where it sits ON the stage-coloured fill: light on
-- the red fill, near-black on the lime/yellow fill.
local function textOnStage(stage)
  if stage >= 2 then return ON_DARK end
  return DARK.panel  -- near-black reads well on lime/yellow
end

-- Draw `text` two-tone: each glyph uses `onFill` left of the bar's fill edge,
-- `onTrack` beyond it -- so the status word reads on both fill and empty track.
local function drawSplitText(x, y, text, flags, fillRight, onFill, onTrack)
  local cx = x
  for i = 1, #text do
    local ch = string.sub(text, i, i)
    local cw = textW(ch, flags)
    local col = (cx + cw / 2 <= fillRight) and onFill or onTrack
    dtext(cx, y, ch, col, flags)
    cx = cx + cw
  end
end

-- ---------------------------------------------------------------------------
-- Display derivation (Widget-only). Picks values from core's result for the
-- running tile. The active-antenna RSS selection lives HERE (display logic);
-- core's warning decision does not use ANT.
--   stage : 0 = OK, 1 = WARNING, 2 = CRITICAL
-- ---------------------------------------------------------------------------
local function buildDisplay(ctx, r)
  local snap = r.snapshot
  local ant  = snap.ant                              -- 0/1, or nil (no ANT sensor)
  return {
    stage     = r.stage,
    rfmode    = r.modeName or tostring(snap.rfmd),    -- raw number if name unknown
    sensLimit = r.sensLimit,
    rssActive = (ant == 1) and snap.rss2 or snap.rss1,  -- dBm readout: active antenna
    linkRssi  = r.linkRssi,                              -- range bar: governing (stronger) antenna
    antNum    = (ant == 1) and 2 or 1,
    tpwr      = snap.tpwr,                            -- nil -> "--"
    reserve   = r.pwrReservePct,                      -- DYN: lightened end of the range bar
    fm        = snap.fm ~= "" and snap.fm or nil,     -- nil or empty -> "--"
    rqly      = snap.rqly,
    modLine   = ctx.state.modLine,                    -- CRSF device-info line (nil until detected)
  }
end

-- Anti-flicker smoothing of ctx[key], refresh-paced: +-1%/frame, +-4% when far
-- (>8%). Snaps on the first frame; the caller resets it on link loss.
local function smoothRange(ctx, key, target)
  if target == nil then return end
  local cur = ctx[key]
  if cur == nil then
    ctx[key] = target
    return
  end
  local diff = target - cur
  local step = (math.abs(diff) > RANGE_JUMP) and RANGE_STEP_BIG or RANGE_STEP_SMALL
  if diff > 0 then
    ctx[key] = math.min(target, cur + step)
  elseif diff < 0 then
    ctx[key] = math.max(target, cur - step)
  end
end

-- ---------------------------------------------------------------------------
-- CRSF queue: this widget's own copy of the incoming frames. Drained here once per
-- tick and handed to the core, which keeps the module line (cosmetic header).
-- ---------------------------------------------------------------------------
local MAX_POPS_PER_TICK = 16    -- drains the 256-byte queue faster than frames arrive

local function pollFrames(ctx)
  if not crossfireTelemetryPop then return end   -- no CRSF on this radio
  for _ = 1, MAX_POPS_PER_TICK do
    local cmd, data = crossfireTelemetryPop()
    if cmd == nil then break end
    core.handleFrame(ctx.state, cmd, data)
  end
  core.pollModule(ctx.state)
end

-- ---------------------------------------------------------------------------
-- Drawing helpers + status indicators
-- ---------------------------------------------------------------------------

-- Brand header: brand-coloured square + label, one text line tall (no padding) to stay
-- compact in tight tiers. Returns its height.
local function drawHeader(x, y, label)
  local hdrH = fontH(SMLSIZE)
  local sq   = sx(5)
  lcd.drawFilledRectangle(x, y + math.floor((hdrH - sq) / 2), sq, sq, BRAND)
  dtext(x + sq + sx(3), y, label, BRAND, SMLSIZE)
  return hdrH
end

-- Animated "No RX connected" with 0-3 building dots; centered as if all three
-- dots were present so the base text never shifts.
local NO_RX_BASE = "No RX connected"
local DOT_PERIOD = 50   -- getTime ticks per dot (~0.5 s)
local function drawNoRxStatus(cx, y)
  local n      = math.floor(getTime() / DOT_PERIOD) % 4
  local baseW  = textW(NO_RX_BASE, SMLSIZE)
  local fullW  = textW(NO_RX_BASE .. "...", SMLSIZE)
  local startX = cx - math.floor(fullW / 2)
  dtext(startX, y, NO_RX_BASE, COLORS.muted, SMLSIZE)
  if n > 0 then dtext(startX + baseW, y, string.rep(".", n), COLORS.muted, SMLSIZE) end
end

-- Pulsing red dot, top-right (fades in and out every 2 s); the caller draws it only
-- while telemetry is arriving. drawFilledCircle has no opacity, so the colour is
-- blended by hand between the background and red (light theme: white, the real
-- background there depends on the radio theme).
local HEARTBEAT_PERIOD = 200   -- getTime ticks
local HEARTBEAT_RED    = { 220, 40, 40 }
local HEARTBEAT_BG     = { dark = { 18, 20, 18 }, light = { 255, 255, 255 } }
local function drawHeartbeat(ctx)
  local t  = 0.5 - 0.5 * math.cos(2 * math.pi * (getTime() % HEARTBEAT_PERIOD) / HEARTBEAT_PERIOD)
  local bg = COLORS.transparent and HEARTBEAT_BG.light or HEARTBEAT_BG.dark
  local function mix(i) return math.floor(bg[i] + (HEARTBEAT_RED[i] - bg[i]) * t + 0.5) end
  local r = sx(3)
  lcd.drawFilledCircle(ctx.zone.w - sx(4) - r, sx(4) + r, r, lcd.RGB(mix(1), mix(2), mix(3)))
end

-- ---------------------------------------------------------------------------
-- NO LINK + message / error tiles
-- ---------------------------------------------------------------------------

-- NO LINK tile: brand title over an animated status line, plus the TX module/FW when
-- known (available even without an RX link, as it comes from the module). On a zone too
-- short for the whole block the title is dropped and only the status block stays.
-- Title font sized to this fixed-width anchor instead of the shorter own title, so
-- the splash renders at a predictable, stable size. Widen/narrow the count to
-- shrink/grow the title by a font step.
local TITLE_SIZE_REF = string.rep("M", 8)

local function drawNoLink(ctx)
  -- Laid out on the whole zone like the sibling widgets' splash tiles: title one
  -- font step below the 8-M anchor, status line plus a third line (the module
  -- line, reserved while still unknown), the block centred vertically.
  local z       = ctx.zone
  local title   = "LINK-SENTINEL"
  local tFlag   = SMALLER[fitFont(TITLE_SIZE_REF, math.floor(z.w * 0.95), math.floor(z.h * 0.5))]
  local tH      = fontH(tFlag)
  local sH      = fontH(SMLSIZE)
  local gap, lineGap = sx(4), sx(2)
  local blockH  = sH + lineGap + sH
  local avail   = z.h - 2 * sx(4)
  local modLine = ctx.modLine
  local cx      = math.floor(z.w / 2)

  local function drawStatusBlock(sy)
    drawNoRxStatus(cx, sy)
    if modLine then
      dtext(cx, sy + sH + lineGap, modLine, COLORS.muted, SMLSIZE + CENTER)
    end
  end

  if avail >= tH + gap + blockH then
    local top = math.floor((z.h - (tH + gap + blockH)) / 2)
    dtext(cx, top, title, BRAND, tFlag + CENTER)
    drawStatusBlock(top + tH + gap)
  elseif avail >= blockH then
    drawStatusBlock(math.floor((z.h - blockH) / 2))
  else
    drawNoRxStatus(cx, math.floor((z.h - sH) / 2))
  end
end

-- Centered text lines for status/error tiles. Centered in the band BELOW topY so it
-- never slides up into a header above it; clamped to start at topY at worst.
local function drawCenteredLines(z, lines, color, topY, font)
  color = color or COLORS.fg
  topY = topY or 0
  font = font or SMLSIZE
  local lineH  = fontH(font) + sx(3)
  local startY = topY + math.floor(((z.h - topY) - #lines * lineH) / 2)
  if startY < topY then startY = topY end
  for i, t in ipairs(lines) do
    local tw = textW(t, font)
    dtext(math.floor((z.w - tw) / 2), startY + (i - 1) * lineH, t, color, font)
  end
end

-- Googly eyes: pupils drift and blink. Box (x,y,w,h) sits beside the brand.
local function drawMascotEyes(x, y, w, h)
  local t     = getTime()
  local r     = math.max(sx(3), math.floor(h * 0.30))
  local cy    = y + math.floor(h / 2)
  local cx1   = x + r
  local cx2   = cx1 + 2 * r + sx(2)
  local blink = (t % 250) < 25
  local ph    = (t % 180) / 180 * 2 * math.pi
  local dx    = math.floor(math.cos(ph) * r * 0.4)
  local dy    = math.floor(math.sin(ph) * r * 0.4)
  for _, cx in ipairs({ cx1, cx2 }) do
    lcd.drawFilledCircle(cx, cy, r, EYE_RIM)
    lcd.drawFilledCircle(cx, cy, r - 1, EYE_WHITE)
    if blink then
      lcd.drawFilledRectangle(cx - r, cy - sx(1), 2 * r, math.max(2, sx(2)), EYE_RIM)
    else
      lcd.drawFilledCircle(cx + dx, cy + dy, math.max(1, math.floor(r * 0.5)), EYE_RIM)
    end
  end
end

-- Header-band height of the brand heading (pad + the taller of text / eyes), so
-- callers can reserve it before drawing and decide whether it still fits.
local function brandHeadingH()
  return sx(4) + math.max(fontH(SMLSIZE), sx(14))
end

-- Brand heading with the eyes beside it (eyes dropped if the zone is too narrow).
-- Returns the header-band height it occupies.
local function drawBrandHeading(z)
  local pad = sx(4)
  local hh, sq = fontH(SMLSIZE), sx(5)   -- accent square + title as on GPS Homer
  lcd.drawFilledRectangle(pad, pad + math.floor((hh - sq) / 2), sq, sq, BRAND)
  local tx = pad + sq + sx(3)
  dtext(tx, pad, "LINK-SENTINEL", BRAND, SMLSIZE)
  local hw = textW("LINK-SENTINEL", SMLSIZE)
  local eyeX, eyeW = tx + hw + sx(6), sx(20)
  if eyeX + eyeW <= z.w then
    drawMascotEyes(eyeX, pad, eyeW, math.max(hh, sx(14)))
  end
  return brandHeadingH()
end

-- Error/info tile: heading + two message lines below it. The heading is kept as long
-- as possible -- the message font shrinks first, the heading is only dropped once even
-- a small message no longer fits. Priority: header+STD -> header+SML -> STD -> SML.
local function drawErrorTile(z, line1, line2)
  local lines = { line1, line2 }
  local hb    = brandHeadingH()
  local stdH  = fontH(0) + sx(3)
  local smlH  = fontH(SMLSIZE) + sx(3)
  if z.h - hb >= 2 * stdH then          -- header + standard-size message
    drawBrandHeading(z)
    drawCenteredLines(z, lines, nil, hb, 0)
  elseif z.h - hb >= 2 * smlH then      -- header kept, message shrunk to small
    drawBrandHeading(z)
    drawCenteredLines(z, lines, nil, hb, SMLSIZE)
  elseif z.h >= 2 * stdH then           -- no room with header: drop it, standard size
    drawCenteredLines(z, lines, nil, 0, 0)
  else                                  -- shortest zones: small message, no header
    drawCenteredLines(z, lines, nil, 0, SMLSIZE)
  end
end

-- ---------------------------------------------------------------------------
-- Info grid + range bar
-- ---------------------------------------------------------------------------

-- Range bar: track + stage-coloured fill (length = range %), status word (OK/WARNING/
-- CRITICAL) two-tone inside it. d.range == nil (unknown mode) -> full bar. With
-- dynamic TX power below the maximum the end the bar would lose at full power
-- (d.solid..d.range) is lightened and the word turns light there. The word is
-- drawn only when the bar is tall enough for it; on a thin bar the fill colour alone
-- carries the stage.
local RESERVE_OPACITY = 9   -- 0 opaque .. 15 invisible
local function drawRangeBar(x, y, w, barH, d, sc)
  lcd.drawFilledRectangle(x, y, w, barH, COLORS.track)
  local p     = (d.range == nil) and 100 or math.min(100, math.max(0, d.range))
  local fillW = math.floor(w * p / 100)
  local solidW = (d.range and d.solid) and math.floor(w * math.min(p, math.max(0, d.solid)) / 100) or fillW
  lcd.drawFilledRectangle(x, y, solidW, barH, sc)
  if fillW > solidW then lcd.drawFilledRectangle(x + solidW, y, fillW - solidW, barH, sc, RESERVE_OPACITY) end
  if barH < fontH(SMLSIZE) - sx(5) then return end
  local statusTxt = (d.stage >= 2 and "CRITICAL")
                 or (d.stage >= 1 and "WARNING") or "OK"
  local stFlag = fitFont(statusTxt, w * 0.6, barH - sx(2), nil, true)
  stFlag = stFlag + bold(stFlag)
  drawSplitText(x + sx(4), vcenter(y, barH, stFlag), statusTxt,
                stFlag, x + solidW, textOnStage(d.stage), COLORS.fg)
end

-- Header label: module line once CRSF device-info arrived, brand until then.
local function headerLabel(d)
  return d.modLine or "LINK-SENTINEL"
end

-- Info-grid column x-positions, sized to each column's widest content so values
-- never collide: col 1 = RSS (wider than TX below it), col 2 = the narrow ANT/FM,
-- col 3 = the rest.
local function gridCols(x0, W)
  local gap = sx(4)
  local c1x = x0
  local c2x = c1x + textW("RSS -000 dBm", SMLSIZE) + gap
  local c3x = c2x + textW("FM Angle?", SMLSIZE) + gap
  return c1x, c2x, c3x, (x0 + W) - c3x
end

-- LQ mini bar, colour by quality from the core (core.lqLevel).
local LQ_BAR_H = sx(6)
local function drawLqBar(x, y, w, rqly)
  lcd.drawFilledRectangle(x, y, w, LQ_BAR_H, COLORS.track)
  local rq    = math.min(100, math.max(0, rqly))
  local lvl   = core.lqLevel(rq)
  local rqCol = (lvl == 0 and COLORS.accent) or (lvl == 1 and WARN_COL) or CRIT_COL
  lcd.drawFilledRectangle(x, y, math.floor(w * rq / 100), LQ_BAR_H, rqCol)
end

-- Info row 1: RSS / ANT / LQ. The LQ "%" unit is dropped on a narrow zone so the
-- number never clips; measured against "100 %" so it does not flicker as LQ
-- changes. Returns the columns so the grid reuses them for row 2.
local function drawInfoRow1(x0, W, y, d)
  local c1x, c2x, c3x, col3 = gridCols(x0, W)
  drawKV(c1x, y, "RSS ", d.rssActive .. " dBm")
  drawKV(c2x, y, "ANT ", tostring(d.antNum))
  local lqUnit = (textW("LQ 100 %", SMLSIZE) <= col3) and " %" or ""
  drawKV(c3x, y, "LQ ", d.rqly .. lqUnit)
  return c1x, c2x, c3x, col3
end

-- Full info grid (2 rows x 3 cols): RSS/TX, ANT/FM, LQ/mini bar. r1y/r2y are the
-- text rows, barY the mini-bar top.
local function drawInfoGrid(x0, W, r1y, r2y, barY, d)
  local c1x, c2x, c3x, col3 = drawInfoRow1(x0, W, r1y, d)
  drawKV(c1x, r2y, "TX ", d.tpwr and (d.tpwr .. " mW") or "--")
  local fm = d.fm or "--"
  drawKV(c2x, r2y, "FM ", fm)
  -- A flight mode wider than its column (e.g. ArduPilot "MANU*") may run into
  -- column 3: the LQ bar is dropped then, LQ stays readable in row 1.
  if c2x + textW("FM ", SMLSIZE) + textW(fm, SMLSIZE) <= c3x then
    drawLqBar(c3x, barY, col3 - sx(2), d.rqly)
  end
end

-- Caption on the percent baseline: "MODE <rfmode>" right-aligned (priority), the
-- label after the percent degrading RANGELIMIT -> RANGE -> dropped as the row
-- tightens (e.g. a three-digit percent), so it never collides with MODE.
local function drawPctCaption(x0, W, pctBottom, labelX, d)
  local capY  = pctBottom - fontH(SMLSIZE)
  local modeX = (x0 + W) - (textW("MODE ", SMLSIZE) + textW(d.rfmode, SMLSIZE))
  drawKV(modeX, capY, "MODE ", d.rfmode)
  local avail = modeX - sx(4) - labelX
  local lbl   = "RANGELIMIT"
  if textW(lbl, SMLSIZE) > avail then lbl = "RANGE" end
  if textW(lbl, SMLSIZE) > avail then lbl = nil end
  if lbl then dtext(labelX, capY, lbl, COLORS.muted, SMLSIZE) end
end

-- Percent row for MEDIUM/SMALL: "value %" one size, caption on its baseline.
-- Returns the y just below the percent -- the top of the bar slot.
local function drawPctRow(x0, W, top, maxH, d, sc)
  local pctTxt  = ((d.range == nil) and "--" or tostring(math.floor(d.range + 0.5))) .. " %"
  local numFlag = fitFont("100 %", W * 0.5, maxH, MIDSIZE)
  dtext(x0, top, pctTxt, sc, numFlag)
  local pctBottom = top + fontH(numFlag)
  drawPctCaption(x0, W, pctBottom, x0 + textW(pctTxt, numFlag) + sx(6), d)
  return pctBottom
end

-- ---------------------------------------------------------------------------
-- Main tile (FULL / MEDIUM / SMALL)
-- ---------------------------------------------------------------------------

-- FULL tier: header, range block (big % + bar + status) and the 2x3 info grid.
-- For large/half-page zones (roughly a quarter page and up).
local function drawMainFull(W, H, x0, y0, d)
  local sc   = stageColor(d.stage)
  local hdrH = drawHeader(x0, y0, headerLabel(d))

  -- Below the header: range block, a gap, then 2 info rows. Each row is at least one
  -- line tall so the rows never crowd up into the bar on a short zone.
  local top      = y0 + hdrH + sx(1)
  local rest     = (y0 + H) - top
  local smlH     = fontH(SMLSIZE)
  local infoGap  = sx(3)
  local hInfoRow = math.max(math.floor(rest * 0.20), smlH)
  local hInfo    = hInfoRow * 2
  local hRange   = rest - hInfo - infoGap

  -- ===== RANGE BLOCK =====
  -- Bar takes ~42% of the block, capped so the band above always fits a MIDSIZE number
  -- (the % then reads at value size instead of dropping a font step on a tight zone).
  local barH    = math.max(sx(10),
                           math.min(math.floor(hRange * 0.42), hRange - fontH(MIDSIZE) - sx(3)))
  local barY    = top + hRange - barH
  local bandBot = barY - sx(1)
  local bandH   = bandBot - top

  -- Big percent, LEFT, value + smaller unit ("100" reference: the % is drawn
  -- separately here). d.range is nil for an unknown mode -> show "--" and a
  -- full bar in the warning colour.
  local pctTxt   = (d.range == nil) and "--" or tostring(math.floor(d.range + 0.5))
  local numFlag  = fitFont("100", W * 0.5, bandH, MIDSIZE)
  local unitFlag = SMALLER[numFlag]
  local nW, nH   = textW(pctTxt, numFlag), fontH(numFlag)
  local uW, uH   = textW("%", unitFlag), fontH(unitFlag)
  local uGap     = sx(3)   -- space between value and unit
  -- Percent anchored to the TOP of the band so the gap to the header stays constant
  -- regardless of zone height; spare space sits between the percent row and the bar.
  local pctBottom = top + nH
  dtext(x0, top, pctTxt, sc, numFlag)   -- colored by stage, like the bar fill
  dtext(x0 + nW + uGap, pctBottom - uH, "%", sc, unitFlag)
  drawPctCaption(x0, W, pctBottom, x0 + nW + uGap + uW + sx(6), d)

  -- fill bar: length = range %, color = stage; status word two-tone inside it
  drawRangeBar(x0, barY, W, barH, d, sc)

  -- ===== INFO GRID (2 rows x 3 cols) =====
  local gy  = top + hRange + infoGap
  local r1y = vcenter(gy, hInfoRow, SMLSIZE)
  local r2y = vcenter(gy + hInfoRow, hInfoRow, SMLSIZE)
  local mbY = (gy + hInfoRow) + math.floor((hInfoRow - LQ_BAR_H) / 2)
  drawInfoGrid(x0, W, r1y, r2y, mbY, d)
end

-- MEDIUM tier: same design language as FULL (header, big %, MODE, status bar) plus the
-- info grid, for mid-size zones where FULL's range block would not fit.
local function drawMainMedium(W, H, x0, y0, d)
  local sc = stageColor(d.stage)
  drawHeader(x0, y0, headerLabel(d))

  local smlH = fontH(SMLSIZE)
  -- Rows evenly spread at span/4 (header = line 0): line 1 = %, line 2 = status bar,
  -- lines 3+4 = info rows. On a short zone the pitch is floored so the last row sits at
  -- the bottom pad instead of leaving a larger gap.
  local span    = H - smlH
  local minSpan = 4 * (smlH - sx(4))
  if span < minSpan then span = minSpan end
  local function rowY(i) return y0 + math.floor(i * span / 4 + 0.5) end
  local top   = rowY(1)
  local row1Y = rowY(3)
  local row2Y = rowY(4)

  -- Info grid (3 cols x 2 rows) like FULL, on lines 3 and 4.
  drawInfoGrid(x0, W, row1Y, row2Y, row2Y + math.floor((smlH - LQ_BAR_H) / 2), d)

  -- Percent (big, left) as "value %", value and unit the same size (unlike FULL's
  -- smaller unit), caption on its baseline.
  local pctMaxH = math.floor((row1Y - sx(2) - top) * 0.5)
  local barTop  = drawPctRow(x0, W, top, pctMaxH, d, sc)

  -- Range bar fills the line-2 slot between the percent row and the first info row.
  local barH = math.max(sx(8), (row1Y - sx(1)) - barTop)
  drawRangeBar(x0, barTop, W, barH, d, sc)
end

-- SMALL tier: counts how many full-height rows fit and degrades by priority:
--   >= 3 rows : header + % row + bar (+ info row 1 when a 4th fits)
--   2 rows    : header + a large range % filling the rest
--   <= 1 row  : just the large range % filling the whole zone
-- The % is stage-coloured, so the colour still carries the stage once the word and bar
-- are dropped.
local function drawMainSmall(W, H, x0, y0, d)
  local sc    = stageColor(d.stage)
  local smlH  = fontH(SMLSIZE)
  local gap   = sx(1)
  local nRows = math.floor((H + gap) / (smlH + gap))   -- full-height rows that fit

  -- 1 line: one large stage-coloured %; 2 lines: header and the % row with its
  -- caption.
  if nRows <= 2 then
    local pctBig = (d.range == nil) and "-- %" or (tostring(math.floor(d.range + 0.5)) .. " %")
    if nRows <= 1 then
      local pFlag = fitFont(pctBig, W, H)
      dtext(x0, y0 + math.floor((H - fontH(pFlag)) / 2), pctBig, sc, pFlag)
    else
      -- header + the % row with its RANGELIMIT / RANGE caption and MODE, like MEDIUM
      drawHeader(x0, y0, headerLabel(d))
      local restTop = y0 + smlH + gap
      drawPctRow(x0, W, restTop, (y0 + H) - restTop, d, sc)
    end
    return
  end

  -- >= 3 rows: header + % row + bar; add info row 1 (RSS/ANT/LQ) when a 4th row fits.
  local nInfo   = (nRows >= 4) and 1 or 0
  local divisor = 2 + nInfo
  local span    = H - smlH
  local function rowY(i) return y0 + math.floor(i * span / divisor + 0.5) end

  drawHeader(x0, y0, headerLabel(d))
  local top   = rowY(1)
  local infoY = (nInfo >= 1) and rowY(3) or nil
  if infoY then drawInfoRow1(x0, W, infoY, d) end

  -- % (left) as "value %", RANGELIMIT and MODE on its baseline, like MEDIUM.
  local pctMaxH = math.floor(((infoY or (y0 + H)) - sx(2) - top) * 0.5)
  local barTop  = drawPctRow(x0, W, top, pctMaxH, d, sc)

  -- Range bar between the % row and the info row, or down to the bottom when there is
  -- no info row below it.
  local barBot = (infoY and (infoY - sx(1))) or (y0 + H)
  local barH   = math.max(sx(8), barBot - barTop)
  drawRangeBar(x0, barTop, W, barH, d, sc)
end

-- True when FULL fits. Checks are in absolute pixels because fonts do NOT scale with S
-- (only positions do); measuring the real font metrics makes this self-tuning across
-- radios. The height stack mirrors drawMainFull: header + gap, range block, 2 info rows.
local function mainFitsFull(W, H)
  local gap   = sx(4)
  local gridW = textW("RSS -000 dBm", SMLSIZE) + gap
              + textW("FM Angle?", SMLSIZE) + gap
              + textW("LQ 100 %", SMLSIZE) + sx(2)
  local smlH  = fontH(SMLSIZE)
  local hdrH  = smlH                            -- compact header (one text line, no padding)
  local needH = hdrH + sx(1)                    -- header + gap to content (drawMainFull's top)
              + fontH(MIDSIZE) + sx(1) + sx(12) -- range block: percent band + gap + min bar
              + sx(3) + 2 * smlH                -- infoGap + two info rows
  return W >= gridW - TIER_TOL and H >= needH - TIER_TOL
end

-- True when MEDIUM fits. It spreads header + 4 rows as evenly-spaced lines, so it stays
-- MEDIUM as long as that pitch holds a compressed (smlH - sx(5)); below that it drops to
-- SMALL. Width: the widest left/right pair must fit side by side.
local function mainFitsMedium(W, H)
  local smlH  = fontH(SMLSIZE)
  local needH = smlH + 4 * (smlH - sx(5))   -- header + four rows at a compressed pitch
  local needW = textW("RSS -000 dBm", SMLSIZE) + sx(8)
              + textW("MODE 150Hz", SMLSIZE)
  return W >= needW - TIER_TOL and H >= needH - TIER_TOL
end

local function drawMain(W, H, x0, y0, d)
  if mainFitsFull(W, H) then
    drawMainFull(W, H, x0, y0, d)
  elseif mainFitsMedium(W, H) then
    drawMainMedium(W, H, x0, y0, d)
  else
    drawMainSmall(W, H, x0, y0, d)
  end
end

-- ---------------------------------------------------------------------------
-- Preflight and end pages (flight phases PRE and ENDED): the content of Flight
-- Wingman's link column, title, rows and margins as on the main tile.
-- ---------------------------------------------------------------------------

-- Rows evenly spread below the header like MEDIUM (header = row 0, n rows, the
-- last at the bottom pad); the pitch never drops below a compressed line.
local function rowSpread(H, y0, n)
  local smlH    = fontH(SMLSIZE)
  local span    = H - smlH
  local minSpan = n * (smlH - sx(4))
  if span < minSpan then span = minSpan end
  return function(i) return y0 + math.floor(i * span / n + 0.5) end
end

-- Seconds left on a page timer that started at `since` (the core's ms clock,
-- getTime() * 10) and runs `total` ms.
local function secsLeft(since, total)
  return math.max(0, math.ceil((total - (getTime() * 10 - since)) / 1000))
end

-- Countdown at the bottom right: text left of a bar that runs empty. The text
-- shrinks to the seconds when the row is too narrow.
local function drawCountdown(x0, W, y, secs, total, label)
  local smlH = fontH(SMLSIZE)
  local barH = math.max(3, sx(6))
  local barW = math.max(sx(30), math.floor(W * 0.35))
  local bx   = x0 + W - barW
  local by   = y + math.floor((smlH - barH) / 2)
  lcd.drawFilledRectangle(bx, by, barW, barH, COLORS.track)
  local fw = math.floor(barW * math.max(0, math.min(1, secs / total)))
  if fw > 0 then lcd.drawFilledRectangle(bx, by, fw, barH, COLORS.muted) end
  local txt = string.format("%s in %d s", label, secs)
  if textW(txt, SMLSIZE) > bx - sx(6) - x0 then txt = string.format("%d s", secs) end
  dtext(bx - sx(6) - textW(txt, SMLSIZE), y, txt, COLORS.muted, SMLSIZE)
end

-- Status line: dot plus text in the level colour (LINK OK / WARNING / CRITICAL).
local function drawStatusLine(x, y, st)
  local smlH = fontH(SMLSIZE)
  local r    = math.max(2, sx(4))
  local col  = stageColor(st.level)
  lcd.drawFilledCircle(x + r, y + math.floor(smlH / 2), r, col)
  dtext(x + 2 * r + sx(4), y, st.text, col, SMLSIZE)
  return 2 * r + sx(4) + textW(st.text, SMLSIZE)
end

-- Muted label left, value right-aligned at the row's end.
-- label: text, or { long, short } (the short one when the long one does not fit
-- beside the value); a label that does not fit at all is left out, the value stays.
local function drawLR(x0, W, y, label, value, col)
  local vx   = x0 + W - textW(value, SMLSIZE)
  local room = vx - sx(6) - x0
  if type(label) == "table" then
    label = textW(label[1], SMLSIZE) <= room and label[1] or label[2]
  end
  if textW(label, SMLSIZE) <= room then dtext(x0, y, label, COLORS.muted, SMLSIZE) end
  dtext(vx, y, value, col or COLORS.fg, SMLSIZE)
end

-- Preflight page, laid out like Lipo Nanny's: LQ big (same font box as its
-- per-cell voltage) with the LQ caption beside it and MODE right, then RSSI and TX
-- power, the link status and the countdown to the flight page while the check
-- is met. Status and countdown rows are fixed, the countdown row stays empty
-- while it does not run, so nothing moves. Smaller zones keep LQ, RSSI/TX,
-- status and countdown as far as they fit (two rows: LQ and status), the
-- shortest only the LQ.
local function drawPre(W, H, x0, y0, d, state)
  local smlH  = fontH(SMLSIZE)
  local rq    = math.min(100, math.max(0, d.rqly or 0))
  local lqCol = stageColor(core.lqLevel(rq))
  local lqTxt = tostring(rq) .. " %"
  local st    = core.preflight(d.stage, d.sensLimit)
  local secs  = state.readySince and secsLeft(state.readySince, core.PRE_HOLD_T)
  -- rows below the header at the compressed pitch, as on Lipo Nanny's preflight page
  local nRows = math.floor((H - smlH) / (smlH - sx(4)))
  if nRows < 1 then
    local f = fitFont(lqTxt, W, H)
    dtext(x0, y0 + math.floor((H - fontH(f)) / 2), lqTxt, lqCol, f)
    return
  end
  drawHeader(x0, y0, headerLabel(d))
  local bottomY = y0 + H - smlH
  local half    = math.floor(W / 2)
  local function countdown(y)
    if secs then drawCountdown(x0, W, y, secs, core.PRE_HOLD_T / 1000, "Flight page") end
  end
  local function infoRow(y)
    drawKV(x0, y, "RSSI ", d.linkRssi and (d.linkRssi .. " dBm") or "--")
    local tx  = d.tpwr and (d.tpwr .. " mW") or "--"
    local lbl = textW("TX POWER " .. tx, SMLSIZE) <= W - half and "TX POWER " or "TX PWR "   -- short label on narrow zones
    drawKV(x0 + half, y, lbl, tx)
  end

  if not mainFitsFull(W, H) then
    local k    = (mainFitsMedium(W, H) and nRows >= 4) and 4 or math.min(3, nRows)
    local rowY = rowSpread(H, y0, k)
    local top  = rowY(1)
    local numF = fitFont("100 %", W * 0.5, (k >= 2 and rowY(2) or y0 + H) - sx(2) - top, MIDSIZE)
    dtext(x0, top, lqTxt, lqCol, numF)
    local pctBottom = top + fontH(numF)
    local modeX = (x0 + W) - (textW("MODE ", SMLSIZE) + textW(d.rfmode, SMLSIZE))
    drawKV(modeX, pctBottom - smlH, "MODE ", d.rfmode)
    local lqX = x0 + textW(lqTxt, numF) + sx(6)
    if lqX + textW("LQ", SMLSIZE) <= modeX - sx(4) then dtext(lqX, pctBottom - smlH, "LQ", COLORS.muted, SMLSIZE) end
    if k == 4 then
      infoRow(rowY(2))
      drawStatusLine(x0, rowY(3), st)
      countdown(rowY(4))
    else
      -- no row of its own: the countdown joins the status line, the info row keeps its place
      if k >= 3 then infoRow(rowY(2)) end
      if k >= 2 then
        local cx = x0 + drawStatusLine(x0, rowY(k), st) + sx(8)
        if secs then drawCountdown(cx, x0 + W - cx, rowY(k), secs, core.PRE_HOLD_T / 1000, "Flight page") end
      end
    end
    return
  end

  -- FULL: the spare height is shared out evenly between the blocks, as on
  -- Lipo Nanny's preflight page.
  local top   = y0 + smlH + sx(1)
  local bigF  = fitFont("0.00V", math.floor(W * 0.5), math.floor((bottomY - top) * 0.4))
  local unitF = SMALLER[bigF]
  local bigH  = fontH(bigF)
  local num   = tostring(rq)
  dtext(x0, top, num, lqCol, bigF)
  local capX  = x0 + textW(num, bigF) + sx(3)
  dtext(capX, top + bigH - fontH(unitF), "%", lqCol, unitF)
  capX = capX + textW("%", unitF) + sx(6)
  -- MODE above the value only when it clears the heartbeat dot, else beside it
  local mcapY   = top + bigH - fontH(0) - smlH
  local stacked = mcapY >= sx(12)
  -- above the value a "Full" mode moves into the caption: "MODE (Full)" over "X100Hz"
  local mCap, mVal = "MODE", d.rfmode
  local base = stacked and string.match(d.rfmode, "^(.-) Full$")
  if base then mCap, mVal = "MODE (Full)", base end
  local modeX = x0 + W - (stacked and math.max(textW(mVal, 0), textW(mCap, SMLSIZE))
                                   or (textW(mCap, SMLSIZE) + sx(4) + textW(mVal, 0)))
  if capX + textW("LQ", SMLSIZE) <= modeX - sx(4) then
    dtext(capX, top + bigH - smlH, "LQ", COLORS.muted, SMLSIZE)
  end
  dtext(x0 + W - textW(mVal, 0), top + bigH - fontH(0), mVal, COLORS.fg, 0)
  if stacked then
    dtext(x0 + W - textW(mCap, SMLSIZE), mcapY, mCap, COLORS.muted, SMLSIZE)
  else
    dtext(modeX, top + bigH - smlH, mCap, COLORS.muted, SMLSIZE)
  end
  local fixed = bigH + 2 * smlH
  local gap   = math.max(0, math.floor((bottomY - top - fixed) / 3))
  local infoY = top + bigH + gap
  infoRow(infoY)
  drawStatusLine(x0, infoY + smlH + gap, st)
  countdown(bottomY)
end

-- End page: the flight's lowest LQ, highest RANGELIMIT (coloured by the
-- highest warning stage), highest TX power and the last mode, and the
-- countdown to the wait page. Rows are dropped from the end on short zones.
local function drawEnded(W, H, x0, y0, d, r, state, mode)
  local smlH  = fontH(SMLSIZE)
  local left  = secsLeft(state.endedAt, core.ENDED_HOLD_T)
  local function pct(v) return v and (string.format("%d", math.floor(v + 0.5)) .. " %") or "--" end
  local rows = {
    { { "LOW LINK QUALITY", "LOW LQ" }, pct(r.minRqly), r.minRqly and stageColor(core.lqLevel(r.minRqly)) },
    { "MAX RANGELIMIT", pct(r.maxRangePct), r.maxRangePct and stageColor(r.maxStage or 0) },
    { { "MAX TX POWER", "MAX TX PWR" }, r.maxTpwr and (r.maxTpwr .. " mW") or "--" },
    { "RF MODE", mode or "--" },
  }
  local nRows = math.floor((H - smlH) / (smlH - sx(4)))   -- compressed lines below the header
  if nRows < 2 then
    drawLR(x0, W, y0, rows[1][1], rows[1][2], rows[1][3])
    if H >= 2 * smlH then drawCountdown(x0, W, y0 + H - smlH, left, core.ENDED_HOLD_T / 1000, "Wait page") end
    return
  end
  drawHeader(x0, y0, headerLabel(d))
  local k    = math.min(#rows, nRows - 1)
  local rowY = rowSpread(H, y0, k + 1)
  for i = 1, k do drawLR(x0, W, rowY(i), rows[i][1], rows[i][2], rows[i][3]) end
  drawCountdown(x0, W, rowY(k + 1), left, core.ENDED_HOLD_T / 1000, "Wait page")
end

-- ---------------------------------------------------------------------------
-- Widget lifecycle
-- ---------------------------------------------------------------------------
-- Setup error shown as the configuration error tile: damaged settings file or a
-- missing mandatory sensor (details in the settings tool).
local function setupError(r)
  local snap = r.snapshot
  return core.configDamaged or (snap and (not snap.has1RSS or not snap.hasRQly or not snap.hasRFMD)) or false
end

local function create(zone, opts)
  local ctx = {
    zone = zone, options = opts,
    lastTick = 0, errorStreak = 0, fatalError = false,
    rangeSmoothed = nil, result = nil, lastRunning = nil,
  }
  if core then ctx.state = core.newState() end
  return ctx
end

local function update(ctx, opts)
  ctx.options = opts
end

-- One throttled, fault-tolerant data cycle (no lcd.*). background() only runs while the
-- widget is off-screen, so refresh() must drive it too or the tile freezes. Throttled so
-- the cadence is caller-independent; repeated failures trip a terminal tile.
local function tick(ctx)
  if not core or ctx.fatalError then return end
  local now = getTime()
  if ctx.lastTick ~= 0 and (now - ctx.lastTick) < TICK_INTERVAL then return end
  ctx.lastTick = now
  pcall(pollFrames, ctx)   -- cosmetic header; isolated so CRSF never breaks the tick
  local ok, res = pcall(core.update, ctx.state)
  if ok then
    ctx.result      = res
    if res.status == "running" then
      ctx.lastRunning = res                                      -- held during a brief dropout
    end
    ctx.errorStreak = 0
  else
    ctx.errorStreak = ctx.errorStreak + 1
    if ctx.errorStreak >= ERROR_LIMIT then ctx.fatalError = true end
  end
end

local function background(ctx)
  tick(ctx)
end

local function refresh(ctx, event, touchState)
  tick(ctx)   -- drive logic in the foreground too (background() won't run then)

  local z = ctx.zone
  COLORS = (ctx.options.Theme == 2) and LIGHT or DARK
  BRAND  = brandColor(ctx.options.Accent, ctx.options.AccentColor)

  -- Background per theme: Light gets a milky overlay. Transparency choice 1..6 =
  -- 0..100 % see-through -> opacity 0..15 (15 = invisible); anything else = default.
  if not COLORS.transparent then
    lcd.drawFilledRectangle(0, 0, z.w, z.h, COLORS.panel)
  else
    local trans = ctx.options.Transparency
    if type(trans) ~= "number" or trans < 1 or trans > 6 then trans = 3 end
    if trans < 6 then
      lcd.drawFilledRectangle(0, 0, z.w, z.h, COLOR_THEME_PRIMARY2, 3 * (trans - 1))
    end
  end

  -- Whole render is fault-tolerant so a draw error never crashes EdgeTX.
  local ok = pcall(function()
    local pad = sx(4)   -- edge inset
    local x0, y0 = pad, pad
    local W, H   = z.w - 2 * pad, z.h - 2 * pad

    if not core then
      drawErrorTile(z, "Core missing", "Reinstall Link Sentinel")
      return
    end
    if ctx.fatalError then
      drawErrorTile(z, "Widget error", "Restart radio")
      return
    end

    local r = ctx.result
    if not r then
      drawCenteredLines(z, { "Starting..." })
      return
    end
    -- Setup error takes precedence over the volatile link state: sensor existence
    -- comes from getFieldInfo and does NOT flicker on a missed frame, so it must win
    -- over a momentary getRSSI()==0 instead of letting NO LINK flash over it. The
    -- details are listed in the settings tool.
    if setupError(r) then
      drawErrorTile(z, "Configuration error", "Please check Tool Flight Bag")
      return
    end

    -- After a flight: the end page until the hold runs out (then NO LINK).
    if r.phase == "ENDED" then
      drawEnded(W, H, x0, y0, { modLine = ctx.state.modLine }, r, ctx.state,
                ctx.lastRunning and ctx.lastRunning.modeName)
      return
    end

    -- NO LINK is debounced by core: hold the last good running tile exactly as
    -- long as core holds the warning, then fall through to NO LINK.
    if r.status == "no_link" then
      if ctx.lastRunning and not r.linkLost then
        r = ctx.lastRunning
      else
        ctx.rangeSmoothed, ctx.solidSmoothed = nil, nil   -- next connect snaps fresh
        drawNoLink(ctx)
        return
      end
    end

    -- running (live or held): derive display values, smooth the range bar, draw.
    local d      = buildDisplay(ctx, r)
    if r.phase == "PRE" then
      drawPre(W, H, x0, y0, d, ctx.state)
      return
    end
    -- RANGELIMIT from the core; nil for an unknown mode -> bar full + "--".
    local target = core.rangePct(d.linkRssi, d.sensLimit)
    smoothRange(ctx, "rangeSmoothed", target)
    d.range = (target == nil) and nil or ctx.rangeSmoothed
    -- fully coloured part: the bar at full TX power (DYN), smoothed the same way
    if target and d.reserve then
      smoothRange(ctx, "solidSmoothed", math.max(0, target - d.reserve))
      d.solid = ctx.solidSmoothed
    else
      ctx.solidSmoothed = nil
    end
    drawMain(W, H, x0, y0, d)
  end)
  if not ok then
    dtext(sx(4), sx(4), "Widget error", COLORS.muted, SMLSIZE)
  end

  -- Heartbeat: blink only on the live data tile, never on an error/status tile or during
  -- a held dropout or NO LINK.
  if ok and core and not ctx.fatalError and ctx.result and ctx.result.status == "running"
     and not setupError(ctx.result) then
    pcall(drawHeartbeat, ctx)
  end
end

return {
  name       = "Sentinel",
  options    = {
    -- Theme dropdown (CHOICE labels are a nested table; the value is the 1-based
    -- index, so default 1 = "Dark"; needs EdgeTX 2.11+). Transparency = see-through
    -- share of the milky overlay (default 40%), applied in the Light theme only (Dark stays solid black).
    { "Theme", CHOICE, 1, { "Dark", "Light" } },
    { "Transparency", CHOICE, 3, { "0%", "20%", "40%", "60%", "80%", "100%" } },
    -- Brand/heading colour. Accent: 1 Default (per-palette green), 2 Theme
    -- (COLOR_THEME_FOCUS), 3 Custom (AccentColor). AccentColor shows the native colour
    -- picker; only used when Accent = Custom, default = the original Dark lime.
    { "Accent", CHOICE, 1, { "Default", "Theme", "Custom" } },
    { "AccentColor", COLOR, lcd.RGB(124, 210, 48) },
  },
  create     = create,
  update     = update,
  refresh    = refresh,
  background = background,
}
