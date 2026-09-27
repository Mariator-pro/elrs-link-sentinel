# Compatibility

This page shows which Link Sentinel features work with which flight controller firmware. Link Sentinel is built for ExpressLRS only, so other RC links are not covered.

## Flight controller firmware

| Feature | Betaflight | INAV | ArduPilot |
|---|:-:|:-:|:-:|
| Link warnings (voice, haptic) | ✅&nbsp;<img src="https://img.shields.io/badge/-tested-brightgreen" alt="tested" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> |
| Configuration-error tone | ✅&nbsp;<img src="https://img.shields.io/badge/-tested-brightgreen" alt="tested" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> |
| Link display (range, RF mode, RSSI, LQ, TX power, antenna) | ✅&nbsp;<img src="https://img.shields.io/badge/-tested-brightgreen" alt="tested" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> |
| ELRS module and firmware | ✅&nbsp;<img src="https://img.shields.io/badge/-tested-brightgreen" alt="tested" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> |
| FC flight mode (`FM`) | ✅&nbsp;<img src="https://img.shields.io/badge/-tested-brightgreen" alt="tested" height="20"> | ⚙️&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> | ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> |

## Legend

- ✅&nbsp;<img src="https://img.shields.io/badge/-tested-brightgreen" alt="tested" height="20"> Tested on the radio and in the simulator.
- ✅&nbsp;<img src="https://img.shields.io/badge/-source-blue" alt="source" height="20"> Checked in the source code (flight controller, ExpressLRS and EdgeTX), not tested on hardware yet.
- ⚙️ Works only after setup, see below. A badge next to ⚙️ means the same as next to ✅.

A ✅ means the feature works without extra setup, apart from ExpressLRS telemetry being enabled and the sensors being discovered on the radio.

The warnings and the link display only use values that ExpressLRS itself measures and sends, so they do not depend on the flight controller. Only `FM` comes from the flight controller.

If the receiver runs in MAVLink mode instead of CRSF, `FM` shows ArduPilot mode names (the ExpressLRS TX module converts them), also with INAV.

## Setup

What has to be set so the features work.

| Firmware | Flight controller | Radio |
|---|---|---|
| **Betaflight** | Nothing extra. | Nothing to change. |
| **INAV** | For `FM` only: `feature TELEMETRY` enabled (off by default on some boards) and the receiver set up as CRSF (`serialrx_provider = CRSF`). Warnings and link display need nothing from the flight controller. | Nothing to change. |
| **ArduPilot** | Nothing extra. `FM` needs the receiver on a serial port with `SERIALx_PROTOCOL = 23` (RCIN), which RC control over CRSF needs anyway. | Nothing to change. |
