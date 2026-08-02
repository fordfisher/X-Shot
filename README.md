# X-Shot

Apple Silicon screenshot app for selected parts of the screen. Copies to the clipboard, opens an editor, and includes a library. Default hotkey: **⇧⌘4**.

## Download

Grab the latest compiled app from [Releases](https://github.com/fordfisher/X-Shot/releases): unzip `XShot.app.zip` and open `XShot.app`.

Product site: open [`docs/index.html`](docs/index.html) locally, or enable GitHub Pages from the `docs/` folder.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```bash
git clone https://github.com/fordfisher/X-Shot.git
cd X-Shot
./Scripts/build-app.sh
open dist/XShot.app
```

That produces `dist/XShot.app` with the same icon and resources as this repo (`Resources/AppIcon.icns` + `Resources/AppIcon.iconset/`).

To regenerate the icon from the Swift generator:

```bash
swift Scripts/generate-icon.swift .
```

## Test

```bash
./Scripts/test.sh
```
