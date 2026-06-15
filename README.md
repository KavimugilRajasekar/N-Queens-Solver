# N-Queens Puzzle Studio

**Version 2.1.0** · Flutter · Android

N-Queens Puzzle Studio is a Flutter mobile app that turns the classic N-Queens logic puzzle into an interactive, social experience. Scan printed boards with your camera, design your own region puzzles, watch an AI solve them step-by-step, share boards via encrypted QR codes, play live multiplayer matches with friends, and solve any on-screen board instantly from your Quick Settings tile — all wrapped in a hand-drawn notebook aesthetic.

The puzzle variant used here is a **regional extension** of the classic problem: the board is divided into colored regions, and exactly one queen must be placed per region, with no two queens sharing a row, column, or adjacent cell (including diagonals).

---

## Features at a Glance

| Feature | Description |
|---|---|
| 📷 Camera Capture | Scan any printed N-Queens board; AI digitizes it instantly |
| ✏️ Manual Designer | Paint custom region layouts cell-by-cell and save to library |
| 🤖 AI Solver | On-device MRV backtracking solver with live step streaming |
| 📚 Board Library | Save, rename, delete boards; earn gold trophies for manual solves |
| 🔐 QR Sharing | AES-CBC encrypted board export/import via QR code |
| ⚡ Auto-Generate | BFS seed-growth algorithm generates solvable puzzles on demand |
| 🎮 Multiplayer | Co-op (shared board) and Compete (race) modes via Firebase RTDB |
| 🔔 Auto Updates | Checks GitHub Releases on launch; notifies once per new version |
| 👤 Player Identity | Hardware-derived 6-digit ID (`NQ-XXXXXX`) with custom nickname + icon |
| 📋 Recent Opponents | History panel with player icon, name and ID — refreshed from server |
| 📱 Quick Access Tile | QS tile captures screen, solves board, shows floating overlay — no dialog |

---

## Screens

### Landing Page
Home screen. Listens for incoming FCM game invites and shows the accept/decline dialog. Runs the GitHub update check silently in the background on every launch. Shows your mastery stats (boards manually solved). Three main action buttons: **Enter Studio**, **Compete Mode**, and **Quick Access**.

### Player Profile (`compete_mode_screen`)
Set your nickname and pick one of ten preset player icons (crown, unicorn, dinosaur, alien, etc.). Your profile (nickname, icon, FCM token) is registered to the Vercel server and stored in Firebase RTDB under `players/NQ-XXXXXX`. Your 6-digit ID is displayed here — share it with friends to let them invite you.

### Board Library (`saved_boards_screen`)
All boards saved locally as JSON. Long-press the top-right icon to toggle between rename ✏️ and delete 🗑️ mode. Select multiple boards and export a batch QR code (up to 7 boards). Boards manually solved earn a gold trophy badge and unlock the "My Library" option in multiplayer.

### Match Setup (`match_setup_screen`)
Host configures a multiplayer session:
- **Opponent ID** — enter a 6-digit `NQ-` ID manually, or tap the history icon to expand the recently-connected panel showing each opponent's saved name, icon, and ID.
- **Your Side Color** — Blue or Red (Compete) / Blue or Green (Co-op).
- **How Many Matches?** — 1 Match, Best of 3, or Best of 5.
- **Board Source** — Auto-generate (BFS, choose size 4×4–12×12) or pick from My Library (mastered boards only). Configurable per match in a series.

The history panel silently refreshes opponent nicknames and icons from the server each time it is opened, so you always see their latest profile.

### Multiplayer Board (`peers_play_screen`)
Live game screen for both co-op and compete modes. Boards, timer, activity log, real-time chat, and opponent status are all shown. Firebase RTDB handles real-time sync — no server hop for in-game moves.

### Quick Access Setup (`screenshot_solver_setup_screen`)
One-time onboarding for the QS tile feature. Guides the user through granting two permissions:
1. **Screen Capture (MediaProjection)** — required once; the live session is kept alive so the consent dialog never appears again on subsequent tile taps.
2. **Display Over Other Apps (SYSTEM_ALERT_WINDOW)** — required to show the floating solved-board overlay above any application.

---

## Quick Access Tile

The "NQ Solver" tile lives in the Android Quick Settings panel (pull down notification shade → add tile). Tap it at any time while any app is open to instantly capture, process, and solve whatever N-Queens board is on screen.

### How it works

