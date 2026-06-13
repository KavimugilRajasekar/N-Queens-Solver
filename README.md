# N-Queens Puzzle Studio

**Version 2.0.1** · Flutter · Android

N-Queens Puzzle Studio is a Flutter mobile app that turns the classic N-Queens logic puzzle into an interactive, social experience. Scan printed boards with your camera, design your own region puzzles, watch an AI solve them step-by-step, share boards via encrypted QR codes, and play live multiplayer matches with friends — all wrapped in a hand-drawn notebook aesthetic.

The puzzle variant used here is a **regional extension** of the classic problem: the board is divided into colored regions, and exactly one queen must be placed per region, with no two queens sharing a row, column, or adjacent cell (including diagonals).

---

## Features at a Glance

| Feature | Description |
|---|---|
| 📷 Camera Capture | Scan any printed N-Queens board; AI digitizes it |
| ✏️ Manual Designer | Paint custom region layouts and save to library |
| 🤖 AI Solver | On-device MRV backtracking solver with live step streaming |
| 📚 Board Library | Save, rename, delete boards; earn gold trophies for manual solves |
| 🔐 QR Sharing | AES-CBC encrypted board export/import via QR code |
| ⚡ Auto-Generate | BFS seed-growth algorithm generates solvable puzzles on demand |
| 🎮 Multiplayer | Co-op (shared board) and Compete (race) modes with Firebase |
| 🔔 Auto Updates | Checks GitHub Releases on launch; notifies once per new version |
| 👤 Player Identity | Hardware-derived 6-digit ID (`NQ-XXXXXX`) with custom nickname + icon |
| 📋 Recent Opponents | History panel with player icon, name and ID — refreshed from server |

---

## Screens

### Landing Page
Home screen. Listens for incoming FCM game invites and shows the accept/decline dialog. Runs the GitHub update check silently in the background on every launch. Shows your stats (boards solved, games played).

### Player Profile (`compete_mode_screen`)
Set your nickname and pick one of the preset player icons. Your profile (nickname, icon, FCM token) is registered to the Vercel server and stored in Firebase RTDB under `players/NQ-XXXXXX`. Your 6-digit ID is displayed here — share it with friends to let them invite you.

### Board Library (`saved_boards_screen`)
All boards saved locally as JSON. Long-press the top-right icon to toggle between rename ✏️ and delete 🗑️ mode. Select multiple boards and export a batch QR code (up to 7 boards). Boards manually solved earn a gold trophy badge and unlock the "My Library" option in multiplayer.

### Match Setup (`match_setup_screen`)
Host configures a multiplayer session:
- **Opponent ID** — enter a 6-digit `NQ-` ID manually, or tap the history icon to expand the recently-connected panel showing each opponent's saved name, icon, and ID.
- **Your Side Color** — Blue or Red (Compete) / Blue or Green (Co-op).
- **How Many Matches?** — 1 Match, Best of 3, or Best of 5. Shown above the board config.
- **Board Source** — Auto-generate (BFS, choose size 4×4–12×12) or pick from My Library (mastered boards only). Configurable per match in a series.

The history panel silently refreshes opponent nicknames and icons from the server each time it is opened, so you always see their latest profile.

### Multiplayer Board (`peers_play_screen`)
Live game screen for both co-op and compete modes. Boards, timer, activity log, and opponent status are all shown. Firebase RTDB handles real-time sync — no server hop for in-game moves.

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

---

## Player Identity & Recent Opponents

Each device generates a deterministic 6-digit ID from hardware info on first launch, stored in `SharedPreferences` as `NQ-XXXXXX`. This ID is registered on the Vercel server with the player's FCM token, nickname, and icon.

The **recent opponents** list (up to 10 entries) is stored locally. It is populated automatically on both sides of every connection — not just the host:

- **Host**: saved after `checkPeerValid` confirms the opponent exists.
- **Guest**: saved after `joinConnection` succeeds using the invite payload.

