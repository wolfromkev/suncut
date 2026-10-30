# ROADMAP

**What:** macOS menu-bar helper for SimpleSnip and display brightness/Film Mode.

## Next
1. Finish the Mac App Store listing (below). Build 5 is already uploaded.
2. Optional: split SimpleSnip overlays/recorder out of `UmbrellaSimpleSnipFeature.swift`
3. Optional: wire automated `xcodebuild` once full Xcode is available in CI
4. Optional: notarize the GitHub DMG so the first open does not need a right-click (see `docs/PUBLISHING.md`)

## Mac App Store

The sandboxed build is the **UmbrellaHelper App Store** scheme. Release, `install.sh`, and the GitHub disk image stay unsandboxed. Both use `com.kevinwolfrom.umbrella`, so do not install the store build over `/Applications`.

Already done:

- App Store Connect record for this app, macOS, version **1.0**. Rename it to **Suncut** in App Store Connect before review.
- Bundle ID `com.kevinwolfrom.umbrella`, team `RTKZ7MF6UZ`
- Version **1.0** build **5** uploaded with release Xcode 27.0 (`27A266a`). The earlier 1.0.3 upload will not appear on this version page.
- Category in the app is Utilities (`public.app-category.utilities`)

Still to do in App Store Connect, on version 1.0:

1. Refresh until build **5** finishes processing, then select it. Leave the version at 1.0.
2. Add one Mac screenshot of the app in use, **1280 × 800** or larger.
3. Paste the promotional text, description, and keywords below.
4. **App Information:** name **Suncut**, support URL `https://github.com/wolfromkev/suncut`, copyright `2026 Kevin Wolfrom`, category Utilities.
5. **App Privacy:** precise location, used for app functionality, not linked to the user, not used for tracking. Screenshots and microphone audio stay on the Mac, so they are not collected data.
6. **Pricing and Availability:** free.
7. Paste the review notes below.
8. If the yellow license-agreement banner is still on the Apps page, accept it.
9. Click **Add for Review**.

**Promotional text**

Menu bar screenshots, area recording, and display warmth. Snip a region, copy the text, and dim the evening with Film Mode.

**Description**

Suncut lives in the menu bar for screenshots, screen recording, and display warmth.

SimpleSnip takes an area, a window, or the full screen, copies the image, and can read the text in a selection. You can also record an area with system audio or the microphone.

Brightness controls warmth and brightness, saves presets, and includes Film Mode to dim external displays. An optional daytime curve moves from a night floor to a midday peak, using times you set or your location for sunrise and sunset.

Launch at login and the global hotkeys are included.

**Keywords**

screenshot,screen recording,brightness,warmth,menu bar,snip,OCR,hotkey

**Review notes**

Menu bar utility. Screen Recording is for screenshots, window capture, text recognition, and area recording. The microphone is used only when Record microphone is on. Location is used only when the daytime curve follows sunrise and sunset. No account is required. Click the menu bar icon, take an area snip, and move the brightness slider. Film Mode dims external displays and restores them when it is turned off or the app quits.

Upload again only if build 5 is missing. Use release Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), not the beta. Commands are in `docs/PUBLISHING.md`. The App Store configuration’s version is 1.0; the GitHub Release configuration is 1.0.11.

## Decisions
- Localhost-only personal tool — no cloud backend
- Local installs sign with a stable keychain identity so Screen Recording, Microphone, and Accessibility survive rebuilds
- Film Mode dirty-flag: unclean exit restores gamma and leaves Film Mode off
- Auto brightness follows a sine curve (night floor → midday peak → night) between sunrise/sunset; twilight minutes pad the rise/fall; location can replace manual sun times