```
User taps tile
  └─ ScreenshotSolverTileService.onClick()
       └─ All permissions OK?
            ├─ No → startActivityAndCollapse(MainActivity) → show permission screen
            └─ Yes → startActivityAndCollapse(CaptureTrampoline)
                          Panel collapses, onResume() fires
                          └─ 500 ms delay (panel dismiss animation)
                               └─ startForegroundService(ACTION_CAPTURE → ProjectionSessionService)
                                    ├─ Reuse live MediaProjection (no consent dialog)
                                    ├─ VirtualDisplay → ImageReader → Bitmap
                                    ├─ Show ⏳ loading overlay
                                    ├─ POST JPEG → nqueensserver.vercel.app/process-image
                                    ├─ Parse region grid from response
                                    ├─ Native backtracking solver → solution map
                                    ├─ OverlayWindow.show() → draggable floating board
                                    └─ Broadcast to Flutter (saves to library if app alive)
```

### Why no consent dialog on repeated taps

Android's `MediaProjection` token is single-use. Every call to `getMediaProjection()` with a replayed token triggers the OS consent dialog ("Start recording or casting..."). The fix is `ProjectionSessionService`:

- `getMediaProjection()` is called **exactly once** — immediately in `onActivityResult` while the token is still fresh.
- The resulting live `MediaProjection` object is held inside the persistent foreground service.
- Every tile tap sends `ACTION_CAPTURE` to the running service, which reuses the live projection to create a fresh `VirtualDisplay` — no new `getMediaProjection()` call, no dialog.
- If the service is killed (phone restart), it detects `mediaProjection == null` on the next tap, clears the permission flag, and prompts the user to re-grant from the app.

### Why the panel disappears before the screenshot

`startActivityAndCollapse()` unconditionally collapses the Quick Settings panel before launching the activity. `CaptureTrampoline` — a fully transparent, zero-UI activity — then waits 500 ms for the dismiss animation to finish before sending the capture command. This guarantees the panel is never visible in the captured screenshot.

**Android 14+ fix:** `startActivityAndCollapse(Intent)` was removed in API 34. The tile service uses `startActivityAndCollapse(PendingIntent)` on API 34+ and falls back to the `Intent` overload on older versions, preventing the crash and panel-not-closing bug.

### Overlay

The solved board appears as a compact, draggable `TYPE_APPLICATION_OVERLAY` window:
- Automatically sized to 88% of screen width, square aspect ratio.
- Color-coded region cells matching the app's palette.
- Gold ★ queen markers on solution cells.
- Drag anywhere on screen; close button in top-right corner.
- Tapping the tile again while the overlay is visible dismisses it and takes a fresh screenshot.

### Overlay Permission on Physical Devices

Some OEM Android skins (Samsung One UI, MIUI, ColorOS) ignore the `package:` URI in `Settings.ACTION_MANAGE_OVERLAY_PERMISSION` and show an empty screen. The app uses a three-step fallback:
1. Direct app-specific overlay settings page (stock Android).
2. Generic "Display over other apps" list (always works on OEMs).
3. Full Application Info settings page (last resort).

---

## Multiplayer

Two modes, one connection system. The **Host** picks a colour at match setup. The **Peer (Joiner)** is automatically assigned the complementary colour.

| Mode | Host picks | Peer gets |
|---|---|---|
| Combine Solving (Co-op) | Blue | Green |
| Combine Solving (Co-op) | Green | Blue |
| Compete (Duel) | Blue | Red |
| Compete (Duel) | Red | Blue |

### Combine Solving (Co-op)
Both players share a single board. Every cell tap is mirrored on the partner's screen in real time. Pieces are colour-coded per player. The board is solved when the combined placement satisfies all N-Queens constraints — both players win together.

### Compete (Duel)
Each player gets their own independent copy of the same board. You race to solve it first. You only see your opponent's progress as a queen counter. First to solve wins the round. Play best-of-1, best-of-3, or best-of-5.

### Connection Flow

