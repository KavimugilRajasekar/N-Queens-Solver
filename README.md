# N-Queens Puzzle Studio

N-Queens Puzzle Studio is a Flutter mobile app that turns the classic N-Queens logic puzzle into an interactive, social experience. It lets you scan printed boards with your camera, design your own region puzzles, watch an AI solve them step by step, share boards via encrypted QR codes, and play live multiplayer matches with friends — all wrapped in a hand-drawn notebook aesthetic.

The puzzle variant used here is a regional extension of the classic problem: the board is divided into colored regions, and exactly one queen must be placed in each region, with no two queens sharing a row, column, or touching cell (including diagonals).

---

## What the app does

### Single-player

**Camera capture** — Point your camera at any printed N-Queens board. The app uploads the image to the Vercel server, which uses OpenCV to detect the grid, measure cell colors, and flood-fill them into regions. The result comes back as a structured board you can immediately start solving.

**Manual designer** — Paint your own region layout on a blank grid. Tap cells to assign them to regions, name the board, and save it to your personal library. Any board you design can be used in multiplayer.

**AI solver** — The app runs a recursive backtracking solver with a Minimum Remaining Values (MRV) heuristic directly on-device. Every step the algorithm takes — placing a queen, detecting a conflict, backtracking — is streamed to the screen in real time so you can watch the logic unfold.

**Board library** — All boards (scanned, designed, or generated) are saved locally as JSON. Boards you solve manually earn a gold trophy badge and become available for multiplayer use.

**QR sharing** — Export any board as an AES-CBC encrypted QR code. Anyone with the app can scan it to import the board. The encryption key is embedded in the app, so only Studio users can decode it.

### Multiplayer

Two modes, one connection system.

**Combine Solving (Co-op)** — Both players share a single board. Every cell tap one player makes is mirrored on the other player's screen in real time via Firebase Realtime Database. Queens placed by you appear in blue; queens placed by your partner appear in green. The board is solved when the combined placement satisfies all N-Queens constraints. Both players win together.

**Competing (Duel)** — Each player gets their own independent copy of the same board. You race to solve it first. Your moves stay on your screen; you only see your opponent's progress as a queen counter ("Placing Queens... 3/8"). First to solve wins the round. Play best-of-1, best-of-3, or best-of-5.

Both modes support series play. The host configures the number of matches and the board source (auto-generated or from their library). Board data is stored in Firebase RTDB — it never travels through FCM, so there is no size limit.

---

## How multiplayer works

