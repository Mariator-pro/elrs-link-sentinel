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

-- ---------------------------------------------------------------------
-- Responsive scaling: every pixel constant runs through sx(); positions scale
-- with S, fonts are fixed EdgeTX stages.
-- ---------------------------------------------------------------------
local S = (LCD_W or 480) / 480
local function sx(v) return math.floor(v * S + 0.5) end

-- Slack on the tier thresholds so a zone sitting a pixel or two above a boundary
-- doesn't flip tier on a minor font-metric change.
local TIER_TOL = sx(4)

-- ---------------------------------------------------------------------
-- Shared core module. Loaded once here (module level) for all instances. If
-- it cannot be loaded, refresh() shows a "Core missing" tile instead.
-- ---------------------------------------------------------------------
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

-- Show the NO LINK tile only after the link has been gone this long; brief
-- dropouts keep the last good tile instead of flickering to NO LINK.
local NO_LINK_DEBOUNCE = 150   -- getTime ticks (1.5 s)

-- LQ mini-bar: green at/above this %, yellow down to core's RQLY_THRESHOLD, red
-- below. Only green->yellow is display-only; the red end ties to the shared threshold.
local LQ_OK_PCT = 70

-- ---------------------------------------------------------------------
-- Color palettes. Set per frame from the Theme option. Escalation colors are
-- theme-independent.
-- ---------------------------------------------------------------------
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
-- TxtColor option only repaints the brand, never the state bars/thresholds. Set per
-- frame; default is the palette's accent green (so Light/Dark each keep their green).
local BRAND = DARK.accent

-- Resolve the brand text colour from the TxtColor option. "Theme" pulls the active
-- EdgeTX theme's focus colour, "Custom" the COLOR option's picked value; lcd.getColor
-- normalises either to an RGB value usable by dtext/CUSTOM_COLOR (and the COLOR option
-- may be a theme index, not a raw RGB). Falls back to accent green if unavailable.
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

-- ---------------------------------------------------------------------
-- Widget options (EdgeTX limits: name <= 10 chars, no spaces, <=5 on 2.10)
-- ---------------------------------------------------------------------
local options = {
  { "Theme",    CHOICE, 1, { "Dark", "Light" } },  -- 1=Dark, 2=Light (EdgeTX 2.11+)
  { "Transp",   VALUE,  2, 0, 5 },                  -- milky overlay, Light only
  { "TxtColor",  CHOICE, 1, { "Default", "Theme", "Custom" } },  -- heading/brand text: 1=accent, 2=theme focus, 3=custom
  { "CustomCol", COLOR,  lcd.RGB(124, 210, 48) },                 -- used only when TxtColor = Custom
}

-- ---------------------------------------------------------------------
-- Text helper: custom color via CUSTOM_COLOR so a raw RGB never collides
-- with the size/attribute bits in the flags. flags = only size / align / BOLD.
-- ---------------------------------------------------------------------
local function dtext(x, y, text, color, flags)
  lcd.setColor(CUSTOM_COLOR, color)
  lcd.drawText(x, y, text, CUSTOM_COLOR + (flags or 0))
end

-- Font stages, largest -> smallest.
local FONT_STEPS = { XXLSIZE, DBLSIZE, MIDSIZE, 0, SMLSIZE }
local SMALLER    = { [XXLSIZE] = DBLSIZE, [DBLSIZE] = MIDSIZE,
                     [MIDSIZE] = 0, [0] = SMLSIZE, [SMLSIZE] = SMLSIZE }

-- Largest font whose text fits in maxW x maxH. Dimension big numbers from
-- a fixed reference string so "1%" never gets a bigger font than "100%".
local function fitFont(text, maxW, maxH, extra)
  extra = extra or 0
  for _, f in ipairs(FONT_STEPS) do
    local w, h = lcd.sizeText(text, f + extra)
    if w <= maxW and (not maxH or h <= maxH) then return f end
  end
  return SMLSIZE
end

-- Vertical-center offset for a row, measured against a reference glyph.
local function vcenter(ry, rh, flags)
  local _, th = lcd.sizeText("0", flags or 0)
  return ry + math.floor((rh - th) / 2)
end

-- Draw a sequence of {text,color[,flags]} segments left to right; returns
-- width. A segment may override the row flags (e.g. BOLD for emphasis).
local function drawSegs(x, y, segs, flags)
  local cx = x
  for _, s in ipairs(segs) do
    local f = s.flags or flags or 0
    dtext(cx, y, s.text, s.color, f)
    cx = cx + lcd.sizeText(s.text, f)
  end
  return cx - x
end

-- Total pixel width of a segment list (for right-aligned placement).
local function segsWidth(segs, flags)
  local w = 0
  for _, s in ipairs(segs) do w = w + lcd.sizeText(s.text, s.flags or flags or 0) end
  return w
end

