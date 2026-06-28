# elrs-link-sentinel

![elrs-link-sentinel: EdgeTX Lua script for early ExpressLRS audible warnings](docs/banner.png)

A small EdgeTX project that watches your ExpressLRS link in the background and audibly warns you **before** the connection breaks down. It ships in two interchangeable flavors: a tiny **function script** (audio only) and a **color widget** (the same audio warnings *plus* a live link display).

[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](LICENSE)
[![EdgeTX](https://img.shields.io/badge/EdgeTX-%E2%89%A5%202.11-brightgreen)](https://edgetx.org)
[![ExpressLRS](https://img.shields.io/badge/ExpressLRS-%E2%89%A5%204.0-orange)](https://www.expresslrs.org)
[![GitHub issues](https://img.shields.io/github/issues/Mariator-pro/elrs-link-sentinel)](../../issues)
[![GitHub last commit](https://img.shields.io/github/last-commit/Mariator-pro/elrs-link-sentinel)](../../commits/main)

---

## 📑 Table of Contents

- [📋 Compatibility](#-compatibility)
- [🎯 What is it for?](#-what-is-it-for)
- [🧩 Script variants](#-script-variants)
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
| EdgeTX    | v2.11           | v2.12.0   | Radiomaster TX15, Radiomaster TX16S MK3 |
| ExpressLRS| v4.0.0          | v4.0.0    | Radiomaster RP1 V2, RP3 V2, RP4TD |

---

## 🎯 What is it for?

With ELRS, the usable range depends heavily on the selected RF mode (packet rate). Each mode has its own receiver sensitivity limit. If you don't keep a constant eye on a live telemetry screen, you usually only notice a weakening link when it's already too late.

The sentinel reads the receiver's telemetry values (RSSI of both antennas, link quality, current RF mode) and plays two graded warning tones:

- **Link Warning:** The antenna(s) are near the current mode's sensitivity limit. *"Time to turn back toward the pilot."*
- **Link Critical:** Same condition, plus packets starting to drop (RQly < 42 %). *"Come back now."*

If telemetry is lost completely, the sentinel intentionally stays silent, because EdgeTX itself already raises an alarm in that case.

If telemetry is up but the required sensors (`RFMD`, `1RSS`, `RQly`) never show up, it plays a separate **configuration-error tone** so you know it cannot warn you. The tone repeats every 30 seconds until the sensors appear.

---

## 🧩 Script variants

The warning logic lives in a shared core module (`core.lua`). On top of it sit two wrappers, and you install **exactly one** of them:

| | **Function script** | **Widget** |
|---|---|---|
| Audible warnings | ✅ | ✅ |
| Visual link display | ❌ | ✅ (range %, RF mode, RSSI, LQ, TX power, FC flight mode, active antenna, ELRS module + firmware) |
| Runs in the background | ✅ (Special Function) | ✅ (keeps warning even when the screen is not shown) |
| Supported radios | all EdgeTX radios | color-display radios only |

> ⚠️ **Don't install both at the same time**, or they would play the warning tones twice. The widget fully replaces the function script.

Both variants need `core.lua` on the SD card, because it holds the shared warning logic that keeps audio and display in sync.

---

## 🧰 Requirements

- A radio running EdgeTX (color display required for the widget variant)
- An ExpressLRS receiver running firmware 4.0 or newer with telemetry enabled
- The following ELRS telemetry sensors must be discovered on the radio (they appear automatically after a telemetry discovery):
  - **Mandatory:** `RFMD`, `1RSS`, `RQly`
  - **Dual-antenna receivers:** `2RSS`
  - **Widget display only (optional):** `ANT`, `TPWR`, `FM` (shown when present)

---

## 📥 Installation

### 1. Copy the files to the SD card

Take the SD card out of the radio (or connect the radio via USB as mass storage). Just copy everything below 1:1, since it does no harm to have both variants on the card. You then pick which one to use later by **either** activating the widget **or** adding the function script to a Special Function (just not both, see [Script variants](#-script-variants)):

```
SCRIPTS/
├── SNTNL/
│   └── core.lua            ← shared logic (used by both variants)
├── FUNCTIONS/
│   └── sntnl.lua           ← function-script variant
└── TOOLS/
    └── SNTNL.lua           ← on-radio settings tool (optional)
WIDGETS/
└── SNTNL/
    └── main.lua            ← widget variant
SOUNDS/
└── en/
    └── SCRIPTS/
        └── SNTNL/
            ├── stage1.wav
            ├── stage2.wav
            └── cfgerr.wav
```

All files are available in the matching folders of this repository, so just copy them to the same locations on the SD card. The WAV files always live under `/SOUNDS/en/SCRIPTS/SNTNL/` regardless of the radio's language setting; the script uses an absolute path to play them.

### 2a. Set up the function script (Special Function)

1. Put the SD card back into the radio and switch it on.
2. Open the **Model Settings** of the desired model and go to the **Special Functions** (also called "SF") page.
3. Pick a free slot and configure it as follows:
   - **Switch / Condition:** `On` (the script runs permanently in the background)
   - **Action:** `Lua Script`
   - **Value / Script:** `sntnl`
   - **Repeat:** `On`
   - **Enable:** `On`
4. Save the settings.

### 2b. *(Alternative)* Set up the widget

1. Put the SD card back into the radio and switch it on.
2. Open the model's **Telemetry / Display** (widget screens) configuration.
3. Add a widget to a free zone and pick **Sentinel** from the list.
4. *(Optional)* Open the widget settings to adjust:
   - **Theme**: `Dark` / `Light`.
   - **Transparency**: milky-overlay transparency level (light theme only).
   - **Accent**: color of the heading / brand text: `Default` (the classic green), `Theme` (the focus color of your active EdgeTX theme), or `Custom` (pick any color via **AccentColor**).

> 📐 **Recommended screen layouts:** EdgeTX names its widget-screen layouts `columns × rows` (e.g. `2×4` = 2 columns next to each other, 4 rows on top of each other → 8 zones). The Sentinel widget is designed for a **half-width** zone, so it looks best in the layouts with **2 columns**:
>
> - **2×2**: half width, half height (the quarter-tile). This is the primary use case and shows the full layout with every value.
> - **2×3**: half width, one third height. Slightly shorter, so the widget automatically switches to a more compact layout.
> - **2×4**: half width, one quarter height. The shortest supported zone; it falls back to the most compact layout to stay readable.

### 3. Test it

- Bind the model and verify telemetry (RSSI values and RQly must show up on the radio).
- When you intentionally weaken the link (e.g. move the model away, cover an antenna), the first warning tone should play after about 2 seconds and repeat every 5 seconds.
- With a very weak link **and** packet loss the sentinel automatically switches to the critical warning tone.
- If you enabled haptic feedback, the radio vibrates together with each warning tone.
- On the widget, the range bar fills towards 100 % and changes color (green → yellow → red) in lockstep with the audio warning.

---

## ⚙️ Customizing

To adjust the warning thresholds and pick custom sounds, use the bundled **settings tool**. Copy `/SCRIPTS/TOOLS/SNTNL.lua` to the SD card (see the file tree above) and open it on the radio via **SYS → Tools → "Link Sentinel"**.

- **Settings**: a two-row table (`Stage 1`, `Stage 2`). Scroll onto a row and press ENTER to step through its cells (Threshold → Sound → Test):
  - **Stage 1 → Threshold**: the warning margin in dB above the mode's sensitivity limit. **Editable 10-30 dB** (default 10). Higher = warns *earlier* / keeps more reserve.
  - **Stage 2 → Threshold**: the RQly bound (%) for the critical warning. **Editable 30-70 %** (default 42). Higher = critical fires *earlier*.
  - **Sound**: pick `Default` or any `.wav` you dropped into `/SOUNDS/en/SCRIPTS/SNTNL/`, per stage. Files can have **any name**, and every `.wav` in that folder shows up in the list automatically.
  - **Test**: plays the row's currently selected sound so you can compare them on the spot.
- **Haptic feedback**: vibrate alongside the warning tones (needs a radio with a vibration motor). Off by default; turn it `On` to add a pulse for Stage 1 and a stronger double pulse for Stage 2.
  - **Haptic strength**: pulse-length tier (`Soft` / `Normal` / `Strong`, default `Normal`). Only shown while haptic feedback is on.
- **Reset config** restores the defaults.
- **About**: version and the paths the project uses.

Press **Save** to write the settings. They land in `/SCRIPTS/SNTNL/config.lua`, which `core.lua` reads once when the script starts, so **both variants** (function script *and* widget) use them after the next model select (or reboot). The config file is **optional**: without it the hard-coded defaults stay in force.

---

## 🛠️ Troubleshooting

- **Script doesn't show up when picking it for the Special Function:** Check the file name. It must be exactly `sntnl.lua` (max. 6 characters, otherwise EdgeTX hides function scripts).
- **Widget shows "Core missing / Reinstall SNTNL", or the function script errors on load:** `core.lua` is not where it should be. Make sure `/SCRIPTS/SNTNL/core.lua` exists on the SD card, since both variants depend on it.
- **Widget shows "Sensor missing / Discover in EdgeTX" (and the config-error tone plays):** One of the mandatory sensors (`RFMD`, `1RSS`, `RQly`) is missing. Run a telemetry discovery on the radio while the link is up.
- **No warning tone is ever played:** Make sure the WAV files really sit in `/SOUNDS/en/SCRIPTS/SNTNL/` (the `en/` folder is mandatory even if your radio is set to another language). The quickest check is the settings tool: press **Test** on a stage to play its tone directly, which confirms the file is found and your radio's volume is up.
- **Permanent warning / range shows "--" despite good reception:** Your ELRS setup is probably using a mode whose sensitivity limit isn't yet listed in `core.lua`. Please [open an issue](../../issues) so it can be added.

---

## 💡 Credits

The idea for this script comes from the RC Video Reviews YouTube video ["Express LRS Link Telemetry • How-to Setup Your Radio Correctly"](https://www.youtube.com/watch?v=sl68I-MoJ9Q).

---

## 🤝 Contributing

Found a bug, have an idea for an improvement, or running an ELRS mode that isn't covered yet? Please [open an issue](../../issues) on GitHub. Pull requests are welcome too.

---

## ⚠️ Disclaimer

This project is provided **as is** and is intended as an additional aid only. It does **not** replace careful flying within visual range, your own judgement, or the safety mechanisms of your transmitter and receiver. Always be ready to react manually. Use at your own risk.

---

## 📄 License

Released under the [GNU General Public License v2.0](LICENSE).