# Publishing Bashteroids on the App Store

## 1. Apple Developer Program

Enroll at https://developer.apple.com — $99/year. Required for App Store distribution on iOS, Mac, and tvOS.

## 2. App Store Connect setup

1. Go to https://appstoreconnect.apple.com and create a new app record.
2. Set the bundle ID to match `PRODUCT_BUNDLE_IDENTIFIER` in Xcode (`com.markus.Bashteroids`).
3. Under **Platforms**, enable **iOS**, **macOS**, and **tvOS** on the same record (single-target multi-destination — one binary, three storefront listings auto-generated from the same metadata).
4. Fill in the metadata below.

## 3. Required metadata (drafts — edit to taste before submitting)

### App name (≤30 chars)
```
Bashteroids
```

### Subtitle (≤30 chars)
```
Couch co-op vector arcade
```

### Promotional text (≤170 chars, editable post-release without re-review)
```
Up to four players, up to four controllers, one screen. Pure vector ships, hollow asteroids, and the occasional alien monster. No ads. No IAP. Just play.
```

### Description (≤4000 chars)
```
Bashteroids is a classic-vector Asteroids-style arcade game built for couch co-op. One to four players, each with their own Bluetooth game controller, share a single screen and shoot, dodge, and chase across a wrap-around starfield.

Everything is drawn live as line vectors and synthesised on the fly — no bundled images, no recorded audio. Just glowing edges, bursts of noise, and the satisfying thump of a 6502-era arcade rebuilt in modern Swift.

CONTROLS
• Turn, thrust, fire — three buttons, no menus mid-game
• Pick up shields (stack to 2), twin laser, and brakes
• MFi and Bluetooth pads, Apple TV Siri Remote, or a hardware keyboard

ENEMIES
• Asteroids that drift and split
• UFOs that arc across the screen and snipe at the nearest ship
• Alien monsters with short-range lasers
• Six-segment snakes that home on you and weave around your bullets
• Mines that drop without warning and detonate on a timer
• Rocks: indestructible, ignore your shields, ruin your day

EVERY LEVEL ESCALATES
Asteroids speed up and grow. New enemy types unlock as you climb. The HUD stays out of your way. There is no high-score upload, no account, no telemetry — your three best runs live on the device that recorded them.

REQUIREMENTS
• iPad (landscape) or Mac with macOS 15+, or Apple TV (tvOS 17+)
• A Bluetooth game controller per player for multiplayer (one player can use a hardware keyboard or the Apple TV Siri Remote)
```

### Keywords (≤100 chars total, comma-separated, no spaces after commas)
```
asteroids,arcade,vector,couch coop,multiplayer,retro,space,controller,local,party
```

### Primary category
```
Games → Arcade
```

### Secondary category
```
Games → Action
```

### Copyright
```
© 2026 Markus Döring
```

### Support URL (required — placeholder until set up)
```
https://github.com/<your-username>/bashteroids/issues
```

### Marketing URL (optional)
```
(blank)
```

### Privacy policy URL (required even though no data is collected)

Host a simple page that says "Bashteroids does not collect, transmit, or store any personal data. All gameplay state is held locally on the device." A GitHub Pages page or a single-file Gist is sufficient. Then enter:

```
https://<your-pages-host>/bashteroids-privacy
```

### App Privacy questionnaire ("Data Types" section)

Answer **"No, we do not collect data from this app"** for the entire questionnaire. The app makes no network calls and stores high scores / player names only in `UserDefaults` on-device.

### Age rating questionnaire

Expected outcome: **9+**.

| Question | Answer |
|---|---|
| Cartoon or fantasy violence | **Infrequent / Mild** (ships explode into vector debris) |
| Realistic violence | None |
| Prolonged graphic / sadistic violence | None |
| Profanity / crude humour | None |
| Mature / suggestive themes | None |
| Horror / fear themes | None |
| Medical / treatment information | None |
| Alcohol, tobacco, drug use | None |
| Sexual content / nudity | None |
| Gambling | None |
| Contests | None |
| Unrestricted web access | None |
| Gambling and contests | None |