-- BOLD works for every font EXCEPT the small one: SMLSIZE + BOLD makes EdgeTX
-- jump to the max font. So apply BOLD everywhere except SMLSIZE.
local function bold(flag)
  if flag == SMLSIZE then return 0 end
  return BOLD
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
    local cw = lcd.sizeText(ch, flags)
    local col = (cx + cw / 2 <= fillRight) and onFill or onTrack
    dtext(cx, y, ch, col, flags)
    cx = cx + cw
  end
end

-- ---------------------------------------------------------------------
-- Display derivation (Widget-only). Picks values from core's result for the
-- running tile. The active-antenna RSS selection lives HERE (display logic);
-- core's warning decision does not use ANT.
--   stage : 0 = OK, 1 = WARNING, 2 = CRITICAL
-- ---------------------------------------------------------------------
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
    fm        = snap.fm,                              -- nil -> "--"
    rqly      = snap.rqly,
    module    = ctx.module,                           -- CRSF device-info (nil until detected)
    fw        = ctx.fw,
  }
end

-- Range budget in % (0..100) from linkRssi against the mode's raw sensitivity
-- limit. nil for a placeholder/unknown mode (sensLimit == 0) -> bar full + "--".
local function rangeTarget(rss, sensLimit)
  if not sensLimit or sensLimit == 0 then return nil end
  local pct = 100 * (rss + 50) / (sensLimit + 50)
  if pct < 0 then return 0 elseif pct > 100 then return 100 end
  return pct
end

-- Anti-flicker smoothing, refresh-paced: +-1%/frame, +-4% when far (>8%).
-- Snaps on the first frame; the caller resets it on link loss.
local function smoothRange(ctx, target)
  if target == nil then return end
  if ctx.rangeSmoothed == nil then
    ctx.rangeSmoothed = target
    return
  end
  local diff = target - ctx.rangeSmoothed
  local step = (math.abs(diff) > RANGE_JUMP) and RANGE_STEP_BIG or RANGE_STEP_SMALL
  if diff > 0 then
    ctx.rangeSmoothed = math.min(target, ctx.rangeSmoothed + step)
  elseif diff < 0 then
    ctx.rangeSmoothed = math.max(target, ctx.rangeSmoothed - step)
  end
end

-- ---------------------------------------------------------------------
-- CRSF device-info (cosmetic header: module name + firmware). Ping the module,
-- parse its device-info reply. Frame types / addresses / layout are fixed by CRSF.
-- ---------------------------------------------------------------------
local CRSF_PING        = 0x28   -- ping devices (request)
local CRSF_DEVICE_INFO = 0x29   -- device info (reply)
local ADDR_BROADCAST   = 0x00
local ADDR_RADIO       = 0xEA   -- the handset
local ADDR_TX_MODULE   = 0xEE   -- the ELRS TX module (only sender we accept)
local DEV_PING_PERIOD  = 100    -- getTime ticks (1 s) between active pings

