-- =====================================================================
-- sntnl.lua  --  EdgeTX function script that monitors the ELRS radio link.
-- =====================================================================
-- SD card path: /SCRIPTS/FUNCTIONS/sntnl.lua
-- Requires the shared module /SCRIPTS/SNTNL/core.lua on the SD card.
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

local CORE_PATH = "/SCRIPTS/SNTNL/core.lua"

local core    -- the loaded core module
local state   -- core's caller-owned warning state

-- loadScript does file I/O, so load core once here, not every run.
local function init_func()
  core  = assert(loadScript(CORE_PATH))()
  state = core.newState()
end

local function run_func()
  core.update(state)
end

return { init = init_func, run = run_func }
