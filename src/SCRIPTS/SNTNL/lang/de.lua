-- =====================================================================
-- lang/de.lua  --  German texts of Link Sentinel in the Flight Bag tool
-- =====================================================================
-- SD card path: /SCRIPTS/SNTNL/lang/de.lua
-- Same areas and ids as lang/en.lua; a text missing here is shown in
-- English. {name} is a placeholder. Plain quotes and dots only: the
-- radio's font has no typographic ones.
-- =====================================================================
-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Mariator-pro
-- =====================================================================

return {
  fields = {
    warnOffsetDb   = { label = "Verbindung schwach", hint = "Frühe Warnung {v} vor der RSSI-Grenze (1RSS/2RSS)" },
    rqlyThreshold  = { label = "Verbindung kritisch", hint = "Kritische Warnung, wenn RQly unter {v} fällt" },
    audio          = { label = "Töne", hint = "Aus schaltet alle Ansagen stumm, die Vibration bleibt" },
    haptic         = { label = "Vibration" },
    hapticStrength = { label = "Stärke", choices = { "Schwach", "Normal", "Stark" } },
    language       = { label = "Sprache", hint = "Sprache von Flight Bag" },
  },
  sounds = {
    stage1 = { label = "Verbindung schwach", hint = "Signal nah an der Grenze" },
    stage2 = { label = "Verbindung kritisch", hint = "Signal an der Grenze und Verbindungsqualität niedrig" },
    lost   = { label = "Verbindung verloren", hint = "Verbindung im Flug weg (ab Werk aus)" },
    conn   = { label = "Verbindung steht", hint = "Verbindung für einen neuen Flug da (ab Werk aus)" },
    rec    = { label = "Verbindung wieder da", hint = "Verbindung nach einem Verlust im Flug zurück (ab Werk aus)" },
  },
  resets = {
    settings = { label = "Einstellungen zurücksetzen", ask = "Einstellungen von Link Sentinel auf Werkseinstellungen zurücksetzen?",
                 desc = "Link Sentinel bekommt wieder seine Werkseinstellungen." },
  },
  setup = {
    damaged        = "Einstellungsdatei beschädigt",
    missingSensors = "Sensoren fehlen: {sensors}",
    checkSensors   = "Sensoren des Modells prüfen",
  },
  files = { core = "Core", config = "Einstellungen", widget = "Widget", func = "Funktion", sounds = "Töne" },
}
