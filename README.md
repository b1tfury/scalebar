# ScaleBar

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="ScaleBar icon">
</p>

A small native macOS menu-bar app for a Dr Trust 509 body-composition scale (Bluetooth name `SWAN`). Click the menu-bar icon, step on the scale barefoot, and it shows the reading. It saves the row locally and can send **weight and BMI** to Garmin Connect.

No Electron. No Dock icon. Bluetooth is off until you open it. It idles at about 14 MB.

The figure in the panel is [Silhouette of man standing and facing forward](https://commons.wikimedia.org/wiki/File:Silhouette_of_man_standing_and_facing_forward.svg) by Madeleine Price Ball, CC0.

## Install

```sh
git clone https://github.com/b1tfury/scalebar.git
cd scalebar
make install
open /Applications/ScaleBar.app
```

Needs Swift 5.9 or later. The Xcode Command Line Tools are enough (`xcode-select --install`). macOS 13 or later, Apple Silicon.

The first time you open it, allow Bluetooth. The download is ad-hoc signed, so if macOS blocks it: right-click the app, choose Open, then Open again.

| Command | What it does |
| --- | --- |
| `make app` | Release build at `build/ScaleBar.app` |
| `make run` | Build and open that bundle |
| `make install` | Build and copy to `/Applications/ScaleBar.app` |
| `make test` | Unit tests |
| `make dev` | `swift run` |

## What you see

Weight, then four bars: weight, BMI, body fat, and body water. Each bar marks a reference range and where this reading sits. Muscle, lean mass, bone and BMR sit underneath.

The scale itself only measures two things: kilograms, and a single impedance in ohms. Fat, water, muscle, bone and BMR are calculated from those. BMI is weight and height.

## Your profile

Sex, age and height are hardcoded for one person in `Sources/ScaleBarCore/Composition.swift` (`Profile.sahil`). Change them before you trust the calculated numbers. The scale needs that profile in the Bluetooth setup as well (`ScaleProtocol.configPackets`).

Readings go to `~/health/health.db`, table `weighin`. Point it somewhere else with:

```sh
defaults write dev.bitfury.scalebar dbPath "$HOME/scalebar/health.db"
```

## Garmin

ScaleBar uploads **weight and BMI only**. It does not upload fat, water, muscle, bone or BMR.

The upload uses a token stored on your Mac at `~/.garminconnect`. The app never asks for your password, and this repository must never contain that folder, a password, or a token.

Create the token once, in a terminal, from this repo:

```sh
uv run scripts/garmin_login.py
```

It asks for your Garmin email and password. The password is not written to disk. What is written is a login token in `~/.garminconnect`. If Garmin sends a verification code, type it in that same terminal.

You need [uv](https://docs.astral.sh/uv/). Check the folder exists and then leave it alone:

```sh
ls ~/.garminconnect
```

After that, a new reading is pushed when the weigh-in finishes. The panel says `On Garmin since HH:MM`, or shows the error with a Retry button. A row that was already pushed is not pushed again.

You can also push one saved row yourself:

```sh
uv run scripts/garmin_push.py --db ~/health/health.db --push 2026-10-07T09:36:56
```

See it on the site: [connect.garmin.com/modern/weight](https://connect.garmin.com/modern/weight).

## License

[MIT](LICENSE).