```
Host app                    Vercel Server              Firebase RTDB          Guest app
   |                              |                          |                     |
   |-- POST /create-room -------->|                          |                     |
   |   {boards, matchCount,       |-- PUT /rooms/{id} ------>|                     |
   |    hostColor, ...}           |-- FCM push --------------|-------------------->|
   |<-- {roomId} ----------------|                          |                     |
   |                              |                          |                     |
   |-- RTDB onValue(rooms/{id}) --|------------------------->|                     |
   |   (waiting for guestJoined)  |                          |                     |
   |                              |                          |<-- RTDB get(room) --|
   |                              |                          |<-- PATCH guestJoined|
   |<-- onValue fires ------------|--------------------------|                     |
   |   (guestJoined: true)        |                          |                     |
   |-- RTDB PATCH hostReady:true -|------------------------->|                     |
   |                              |                          |-- onValue fires ---->|
   |                              |                          |   (hostReady: true)  |
   |                              |                          |                     |
   |<======= In-game: RTDB /rooms/{id}/gameState (direct, no server) =============>|
   |                              |                          |                     |
   |  (either player leaves)      |                          |                     |
   |-- DELETE /room/{id} -------->|                          |                     |
   |                              |-- DELETE /rooms/{id} --->|                     |
   |                              |                          |-- onValue(null) ---->|
   |                              |                          |   navigate to lobby  |
```

**Room lifecycle is server-controlled.** The Flutter app never writes to `/rooms` directly. `POST /create-room` creates a room. `DELETE /room/{id}` deletes it. The server is the single source of truth.

**In-game state is RTDB-direct.** Once connected, all game messages go straight to `/rooms/{id}/gameState` via `push()`. Each message carries a `sender` field so each device only processes messages from the other player.

**Room deletion = kick.** When either player leaves, the server hard-deletes the room. The other player's `onValue` listener fires with a null snapshot, triggering a snackbar and navigation back to the lobby.

### In-Game Message Types

| `type` | Used in | What it does |
|---|---|---|
| `cell_tap` | Co-op | Mirrors a single cell change on the partner's board |
| `clear_board` | Co-op | Clears the entire shared board on the partner's screen |
| `progress` | Compete | Updates the opponent's queen-placement counter |
| `round_over` | Both | Signals the sender has solved the board for this round |
| `chat` | Both | Sends a chat message to the opponent |
| `quit_game` | Both | Signals the sender has ended the game session |

---

## Player Identity & Recent Opponents

Each device generates a deterministic 6-digit ID from hardware info on first launch, stored in `SharedPreferences` as `NQ-XXXXXX`. This ID is registered on the Vercel server with the player's FCM token, nickname, and icon.

The **recent opponents** list (up to 10 entries) is stored locally. It is populated automatically on both sides of every connection:

- **Host**: saved after `checkPeerValid` confirms the opponent exists.
- **Guest**: saved after `joinConnection` succeeds using the invite payload.

Each entry stores `id` (canonical `NQ-XXXXXX`), `nickname`, and `icon`. Opening the history panel triggers a silent server refresh — if the opponent changed their name or icon since the last session, the local entry is updated automatically. All IDs are normalized to bare digits for dedup so the same player can never appear twice regardless of how the ID was formatted.

---

## Automatic Update Notifications

On every launch the app silently checks:

```
GET https://api.github.com/repos/KavimugilRajasekar/N-Queens-Solver/releases/latest
```

The installed version is read at runtime via `package_info_plus` — always in sync with `pubspec.yaml`. If the release `tag_name` is semantically newer, a popup appears with the new version number and a **DOWNLOAD NOW** button that opens the GitHub release page in the browser. Shown once per new version, tracked via `SharedPreferences`.

---

## Server API (`n_queens_server`)

Deployed on Vercel. All endpoints are prefixed at `https://nqueensserver.vercel.app`.

| Method | Path | Description |
|---|---|---|
| `POST` | `/register-player` | Register or update a player profile (FCM token, nickname, icon) |
| `GET` | `/player/{playerId}` | Fetch a player's current profile |
| `PATCH` | `/player/{playerId}/nickname` | Update only the nickname field |
| `POST` | `/create-room` | Create a room in Firebase RTDB and send FCM invite to guest |
| `DELETE` | `/room/{roomId}` | Delete a room from Firebase RTDB (kicks the other player) |
| `POST` | `/process-image` | Upload a board photo; returns parsed region grid |

---

## Project Structure

