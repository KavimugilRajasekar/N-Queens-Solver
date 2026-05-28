import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import '../utils/board_processor.dart';
import '../constants/region_colors.dart';
import '../utils/firebase_game_manager.dart';

class PeersPlayScreen extends StatefulWidget {
  final bool isCompeteMode;
  final String opponentId;
  final String playerColor;
  final int matchCount;
  final List<BoardData> matchBoards;

  const PeersPlayScreen({
    super.key,
    required this.isCompeteMode,
    required this.opponentId,
    required this.playerColor,
    required this.matchCount,
    required this.matchBoards,
  });

  @override
  State<PeersPlayScreen> createState() => _PeersPlayScreenState();
}

class _PeersPlayScreenState extends State<PeersPlayScreen> {
  // Current Match details
  int _currentMatchIndex = 0;
  int _playerScore = 0;
  int _opponentScore = 0;
  bool _isSeriesOver = false;

  // Active board data
  late BoardData _currentBoard;
  
  // Grid cell status: "r,c" -> {'value': 0/1/2 (empty/X/Queen), 'player': 'blue'/'red'/'pink'}
  final Map<String, Map<String, dynamic>> _gameGrid = {};

  // Timers & Stats
  int _secondsElapsed = 0;
  Timer? _gameTimer;
  bool _isPaused = false;
  String _latestActivityLog = "Match initiated! Link established.";

  // Mock Multiplayer Simulator triggers
  Timer? _mockOpponentActionTimer;
  int _mockOpponentQueensPlaced = 0;
  String _opponentStatus = "Analyzing regions... 🤔";

  // Selected Player & Opponent Avatars / Names
  String _playerIconPath = 'assets/player_icons/crown.png'; // default
  String _opponentIconPath = 'assets/player_icons/unicorn.png'; // default
  String _playerNickname = "YOU"; // default player name
  String _opponentNickname = "PARTNER"; // default partner name

  // Guard: prevents _handleRoundEnded from being called twice for the same
  // round (e.g. local win detection + incoming round_over message arriving
  // at the same time in co-op mode).
  bool _roundEndedForCurrentMatch = false;

  StreamSubscription? _gameSubscription;

  @override
  void initState() {
    super.initState();
    _loadPlayerIcons();

    // Subscribe to Firebase RTDB game state events
    _gameSubscription = FirebaseGameManager.instance.dataMessageStream.listen((data) {
      _handleWebRTCMessage(data);
    });

    // Watch for room deletion — fires when the other player calls disconnect()
    // which asks the server to hard-delete the room from RTDB.
    FirebaseGameManager.instance.roomDeletedNotifier.addListener(_handleRoomDeleted);

    _startNewMatchRound(_currentMatchIndex);
  }

