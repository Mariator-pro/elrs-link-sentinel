-- =====================================================================
-- flights_model.lua  --  Logged flights of GPS Homer (no drawing)
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/flights_model.lua
-- The flight list, newest first, with the texts and the map link of one
-- flight. Used by both Flight Bag tools (flights.lua, LVGL/flights.lua).
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return function(ctx)
  local core
  for _, app in ipairs(ctx.apps) do
    if app.folder == "GPSHOMER" then core = app.core end
  end

  local M = { flights = core and core.readFlights() or {} }

  -- "2026-10-12  17:42", either part alone, or "no clock".
  function M.stamp(entry)
    local stamp = entry.date
    if entry.time ~= "" then stamp = (stamp == "" and entry.time) or (stamp .. "  " .. entry.time) end
    if stamp == "" then stamp = "no clock" end
    return stamp
  end

  function M.url(entry) return core.mapUrl(entry.lat, entry.lon) end
  function M.coord(v) return core.formatCoord(v) end

  return M
end