```
n-queens-solver/
├── lib/
│   ├── main.dart                               # Entry point; Firebase init; screenshot service init
│   ├── constants/
│   │   ├── colors.dart                         # App-wide colour palette
│   │   └── region_colors.dart                  # Per-region colour assignment
│   ├── screens/
│   │   ├── landing_page.dart                   # Home; FCM invite listener; update check
│   │   ├── compete_mode_screen.dart            # Player profile (nickname, icon, ID)
│   │   ├── match_setup_screen.dart             # Host configures + initiates multiplayer
│   │   ├── peers_play_screen.dart              # Live multiplayer board
│   │   ├── n_queens_board.dart                 # Single-player board (solve / edit / AI)
│   │   ├── saved_boards_screen.dart            # Board library
│   │   ├── camera_screen.dart                  # Camera capture flow
│   │   ├── create_board_screen.dart            # Manual board designer
│   │   ├── generate_board_screen.dart          # AI board generation
│   │   └── screenshot_solver_setup_screen.dart # QS tile onboarding (permissions)
│   ├── utils/
│   │   ├── firebase_game_manager.dart          # Multiplayer singleton (RTDB + FCM + server)
│   │   ├── update_service.dart                 # GitHub release check + update popup
│   │   ├── board_processor.dart                # Image upload + region parsing
│   │   ├── board_generator.dart                # On-device BFS board generation
│   │   ├── solver_logic.dart                   # MRV backtracking solver
│   │   ├── storage_manager.dart                # Local JSON persistence
│   │   ├── screenshot_solver_service.dart      # Flutter bridge for QS tile results
│   │   ├── shortcut_manager.dart               # Home screen long-press shortcuts
│   │   └── qr_crypto.dart                      # AES-CBC QR encryption / decryption
│   └── widgets/
│       ├── notebook_painter.dart               # Lined-paper background
│       ├── funky_loader_dialog.dart            # Animated connection waiting dialog
│       ├── funky_lobby_details_dialog.dart     # Match confirmation dialog
│       ├── error_dialog.dart                   # Styled error dialog
│       └── success_dialog.dart                 # Styled success dialog
│
├── android/app/src/main/kotlin/.../
│   ├── MainActivity.kt                         # Flutter ↔ native bridge (MethodChannel + EventChannel)
│   ├── ScreenshotSolverTileService.kt          # Quick Settings tile (API 34+ PendingIntent fix)
│   ├── CaptureTrampoline.kt                    # Transparent activity; collapses panel; sends capture command
│   ├── ProjectionSessionService.kt             # Persistent MediaProjection session; no re-consent
│   ├── ScreenshotOverlayService.kt             # Legacy capture service (retained for compatibility)
│   └── OverlayWindow.kt                        # Draggable TYPE_APPLICATION_OVERLAY board view
│
n_queens_server/
├── app/
│   ├── routers/
│   │   ├── players.py                          # /register-player, /player/{id}, /nickname
│   │   ├── signaling.py                        # /create-room, /room/{id}
│   │   └── image_processing.py                 # /process-image
│   ├── services/
│   │   └── firebase_service.py                 # Firebase RTDB helpers + FCM dispatch
│   ├── models/
│   │   └── pydantic_models.py                  # Request/response schemas
│   └── utils/
│       └── helpers.py                          # ID normalisation, misc utilities
└── requirements.txt
```

---

## Android Native Components

| File | Role |
|---|---|
| `MainActivity.kt` | MethodChannel + EventChannel bridge to Flutter; MediaProjection dialog; overlay permission fallback chain |
| `ScreenshotSolverTileService.kt` | QS tile; permission checks; `collapseAndLaunch()` helper with API 34+ `PendingIntent` fix |
| `CaptureTrampoline.kt` | Zero-UI transparent activity; 500 ms panel-dismiss buffer; sends `ACTION_CAPTURE` |
| `ProjectionSessionService.kt` | Persistent foreground service; holds live `MediaProjection`; native backtracking solver; shows `OverlayWindow` |
| `ScreenshotOverlayService.kt` | One-shot capture service (Flutter event pipeline fallback) |
| `OverlayWindow.kt` | Singleton `SYSTEM_ALERT_WINDOW` overlay; `BoardGridView` custom draw; drag-to-move |

### Required Android Permissions

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

