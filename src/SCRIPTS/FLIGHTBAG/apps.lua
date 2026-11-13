-- =====================================================================
-- apps.lua  --  Installed apps and topic pages of the Flight Bag tools
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/apps.lua
-- Finds the apps (every /SCRIPTS/<NAME>/ with a core.lua), loads and drops
-- their core, manifest and config, describes the app popup (text lines and
-- actions), names the models and holds the language: Flight Bag's own texts
-- (lang/<code>.lua) and the code the apps' manifests are asked for. No
-- drawing: both Flight Bag tools show it their own way; the pages get it as
-- ctx.lib.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

local A = {}

A.BASE      = "/SCRIPTS/FLIGHTBAG/"
-- Interface version of this file and the page logic (*_model.lua) for programs that run them
-- outside the radio, such as a computer app: { breaking, additive }.
A.API       = { 1, 0 }
local API_MAJOR = 1          -- core interface the tools understand: { 1, >= 0 }
local HEAD_MAX  = 2048       -- VERSION, API and CONFIG_PATH sit within this many bytes
local FIRST     = "WINGMAN"  -- listed first

-- Topic pages. `needs`: the page shows while one of these apps is installed;
-- `only` limits the page to them (otherwise every app takes part). `fields`:
-- the page shows while an installed app has a field on it. `label` is set by
-- A.setLang.
local SETTINGS_APPS = { LIPONY = true, SNTNL = true, GPSHOMER = true }
A.PAGES = {
  { id = "warnings",  needs = SETTINGS_APPS },
  { id = "alerts",    needs = SETTINGS_APPS },
  { id = "batteries", needs = { LIPONY = true }, only = true },
  { id = "models",    needs = { LIPONY = true, WINGMAN = true }, only = true },
  { id = "flights",   needs = { GPSHOMER = true }, only = true },
  { id = "display",   needs = {}, fields = true },
}

-- ---------------------------------------------------------------------------
-- Language: Flight Bag's texts by area and id, one file per language. A text
-- missing in the chosen language comes from English, then its id is shown.
-- ---------------------------------------------------------------------------

A.LANGUAGES = { "en", "de" }
A.lang = "en"
local own, english   -- texts of A.lang (nil for English) and of English, loaded when first needed

local function loadLang(code)
  local chunk = loadScript(A.BASE .. "lang/" .. code .. ".lua")
  local ok, t = false, nil
  if chunk then ok, t = pcall(chunk) end
  return ok and type(t) == "table" and t or {}
end

local function dig(t, a, b, c, d)
  for _, k in ipairs({ a, b, c, d }) do
    if type(t) ~= "table" then return nil end
    t = t[k]
  end
  return t
end

-- The text at area, id (and part, key), or nil.
function A.text(a, b, c, d)
  local v = own and dig(own, a, b, c, d)
  if v == nil then
    english = english or loadLang("en")
    v = dig(english, a, b, c, d)
  end
  return v
end

-- A text with its {name} placeholders filled from `values`.
function A.fill(s, values)
  return (string.gsub(s, "{(%w+)}", function(k)
    local v = values and values[k]
    if v ~= nil then return tostring(v) end
  end))
end

-- The text of area and id with `values` filled in; the id when there is none.
function A.t(area, id, values)
  local s = A.text(area, id)
  if type(s) ~= "string" then return id end
  return values and A.fill(s, values) or s
end

-- Chooses the language (an unknown code is English) and names the pages in it.
-- Apps already loaded keep their texts until they are loaded again.
function A.setLang(code)
  local lang = "en"
  for _, c in ipairs(A.LANGUAGES) do if c == code then lang = c end end
  A.lang = lang
  own = lang ~= "en" and loadLang(lang) or nil
  for _, p in ipairs(A.PAGES) do p.label = A.t("pages", p.id) end
end

-- The language the installed apps agree on (their setting `language`, kept
-- from the last load); English while they differ or none has it.
function A.sharedLang(apps)
  local lang
  for _, app in ipairs(apps) do
    if app.language then
      if lang and lang ~= app.language then return "en" end
      lang = app.language
    end
  end
  return lang or "en"
end

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

-- Apps sorted by folder, Wingman first: { folder, base, version, configPath,
-- hasManifest, name, ok, apiMinor, noConfig, icon (Bitmap), iconPath }.
function A.scan()
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
        app.apiMinor = tonumber(b)
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
    local path = app.base .. "icon.png"
    local bmp = exists(path) and Bitmap.open(path)
    if bmp and Bitmap.getSize(bmp) > 0 then   -- size 0: missing or broken
      app.icon, app.iconPath = bmp, path
    end
  end
  return list
end