```
Host app                    Vercel Server              Firebase RTDB          Guest app
   |                              |                          |                     |
   |-- POST /create-room -------->|                          |                     |
   |   {boards, matchCount...}    |-- PUT /rooms/{id} ------>|                     |
   |                              |-- FCM push --------------|-------------------->|
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

**Room lifecycle is server-controlled.** The Flutter app never writes to `/rooms` directly. `POST /create-room` is the only way a room is created. `DELETE /room/{id}` is the only way it is deleted. This means the server is the single source of truth for whether a game session exists.

**In-game state is RTDB-direct.** Once both players are connected, all game messages go straight to `/rooms/{id}/gameState` via `push()`. No server hop, no added latency. Each message carries a `sender` field so each device only processes messages from the other player.

**Room deletion = kick.** When a player leaves (taps END GAME, navigates away, or the app is killed), the server hard-deletes the room. The other player's `onValue` listener fires with a null snapshot, which triggers a snackbar ("opponent left") and automatic navigation back to the lobby.

### Message types

| `type` | Direction | Used in | What it does |
|---|---|---|---|
| `cell_tap` | Both → both | Co-op only | Mirrors a single cell change on the partner's board |
| `clear_board` | Both → both | Co-op only | Clears the entire shared board on the partner's screen |
| `progress` | Both → both | Compete only | Updates the opponent's queen-placement counter |
| `round_over` | Both → both | Both | Signals that the sender has solved the board for this round |

---

## Player identity

Each device generates a deterministic 6-digit ID (`NQ-XXXXXX`) from hardware info on first launch and stores it in `SharedPreferences`. This ID is registered with the Vercel server along with the FCM token, nickname, and icon. Other players invite you by entering your 6-digit number.

---

## Project structure

```
lib/
├── main.dart                        # App entry; initialises FirebaseGameManager
├── constants/
│   ├── colors.dart                  # App-wide colour palette
│   └── region_colors.dart           # Per-region colour assignment
├── screens/
│   ├── landing_page.dart            # Home screen; listens for incoming FCM invites
│   ├── compete_mode_screen.dart     # Player profile setup (nickname, icon, ID)
│   ├── match_setup_screen.dart      # Host configures match and initiates connection
│   ├── peers_play_screen.dart       # Live multiplayer board (co-op + compete)
│   ├── n_queens_board.dart          # Single-player board (solve / edit / AI)
│   ├── saved_boards_screen.dart     # Board library
│   └── camera_screen.dart           # Camera capture flow
├── utils/
│   ├── firebase_game_manager.dart   # All multiplayer logic (singleton)
│   ├── board_processor.dart         # Image upload and region text parsing
│   ├── board_generator.dart         # On-device BFS board generation
│   ├── solver_logic.dart            # Backtracking solver with step streaming
│   ├── storage_manager.dart         # JSON file persistence
│   └── qr_crypto.dart              # AES-CBC QR encryption / decryption
└── widgets/
    ├── notebook_painter.dart        # Lined-paper background
    ├── funky_loader_dialog.dart     # Animated connection waiting dialog
    ├── funky_lobby_details_dialog.dart
    └── ...
```

---

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `firebase_core` | ^4.9.0 | Firebase initialisation |
| `firebase_messaging` | ^16.2.2 | FCM push notifications (invite delivery only) |
| `firebase_database` | ^12.4.1 | Real-time game state sync |
| `http` | ^1.6.0 | REST calls to Vercel server |
| `shared_preferences` | ^2.5.2 | Player ID / nickname / icon persistence |
| `camera` | ^0.11.0+1 | Board photo capture |
| `mobile_scanner` | ^7.2.0 | QR code scanning |
| `encrypt` | ^5.0.3 | AES-CBC QR encryption |
| `device_info_plus` | ^13.1.0 | Hardware-based player ID generation |
| `lottie` | ^3.3.1 | Animations (trophy, cat loader, etc.) |
| `pretty_qr_code` | ^3.6.0 | QR code rendering |
| `share_plus` | ^13.1.0 | Share board images |
| `palette_generator` | ^0.3.3+3 | Colour extraction from camera frames |

---

## Setup

### Prerequisites

- Flutter SDK ≥ 3.11
- A Firebase project with Realtime Database and Cloud Messaging enabled
- `google-services.json` at `android/app/google-services.json`
- The N-Queens server deployed (see `../n_queens_server/README.md`)

### Run

```bash
flutter pub get
flutter run
```

---

## Race conditions and correctness guarantees

| Scenario | How it is handled |
|---|---|
| Host's RTDB listener fires multiple times before guest-join is processed | `_guestJoinHandled` boolean; the handler body runs exactly once per session |
| Guest subscribes to `onValue` after host already set `status:active` | Firebase `onValue` always delivers the current snapshot immediately on subscribe |
| `disconnect()` called re-entrantly from `dispose()` while cleanup is in progress | `_disconnecting` boolean guard; second call returns immediately |
| Both players detect co-op win simultaneously | `_roundEndedForCurrentMatch` flag reset each round; only the first caller proceeds |
| Incoming `round_over` arrives after local win detection | Same `_roundEndedForCurrentMatch` guard applied to the incoming message handler |
| `roomDeletedNotifier` fires after `dispose()` removed the listener | Listener removed before `disconnect()` is called; notifier reset to `false` for next session |
| `sendMessage` called inside `setState` (async in sync context) | Moved outside `setState`; fire-and-forget is safe since we don't need the return value |