Each entry stores `id` (canonical `NQ-XXXXXX`), `nickname`, and `icon`. Opening the history panel triggers a silent server refresh — if the opponent changed their name or icon since the last session, the local entry is updated and re-persisted automatically. All IDs are normalized to bare digits for dedup so the same player can never appear twice regardless of how the ID was formatted when stored.

---

## Automatic Update Notifications

On every launch the app silently checks:

```
GET https://api.github.com/repos/KavimugilRajasekar/N-Queens-Solver/releases/latest
```

The installed version is read at runtime via `package_info_plus` — always in sync with `pubspec.yaml`. If the release `tag_name` is semantically newer, a popup appears with the new version number and a **DOWNLOAD NOW** button that opens the GitHub release page in the browser (`LaunchMode.externalApplication`). Shown once per new version, tracked via `SharedPreferences`.

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
│   ├── main.dart                          # Entry point; Firebase init
│   ├── constants/
│   │   ├── colors.dart                    # App-wide colour palette
│   │   └── region_colors.dart             # Per-region colour assignment
│   ├── screens/
│   │   ├── landing_page.dart              # Home; FCM invite listener + update check
│   │   ├── compete_mode_screen.dart       # Player profile (nickname, icon, ID)
│   │   ├── match_setup_screen.dart        # Host configures + initiates multiplayer
│   │   ├── peers_play_screen.dart         # Live multiplayer board
│   │   ├── n_queens_board.dart            # Single-player board (solve / edit / AI)
│   │   ├── saved_boards_screen.dart       # Board library
│   │   ├── camera_screen.dart             # Camera capture flow
│   │   ├── create_board_screen.dart       # Manual board designer
│   │   └── generate_board_screen.dart     # AI board generation
│   ├── utils/
│   │   ├── firebase_game_manager.dart     # Multiplayer singleton (RTDB + FCM + server)
│   │   ├── update_service.dart            # GitHub release check + update popup
│   │   ├── board_processor.dart           # Image upload + region parsing
│   │   ├── board_generator.dart           # On-device BFS board generation
│   │   ├── solver_logic.dart              # MRV backtracking solver
│   │   ├── storage_manager.dart           # Local JSON persistence
│   │   └── qr_crypto.dart                 # AES-CBC QR encryption / decryption
│   └── widgets/
│       ├── notebook_painter.dart          # Lined-paper background
│       ├── funky_loader_dialog.dart        # Animated connection waiting dialog
│       ├── funky_lobby_details_dialog.dart # Match confirmation dialog
│       └── library_board_card.dart        # Board card in library list
│
n_queens_server/
├── app/
│   ├── routers/
│   │   ├── players.py                     # /register-player, /player/{id}, /nickname
│   │   ├── signaling.py                   # /create-room, /room/{id}, /send-signal
│   │   └── image_processing.py            # /process-image
│   ├── services/
│   │   └── firebase_service.py            # Firebase RTDB helpers + FCM dispatch
│   ├── models/
│   │   └── pydantic_models.py             # Request/response schemas
│   └── utils/
│       └── helpers.py                     # ID normalisation, misc utilities
└── requirements.txt
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
| `lottie` | ^3.3.1 | Animations (trophy, loader, etc.) |
| `pretty_qr_code` | ^3.6.0 | QR code rendering |
| `share_plus` | ^13.1.0 | Share board images |
| `screenshot` | ^3.0.0 | Capture board as image for sharing |
| `palette_generator` | ^0.3.3+3 | Colour extraction from camera frames |
| `shake` | ^3.0.0 | Shake gesture to toggle rename/delete mode |
| `quick_actions` | ^1.1.0 | Home screen shortcuts |
| `permission_handler` | ^11.1.0 | Camera and notification permissions |

---

## Setup

### Prerequisites

- Flutter SDK ≥ 3.11
- Android device or emulator (API 21+)
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
| `canLaunchUrl` returns false on Android 11+ for update download | `<queries>` block in `AndroidManifest.xml` declares `https` scheme intent; `launchUrl` called directly without pre-check gate |
| Guest's recent-opponents list never updated when receiving an invite | `saveRecentOpponent` called on guest side after `joinConnection` succeeds using invite payload data |
