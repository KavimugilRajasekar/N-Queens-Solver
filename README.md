# 👑 N-Queens Puzzle Studio

A production-ready, highly aesthetic Flutter application dedicated to the legendary **N-Queens Problem**. This isn't just a solver; it's a complete ecosystem for creating, scanning, and sharing regional N-Queens puzzles with a premium "Funky Notebook" aesthetic.

![Landing Page Teaser](assets/icons/n_queen_logo.png)

## 🎨 Design Philosophy: "The Funky Notebook"
The application is built around a cohesive design system that blends academic nostalgia with modern micro-interactions:
- **Notebook-Line Backgrounds**: Custom `CustomPainter` rendering of classic school-line patterns.
- **Sticker-Style UI**: Tilted containers with sharp, bold drop shadows for buttons and cards.
- **Premium Typography**: A curated blend of `DynaPuff`, `Comfortaa`, and `PlaywriteUSModern`.
- **Micro-Animations**: Extensive use of Lottie animations and Tween-based transitions.

## 🚀 Core Features

### 1. 🪄 AI Board Generator
Generate infinite, unique, and guaranteed-solvable puzzles. 
- **Custom Sizes**: Support for board dimensions from **4x4 up to 12x12**.
- **Randomized Regions**: Utilizes a custom flood-fill algorithm to create distinct, non-contiguous color regions around pre-calculated solution seeds.
- **Uniqueness Check**: Automatically verifies that every generated board is unique in your library.

### 2. 📸 Digital Capture & Scanning
- **Real-Time Scanning**: Integrated `mobile_scanner` for rapid QR detection.
- **Camera Digitization**: Capture physical boards (from books or magazines) and let the AI digitize them into playable puzzles.
- **Two-Step Import**: Scan a QR to preview multiple boards in a selection drawer before deciding which to import.

### 3. 🔒 Secure "Funky" Sharing
The world's first **AES-256 Encrypted** N-Queens sharing ecosystem.
- **High Security**: Board data is encrypted using a hardcoded 256-bit hex key before being encoded into QR codes.
- **Numbered Selection**: Multi-select up to **7 boards** at a time with ordered selection badges.
- **Privacy-First**: Shared boards are unreadable to standard QR scanners, requiring the Puzzle Studio for decryption.

### 4. 🧠 Pro-Grade AI Solver
- **Backtracking Algorithm**: A highly optimized recursive solver capable of finding solutions for large boards in milliseconds.
- **Visual Reasoning**: A real-time **Algorithm Log** allows users to watch the AI navigate the search tree.
- **Hints & Auto-Solve**: Get partial help or watch a full masterclass on any puzzle.

## 📜 The "Funky" Rules
This app focuses on a specific, popular variant of the N-Queens problem:
1. **Row & Column**: Exactly one queen per row and one per column.
2. **Regions**: The board is divided into distinct color regions. Each region must contain exactly one queen.
3. **8-Neighbors**: No two queens can touch, even diagonally (no queens in adjacent 3x3 cells).

## 🛠️ Technology Stack
- **Framework**: Flutter (Dart)
- **State Management**: StatefulWidgets with localized state synchronization.
- **Persistence**: Local JSON-based storage using `path_provider`.
- **Cryptography**: `encrypt` package (AES-256 CBC).
- **QR Engine**: `pretty_qr_code` & `mobile_scanner`.
- **Visuals**: `lottie`, `screenshot`, `palette_generator`.

## 📦 Getting Started

### Prerequisites
- Flutter SDK (latest stable)
- Android Studio / VS Code
- A physical device (for camera/scanning features)

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/KavimugilRajasekar/n_queens_solver.git
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

---
*Created with ❤️ for the love of logic and aesthetics.*