  void _handleRoomDeleted() {
    if (!FirebaseGameManager.instance.roomDeletedNotifier.value) return;
    if (!mounted) return;

    // Reset the notifier so it doesn't re-fire on the next session
    FirebaseGameManager.instance.roomDeletedNotifier.value = false;

    // Cancel timers so nothing fires after we leave
    _gameTimer?.cancel();
    _mockOpponentActionTimer?.cancel();

    // Show a one-time snackbar then pop back to the lobby
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
        content: Text(
          '$_opponentNickname left the game. Returning to lobby...',
          style: const TextStyle(
            fontFamily: 'Comfortaa',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );

    // Small delay so the snackbar is visible before the screen pops
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _loadPlayerIcons() async {
    final prefs = await SharedPreferences.getInstance();
    final storedIcon = prefs.getString('player_icon');
    if (storedIcon != null && storedIcon.isNotEmpty) {
      setState(() {
        _playerIconPath = storedIcon;
      });
    }
    final storedName = prefs.getString('player_nickname');
    if (storedName != null && storedName.isNotEmpty) {
      setState(() {
        _playerNickname = storedName;
      });
    }
    
    // Load Opponent nickname and icon from FirebaseGameManager
    setState(() {
      _opponentNickname = FirebaseGameManager.instance.activePeerNickname ?? "RIVAL";
      _opponentIconPath = FirebaseGameManager.instance.activePeerIcon ?? 'assets/player_icons/unicorn.png';
    });
  }

  @override
  void dispose() {
    FirebaseGameManager.instance.roomDeletedNotifier.removeListener(_handleRoomDeleted);
    _gameTimer?.cancel();
    _mockOpponentActionTimer?.cancel();
    _gameSubscription?.cancel();
    FirebaseGameManager.instance.disconnect(); // asks server to delete room
    super.dispose();
  }

  // Set up board and WebRTC state for the current round index
  void _startNewMatchRound(int matchIdx) {
    if (matchIdx >= widget.matchBoards.length) {
      setState(() => _isSeriesOver = true);
      return;
    }

    _currentBoard = widget.matchBoards[matchIdx];
    _gameGrid.clear();
    _secondsElapsed = 0;
    _latestActivityLog = "Round ${matchIdx + 1} started! Solve the board.";
    _mockOpponentQueensPlaced = 0;
    _roundEndedForCurrentMatch = false; // reset guard for new round
    _opponentStatus = widget.isCompeteMode ? "Solving... 🧠" : "Active & Synchronized! 🔗";

    // 1. Start game timer
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && !_isSeriesOver && mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  // Handle real-time Firebase game state messages from peer
  void _handleWebRTCMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final String? type = data['type'];
    if (type == null) return;

    switch (type) {

      // ── CO-OP ONLY: partner placed / removed a marker on the shared board ──
      case 'cell_tap':
        if (!widget.isCompeteMode) {
          final int r   = data['row']    as int;
          final int c   = data['col']    as int;
          final int val = data['val']    as int;
          final String owner = data['player'] as String;
          final String key   = '$r,$c';

          setState(() {
            if (val == 0) {
              _gameGrid.remove(key);
            } else {
              _gameGrid[key] = {'value': val, 'player': owner};
            }
            _latestActivityLog = val == 2
                ? 'Partner $_opponentNickname placed a Queen at [${r + 1}, ${c + 1}]!'
                : val == 1
                    ? 'Partner $_opponentNickname marked [${r + 1}, ${c + 1}] with X.'
                    : 'Partner $_opponentNickname cleared [${r + 1}, ${c + 1}].';
            _opponentStatus = 'Active — last move at [${r + 1}, ${c + 1}] 🔗';
          });
          // Check if the combined board is now solved
          _checkCoopWinCondition();
        }
        break;

      // ── CO-OP ONLY: partner cleared the entire shared board ──
      case 'clear_board':
        if (!widget.isCompeteMode) {
          setState(() {
            _gameGrid.clear();
            _latestActivityLog = 'Partner $_opponentNickname cleared the board!';
            _opponentStatus    = 'Board cleared by partner 🧹';
          });
        }
        break;

      // ── COMPETE ONLY: opponent's queen-placement progress update ──
      case 'progress':
        if (widget.isCompeteMode) {
          final int count = data['queensPlaced'] as int;
          setState(() {
            _mockOpponentQueensPlaced = count;
            _opponentStatus = count < _currentBoard.size
                ? 'Placing Queens... 👑 ($count/${_currentBoard.size})'
                : 'Solved! 🎉';
            _latestActivityLog = count < _currentBoard.size
                ? 'Rival $_opponentNickname placed a Queen! ($count/${_currentBoard.size})'
                : 'Rival $_opponentNickname solved the board!';
          });
        }
        break;

      // ── BOTH MODES: round finished ──
      case 'round_over':
        if (_roundEndedForCurrentMatch) break; // guard: already handled locally

        if (widget.isCompeteMode) {
          // Opponent sent 'me' meaning they won — we lost this round
          if (data['winner'] == 'me') {
            _roundEndedForCurrentMatch = true;
            _gameTimer?.cancel();
            _handleRoundEnded(winner: 'opponent');
          }
        } else {
          // Co-op: partner's board also reached the solved state
          // (can arrive slightly after our own local detection — guard handles it)
          _roundEndedForCurrentMatch = true;
          _gameTimer?.cancel();
          _handleRoundEnded(winner: 'coop');
        }
        break;
    }
  }

  void _startMockOpponentSimulation() {
    _mockOpponentActionTimer?.cancel();
    
    // In Co-op Mode: opponent will place cooperative markers on the SAME board every 8-12 seconds
    // In Compete Mode: opponent is speed-running their OWN identical copy of the board
    _mockOpponentActionTimer = Timer.periodic(Duration(seconds: widget.isCompeteMode ? 5 : 9), (timer) {
      if (_isPaused || _isSeriesOver || !mounted) return;

      final random = Random();

      if (widget.isCompeteMode) {
        // --- COMPETE MODE SIMULATION ---
        setState(() {
          _mockOpponentQueensPlaced++;
          if (_mockOpponentQueensPlaced < _currentBoard.size) {
            _opponentStatus = "Placing Queens... 👑 ($_mockOpponentQueensPlaced/${_currentBoard.size})";
            _latestActivityLog = "Opponent $_opponentNickname placed a Queen!";
          } else {
            // Opponent solved the board! Complete the round and award opponent the point!
            _opponentStatus = "Solved! 🎉";
            _latestActivityLog = "Opponent $_opponentNickname solved Match ${_currentMatchIndex + 1} first!";
            _mockOpponentActionTimer?.cancel();
            _gameTimer?.cancel();
            _handleRoundEnded(winner: 'opponent');
          }
        });
      } else {
        // --- CO-OP MODE SIMULATION ---
        // Opponent places an X or Queen on the shared board
        int attempts = 0;
        while (attempts < 15) {
          int r = random.nextInt(_currentBoard.size);
          int c = random.nextInt(_currentBoard.size);
          String key = "$r,$c";

          // If spot is empty, place something cooperative
          if (!_gameGrid.containsKey(key) || _gameGrid[key]?['value'] == 0) {
            setState(() {
              // 60% chance for dot marker, 40% chance for a Queen
              final isQueen = random.nextDouble() > 0.6;
              _gameGrid[key] = {
                'value': isQueen ? 2 : 1,
                'player': 'green', // Collaborative partner is Green in color!
              };
              _latestActivityLog = isQueen 
                ? "Partner $_opponentNickname placed a Queen at cell [${r + 1}, ${c + 1}]!"
                : "Partner $_opponentNickname marked [${r + 1}, ${c + 1}] with X.";
            });
            _checkCoopWinCondition();
            break;
          }
          attempts++;
        }
      }
    });
  }

  // --- PLAY INTERACTIONS ---
  void _handleCellTap(int r, int c) {
    if (_isPaused || _isSeriesOver) return;

    final String cellKey    = '$r,$c';
    final String playerColor = widget.playerColor.toLowerCase();

    // Compute new value before setState so we can use it outside
    final currentValue = _gameGrid[cellKey]?['value'] ?? 0;
    final int newValue = currentValue == 0 ? 1 : currentValue == 1 ? 2 : 0;

    setState(() {
      if (newValue == 0) {
        _gameGrid.remove(cellKey);
      } else {
        _gameGrid[cellKey] = {'value': newValue, 'player': playerColor};
      }

      _latestActivityLog = newValue == 2
          ? 'You placed a Queen at [${r + 1}, ${c + 1}]!'
          : newValue == 1
              ? 'You marked [${r + 1}, ${c + 1}] with X.'
              : 'You cleared [${r + 1}, ${c + 1}].';
    });

    // ── Sync to peer via Firebase RTDB ──────────────────────────────────
    if (!widget.isCompeteMode) {
      // Co-op: send the exact cell change so the partner's board mirrors it
      FirebaseGameManager.instance.sendMessage({
        'type':   'cell_tap',
        'row':    r,
        'col':    c,
        'val':    newValue,
        'player': playerColor,
      });
    } else {
      // Compete: only broadcast how many queens this player has placed
      final queensCount = _gameGrid.values
          .where((cell) => cell['value'] == 2 && cell['player'] == playerColor)
          .length;
      FirebaseGameManager.instance.sendMessage({
        'type':         'progress',
        'queensPlaced': queensCount,
      });
    }

    // ── Win detection ────────────────────────────────────────────────────
    if (widget.isCompeteMode) {
      _checkCompeteWinCondition();
    } else {
      _checkCoopWinCondition();
    }
  }

  // Checks win condition for Independent Compete Mode
  void _checkCompeteWinCondition() {
    if (_roundEndedForCurrentMatch) return;
    if (_hasSolvedBoardCorrectly()) {
      _roundEndedForCurrentMatch = true;
      _gameTimer?.cancel();
      FirebaseGameManager.instance.sendMessage({
        "type": "round_over",
        "winner": "me",
      });
      _handleRoundEnded(winner: 'player');
    }
  }

  // Checks win condition for Collaborative Shared Co-op Mode
  void _checkCoopWinCondition() {
    if (_roundEndedForCurrentMatch) return;
    if (_hasSolvedBoardCorrectly()) {
      _roundEndedForCurrentMatch = true;
      _gameTimer?.cancel();
      FirebaseGameManager.instance.sendMessage({
        "type": "round_over",
        "winner": "coop",
      });
      _handleRoundEnded(winner: 'coop');
    }
  }

  // Validation logic: standard N-Queens region constraint solver check
  bool _hasSolvedBoardCorrectly() {
    // Extract queen positions placed on the active grid
    final List<Point> queens = [];
    _gameGrid.forEach((key, data) {
      if (data['value'] == 2) {
        final parts = key.split(',');
        queens.add(Point(int.parse(parts[0]) + 1, int.parse(parts[1]) + 1));
      }
    });

    if (queens.length != _currentBoard.size) return false;

    // Check row, col, region, and neighborhood conflicts
    final Set<int> rows = {};
    final Set<int> cols = {};
    final Set<int> regions = {};

    for (int i = 0; i < queens.length; i++) {
      final p1 = queens[i];
      final r1 = p1.x - 1;
      final c1 = p1.y - 1;
      final reg1 = _currentBoard.regionIds[r1][c1];

      if (rows.contains(r1) || cols.contains(c1) || regions.contains(reg1)) {
        return false; // conflict exists!
      }

      rows.add(r1);
      cols.add(c1);
      regions.add(reg1);

      // Neighborhood check (adjacent blocks)
      for (int j = i + 1; j < queens.length; j++) {
        final p2 = queens[j];
        if ((p1.x - p2.x).abs() <= 1 && (p1.y - p2.y).abs() <= 1) {
          return false;
        }
      }
    }

    return regions.length == _currentBoard.size;
  }

  // Live Conflict calculations for manual validation overlays
  Map<String, dynamic> _getConflicts() {
    final Map<String, dynamic> conflicts = {
      'rows': <int>{},
      'cols': <int>{},
      'regions': <int>{},
      'neighborhood': <String>{},
      'queens': <String>{},
    };

    final List<Point> queens = [];
    _gameGrid.forEach((key, data) {
      if (data['value'] == 2) {
        final parts = key.split(',');
        queens.add(Point(int.parse(parts[0]) + 1, int.parse(parts[1]) + 1));
      }
    });

    for (int i = 0; i < queens.length; i++) {
      final p1 = queens[i];
      final r1 = p1.x - 1;
      final c1 = p1.y - 1;
      final reg1 = _currentBoard.regionIds[r1][c1];

      for (int j = i + 1; j < queens.length; j++) {
        final p2 = queens[j];
        final r2 = p2.x - 1;
        final c2 = p2.y - 1;
        final reg2 = _currentBoard.regionIds[r2][c2];

        bool pairHasConflict = false;

        if (r1 == r2) {
          (conflicts['rows'] as Set<int>).add(r1);
          pairHasConflict = true;
        }
        if (c1 == c2) {
          (conflicts['cols'] as Set<int>).add(c1);
          pairHasConflict = true;
        }
        if (reg1 == reg2) {
          (conflicts['regions'] as Set<int>).add(reg1);
          pairHasConflict = true;
        }
        if ((r1 - r2).abs() <= 1 && (c1 - c2).abs() <= 1) {
          // Add all neighbors of p1
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              int nr = r1 + dr, nc = c1 + dc;
              if (nr >= 0 && nr < _currentBoard.size && nc >= 0 && nc < _currentBoard.size) {
                (conflicts['neighborhood'] as Set<String>).add("$nr,$nc");
              }
            }
          }
          // Add all neighbors of p2
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              int nr = r2 + dr, nc = c2 + dc;
              if (nr >= 0 && nr < _currentBoard.size && nc >= 0 && nc < _currentBoard.size) {
                (conflicts['neighborhood'] as Set<String>).add("$nr,$nc");
              }
            }
          }
          pairHasConflict = true;
        }

        if (pairHasConflict) {
          (conflicts['queens'] as Set<String>).add("$r1,$c1");
          (conflicts['queens'] as Set<String>).add("$r2,$c2");
        }
      }
    }
    return conflicts;
  }

  // --- ROUND TRANSITIONS ---
  void _handleRoundEnded({required String winner}) {
    String dialogTitle = "";
    String dialogMsg = "";
    Color themeColor = Colors.white;
    String lottieAsset = "assets/json/success.json";
    Color buttonColor = AppColors.navyBlue;
    Color buttonTextColor = Colors.white;

    if (winner == 'player') {
      _playerScore++;
      dialogTitle = "ROUND SECURED! 🏆";
      dialogMsg = "Fantastic! You solved Match ${_currentMatchIndex + 1} first! Point awarded to your margin.";
      themeColor = const Color(0xFFF1F8E9); // light green
      lottieAsset = "assets/json/trophy.json";
      buttonColor = AppColors.gold;
      buttonTextColor = AppColors.navyBlue;
    } else if (winner == 'opponent') {
      _opponentScore++;
      dialogTitle = "ROUND CONCEDED! 😢";
      dialogMsg = "So close! $_opponentNickname solved Match ${_currentMatchIndex + 1} first! Get ready for the next round.";
      themeColor = const Color(0xFFFFEBEE); // light red
      lottieAsset = "assets/json/error.json";
      buttonColor = const Color(0xFFFF5252);
      buttonTextColor = Colors.white;
    } else {
      // Co-op Success
      _playerScore++;
      _opponentScore++;
      dialogTitle = "BLUEPRINT LOCKED! 🔒🎉";
      dialogMsg = "Co-op Success! You and $_opponentNickname successfully linked margins and solved Match ${_currentMatchIndex + 1} in ${formatTime(_secondsElapsed)}!";
      themeColor = const Color(0xFFE3F2FD); // light blue
      lottieAsset = "assets/json/winner_badge.json";
      buttonColor = const Color(0xFF1E88E5);
      buttonTextColor = Colors.white;
    }

    // Check if the overall series is solved
    final seriesLimit = (widget.matchCount / 2).ceil();
    final isPlayerSeriesWon = _playerScore >= seriesLimit;
    final isOpponentSeriesWon = _opponentScore >= seriesLimit;
    final isLastMatch = _currentMatchIndex == widget.matchCount - 1;

    final isOver = widget.isCompeteMode 
        ? (isPlayerSeriesWon || isOpponentSeriesWon || isLastMatch)
        : isLastMatch;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Transform.rotate(
          angle: winner == 'player' ? 0.015 : (winner == 'opponent' ? -0.015 : 0.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: themeColor,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: AppColors.navyBlue, width: 2.5),
              boxShadow: [
                BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(6, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Lottie.asset(lottieAsset, repeat: winner == 'opponent' ? false : true),
                ),
                const SizedBox(height: 12),
                Text(
                  dialogTitle, 
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                ),
                const SizedBox(height: 10),
                Text(
                  dialogMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.darkText, height: 1.4),
                ),
                const SizedBox(height: 24),
                Transform.rotate(
                  angle: 0.01,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context); // Close dialog
                      if (isOver) {
                        setState(() => _isSeriesOver = true);
                      } else {
                        setState(() {
                          _currentMatchIndex++;
                          _startNewMatchRound(_currentMatchIndex);
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: buttonColor,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                        boxShadow: [
                          BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(4, 4)),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isOver 
                              ? (widget.isCompeteMode ? 'VIEW SERIES STANDINGS' : 'VIEW CO-OP MARGINS')
                              : 'CONTINUE PLAYING',
                          style: TextStyle(
                            fontFamily: 'DynaPuff', 
                            fontSize: 14, 
                            fontWeight: FontWeight.bold, 
                            color: buttonTextColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Resets the current board layout
  void _clearActiveBoard() {
    if (_isSeriesOver) return;

    setState(() {
      _gameGrid.clear();
      _latestActivityLog = 'Board cleared!';
    });

    if (!widget.isCompeteMode) {
      // Co-op: tell partner to clear their copy of the shared board too
      FirebaseGameManager.instance.sendMessage({'type': 'clear_board'});
    } else {
      // Compete: reset our queen count on the opponent's progress display
      FirebaseGameManager.instance.sendMessage({
        'type':         'progress',
        'queensPlaced': 0,
      });
    }
  }

  // --- UI BUILDING BLOCKS ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Classic Notebook Lines Background
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),

          SafeArea(
            child: _isSeriesOver ? _buildSeriesOverView() : _buildPlayArenaView(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayArenaView() {
    final scale = 0.85;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Row 1: Mode Banner Capsule only (without 'x' exit icon in AppBar)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.isCompeteMode ? const Color(0xFFFF4081) : const Color(0xFF81C784),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))],
                ),
                child: Text(
                  widget.isCompeteMode ? "COMPETE DUEL" : "CO-OP SYNC",
                  style: const TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Header Deck depending on active mode (Scorecard only in competing mode)
          widget.isCompeteMode ? _buildScoreboardHeader() : _buildCoopHeader(),
          const SizedBox(height: 20),

          // Active Timer & Series progress sticker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Timer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: AppColors.navyBlue),
                    const SizedBox(width: 6),
                    Text(
                      formatTime(_secondsElapsed),
                      style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                    ),
                  ],
                ),
              ),

              // Match Count Capsule
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))],
                ),
                child: Text(
                  "MATCH ${_currentMatchIndex + 1} OF ${widget.matchCount}",
                  style: const TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Core Board grid
          _buildMultiplayerBoardGrid(scale),
          const SizedBox(height: 25),

          // Activity / Status log tape
          _buildActivityTape(),
          const SizedBox(height: 20),

          // Live Opponent Status Deck
          _buildOpponentProgressDeck(),
          const SizedBox(height: 25),

          // Control row
          _buildGameplayControls(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildCoopHeader() {
    // Derive colours directly from what each player chose at setup.
    // In co-op the two colours are always blue and green.
    final myColor      = _colorFromPlayerString(widget.playerColor);
    final myColorLight = _lightColorFromPlayerString(widget.playerColor);

    // Partner's colour is whichever co-op colour the local player did NOT pick.
    final partnerColorStr  = widget.playerColor.toLowerCase() == 'blue' ? 'green' : 'blue';
    final partnerColor     = _colorFromPlayerString(partnerColorStr);
    final partnerColorLight = _lightColorFromPlayerString(partnerColorStr);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.navyBlue, width: 2.5),
        boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(5, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // ── Local player ──────────────────────────────────────────────
          Column(
            children: [
              Image.asset(
                _playerIconPath,
                width: 32, height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person_rounded, size: 32, color: myColor),
              ),
              const SizedBox(height: 4),
              Text(
                _playerNickname.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: myColor,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: myColorLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: myColor, width: 1.5),
                ),
                child: Text(
                  widget.playerColor.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Comfortaa',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: myColor,
                  ),
                ),
              ),
            ],
          ),

          Icon(Icons.link_rounded, color: AppColors.navyBlue, size: 24),

          // ── Partner ───────────────────────────────────────────────────
          Column(
            children: [
              Image.asset(
                _opponentIconPath,
                width: 32, height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person_rounded, size: 32, color: partnerColor),
              ),
              const SizedBox(height: 4),
              Text(
                _opponentNickname.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: partnerColor,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: partnerColorLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: partnerColor, width: 1.5),
                ),
                child: Text(
                  partnerColorStr.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Comfortaa',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: partnerColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreboardHeader() {
    // Derive colours from what each player chose — no hardcoded blue/red.
    // In compete mode the two colours are always blue and red.
    final myColor       = _colorFromPlayerString(widget.playerColor);
    final myColorLight  = _lightColorFromPlayerString(widget.playerColor);

    // Opponent's colour is whichever compete colour the local player did NOT pick.
    final opponentColorStr  = widget.playerColor.toLowerCase() == 'blue' ? 'red' : 'blue';
    final opponentColor     = _colorFromPlayerString(opponentColorStr);
    final opponentColorLight = _lightColorFromPlayerString(opponentColorStr);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.navyBlue, width: 2.5),
        boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(5, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // ── Local player ──────────────────────────────────────────────
          Column(
            children: [
              Image.asset(
                _playerIconPath,
                width: 32, height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person_rounded, size: 32, color: myColor),
              ),
              const SizedBox(height: 4),
              Text(
                _playerNickname.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: myColor,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: myColorLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: myColor, width: 1.5),
                ),
                child: Text(
                  '👑 $_playerScore',
                  style: const TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyBlue,
                  ),
                ),
              ),
            ],
          ),

          const Text(
            'VS',
            style: TextStyle(
              fontFamily: 'DynaPuff',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.navyBlue,
            ),
          ),

          // ── Opponent ──────────────────────────────────────────────────
          Column(
            children: [
              Image.asset(
                _opponentIconPath,
                width: 32, height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person_rounded, size: 32, color: opponentColor),
              ),
              const SizedBox(height: 4),
              Text(
                _opponentNickname.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: opponentColor,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: opponentColorLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: opponentColor, width: 1.5),
                ),
                child: Text(
                  '👑 $_opponentScore',
                  style: const TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyBlue,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Maps the stored player-colour string to an actual [Color].
  /// These are the exact colours players chose at match setup:
  ///   'blue'  → deep blue  (host default in co-op / compete)
  ///   'green' → green      (guest default in co-op)
  ///   'red'   → red        (guest default in compete)
  /// Any unknown string falls back to grey so nothing is invisible.
  Color _colorFromPlayerString(String playerStr) {
    switch (playerStr.toLowerCase()) {
      case 'blue':
        return const Color(0xFF1565C0);   // deep blue
      case 'green':
        return const Color(0xFF2E7D32);   // deep green
      case 'red':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  /// Light pastel background tint that pairs with [_colorFromPlayerString].
  Color _lightColorFromPlayerString(String playerStr) {
    switch (playerStr.toLowerCase()) {
      case 'blue':
        return const Color(0xFFE3F2FD);   // light blue
      case 'green':
        return const Color(0xFFE8F5E9);   // light green
      case 'red':
        return const Color(0xFFFFEBEE);   // light red
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  Widget _buildMultiplayerBoardGrid(double boardScale) {
    final double gridWidth = MediaQuery.of(context).size.width * boardScale;
    
    // Live validation conflicts mapping calculation
    final conflicts = _getConflicts();
    final Set<int> rowConflicts = conflicts['rows'] as Set<int>;
    final Set<int> colConflicts = conflicts['cols'] as Set<int>;
    final Set<int> regionConflicts = conflicts['regions'] as Set<int>;
    final Set<String> queenConflicts = conflicts['queens'] as Set<String>;
    final Set<String> neighborhoodConflicts = conflicts['neighborhood'] as Set<String>;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.navyBlue, width: 3),
          boxShadow: const [
            BoxShadow(color: AppColors.navyBlue, offset: Offset(8, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: gridWidth,
            height: gridWidth,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _currentBoard.size,
              ),
              itemCount: _currentBoard.size * _currentBoard.size,
              itemBuilder: (context, index) {
                int r = index ~/ _currentBoard.size;
                int c = index % _currentBoard.size;

                String cellKey = "$r,$c";
                final cellData = _gameGrid[cellKey];
                final cellVal = cellData?['value'] ?? 0;
                final cellOwner = cellData?['player'] ?? "";

                // Get region ID color
                int regId = _currentBoard.regionIds[r][c];

                // Conflicts check
                bool isRowConflict = rowConflicts.contains(r);
                bool isColConflict = colConflicts.contains(c);
                bool isRegionConflict = regionConflicts.contains(regId);
                bool isQueenConflict = queenConflicts.contains(cellKey);
                bool isNeighborhoodConflict = neighborhoodConflicts.contains(cellKey);

                // Resolve the display colour for this cell from the stored
                // owner string ('blue', 'green', 'red').
                // In co-op both players chose their colour at setup, so we
                // honour exactly what is stored — no mode-based overrides.
                Color ownerColor = Colors.transparent;
                if (cellVal > 0) {
                  ownerColor = _colorFromPlayerString(cellOwner);
                }

                return GestureDetector(
                  onTap: () => _handleCellTap(r, c),
                  child: Container(
                    decoration: BoxDecoration(
                      color: RegionColors.getRegionColor(regId, _currentBoard.size),
                      border: Border.all(
                        color: Colors.black.withOpacity(0.06), 
                        width: 0.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Row/Col background conflict tint
                        if (isRowConflict || isColConflict)
                          Container(color: Colors.red.withOpacity(0.08)),

                        // Colored highlight indicating cell ownership marker
                        if (cellVal > 0 && !isQueenConflict)
                          Container(color: ownerColor.withOpacity(0.12)),

                        // Low-opacity conflict cross behind icons
                        if (isRegionConflict || isRowConflict || isColConflict || isQueenConflict || isNeighborhoodConflict)
                          Center(
                            child: Opacity(
                              opacity: 0.15,
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.red.shade900,
                                size: gridWidth / _currentBoard.size,
                              ),
                            ),
                          ),

                        // Render X Dot blocker
                        if (cellVal == 1)
                          Center(
                            child: Text(
                              'x',
                              style: TextStyle(
                                fontFamily: 'Comfortaa',
                                fontSize: (gridWidth * 0.5) / _currentBoard.size,
                                color: ownerColor.withOpacity(0.65),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                        // Render Queen Crown icon (turns dark red on conflict)
                        if (cellVal == 2)
                          Center(
                            child: Icon(
                              Icons.stars_rounded,
                              color: isQueenConflict ? Colors.red.shade900 : ownerColor,
                              size: (gridWidth * 0.8) / _currentBoard.size,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityTape() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7), // Sticky note yellow margin ribbon
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navyBlue, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_edu_rounded, size: 18, color: Colors.brown),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _latestActivityLog,
              style: const TextStyle(
                fontFamily: 'Comfortaa',
                fontSize: 11,
                color: Colors.brown,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentProgressDeck() {
    final rivalColor = widget.isCompeteMode ? Colors.pink : Colors.green;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.navyBlue, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: rivalColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isCompeteMode
                      ? 'RIVAL ${_opponentNickname.toUpperCase()} LIVE STATE'
                      : 'PARTNER ${_opponentNickname.toUpperCase()} LIVE STATE',
                  style: const TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Status: $_opponentStatus',
            style: const TextStyle(
              fontFamily: 'Comfortaa',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameplayControls() {
    if (!widget.isCompeteMode) {
      // Co-op Sync Mode: Show both CLEAR BOARD and END GAME next to each other
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Clear Active Board
          GestureDetector(
            onTap: _clearActiveBoard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))],
              ),
              child: const Row(
                children: [
                  Icon(Icons.cleaning_services_rounded, size: 16, color: AppColors.navyBlue),
                  SizedBox(width: 6),
                  Text(
                    "CLEAR BOARD",
                    style: TextStyle(fontFamily: 'DynaPuff', fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 15),

          // End Game button
          GestureDetector(
            onTap: _showExitConfirmation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))],
              ),
              child: const Row(
                children: [
                  Icon(Icons.power_settings_new_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    "END GAME",
                    style: TextStyle(
                      fontFamily: 'DynaPuff', 
                      fontSize: 11, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Compete Mode controls
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Clear Active Deck
        GestureDetector(
          onTap: _clearActiveBoard,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.navyBlue, width: 2),
              boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))],
            ),
            child: const Row(
              children: [
                Icon(Icons.cleaning_services_rounded, size: 16, color: AppColors.navyBlue),
                SizedBox(width: 6),
                Text(
                  "CLEAR BOARD",
                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 15),

        // End Game / Surrender Sticker
        GestureDetector(
          onTap: _showExitConfirmation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: AppColors.navyBlue, 
                width: 2,
              ),
              boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))],
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.flag_rounded, 
                  size: 16, 
                  color: Colors.white,
                ),
                SizedBox(width: 6),
                Text(
                  "END GAME",
                  style: TextStyle(
                    fontFamily: 'DynaPuff', 
                    fontSize: 11, 
                    fontWeight: FontWeight.bold, 
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- SERIES ENDED / RESULTS SCREEN ---
  Widget _buildSeriesOverView() {
    // Co-op: both players always "win" together — celebrate the team
    // Compete: whoever has more points wins
    final bool isCoopMode = !widget.isCompeteMode;
    final bool playerWon  = _playerScore > _opponentScore;

    final String winnerTitle = isCoopMode
        ? (_playerScore == widget.matchCount
            ? 'PERFECT CO-OP! 🎉'
            : 'SERIES COMPLETE! 🔗')
        : (playerWon ? 'CHAMPION OF MARGINS! 👑' : 'DEFEATED IN DUEL! 😢');

    final String winnerSubtitle = isCoopMode
        ? 'You and $_opponentNickname solved $_playerScore of ${widget.matchCount} boards together!'
        : (playerWon
            ? 'You outperformed $_opponentNickname in the series race!'
            : '$_opponentNickname claimed the trophy! Rematch to secure revenge.');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            Transform.rotate(
              angle: -0.015,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF9F5), // warm notebook white
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.navyBlue, width: 3.5),
                  boxShadow: const [
                    BoxShadow(color: AppColors.navyBlue, offset: Offset(8, 8)),
                  ],
                ),
                child: Column(
                  children: [
                    // Giant Crown Trophy Sticker
                    Transform.scale(
                      scale: 1.1,
                      child: Icon(
                        isCoopMode
                            ? Icons.group_work_rounded
                            : (playerWon
                                ? Icons.emoji_events_rounded
                                : Icons.sentiment_very_dissatisfied_rounded),
                        size: 80,
                        color: isCoopMode
                            ? Colors.green
                            : (playerWon ? AppColors.gold : Colors.redAccent),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Head Header
                    Text(
                      winnerTitle,
                      style: const TextStyle(
                        fontFamily: 'DynaPuff',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyBlue,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      winnerSubtitle,
                      style: const TextStyle(
                        fontFamily: 'Comfortaa',
                        fontSize: 12,
                        color: AppColors.secondaryText,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 25),

                    // Final Scoreboard sticker
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "FINAL SERIES SCORE",
                            style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: AppColors.secondaryText, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 15),
                          
                          // Player Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                _playerIconPath,
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 28),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "${_playerNickname.toUpperCase()} : $_playerScore PTS",
                                style: const TextStyle(
                                  fontFamily: 'DynaPuff', 
                                  fontSize: 16, 
                                  fontWeight: FontWeight.bold, 
                                  color: Color(0xFF0D47A1), // Darker elegant blue text
                                ),
                              ),
                            ],
                          ),
                          
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Icon(Icons.bolt_rounded, color: AppColors.navyBlue, size: 20),
                          ),
                          
                          // Opponent Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                _opponentIconPath,
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 28),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "${_opponentNickname.toUpperCase()} : $_opponentScore PTS",
                                style: TextStyle(
                                  fontFamily: 'DynaPuff', 
                                  fontSize: 16, 
                                  fontWeight: FontWeight.bold, 
                                  color: widget.isCompeteMode ? Colors.pink : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Exit action button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: AppColors.navyBlue, width: 2.5),
                          boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(4, 4))],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          "RETURN TO LOBBY",
                          style: TextStyle(
                            fontFamily: 'DynaPuff',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.navyBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.navyBlue, width: 3),
        ),
        backgroundColor: Colors.white,
        title: const Text(
          "End Play Session?",
          style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
        content: const Text(
          "Are you sure you want to disconnect from this live lobby and return to arena home?",
          style: TextStyle(fontFamily: 'Comfortaa', fontSize: 14, color: AppColors.darkText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(this.context); // exit play screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("END GAME", style: TextStyle(fontFamily: 'DynaPuff')),
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---
  String formatTime(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // --- MOCK REALTIME EMISSION & SOCKET.IO INTEGRATION CODEBLOCKS ---
  // (Production-ready commented out backend logic stubs)
  void _emitRealtimeMoveToSocket(int row, int col, int cellValue, String playerColor) {
    /*
    // ----------------------------------------------------
    // SOCKET.IO REALTIME EMISSION STUB
    // ----------------------------------------------------
    try {
      final String lobbyRoomId = "NQ_ROOM_${widget.opponentId}";
      final payload = {
        'room': lobbyRoomId,
        'action': 'cell_update',
        'row': row,
        'col': col,
        'value': cellValue,
        'player': playerColor,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Emit details via WebSocket connection
      if (socket.connected) {
        socket.emit('game_move', payload);
      }
      
      // OR update Firebase Realtime Database
      // FirebaseDatabase.instance.ref("lobbies/$lobbyRoomId/grid/$row,$col").set(payload);
      
    } catch(e) {
      debugPrint("Realtime backend WebSocket write failed: $e");
    }
    // ----------------------------------------------------
    */
  }

  /*
  // ----------------------------------------------------
  // SOCKET.IO REALTIME RECEPTION & SUBSCRIPTION HANDLER
  // ----------------------------------------------------
  void connectAndSubscribeToLobby() {
    final String lobbyRoomId = "NQ_ROOM_${widget.opponentId}";
    
    // Subscribe to gameplay move broadcast topic
    socket.on('opponent_game_move', (data) {
      if (!mounted) return;
      
      final int r = data['row'];
      final int c = data['col'];
      final int value = data['value'];
      final String owner = data['player'];
      
      setState(() {
        final key = "$r,$c";
        if (value == 0) {
          _gameGrid.remove(key);
        } else {
          _gameGrid[key] = {
            'value': value,
            'player': owner,
          };
        }
        
        _latestActivityLog = "NQ-${widget.opponentId} placed a marker!";
      });
      
      if (!widget.isCompeteMode) {
        _checkCoopWinCondition();
      }
    });

    // Subscribe to Opponent Solved Broadcast topic
    socket.on('opponent_solved_match', (data) {
      if (!mounted) return;
      final int solvedMatchIndex = data['matchIndex'];
      if (solvedMatchIndex == _currentMatchIndex && widget.isCompeteMode) {
         _handleRoundEnded(winner: 'opponent');
      }
    });
  }
  // ----------------------------------------------------
  */
}