### Review notes (for the Apple reviewer)
```
This is a single-player / local couch co-op arcade game. There is no
network code, no IAP, no analytics, no third-party SDKs.

Multiplayer requires Bluetooth game controllers (one per player). On
iPad and Mac the reviewer can play single-player with a connected MFi
pad or any USB/Bluetooth keyboard (arrow keys + space). On Apple TV
the bundled Siri Remote works as a single-player controller.

There is no login, no account, no demo credentials needed.
```

### Demo account
```
Not applicable — no login.
```

### Contact information

Use the email associated with the developer account (`m.doering@mac.com`).

### Version-specific "What's New" text (≤4000 chars)

For v0.1 (first submission):
```
Initial release.
```

## 4. Screenshots

App Store Connect requires screenshots per platform. Capture from a Simulator (**File → Save Screen** in Simulator, or `xcrun simctl io <udid> screenshot out.png`) or a real device.

| Platform | Required dimensions |
|---|---|
| **iPad** (12.9" / 13" iPad Pro) | 2732×2048 (landscape) |
| **Mac** | 2880×1800 or 1280×800 |
| **Apple TV** | 3840×2160 or 1920×1080 |

Three to ten screenshots per platform. Suggested shots:

1. Title screen with two slots claimed (shows "PRESS A TO JOIN")
2. In-game with two ships, several asteroids, a UFO incoming
3. Mid-action with shield + twin-laser power-ups visible on a ship
4. Snake winding toward a ship
5. Game-over screen with a score readout

## 5. Build for distribution

1. In Xcode, open **Signing & Capabilities** and set your team. Enable "Automatically manage signing" for each destination.
2. **Product → Archive** with the destination set to **Any iOS Device (arm64)**, then again with **My Mac (Mac Catalyst)**, then again with **Any tvOS Device**. Each Archive emits a separate uploadable artifact.
3. In the Organizer window: **Distribute App → App Store Connect → Upload** for each archive.
4. In App Store Connect, attach the uploaded build to the matching platform listing on the same app record.

## 6. App icons

- **iOS / Mac Catalyst:** `Bashteroids/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024×1024).
- **tvOS:** `Bashteroids/Assets.xcassets/AppIcon.brandassets/` — three layered images for parallax (back, middle, front) at 1280×768 + 400×240, plus 1920×720 and 2320×720 top-shelf images. Regenerate with `./scripts/render-tv-icons.sh` if `icon.svg` changes.
- **App Store marketing icon (1024×1024):** Auto-extracted by App Store Connect from the App Icon you upload — no separate upload needed if `AppIcon.appiconset` is populated.

## 7. Review checklist

- [ ] Bundle ID `com.markus.Bashteroids` matches the App Store Connect record
- [ ] Marketing version + build number bumped (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.pbxproj`)
- [ ] App icons in place for all three platforms (`AppIcon.appiconset` + `AppIcon.brandassets`)
- [ ] Screenshots uploaded for iPad, Mac, and Apple TV
- [ ] Privacy policy URL hosted and entered
- [ ] Support URL points to a real, reachable page
- [ ] Age rating questionnaire completed
- [ ] App Privacy questionnaire = "no data collected"
- [ ] Description mentions controller requirement (Bluetooth game controller needed for multiplayer; Siri Remote works for solo on Apple TV)
- [ ] Build uploaded and selected for each platform's submission
- [ ] Review notes cover the controller-or-keyboard-or-Siri-Remote alternatives so a reviewer without an MFi pad can still play

## 8. Notes specific to this project

- **Three platforms, one binary.** iOS + Mac Catalyst + tvOS all ship from the same target; one upload per platform but the same source archive.
- No in-app purchases, no network calls, no third-party SDKs → review should be straightforward.
- Typical review time: 1–3 business days after submission.
- TestFlight: optional but recommended for catching tvOS-specific input bugs (Siri Remote behaviour can't be exercised by `xcodebuild` — see CLAUDE.md "Manual verification").