-- Read a null-terminated CRSF string from byte array `b` starting at index
-- `from`. Returns the decoded string and the index just past the terminator.
local function crsfReadString(b, from)
  local out, i = {}, from
  while b[i] and b[i] ~= 0 do
    out[#out + 1] = string.char(b[i])
    i = i + 1
  end
  return table.concat(out), i + 1
end

-- Decode a device-info payload into ctx.module / ctx.fw. Accept only frames
-- from the TX module; everything else (e.g. a receiver) is ignored.
local function parseDeviceInfo(ctx, b)
  if not b or b[2] ~= ADDR_TX_MODULE then return end
  local name, p = crsfReadString(b, 3)
  -- payload after the name: serial(4) + hardware(4) + software(4); the
  -- firmware version is the last three bytes of the software field.
  local maj, min, rev = b[p + 9], b[p + 10], b[p + 11]
  if name ~= "" and maj and min and rev then
    ctx.module = name
    ctx.fw     = string.format("%d.%d.%d", maj, min, rev)
  end
end

-- Drain one incoming CRSF frame; while the module is still unknown, actively
-- ping once per second. Once known we stop pinging -- EdgeTX keeps polling, so
-- a module swap is still picked up.
local function pollDeviceInfo(ctx)
  if not crossfireTelemetryPop then return end   -- no CRSF on this radio
  local cmd, data = crossfireTelemetryPop()
  if cmd == CRSF_DEVICE_INFO then
    parseDeviceInfo(ctx, data)
  end
  if not ctx.module then
    local now = getTime()
    if now - (ctx.lastDevPing or 0) > DEV_PING_PERIOD then
      crossfireTelemetryPush(CRSF_PING, { ADDR_BROADCAST, ADDR_RADIO })
      ctx.lastDevPing = now
    end
  end
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

-- Brand header: brand-coloured square + label, one text line tall (no padding) to stay
-- compact in tight tiers. Returns its height.
local function drawHeader(x, y, label)
  local hdrH = select(2, lcd.sizeText("0", SMLSIZE))
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
  local baseW  = lcd.sizeText(NO_RX_BASE, SMLSIZE)
  local fullW  = lcd.sizeText(NO_RX_BASE .. "...", SMLSIZE)
  local startX = cx - math.floor(fullW / 2)
  dtext(startX, y, NO_RX_BASE, COLORS.muted, SMLSIZE)
  if n > 0 then dtext(startX + baseW, y, string.rep(".", n), COLORS.muted, SMLSIZE) end
end

-- Blinking red dot, top-right (0.5 Hz), shown while telemetry is arriving -- a
-- live "fresh packets + script running" sign that stops the instant packets do.
local HEARTBEAT_HALF = 100   -- getTime ticks: 1 s on / 1 s off
local function drawHeartbeat(ctx)
  if math.floor(getTime() / HEARTBEAT_HALF) % 2 ~= 0 then return end
  local z = ctx.zone
  local r = sx(3)
  lcd.drawFilledCircle(z.w - sx(4) - r, sx(4) + r, r, CRIT_COL)
end

-- NO LINK tile: brand title over an animated status line, plus the TX module/FW when
-- known (available even without an RX link, as it comes from the module). On a zone too
-- short for the whole block the title is dropped and only the status block stays.
local function drawNoLink(ctx, x0, y0, W, H)
  local title   = "LINK-SENTINEL"
  local tFlag   = SMALLER[fitFont(title, W * 0.95, H * 0.5)]
  local _, tH   = lcd.sizeText(title, tFlag)
  local _, sH   = lcd.sizeText(NO_RX_BASE, SMLSIZE)
  local gap     = sx(4)
  local modLine = ctx.module and (ctx.module .. " (v" .. ctx.fw .. ")") or nil
  local modH    = modLine and (sx(2) + sH) or 0
  local cx      = x0 + math.floor(W / 2)

  -- Status block (animated "No RX" line + optional module line), top at sy.
  local function drawStatusBlock(sy)
    drawNoRxStatus(cx, sy)
    if modLine then
      dtext(cx, sy + sH + sx(2), modLine, COLORS.muted, SMLSIZE + CENTER)
    end
  end

  if H >= tH + gap + sH + modH then
    local by = y0 + math.floor((H - (tH + gap + sH + modH)) / 2)
    dtext(cx, by, title, BRAND, tFlag + CENTER)
    drawStatusBlock(by + tH + gap)
  else
    drawStatusBlock(y0 + math.floor((H - (sH + modH)) / 2))
  end
end

-- Centered text lines for status/error tiles. Centered in the band BELOW topY so it
-- never slides up into a header above it; clamped to start at topY at worst.
local function drawCenteredLines(z, lines, color, topY, font)
  color = color or COLORS.fg
  topY = topY or 0
  font = font or SMLSIZE
  local _, th  = lcd.sizeText("0", font)
  local lineH  = th + sx(3)
  local startY = topY + math.floor(((z.h - topY) - #lines * lineH) / 2)
  if startY < topY then startY = topY end
  for i, t in ipairs(lines) do
    local tw = lcd.sizeText(t, font)
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
  local _, hh = lcd.sizeText("LINK-SENTINEL", SMLSIZE)
  return sx(4) + math.max(hh, sx(14))
end

-- Brand heading with the eyes beside it (eyes dropped if the zone is too narrow).
-- Returns the header-band height it occupies.
local function drawBrandHeading(z)
  local pad = sx(4)
  dtext(pad, pad, "LINK-SENTINEL", BRAND, SMLSIZE)
  local hw, hh   = lcd.sizeText("LINK-SENTINEL", SMLSIZE)
  local eyeX, eyeW = pad + hw + sx(6), sx(20)
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
  local stdH  = select(2, lcd.sizeText("0", 0)) + sx(3)
  local smlH  = select(2, lcd.sizeText("0", SMLSIZE)) + sx(3)
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

-- Range bar: track + stage-coloured fill (length = range %), status word (OK/WARNING/
-- CRITICAL) two-tone inside it. d.range == nil (unknown mode) -> full bar. The word is
-- drawn only when the bar is tall enough for it; on a thin bar the fill colour alone
-- carries the stage.
local function drawRangeBar(x, y, w, barH, d, sc)
  lcd.drawFilledRectangle(x, y, w, barH, COLORS.track)
  local p     = (d.range == nil) and 100 or math.min(100, math.max(0, d.range))
  local fillW = math.floor(w * p / 100)
  lcd.drawFilledRectangle(x, y, fillW, barH, sc)
  local _, smlH = lcd.sizeText("0", SMLSIZE)
  if barH < smlH - sx(5) then return end
  local statusTxt = (d.stage >= 2 and "CRITICAL")
                 or (d.stage >= 1 and "WARNING") or "OK"
  local stFlag = fitFont(statusTxt, w * 0.6, barH - sx(2))
  drawSplitText(x + sx(4), vcenter(y, barH, stFlag), statusTxt,
                stFlag + bold(stFlag), x + fillW, textOnStage(d.stage), COLORS.fg)
end

-- FULL tier: header, range block (big % + bar + status) and the 2x3 info grid.
-- For large/half-page zones (roughly a quarter page and up).
local function drawMainFull(z, W, H, x0, y0, d)
  local sc = stageColor(d.stage)

  -- Header: brand square + module/FW (brand placeholder until CRSF device-info).
  local hdrLabel = d.module and (d.module .. " (v" .. d.fw .. ")") or "LINK-SENTINEL"
  local hdrH     = drawHeader(x0, y0, hdrLabel)

  -- Below the header: range block, a gap, then 2 info rows. Each row is at least one
  -- line tall so the rows never crowd up into the bar on a short zone.
  local top      = y0 + hdrH + sx(1)
  local rest     = (y0 + H) - top
  local _, smlH  = lcd.sizeText("0", SMLSIZE)
  local infoGap  = sx(3)
  local hInfoRow = math.max(math.floor(rest * 0.20), smlH)
  local hInfo    = hInfoRow * 2
  local hRange   = rest - hInfo - infoGap

  -- ===== RANGE BLOCK =====
  -- Bar takes ~42% of the block, capped so the band above always fits a MIDSIZE number
  -- (the % then reads at value size instead of dropping a font step on a tight zone).
  local _, midNumH = lcd.sizeText("0", MIDSIZE)
  local barH    = math.max(sx(10),
                           math.min(math.floor(hRange * 0.42), hRange - midNumH - sx(3)))
  local barY    = top + hRange - barH
  local bandBot = barY - sx(1)
  local bandH   = bandBot - top

  -- Big percent, LEFT, value + smaller unit. Capped at MIDSIZE, shrunk only if it would
  -- not fit; sized from a fixed "100" reference so "1%" never dwarfs "100%". d.range is
  -- nil for an unknown mode -> show "--" and a full bar in the warning colour.
  local unknownMode = (d.range == nil)
  local pctTxt   = unknownMode and "--" or tostring(math.floor(d.range + 0.5))
  local numFlag  = MIDSIZE
  while numFlag ~= SMLSIZE and
        (lcd.sizeText("100", numFlag) > W * 0.5 or
         select(2, lcd.sizeText("100", numFlag)) > bandH) do
    numFlag = SMALLER[numFlag]
  end
  local unitFlag = SMALLER[numFlag]
  local nW, nH   = lcd.sizeText(pctTxt, numFlag)
  local uW, uH   = lcd.sizeText("%", unitFlag)
  local uGap     = sx(3)   -- space between value and unit
  -- Percent anchored to the TOP of the band so the gap to the header stays constant
  -- regardless of zone height; spare space sits between the percent row and the bar.
  local pctBottom = top + nH
  dtext(x0, top, pctTxt, sc, numFlag)   -- colored by stage, like the bar fill
  dtext(x0 + nW + uGap, pctBottom - uH, "%", sc, unitFlag)

  -- Percent baseline: RANGELIMIT label after the %, "MODE <rfmode>" right-aligned. MODE
  -- has priority -- the label degrades RANGELIMIT -> RANGE -> dropped as the row tightens
  -- (e.g. a three-digit percent), so it never collides with MODE.
  local capH = select(2, lcd.sizeText("RANGE", SMLSIZE))
  local capY = pctBottom - capH
  local modeSegs = {
    { text = "MODE ",  color = COLORS.muted },
    { text = d.rfmode, color = COLORS.fg },
  }
  local modeX  = (x0 + W) - segsWidth(modeSegs, SMLSIZE)
  drawSegs(modeX, capY, modeSegs, SMLSIZE)
  local labelX = x0 + nW + uGap + uW + sx(6)
  local avail  = modeX - sx(4) - labelX
  local lbl    = "RANGELIMIT"
  if lcd.sizeText(lbl, SMLSIZE) > avail then lbl = "RANGE" end
  if lcd.sizeText(lbl, SMLSIZE) > avail then lbl = nil end
  if lbl then dtext(labelX, capY, lbl, COLORS.muted, SMLSIZE) end

  -- fill bar: length = range %, color = stage; status word two-tone inside it
  drawRangeBar(x0, barY, W, barH, d, sc)

  -- ===== INFO GRID (2 rows x 3 cols) =====
  -- col1: RSS(active) / ANT   col2: TX / FM   col3: LQ / mini bar
  local gy   = top + hRange + infoGap
  -- Column x-positions sized to each column's widest content so values never collide:
  -- col 1 = RSS (wider than TX below it), col 2 = the narrow ANT/FM, col 3 = the rest.
  local gap  = sx(4)
  local c1x  = x0
  local c2x  = c1x + lcd.sizeText("RSS -000 dBm", SMLSIZE) + gap
  local c3x  = c2x + lcd.sizeText("FM Angle?", SMLSIZE) + gap
  local col3 = (x0 + W) - c3x
  local r1y = vcenter(gy, hInfoRow, SMLSIZE)
  local r2y = vcenter(gy + hInfoRow, hInfoRow, SMLSIZE)

  -- Col 1: active-antenna RSS (row 1) / TX power (row 2).
  drawSegs(c1x, r1y, {
    { text = "RSS ",                color = COLORS.muted },
    { text = tostring(d.rssActive), color = COLORS.fg },
    { text = " dBm",                color = COLORS.fg },
  }, SMLSIZE)
  drawSegs(c1x, r2y, {
    { text = "TX ", color = COLORS.muted },
    { text = d.tpwr and (d.tpwr .. " mW") or "--", color = COLORS.fg },
  }, SMLSIZE)

  -- Col 2: active antenna number (row 1) / FC flight mode (row 2).
  drawSegs(c2x, r1y, {
    { text = "ANT ",             color = COLORS.muted },
    { text = tostring(d.antNum), color = COLORS.fg },
  }, SMLSIZE)
  drawSegs(c2x, r2y, {
    { text = "FM ",        color = COLORS.muted },
    { text = d.fm or "--", color = COLORS.fg },
  }, SMLSIZE)

  -- Col 3: LQ number (row 1) / mini bar (row 2), bar color by quality
  drawSegs(c3x, r1y, {
    { text = "LQ ",          color = COLORS.muted },
    { text = d.rqly .. " %", color = COLORS.fg },
  }, SMLSIZE)
  local mbH = sx(6)
  local mbY = (gy + hInfoRow) + math.floor((hInfoRow - mbH) / 2)
  local mbW = col3 - sx(2)
  lcd.drawFilledRectangle(c3x, mbY, mbW, mbH, COLORS.track)
  local rq     = math.min(100, math.max(0, d.rqly))
  local critLQ = core.PARAMS.RQLY_THRESHOLD       -- shared threshold, not hard-coded
  local rqCol  = (rq >= LQ_OK_PCT and COLORS.accent) or (rq >= critLQ and WARN_COL) or CRIT_COL
  lcd.drawFilledRectangle(c3x, mbY, math.floor(mbW * rq / 100), mbH, rqCol)
end

-- MEDIUM tier: same design language as FULL (header, big %, MODE, status bar) plus the
-- info grid, for mid-size zones where FULL's range block would not fit.
local function drawMainMedium(z, W, H, x0, y0, d)
  local sc       = stageColor(d.stage)
  local hdrLabel = d.module and (d.module .. " (v" .. d.fw .. ")") or "LINK-SENTINEL"
  drawHeader(x0, y0, hdrLabel)

  local _, smlH = lcd.sizeText("0", SMLSIZE)
  -- Rows evenly spread at span/4 (header = line 0): line 1 = %, line 2 = status bar,
  -- lines 3+4 = info rows. On a short zone the pitch is floored so the last row sits at
  -- the bottom pad instead of leaving a larger gap.
  local span    = H - smlH
  local minSpan = 4 * (smlH - sx(4))
  if span < minSpan then span = minSpan end
  local function rowY(i) return y0 + math.floor(i * span / 4 + 0.5) end
  local top     = rowY(1)

  -- Info grid (3 cols x 2 rows) like FULL, on lines 3 and 4.
  local row1Y = rowY(3)
  local row2Y = rowY(4)
  local gap   = sx(4)
  local c1x   = x0
  local c2x   = c1x + lcd.sizeText("RSS -000 dBm", SMLSIZE) + gap
  local c3x   = c2x + lcd.sizeText("FM Angle?", SMLSIZE) + gap
  local col3  = (x0 + W) - c3x
  -- Col 1: RSS (line 3) / TX (line 4)
  drawSegs(c1x, row1Y, {
    { text = "RSS ", color = COLORS.muted }, { text = tostring(d.rssActive), color = COLORS.fg },
    { text = " dBm", color = COLORS.fg },
  }, SMLSIZE)
  drawSegs(c1x, row2Y, {
    { text = "TX ", color = COLORS.muted },
    { text = d.tpwr and (d.tpwr .. " mW") or "--", color = COLORS.fg },
  }, SMLSIZE)
  -- Col 2: ANT (line 3) / FM (line 4)
  drawSegs(c2x, row1Y, {
    { text = "ANT ", color = COLORS.muted }, { text = tostring(d.antNum), color = COLORS.fg },
  }, SMLSIZE)
  drawSegs(c2x, row2Y, {
    { text = "FM ", color = COLORS.muted }, { text = d.fm or "--", color = COLORS.fg },
  }, SMLSIZE)
  -- Col 3: LQ number (line 3) / mini bar (line 4), bar colour by quality. The "%" unit
  -- is dropped on a narrow zone so the number never clips; measured against "100 %" so
  -- it does not flicker as LQ changes.
  local lqUnit = (lcd.sizeText("LQ 100 %", SMLSIZE) <= col3) and " %" or ""
  drawSegs(c3x, row1Y, {
    { text = "LQ ", color = COLORS.muted }, { text = d.rqly .. lqUnit, color = COLORS.fg },
  }, SMLSIZE)
  local mbH = sx(6)
  local mbY = row2Y + math.floor((smlH - mbH) / 2)
  local mbW = col3 - sx(2)
  lcd.drawFilledRectangle(c3x, mbY, mbW, mbH, COLORS.track)
  local rq     = math.min(100, math.max(0, d.rqly))
  local critLQ = core.PARAMS.RQLY_THRESHOLD       -- shared threshold, not hard-coded
  local rqCol  = (rq >= LQ_OK_PCT and COLORS.accent) or (rq >= critLQ and WARN_COL) or CRIT_COL
  lcd.drawFilledRectangle(c3x, mbY, math.floor(mbW * rq / 100), mbH, rqCol)

  -- Percent (big, left) as "value %", value and unit the same size (unlike FULL's
  -- smaller unit). Sized from a fixed "100 %" reference so "1 %" never dwarfs "100 %".
  local unknownMode = (d.range == nil)
  local pctTxt      = (unknownMode and "--" or tostring(math.floor(d.range + 0.5))) .. " %"
  local pctMaxH     = math.floor((row1Y - sx(2) - top) * 0.5)
  local numFlag     = MIDSIZE
  while numFlag ~= SMLSIZE and
        (lcd.sizeText("100 %", numFlag) > W * 0.5 or
         select(2, lcd.sizeText("100 %", numFlag)) > pctMaxH) do
    numFlag = SMALLER[numFlag]
  end
  local nW, nH    = lcd.sizeText(pctTxt, numFlag)
  local pctBottom = top + nH
  dtext(x0, top, pctTxt, sc, numFlag)

  -- RANGELIMIT after the %, MODE right-aligned, same degradation as FULL.
  local capH = select(2, lcd.sizeText("RANGE", SMLSIZE))
  local capY = pctBottom - capH
  local modeSegs = {
    { text = "MODE ",  color = COLORS.muted },
    { text = d.rfmode, color = COLORS.fg },
  }
  local modeX  = (x0 + W) - segsWidth(modeSegs, SMLSIZE)
  drawSegs(modeX, capY, modeSegs, SMLSIZE)
  local labelX = x0 + nW + sx(6)
  local avail  = modeX - sx(4) - labelX
  local lbl    = "RANGELIMIT"
  if lcd.sizeText(lbl, SMLSIZE) > avail then lbl = "RANGE" end
  if lcd.sizeText(lbl, SMLSIZE) > avail then lbl = nil end
  if lbl then dtext(labelX, capY, lbl, COLORS.muted, SMLSIZE) end

  -- Range bar fills the line-2 slot between the percent row and the first info row.
  local barTop = top + nH
  local barBot = row1Y - sx(1)
  local barH   = math.max(sx(8), barBot - barTop)
  drawRangeBar(x0, barTop, W, barH, d, sc)
end

-- SMALL tier: counts how many full-height rows fit and degrades by priority:
--   >= 3 rows : header + % row + bar (+ info row 1 when a 4th fits)
--   2 rows    : header + a large range % filling the rest
--   <= 1 row  : just the large range % filling the whole zone
-- The % is stage-coloured, so the colour still carries the stage once the word and bar
-- are dropped.
local function drawMainSmall(z, W, H, x0, y0, d)
  local sc      = stageColor(d.stage)
  local _, smlH = lcd.sizeText("0", SMLSIZE)
  local gap     = sx(1)
  local nRows   = math.floor((H + gap) / (smlH + gap))   -- full-height rows that fit
  local pctBig  = (d.range == nil) and "-- %" or (tostring(math.floor(d.range + 0.5)) .. " %")

  -- One line or less: a single large stage-coloured % centred in the zone.
  if nRows <= 1 then
    local pFlag = fitFont(pctBig, W, H)
    local _, ph = lcd.sizeText(pctBig, pFlag)
    dtext(x0, y0 + math.floor((H - ph) / 2), pctBig, sc, pFlag)
    return
  end

  -- Two lines: header + a large left-aligned range % filling the space below it.
  if nRows == 2 then
    drawHeader(x0, y0, d.module and (d.module .. " (v" .. d.fw .. ")") or "LINK-SENTINEL")
    local restTop = y0 + smlH + gap
    local rest    = (y0 + H) - restTop
    local pFlag   = fitFont(pctBig, W, rest)
    local _, ph   = lcd.sizeText(pctBig, pFlag)
    dtext(x0, restTop + math.floor((rest - ph) / 2), pctBig, sc, pFlag)
    return
  end

  -- >= 3 rows: header + % row + bar; add info row 1 (RSS/ANT/LQ) when a 4th row fits.
  local nInfo   = (nRows >= 4) and 1 or 0
  local divisor = 2 + nInfo
  local span    = H - smlH
  local function rowY(i) return y0 + math.floor(i * span / divisor + 0.5) end

  drawHeader(x0, y0, d.module and (d.module .. " (v" .. d.fw .. ")") or "LINK-SENTINEL")
  local top   = rowY(1)
  local infoY = (nInfo >= 1) and rowY(3) or nil

  -- Info row 1 (RSS / ANT / LQ), 3 columns, only when it fits.
  local gap  = sx(4)
  local c1x  = x0
  local c2x  = c1x + lcd.sizeText("RSS -000 dBm", SMLSIZE) + gap
  local c3x  = c2x + lcd.sizeText("FM Angle?", SMLSIZE) + gap
  local col3 = (x0 + W) - c3x
  if infoY then
    drawSegs(c1x, infoY, {
      { text = "RSS ", color = COLORS.muted }, { text = tostring(d.rssActive), color = COLORS.fg },
      { text = " dBm", color = COLORS.fg },
    }, SMLSIZE)
    drawSegs(c2x, infoY, {
      { text = "ANT ", color = COLORS.muted }, { text = tostring(d.antNum), color = COLORS.fg },
    }, SMLSIZE)
    local lqUnit = (lcd.sizeText("LQ 100 %", SMLSIZE) <= col3) and " %" or ""
    drawSegs(c3x, infoY, {
      { text = "LQ ", color = COLORS.muted }, { text = d.rqly .. lqUnit, color = COLORS.fg },
    }, SMLSIZE)
  end

  -- % (left) as "value %", RANGELIMIT and MODE right-aligned, like MEDIUM.
  local pctTxt   = ((d.range == nil) and "--" or tostring(math.floor(d.range + 0.5))) .. " %"
  local pctMaxH  = math.floor(((infoY or (y0 + H)) - sx(2) - top) * 0.5)
  local numFlag  = MIDSIZE
  while numFlag ~= SMLSIZE and
        (lcd.sizeText("100 %", numFlag) > W * 0.5 or
         select(2, lcd.sizeText("100 %", numFlag)) > pctMaxH) do
    numFlag = SMALLER[numFlag]
  end
  local nW, nH    = lcd.sizeText(pctTxt, numFlag)
  local pctBottom = top + nH
  dtext(x0, top, pctTxt, sc, numFlag)
  local capH = select(2, lcd.sizeText("RANGE", SMLSIZE))
  local capY = pctBottom - capH
  local modeSegs = {
    { text = "MODE ",  color = COLORS.muted },
    { text = d.rfmode, color = COLORS.fg },
  }
  local modeX  = (x0 + W) - segsWidth(modeSegs, SMLSIZE)
  drawSegs(modeX, capY, modeSegs, SMLSIZE)
  local labelX = x0 + nW + sx(6)
  local avail  = modeX - sx(4) - labelX
  local lbl    = "RANGELIMIT"
  if lcd.sizeText(lbl, SMLSIZE) > avail then lbl = "RANGE" end
  if lcd.sizeText(lbl, SMLSIZE) > avail then lbl = nil end
  if lbl then dtext(labelX, capY, lbl, COLORS.muted, SMLSIZE) end

  -- Range bar between the % row and the info row, or down to the bottom when there is
  -- no info row below it.
  local barTop = top + nH
  local barBot = (infoY and (infoY - sx(1))) or (y0 + H)
  local barH   = math.max(sx(8), barBot - barTop)
  drawRangeBar(x0, barTop, W, barH, d, sc)
end

-- True when FULL fits. Checks are in absolute pixels because fonts do NOT scale with S
-- (only positions do); measuring the real font metrics makes this self-tuning across
-- radios. The height stack mirrors drawMainFull: header + gap, range block, 2 info rows.
local function mainFitsFull(W, H)
  local gap     = sx(4)
  local gridW   = lcd.sizeText("RSS -000 dBm", SMLSIZE) + gap
                + lcd.sizeText("FM Angle?", SMLSIZE) + gap
                + lcd.sizeText("LQ 100 %", SMLSIZE) + sx(2)
  local _, smlH = lcd.sizeText("0", SMLSIZE)
  local _, midH = lcd.sizeText("0", MIDSIZE)
  local hdrH    = smlH                      -- compact header (one text line, no padding)
  local needH   = hdrH + sx(1)              -- header + gap to content (drawMainFull's top)
                + midH + sx(1) + sx(12)     -- range block: percent band + gap + min bar
                + sx(3) + 2 * smlH          -- infoGap + two info rows
  return W >= gridW - TIER_TOL and H >= needH - TIER_TOL
end

-- True when MEDIUM fits. It spreads header + 4 rows as evenly-spaced lines, so it stays
-- MEDIUM as long as that pitch holds a compressed (smlH - sx(5)); below that it drops to
-- SMALL. Width: the widest left/right pair must fit side by side.
local function mainFitsMedium(W, H)
  local _, smlH = lcd.sizeText("0", SMLSIZE)
  local needH   = smlH + 4 * (smlH - sx(5))   -- header + four rows at a compressed pitch
  local needW   = lcd.sizeText("RSS -000 dBm", SMLSIZE) + sx(8)
                + lcd.sizeText("MODE 150Hz", SMLSIZE)
  return W >= needW - TIER_TOL and H >= needH - TIER_TOL
end

local function drawMain(z, W, H, x0, y0, d)
  if mainFitsFull(W, H) then
    drawMainFull(z, W, H, x0, y0, d)
  elseif mainFitsMedium(W, H) then
    drawMainMedium(z, W, H, x0, y0, d)
  else
    drawMainSmall(z, W, H, x0, y0, d)
  end
end

-- ---------------------------------------------------------------------
-- Widget lifecycle
-- ---------------------------------------------------------------------
local function create(zone, opts)
  local ctx = {
    zone = zone, options = opts,
    lastTick = 0, errorStreak = 0, fatalError = false,
    rangeSmoothed = nil, result = nil, lastRunning = nil, linkLostSince = nil,
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
  pcall(pollDeviceInfo, ctx)   -- cosmetic header; isolated so CRSF never breaks the tick
  local ok, res = pcall(core.update, ctx.state)
  if ok then
    ctx.result      = res
    if res.status == "running" then ctx.lastRunning = res end  -- held during a brief dropout
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
  BRAND  = brandColor(ctx.options.TxtColor, ctx.options.CustomCol)

  -- Background per theme.
  if not COLORS.transparent then
    lcd.drawFilledRectangle(0, 0, z.w, z.h, COLORS.panel)
  else
    local trans = ctx.options.Transp or 0
    if trans > 0 then
      lcd.drawFilledRectangle(0, 0, z.w, z.h, COLOR_THEME_PRIMARY2, 3 * trans)
    end
  end

  -- Whole render is fault-tolerant so a draw error never crashes EdgeTX.
  local ok = pcall(function()
    local pad = sx(4)   -- edge inset
    local x0, y0 = pad, pad
    local W, H   = z.w - 2 * pad, z.h - 2 * pad

    if not core then
      drawErrorTile(z, "Core missing", "Reinstall SNTNL")
      return
    end
    if ctx.fatalError then
      drawErrorTile(z, "Widget error", "Re-add or restart")
      return
    end

    local r = ctx.result
    if not r then
      drawCenteredLines(z, { "Starting..." })
      return
    end
    -- Sensor error takes precedence over the volatile link state: existence comes from
    -- getFieldInfo and does NOT flicker on a missed frame, so "Sensor missing" must win
    -- over a momentary getRSSI()==0 instead of letting NO LINK flash over it.
    local snap = r.snapshot
    if snap and (not snap.has1RSS or not snap.hasRQly or not snap.hasRFMD) then
      drawErrorTile(z, "Sensor missing", "Discover in EdgeTX")
      return
    end

    -- NO LINK is debounced: hold the last good running tile through a brief dropout,
    -- and only fall through to the NO LINK screen once the loss persists.
    if r.status == "no_link" then
      ctx.linkLostSince = ctx.linkLostSince or getTime()
      if ctx.lastRunning and (getTime() - ctx.linkLostSince) < NO_LINK_DEBOUNCE then
        r = ctx.lastRunning
      else
        ctx.rangeSmoothed = nil   -- reset smoothing so the next connect snaps fresh
        drawNoLink(ctx, x0, y0, W, H)
        return
      end
    else
      ctx.linkLostSince = nil
    end

    -- running (live or held): derive display values, smooth the range bar, draw.
    local d      = buildDisplay(ctx, r)
    local target = rangeTarget(d.linkRssi, d.sensLimit)
    smoothRange(ctx, target)
    d.range = (target == nil) and nil or ctx.rangeSmoothed
    drawMain(z, W, H, x0, y0, d)
  end)
  if not ok then
    dtext(4, 4, "Widget error", COLORS.muted, SMLSIZE)
  end

  -- Heartbeat: blink only on the live data tile, never on an error/status tile or during
  -- a held dropout or NO LINK.
  if ok and core and not ctx.fatalError and ctx.result and ctx.result.status == "running" then
    pcall(drawHeartbeat, ctx)
  end
end

return {
  name       = "Sentinel",
  options    = options,
  create     = create,
  update     = update,
  refresh    = refresh,
  background = background,
}