---

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `firebase_core` | ^4.9.0 | Firebase initialisation |
| `firebase_messaging` | ^16.2.2 | FCM push notifications (invite delivery) |
| `firebase_database` | ^12.4.1 | Real-time in-game state sync |
| `http` | ^1.6.0 | Vercel server calls + GitHub Releases API |
| `shared_preferences` | ^2.5.2 | Player ID, profile, recent opponents, update state |
| `camera` | ^0.11.0+1 | Board photo capture |
| `mobile_scanner` | ^7.2.0 | QR code scanning |
| `encrypt` | ^5.0.3 | AES-CBC QR encryption |
| `device_info_plus` | ^13.1.0 | Hardware-based player ID generation |
| `package_info_plus` | ^10.1.0 | Read installed app version for update check |
| `url_launcher` | ^6.3.0 | Open GitHub release page in browser |
| `lottie` | ^3.3.1 | Animations (trophy, loader, winner badge, etc.) |
| `pretty_qr_code` | ^3.6.0 | QR code rendering |
| `share_plus` | ^13.1.0 | Share board images |
| `screenshot` | ^3.0.0 | Capture board as image for sharing |
| `palette_generator` | ^0.3.3+3 | Colour extraction from camera frames |
| `shake` | ^3.0.0 | Shake gesture to toggle rename/delete mode |
| `quick_actions` | ^1.1.0 | Home screen long-press shortcuts |
| `permission_handler` | ^11.1.0 | Camera and notification permissions |

**Native (Android):**

| Library | Purpose |
|---|---|
| `okhttp3:okhttp:4.12.0` | HTTP upload from `ProjectionSessionService` |
| `kotlinx-coroutines-android:1.7.3` | Async work in native services |

---

## Setup

### Prerequisites

- Flutter SDK ≥ 3.11
- Android device or emulator (API 24+; Quick Access Tile requires API 26+)
- A Firebase project with Realtime Database and Cloud Messaging enabled
- `google-services.json` placed at `android/app/google-services.json`
- The N-Queens server deployed to Vercel (see `../n_queens_server/`)

### Run

```bash
flutter pub get
flutter run
```

### Build release APK

```bash
flutter build apk --release
```

### Setting up the Quick Access Tile (on device)

1. Open the app → tap **QUICK ACCESS** on the home screen.
2. Grant **Screen Capture** — shown once; the live session persists.
3. Grant **Display Over Other Apps** — allows the floating overlay.
4. Pull down the notification shade, long-press any tile, and add **NQ Solver** to your Quick Settings panel.
5. Open any app showing an N-Queens board and tap the tile — the solved board appears as a floating overlay within a few seconds.

---

## Race Conditions & Correctness Guarantees

| Scenario | How it is handled |
|---|---|
| Host's RTDB listener fires multiple times before guest-join is processed | `_guestJoinHandled` boolean; handler body runs exactly once per session |
| Guest subscribes to `onValue` after host already set `status:active` | Firebase `onValue` always delivers current snapshot immediately on subscribe |
| `disconnect()` called re-entrantly from `dispose()` during cleanup | `_disconnecting` boolean guard; second call returns immediately |
| Both players detect co-op win simultaneously | `_roundEndedForCurrentMatch` flag reset each round; only first caller proceeds |
| Incoming `round_over` arrives after local win detection | Same `_roundEndedForCurrentMatch` guard on the message handler |
| `roomDeletedNotifier` fires after `dispose()` removed the listener | Listener removed before `disconnect()`; notifier reset to `false` for next session |
| Same opponent stored twice in recent history with different ID formats | All IDs normalized to bare digits at save and load time; `removeWhere` uses bare-digit comparison |
| `canLaunchUrl` returns false on Android 11+ for update download | `<queries>` block in `AndroidManifest.xml` declares `https` scheme intent; `launchUrl` called directly |
| Guest's recent-opponents list never updated when receiving an invite | `saveRecentOpponent` called on guest side after `joinConnection` succeeds using invite payload data |
| QS tile crashes on Android 14+ | `collapseAndLaunch()` uses `startActivityAndCollapse(PendingIntent)` on API 34+ instead of removed `Intent` overload |
| Consent dialog appears on every tile tap | `ProjectionSessionService` holds live `MediaProjection`; `getMediaProjection()` called only once per grant |
| MediaProjection session dies after phone restart | `ProjectionSessionService` detects null projection on `ACTION_CAPTURE`, clears prefs, prompts re-auth |
| Overlay permission screen blank on Samsung/MIUI/ColorOS | Three-step fallback: app-specific page → generic list → full app settings |
| Overlay not showing when Flutter app is backgrounded | `ProjectionSessionService` calls `OverlayWindow.show()` directly in native Kotlin; no Flutter engine dependency |
| Panel visible in screenshot on slow OEM skins | `CaptureTrampoline` waits 500 ms after `onResume()` before sending capture command |
