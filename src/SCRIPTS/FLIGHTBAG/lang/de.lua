-- =====================================================================
-- lang/de.lua  --  German texts of the Flight Bag settings tool
-- =====================================================================
-- SD card path: /SCRIPTS/FLIGHTBAG/lang/de.lua
-- Same areas and ids as lang/en.lua; a text missing here is shown in
-- English. {name} is a placeholder. Plain quotes and dots only: the
-- radio's font has no typographic ones.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return {
  pages = { warnings = "Warnungen", alerts = "Ansagen", batteries = "Akkus", models = "Modelle",
            flights = "Letzte Flüge", display = "Anzeige" },
  titles = { warnings = "WARNUNGEN", alerts = "ANSAGEN", batteries = "AKKUS", models = "MODELLE",
             flights = "LETZTE FLÜGE", display = "ANZEIGE" },

  rows = {
    on = "Ein", off = "Aus", mixed = "Gemischt", default = "Standard",
    mixedHint = "Die Apps haben verschiedene Werte, wähle neu",
    noConfig = "Noch keine Einstellungsdatei", create = "Anlegen",
    damaged = "Einstellungsdatei beschädigt", reset = "Zurücksetzen",
    resetAsk = "Die beschädigte Einstellungsdatei durch die Werkseinstellungen ersetzen?",
  },
  sounds = { off = "Aus", default = "Standard" },

  rules = {
    manufacturerRequired = "Gib einen Hersteller an.",
    lowAboveCritical = '"Akku niedrig" muss über "Akku kritisch" liegen.',
    lastPack = "Das ist der letzte Pack. Lösche stattdessen den Akku.",
    parallelKeepTwo = "{models} nutzen zwei Packs parallel, deshalb behält der Akku mindestens 2.",
    parallelUnassign = "{models} nutzen diesen Akku parallel. Nimm ihn dort zuerst heraus.",
    maxPacks = "Ein Akku hat höchstens {n} Packs.",
    deleteOne = "Akku löschen und seinen Pack archivieren?",
    deleteAll = "Akku löschen und alle {n} Packs archivieren?",
    parallelNeedsTwo = '"Packs parallel" braucht einen Akku mit mindestens 2 Packs.',
    saveFailed = "{app}: Speichern ging nicht, prüfe die SD-Karte",
  },

  popup = {
    updateNeeded = "Update nötig: Diese Version läuft nicht mit diesem Flight Bag.",
    noConfig = "Noch keine Einstellungsdatei",
    damaged = "Einstellungsdatei beschädigt ({detail}).",
    files = "Dateien", create = "Anlegen", reset = "Zurücksetzen",
    resetAsk = "Die beschädigte Einstellungsdatei durch die Werkseinstellungen ersetzen?",
  },

  models = {
    voltage  = { label = "Spannung", hint = "Spannung des ganzen Packs (V). Daraus kommen Ladestand in % und Warnungen. 4S voll etwa 16,8 V, leer etwa 14,0 V." },
    current  = { label = "Strom", hint = "Aktueller Strom (A). Daraus schätzt Lipo Nanny die Restzeit, z. B. 0 bis 120 A." },
    capacity = { label = "Verbrauch", hint = 'Verbrauchte mAh, zählt ab 0 aufwärts (oder %, siehe "Einheit des Verbrauchs"). Löst die Warnungen vor allem aus.' },
    capacityUnit = { label = "Einheit des Verbrauchs", hint = "Nur, wenn der Flight Controller den Rest in % sendet. Seine Kapazität muss den mAh des Packs entsprechen.",
                     choices = { mah = "mAh verbraucht (Standard)", pct = "% Rest" } },
    lipo = { label = "Akku", hint = "Akku-Spalte, Wahl des Packs und Ansagen von Lipo Nanny" },
    link = { label = "Verbindung", hint = "Verbindungs-Spalte und Ansagen von Link Sentinel" },
    gps  = { label = "GPS", hint = "GPS-Spalte, Suchseite und Ansagen von GPS Homer" },
    none = "Keine",
  },

  ui = {
    back = "Zurück", save = "Speichern", delete = "Löschen", close = "Schließen", exit = "Beenden",
    yes = "Ja", no = "Nein", ok = "OK", retry = "Nochmal", cancel = "Abbrechen",
    apply = "Anwenden", remove = "Entfernen", play = "Hören", done = "Fertig", clear = "Leeren",
    discard = "Änderungen verwerfen?",
    saved = "Erledigt.",
    saveFailed = "Speichern ging nicht. Prüfe die SD-Karte.",
    pageFailed = "{page} ließ sich nicht starten. Kopiere {path} erneut auf die SD-Karte.",
    pageError = "Fehler: {msg}",
    noApps = "Keine Einstellungen gefunden.\n\nFlight Bag zeigt die Einstellungen der installierten Scripts. Kopiere ein Script auf die SD-Karte und öffne Flight Bag erneut.",
    nothing = "Hier gibt es nichts einzustellen.",
    soundPicker = "Ton für {label}",

    noQr = "Kein QR-Code",
    noFlights = "Noch kein Flug gespeichert.",
    noFlightsHint = "Die Position wird gespeichert, wenn nach einem Flug die Telemetrie endet.",
    roller = "RAD", olderNewer = "älter / neuer",
    lastPosition = "LETZTE POSITION", lat = "BREITE", lon = "LÄNGE",
    noClock = "ohne Uhrzeit",

    noBatteries = "Noch keine Akkus. Lege deinen ersten an.",
    addNew = "[+] Neuer Akku",
    lipoBroken = "Die Einstellungsdatei von Lipo Nanny ist nicht lesbar.",
    lipoBrokenFix = "Behebe das in der App Lipo Nanny (Startseite).",
    name = "Name", auto = "(auto)", manufacturer = "Hersteller", chemistry = "Zellchemie",
    capacity = "Kapazität", cells = "Zellen", packs = "Packs", statistics = "Statistik",
    batteryLow = "Akku niedrig", batteryCritical = "Akku kritisch",
    pctDefault = "{v} % (Standard)",
    resetName = "Name zurücksetzen",
    titleEditName = "NAME BEARBEITEN", titleEditManufacturer = "HERSTELLER BEARBEITEN",
    titleAddBattery = "AKKU HINZUFÜGEN", titleEditBattery = "AKKU BEARBEITEN",
    switchGroup = "Gruppe wechseln", wheel = "Rad", slot = "Stelle", enter = "ENTER", edit = "ändern",
    step = "Schritt {n}",
    titlePacks = "PACKS - {name}", titleStats = "STATISTIK - {name}",
    colId = "ID", colCycles = "Zyklen", colWear = "Verschleiß", colBought = "Gekauft", colDelete = "Löschen",
    colLifeMah = "mAh gesamt", colVmin = "Vmin", colLastUsed = "Zuletzt genutzt",
    addPack = "[+] Neuer Pack",

    noModels = "Noch keine Modelle eingerichtet.",
    active = "[aktiv]",
    addCurrent = "[+] Aktuelles Modell hinzufügen",
    titleAddModel = "MODELL HINZUFÜGEN  {name}", titleEditModel = "MODELL BEARBEITEN  {name}",
    battery = "Akku", showInWingman = "In Wingman zeigen", sdLogs = "SD-Logs",
    oneBattery = "{n} Akku", manyBatteries = "{n} Akkus",
    parallelDrop = '"Packs parallel" nimmt {batteries} mit weniger als 2 Packs aus dem Modell. Weiter?',
    cellsDrop = "Die neue Zellenzahl nimmt {batteries} aus dem Modell. Weiter?",
    deleteModel = "Einrichtung von {name} löschen?",
    titleBattery = "AKKU  {name}",
    parallelPacks = "Packs parallel", batteries = "Akkus", selected = "{n} gewählt",
    sensors = "Sensoren", custom = "eigene", default = "Standard",
    titleSelect = "AKKUS MIT {cells}S WÄHLEN", titleSelectParallel = "PARALLELE AKKUS MIT {cells}S WÄHLEN",
    noMatching = "Keine passenden Akkus.",
    titleSensors = "SENSOREN  {name}",
    sensorDefault = "{name} (Standard)",
    sensorPicker = "Sensor für {label}",
    activateToEdit = "Wähle dieses Modell am Sender, um die Sensoren zu ändern.",
    resetSensors = "Standard-Sensoren nutzen",
    titleShowInWingman = "IN WINGMAN ZEIGEN  {name}",

    titleLogs = "SD-LOGS  {name}",
    setUp = "Einrichten",
    log = "Log", armSwitch = "Arm-Schalter", interval = "Intervall",
    armed = "Scharf", alwaysOn = "Immer an",
    chooseArm = "Arm-Schalter wählen",
    onlyActive = "Nur für das gewählte Modell",
    noTriggerShort = "Kein Auslöser", disabledSuffix = ", abgeschaltet",
    noTrigger = "Kein Auslöser im Modell",
    noTriggerHelp = 'Ohne Schalter schreibt EdgeTX nie ein Log. Wähle den Arm-Schalter und dann "Anwenden".',
    disabled = "Im Modell abgeschaltet",
    disabledHelp = 'Die Spezialfunktion ist abgeschaltet. "Anwenden" schaltet sie wieder ein.',
    logSensorsSome = "Log-Sensoren: {found} von {total} gefunden",
    logSensorsAll = "Log-Sensoren: alle {total} gefunden",
    discoverHelp = 'Öffne Model > Telemetry und wähle "Discover new sensors", während die Apps laufen.',
    logHint = "Wann der Sender das Log schreibt: solange scharf oder immer",
    armSwitchHint = "Schalterstellung, die das Modell scharf schaltet, solange läuft das Log",
    intervalHint = "Abstand zwischen zwei Zeilen im Log",
    chooseArmFirst = "Wähle zuerst den Arm-Schalter.",
    noFreeSlot = "Keine Spezialfunktion frei. Entferne eine im Modell.",
    removeLogs = "SD-Logs aus diesem Modell entfernen?",
  },

  uix = {
    settings = "Einstellungen",
    saveFailedRetry = "Speichern ging nicht. Prüfe die SD-Karte. Nochmal versuchen?",
    show = "Zeigen", defaultMark = "(Standard)", newer = "Neuer", older = "Älter",
    addBattery = "Akku hinzufügen", editBattery = "Akku bearbeiten", nameAuto = "Name (auto)",
    packsOf = "Packs - {name}", statsOf = "Statistik - {name}",
    addModel = "Modell hinzufügen  {name}", editModel = "Modell bearbeiten  {name}",
    batteryOf = "Akku  {name}", sensorsOf = "Sensoren  {name}",
    select = "Akkus mit {cells}S wählen", selectParallel = "Parallele Akkus mit {cells}S wählen",
    showInWingmanOf = "In Wingman zeigen  {name}", logsOf = "SD-Logs  {name}",
  },
}
