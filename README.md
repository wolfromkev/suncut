# Suncut

<p align="center">
  <img src="branding/icon-1024.png" alt="Suncut logo" width="128" height="128">
</p>

A native macOS menu bar app for screen capture/recording and display warmth/brightness (including Film Mode).

## Features

- **SimpleSnip:** area / window / full-screen screenshots, area recording, and OCR text copy
- **Brightness:** warmth + brightness controls, presets, Film Mode (dims external displays), and an optional daytime curve (dim at night, peak at midday) with manual or location-based sunrise/sunset
- **Menu bar:** click for controls; right-click for Settings / Restart / Quit
- **Launch at login** and customizable global hotkeys

## Requirements

- macOS 14 (Sonoma) or later

## Install

Download the disk image. You do not need Xcode.

**[Download Suncut](https://github.com/wolfromkev/suncut/releases/latest/download/Suncut.dmg)**

1. Open the DMG and drag **Suncut** onto Applications.
2. Right-click **Suncut** in Applications and choose **Open**, then **Open** again. macOS blocks this download the first time because it is not notarized.
3. If macOS says the app is damaged, open Terminal and run:

```bash
xattr -cr "/Applications/Suncut.app"
```

Then right-click the app and choose **Open** again.

## Build from source

Requires Xcode 27 (or Xcode 26 on macOS Tahoe).

```bash
git clone https://github.com/wolfromkev/suncut.git
cd suncut
chmod +x install.sh
./install.sh
```

Or build, install, and relaunch:

```bash
./build-and-install.sh
```

The script builds a Release app, copies it to `/Applications/Suncut.app`, and signs it with a stable certificate from your keychain (Apple Development, or `UMBRELLA_SIGN_IDENTITY` if you set one). That keeps Screen Recording, Microphone, and Accessibility granted across rebuilds. The first launch after switching off ad-hoc signing asks for those permissions once.

## First-time setup

1. Launch **Suncut** from Applications.
2. Open **Settings** (menu bar → right-click → Settings, or `⌘,`).
3. Under **Permissions**, grant **Screen Recording** (and Microphone if you record with mic).

Default shortcuts (all configurable): **⌘⇧S** area snip · **⌘⇧W** window · **⌘⇧A** full screen · **⌘⇧R** record · **⌘⇧T** text OCR · **F1/F2** brightness · **⇧F1/⇧F2** warmth.

## Branding

Open-source assets live in `branding/`:

| File | Use |
|------|-----|
| `logo.svg` | README, docs |
| `icon-1024.png` | App icon master |

## License

MIT — see [LICENSE](LICENSE).
