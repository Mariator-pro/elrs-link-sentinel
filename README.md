# elrs-link-sentinel

![elrs-link-sentinel: EdgeTX Lua script for early ExpressLRS audible warnings](docs/banner.png)

A small EdgeTX Lua script that watches your ExpressLRS link in the background and audibly warns you **before** the connection breaks down.

[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](LICENSE)
[![EdgeTX](https://img.shields.io/badge/EdgeTX-%E2%89%A5%202.10-brightgreen)](https://edgetx.org)
[![ExpressLRS](https://img.shields.io/badge/ExpressLRS-%E2%89%A5%204.0-orange)](https://www.expresslrs.org)
[![GitHub issues](https://img.shields.io/github/issues/Mariator-pro/elrs-link-sentinel)](../../issues)
[![GitHub last commit](https://img.shields.io/github/last-commit/Mariator-pro/elrs-link-sentinel)](../../commits/main)

---

## 📑 Table of Contents

- [📋 Compatibility](#-compatibility)
- [🎯 What is it for?](#-what-is-it-for)
- [🧰 Requirements](#-requirements)
- [📥 Installation](#-installation)
- [⚙️ Customizing](#️-customizing)
- [🛠️ Troubleshooting](#️-troubleshooting)
- [💡 Credits](#-credits)
- [🤝 Contributing](#-contributing)
- [⚠️ Disclaimer](#️-disclaimer)
- [📄 License](#-license)

---

## 📋 Compatibility

| Component | Minimum Version | Tested On | Test Hardware |
|-----------|-----------------|-----------|---------------|
| EdgeTX    | v2.10           | v2.12.0   | Radiomaster TX15, Radiomaster TX16S MK3 |
| ExpressLRS| v4.0.0          | v4.0.0    | Radiomaster RP1 V2, RP3 V2, RP4TD |

---

## 🎯 What is it for?

With ELRS, the usable range depends heavily on the selected RF mode (packet rate). Each mode has its own receiver sensitivity limit. If you don't keep a constant eye on a live telemetry screen, you usually only notice a weakening link when it's already too late.

`sntnl.lua` reads the receiver's telemetry values (RSSI of both antennas, link quality, current RF mode) and plays two graded warning tones:

- **Link Warning:** The receiver's antenna(s) are close to the sensitivity limit of the current mode. On a dual-antenna receiver both antennas have to drop below the threshold; a single-antenna receiver is evaluated on its only RSSI value. *"Time to turn back toward the pilot."*
- **Link Critical:** Same RSSI condition as above **and** packets are starting to drop (RQly < 42 %). *"Come back now."*

If telemetry is lost completely, the script intentionally stays silent, because EdgeTX itself already raises an alarm in that case.

If telemetry is up but the required sensors (`1RSS`, `RQly`) never show up (typically because sensor discovery was skipped or the receiver's telemetry is configured non-standard), the script plays a separate **configuration-error tone** so you know it cannot warn you. The tone repeats every 30 seconds until the sensors appear.

---

## 🧰 Requirements

- A radio running EdgeTX
- An ExpressLRS receiver running firmware 4.0 or newer with telemetry enabled
- The following ELRS telemetry sensors must be discovered on the radio: `RFMD`, `1RSS`, `RQly`, and `2RSS` on dual-antenna receivers (they appear automatically after a telemetry discovery)

---

## 📥 Installation

### 1. Copy the files to the SD card

Take the SD card out of the radio (or connect the radio via USB as mass storage) and create the following structure:

```
SCRIPTS/
└── FUNCTIONS/
    └── sntnl.lua
SOUNDS/
└── en/
    └── SCRIPTS/
        └── SNTNL/
            ├── stage1.wav
            ├── stage2.wav
            └── cfgerr.wav
```

All four files are available in the matching folders of this repository. Just copy them 1:1 to the same locations on the SD card. The WAV files always live under `/SOUNDS/en/SCRIPTS/SNTNL/` regardless of the radio's language setting; `sntnl.lua` uses an absolute path to play them.

### 2. Set up a Special Function on the model

1. Put the SD card back into the radio and switch it on.
2. Open the **Model Settings** of the desired model and go to the **Special Functions** (also called "SF") page.
3. Pick a free slot and configure it as follows:
   - **Switch / Condition:** `On` (the script runs permanently in the background)
   - **Action:** `Lua Script`
   - **Value / Script:** `sntnl`
   - **Repeat:** `On`
   - **Enable:** `On`
4. Save the settings.

### 3. Test it

- Bind the model and verify telemetry (RSSI values and RQly must show up on the radio).
- When you intentionally weaken the link (e.g. move the model away, cover an antenna), the first warning tone should play after about 2 seconds and repeat every 5 seconds.
- With a very weak link **and** packet loss the script automatically switches to the critical warning tone.

---

## ⚙️ Customizing

If you want to tweak the thresholds or timings, open `sntnl.lua` in a text editor. The first lines of the script define four constants:

| Constant          | Default | Meaning                                              |
|-------------------|---------|------------------------------------------------------|
| `WARN_OFFSET_DB`  | `10`    | Margin above the sensitivity limit (dBm) that triggers a warning |
| `RQLY_THRESHOLD`  | `42`    | RQly threshold in % for the critical warning        |
| `DEBOUNCE_MS`     | `2000`  | How long the condition must hold (ms)               |
| `REPEAT_MS`       | `5000`  | Gap between two warning tones (ms)                  |

After saving, copy the file back to the SD card. No reboot needed; EdgeTX reloads the script the next time the model is activated.

### Replacing the warning sounds

If you don't like the supplied tones, feel free to drop in your own audio files. Just keep the file names exactly as they are (`stage1.wav` for the warning, `stage2.wav` for the critical alert) and leave them in the `/SOUNDS/en/SCRIPTS/SNTNL/` folder.

---

## 🛠️ Troubleshooting

- **Script doesn't show up when picking it for the Special Function:** Check the file name. It must be exactly `sntnl.lua` (max. 6 characters, otherwise EdgeTX hides function scripts).
- **No warning tone is ever played:** Make sure the WAV files really sit in `/SOUNDS/en/SCRIPTS/SNTNL/` (the `en/` folder is mandatory even if your radio is set to another language).
- **Permanent warning despite good reception:** Your ELRS setup is probably using a mode whose sensitivity limit isn't yet listed in the script. Please [open an issue](../../issues) so it can be added.

---

## 💡 Credits

The idea for this script comes from the RC Video Reviews YouTube video ["Express LRS Link Telemetry • How-to Setup Your Radio Correctly"](https://www.youtube.com/watch?v=sl68I-MoJ9Q).

---

## 🤝 Contributing

Found a bug, have an idea for an improvement, or running an ELRS mode that isn't covered yet? Please [open an issue](../../issues) on GitHub. Pull requests are welcome too.

---

## ⚠️ Disclaimer

This script is provided **as is** and is intended as an additional aid only. It does **not** replace careful flying within visual range, your own judgement, or the safety mechanisms of your transmitter and receiver. Always be ready to react manually. Use at your own risk.

---

## 📄 License

Released under the [GNU General Public License v2.0](LICENSE).