-- The pages of A.PAGES with at least one usable app, limited to `ids` (a set) when given.
function A.menu(apps, ids)
  local menu = {}
  for _, p in ipairs(A.PAGES) do
    if not ids or ids[p.id] then
      for _, app in ipairs(apps) do
        if app.ok and (p.needs[app.folder] or (p.fields and A.fieldPages(app)[p.id])) then
          menu[#menu + 1] = p; break
        end
      end
    end
  end
  return menu
end

-- ---------------------------------------------------------------------------
-- Loading an app (core, manifest, config) for a page or the popup
-- ---------------------------------------------------------------------------

-- The pages an app has fields on (a set), known from its last load; an app
-- not loaded yet is loaded once for it.
function A.fieldPages(app)
  if not app.pages and app.ok and A.load(app) then A.unload({ app }) end
  return app.pages or {}
end

function A.load(app)
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
  if type(core) == "table" and type(mk) == "function" then ok, man = pcall(mk, core, A.lang) end
  if not ok or type(man) ~= "table" then
    app.loadError = true
    return false
  end
  app.core, app.man = core, man
  if core.loadConfig then
    app.cfg, app.err, app.errDetail = core.loadConfig()
  end
  -- Kept past the unload: the app's language setting and its pages with fields.
  app.language = app.cfg and app.cfg.language or nil
  app.pages = {}
  for _, f in ipairs(man.fields or {}) do if f.page then app.pages[f.page] = true end end
  -- Setup problems of the active model, listed in the popup: by id
  -- (app.setupIssues) with their texts in the language, or as the sentences of
  -- an older core. app.warn (the warning sign) outlives the unload.
  app.setupErrs, app.setupIssues = nil, nil
  if type(core.setupIssues) == "function" and type(core.texts) == "function" then
    local sok, list = pcall(core.setupIssues)
    if sok and type(list) == "table" and #list > 0 then
      local T = core.texts(A.lang)
      app.setupIssues, app.setupErrs = list, {}
      for i, e in ipairs(list) do app.setupErrs[i] = core.fillText(T("setup", e.id) or e.id, e) end
    end
  elseif type(core.setupErrors) == "function" then
    local sok, list = pcall(core.setupErrors)
    if sok and type(list) == "table" and #list > 0 then app.setupErrs = list end
  end
  app.warn = app.err ~= nil or app.setupErrs ~= nil
  return true
end

-- Drops the loaded modules so the next page starts from the files again.
function A.unload(apps)
  for _, app in ipairs(apps) do
    app.core, app.man, app.cfg, app.err, app.errDetail, app.loadError = nil, nil, nil, nil, nil, nil
    app.setupErrs, app.setupIssues = nil, nil
    app.noConfig = app.ok and app.configPath ~= nil and not exists(app.configPath)
  end
  collectgarbage()
end

-- Loads each app once for its warning sign (damaged settings, setup errors):
-- at start and after a page or popup closed, which may have fixed the problem.
function A.refreshWarnings(apps)
  for _, app in ipairs(apps) do
    if app.ok then A.load(app); A.unload(apps) end
  end
end

-- True when the app's icon should carry the warning sign.
function A.needsSign(app) return not app.ok or app.noConfig or app.warn end

-- The loaded apps taking part in page p.
function A.pageApps(apps, p)
  local list = {}
  for _, app in ipairs(apps) do
    if app.ok and (not p.only or p.needs[app.folder]) and A.load(app) then
      list[#list + 1] = app
    end
  end
  return list
end

-- ---------------------------------------------------------------------------
-- App popup: About data, file list and resets
-- ---------------------------------------------------------------------------

-- Popup text: { text, warn } per line; the first line is the title.
function A.popupLines(app)
  local lines = {}
  local function add(t, warn) lines[#lines + 1] = { t, warn } end
  local name = app.man and app.man.name or app.folder
  add(name .. (app.version and ("  v" .. app.version) or ""))
  local man = app.man or {}
  add("(c) " .. (man.author or "Mariator-pro") .. "   " .. (man.license or "GPL-2.0"))
  if man.url then add(man.url) end
  if not app.ok or app.loadError then
    add(A.t("popup", "updateNeeded"), true)
  elseif app.noConfig then
    add(A.t("popup", "noConfig"), true)
  elseif app.err then
    add(A.t("popup", "damaged", { detail = tostring(app.err) }), true)
  elseif app.setupErrs then
    for _, e in ipairs(app.setupErrs) do add(e, true) end
  end
  return lines
end

-- Popup actions of a loaded app: { id, label, rows } lists files (label/value
-- rows), { id, label, run, ask } runs a write after the question `ask` (none:
-- at once). run returns true on success. id: "files", "create", "reset" or
-- the id of the manifest's reset.
function A.popupActions(app)
  local b = {}
  if not (app.ok and app.man) then return b end
  b[#b + 1] = { id = "files", label = A.t("popup", "files"), rows = app.man.paths or {} }
  local core = app.core
  local function factory() return core.saveConfig(core.defaultConfig()) end
  if app.noConfig then
    b[#b + 1] = { id = "create", label = A.t("popup", "create"), run = factory }
  elseif app.err then
    b[#b + 1] = { id = "reset", label = A.t("popup", "reset"), run = factory, ask = A.t("popup", "resetAsk") }
  else
    for _, r in ipairs(app.man.resets or {}) do
      b[#b + 1] = { id = r.id, label = r.label, run = r.run, ask = r.ask, desc = r.desc }
    end
  end
  return b
end

-- Runs an action's write; afterwards the app is reloaded from its files (a
-- created or reset file changes the popup). Returns true on success.
function A.runAction(apps, app, act)
  local ok, res = pcall(act.run)
  A.unload(apps)
  if app.ok then A.load(app) end
  return ok and res and true or false
end

-- ---------------------------------------------------------------------------
-- Models
-- ---------------------------------------------------------------------------

-- The model's EdgeTX display name, read from the head of /MODELS/<filename>
-- (first `name:` field); falls back to the filename, cached per session.
local modelNames = {}
function A.modelName(filename)
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
function A.activeModel()
  local ok, info = pcall(model.getInfo)
  if ok and type(info) == "table" then return info.filename end
  return nil
end

A.setLang("en")

return A
