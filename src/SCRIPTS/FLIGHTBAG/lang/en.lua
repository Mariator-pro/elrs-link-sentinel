-- =====================================================================
-- lang/en.lua  --  English texts of the Flight Bag settings tool
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/lang/en.lua
-- Every text by area and id; the complete set and the fallback of the
-- other languages. {name} is a placeholder. Plain quotes and dots only:
-- the radio's font has no typographic ones. The ids of `ui` are internal
-- and may change with these files; all other ids never change once
-- released (other programs go by them).
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return {
  -- Topic pages: name in the menu, title on the page
  pages = { warnings = "Warnings", alerts = "Alerts", batteries = "Batteries", models = "Models",
            flights = "Last flights", display = "Display" },
  titles = { warnings = "WARNINGS", alerts = "ALERTS", batteries = "BATTERIES", models = "MODELS",
             flights = "LAST FLIGHTS", display = "DISPLAY" },

  -- Rows of the settings pages
  rows = {
    on = "On", off = "Off", mixed = "Mixed", default = "Default",
    mixedHint = "Set differently per script, choose again",
    noConfig = "No settings file yet", create = "Create",
    damaged = "Settings file damaged", reset = "Recreate",
    resetAsk = "Replace the damaged settings file with a new one? Its content is lost.",
  },
  sounds = { off = "Off", default = "Default" },

  -- Messages of the rules for batteries, models and saving
  rules = {
    manufacturerRequired = "Enter a manufacturer.",
    lowAboveCritical = "Battery low must be above Battery critical.",
    lastPack = "This is the last pack. Delete the battery instead.",
    parallelKeepTwo = "Flown in parallel by {models}, so the battery keeps at least 2 packs.",
    parallelUnassign = "Flown in parallel by {models}. Remove it there first.",
    maxPacks = "A battery has at most {n} packs.",
    deleteOne = "Delete the battery and archive its pack?",
    deleteAll = "Delete the battery and archive all {n} packs?",
    parallelNeedsTwo = "Parallel packs need a battery with at least 2 packs.",
    saveFailed = "{app}: save failed, check SD card",
  },

  -- App popup
  popup = {
    updateNeeded = "Update needed: this version does not work with this Flight Bag.",
    noConfig = "No settings file yet",
    damaged = "Settings file damaged ({detail}).",
    files = "Files", create = "Create", reset = "Recreate",
    resetAsk = "Replace the damaged settings file with a new one? Its content is lost.",
  },

  -- Models page: sensor rows and Wingman's module switches
  models = {
    voltage  = { label = "Voltage", hint = "Whole-pack voltage (V). Sets SoC % and warnings. 4S full ~16.8V, empty ~14.0V." },
    current  = { label = "Current", hint = "Live current draw (A). Feeds the remaining-time estimate, e.g. 0-120A." },
    capacity = { label = "Capacity", hint = "Consumed mAh, counts UP from 0 (or %, see Capacity unit). Main warn trigger." },
    capacityUnit = { label = "Capacity unit", hint = "Only if the FC sends remaining %. FC capacity must equal the pack's mAh.",
                     choices = { mah = "mAh used (default)", pct = "% remaining" } },
    lipo = { label = "Battery", hint = "Battery column, pack selection and alerts of Lipo Nanny" },
    link = { label = "Link", hint = "Link column and alerts of Link Sentinel" },
    gps  = { label = "GPS", hint = "GPS column, search page and alerts of GPS Homer" },
    none = "None",
  },

  -- Flight Bag's own pages on the radio (internal ids)
  ui = {
    back = "Back", save = "Save", delete = "Delete", close = "Close", exit = "Exit",
    yes = "Yes", no = "No", ok = "OK", retry = "Retry", cancel = "Cancel",
    apply = "Apply", remove = "Remove", play = "Play", done = "Done", clear = "Clear",
    discard = "Discard changes?",
    saved = "Done.",
    saveFailed = "Save failed. Check SD card.",
    pageFailed = "{page} could not be started. Copy {path} to the SD card again.",
    pageError = "Error: {msg}",
    noApps = "No settings found.\n\nFlight Bag shows the settings of installed scripts. Copy a script to the SD card and open Flight Bag again.",
    nothing = "Nothing to set here.",
    soundPicker = "{label} sound",

    -- Last flights
    noQr = "No QR code",
    noFlights = "No flight logged yet.",
    noFlightsHint = "A position is stored when the telemetry ends after a flight.",
    roller = "ROLLER", olderNewer = "older / newer",
    lastPosition = "LAST POSITION", lat = "LAT", lon = "LON",
    noClock = "no clock",

    -- Batteries
    noBatteries = "No batteries yet - add your first.",
    addNew = "[+] Add new",
    lipoBroken = "Lipo Nanny has no usable settings file.",
    lipoBrokenFix = "Fix it in the Lipo Nanny app (start page).",
    name = "Name", auto = "(auto)", manufacturer = "Manufacturer", chemistry = "Chemistry",
    capacity = "Capacity", cells = "Cells", packs = "Packs", statistics = "Statistics",
    batteryLow = "Battery low", batteryCritical = "Battery critical",
    pctDefault = "{v} % (default)",
    resetName = "Reset name",
    titleEditName = "EDIT NAME", titleEditManufacturer = "EDIT MANUFACTURER",
    titleAddBattery = "ADD BATTERY", titleEditBattery = "EDIT BATTERY",
    switchGroup = "switch group", wheel = "Wheel", slot = "slot", enter = "ENTER", edit = "edit",
    step = "step {n}",
    titlePacks = "PACKS - {name}", titleStats = "STATISTICS - {name}",
    colId = "ID", colCycles = "Cycles", colWear = "Wear", colBought = "Bought", colDelete = "Delete",
    colLifeMah = "Life mAh", colVmin = "Vmin", colLastUsed = "Last used",
    addPack = "[+] Add pack",

    -- Models
    noModels = "No models configured.",
    active = "[active]",
    addCurrent = "[+] Add current model",
    titleAddModel = "ADD MODEL  {name}", titleEditModel = "EDIT MODEL  {name}",
    battery = "Battery", showInWingman = "Show in Wingman", sdLogs = "SD logs",
    oneBattery = "{n} battery", manyBatteries = "{n} batteries",
    parallelDrop = "Parallel mode unassigns {batteries} with < 2 packs. Continue?",
    cellsDrop = "Changing cells unassigns {batteries}. Continue?",
    deleteModel = "Delete model config for {name}?",
    titleBattery = "BATTERY  {name}",
    parallelPacks = "Parallel packs", batteries = "Batteries", selected = "{n} selected",
    sensors = "Sensors", custom = "custom", default = "default",
    titleSelect = "SELECT {cells}S BATTERIES", titleSelectParallel = "SELECT {cells}S PARALLEL PROFILES",
    noMatching = "No matching profiles.",
    titleSensors = "SENSORS  {name}",
    sensorDefault = "{name} (default)",
    sensorPicker = "{label} sensor",
    activateToEdit = "Activate this model to edit sensors.",
    resetSensors = "Reset to CRSF defaults",
    titleShowInWingman = "SHOW IN WINGMAN  {name}",

    -- SD logs
    titleLogs = "SD LOGS  {name}",
    setUp = "Set up",
    log = "Log", armSwitch = "Arm switch", interval = "Interval",
    armed = "Armed", alwaysOn = "Always on",
    chooseArm = "Choose arm switch",
    onlyActive = "Only for the active model",
    noTriggerShort = "No trigger", disabledSuffix = ", disabled",
    noTrigger = "No trigger in the model",
    noTriggerHelp = "Without a switch EdgeTX never logs. Choose the arm switch and Apply.",
    disabled = "Disabled in the model",
    disabledHelp = "The special function is switched off. Apply switches it on again.",
    logSensorsSome = "Log sensors: {found} of {total} found",
    logSensorsAll = "Log sensors: all {total} found",
    discoverHelp = "Open Model > Telemetry and select Discover new sensors while the apps run.",
    logHint = "When the radio writes the log: while armed or all the time",
    armSwitchHint = "Switch position that arms the model, the log runs while it is on",
    intervalHint = "Time between two rows of the log",
    chooseArmFirst = "Choose the arm switch first.",
    noFreeSlot = "No free special function. Remove one in the model.",
    removeLogs = "Remove SD logs from this model?",
  },

  -- Flight Bag (EdgeTX UI) only: texts its pages have beside those of ui (internal ids)
  uix = {
    settings = "Settings",
    saveFailedRetry = "Save failed. Check SD card. Retry?",
    show = "Show", defaultMark = "(default)", newer = "Newer", older = "Older",
    addBattery = "Add battery", editBattery = "Edit battery", nameAuto = "Name (auto)",
    packsOf = "Packs - {name}", statsOf = "Statistics - {name}",
    addModel = "Add model  {name}", editModel = "Edit model  {name}",
    batteryOf = "Battery  {name}", sensorsOf = "Sensors  {name}",
    select = "Select {cells}S batteries", selectParallel = "Select {cells}S parallel profiles",
    showInWingmanOf = "Show in Wingman  {name}", logsOf = "SD logs  {name}",
  },
}
