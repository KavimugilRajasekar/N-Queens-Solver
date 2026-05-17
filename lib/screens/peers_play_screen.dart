import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import '../utils/board_processor.dart';
import '../constants/region_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPlayerIcons();
    _startNewMatchRound(_currentMatchIndex);
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
    // Randomize partner nickname based on opponentId so it stays consistent
    final funkyNames = [
      "PixelQueen", "ChronoSolve", "BinaryKnight", "Algorist", 
      "NeonPuzzler", "RetroRook", "AlphaSolver", "DeltaByte"
    ];
    final int seed = widget.opponentId.hashCode;
    setState(() {
      _opponentNickname = funkyNames[seed.abs() % funkyNames.length];
    });

    // Randomize partner icon from the list of icons so they look different and fun!
    final icons = [
      'assets/player_icons/unicorn.png',
      'assets/player_icons/dinosaur.png',
      'assets/player_icons/alien.png',
      'assets/player_icons/startup.png',
      'assets/player_icons/diamond.png',
      'assets/player_icons/torch.png',
      'assets/player_icons/pizza.png',
      'assets/player_icons/cat.png',
      'assets/player_icons/kitty.png',
    ];
    setState(() {
      _opponentIconPath = icons[Random().nextInt(icons.length)];
    });
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _mockOpponentActionTimer?.cancel();
    super.dispose();
  }

  // Set up board and simulator for the current round index
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
    _opponentStatus = "Analyzing regions... 🤔";

    // 1. Start game timer
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && !_isSeriesOver && mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });

    // 2. Start mock opponent simulation (commented out backend replacement)
    _startMockOpponentSimulation();
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

    final String cellKey = "$r,$c";
    final String playerColor = widget.playerColor.toLowerCase();

    setState(() {
      final currentMap = _gameGrid[cellKey];
      final currentValue = currentMap?['value'] ?? 0;
      
      int newValue = 0;
      if (currentValue == 0) {
        // Empty -> X
        newValue = 1;
      } else if (currentValue == 1) {
        // X -> Queen
        newValue = 2;
      } else {
        // Queen -> Empty
        newValue = 0;
      }

      if (newValue == 0) {
        _gameGrid.remove(cellKey);
      } else {
        _gameGrid[cellKey] = {
          'value': newValue,
          'player': playerColor, // player takes ownership of the cell move
        };
      }

      _latestActivityLog = newValue == 2 
        ? "You placed a Queen at [${r + 1}, ${c + 1}]!"
        : newValue == 1 
          ? "You marked cell [${r + 1}, ${c + 1}] with X."
          : "You cleared cell [${r + 1}, ${c + 1}].";
      
      // Update real-time database or socket here (production-ready commented stub)
      _emitRealtimeMoveToSocket(r, c, newValue, playerColor);
    });

    if (widget.isCompeteMode) {
      _checkCompeteWinCondition();
    } else {
      _checkCoopWinCondition();
    }
  }

  // Checks win condition for Independent Compete Mode
  void _checkCompeteWinCondition() {
    if (_hasSolvedBoardCorrectly()) {
      _mockOpponentActionTimer?.cancel();
      _gameTimer?.cancel();
      _handleRoundEnded(winner: 'player');
    }
  }

  // Checks win condition for Collaborative Shared Co-op Mode
  void _checkCoopWinCondition() {
    if (_hasSolvedBoardCorrectly()) {
      _mockOpponentActionTimer?.cancel();
      _gameTimer?.cancel();
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
      _latestActivityLog = "Active board template cleared!";
    });
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.navyBlue, width: 2.5),
        boxShadow: const [
          BoxShadow(color: AppColors.navyBlue, offset: Offset(5, 5)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Player
          Column(
            children: [
              Image.asset(
                _playerIconPath,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 32, color: AppColors.navyBlue),
              ),
              const SizedBox(height: 4),
              Text(
                _playerNickname.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1), // Darker elegant blue text
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD), // Darker elegant blue container background
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.navyBlue, width: 1.5),
                ),
                child: const Text(
                  "Player",
                  style: TextStyle(fontFamily: 'Comfortaa', fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                ),
              ),
            ],
          ),

          const Icon(Icons.link_rounded, color: AppColors.navyBlue, size: 24),

          // Partner
          Column(
            children: [
              Image.asset(
                _opponentIconPath,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 32, color: AppColors.navyBlue),
              ),
              const SizedBox(height: 4),
              Text(
                _opponentNickname.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.navyBlue, width: 1.5),
                ),
                child: const Text(
                  "Partner",
                  style: TextStyle(fontFamily: 'Comfortaa', fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreboardHeader() {
    final playerIsBlue = widget.playerColor.toLowerCase() == 'blue';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.navyBlue, width: 2.5),
        boxShadow: const [
          BoxShadow(color: AppColors.navyBlue, offset: Offset(5, 5)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Player info
          Column(
            children: [
              Image.asset(
                _playerIconPath,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 32),
              ),
              const SizedBox(height: 4),
              Text(
                _playerNickname.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: playerIsBlue ? const Color(0xFF0D47A1) : Colors.red,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: playerIsBlue ? Colors.blue.shade100 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.navyBlue, width: 1.5),
                ),
                child: Text(
                  "👑 $_playerScore",
                  style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                ),
              ),
            ],
          ),

          // Separator Sticker
          const Text(
            "VS",
            style: TextStyle(
              fontFamily: 'DynaPuff',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.navyBlue,
            ),
          ),

          // Opponent info
          Column(
            children: [
              Image.asset(
                _opponentIconPath,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 32),
              ),
              const SizedBox(height: 4),
              Text(
                _opponentNickname.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: playerIsBlue ? Colors.red : const Color(0xFF0D47A1),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: playerIsBlue ? Colors.red.shade100 : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.navyBlue, width: 1.5),
                ),
                child: Text(
                  "👑 $_opponentScore",
                  style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

                // Check cell ownership colors (Opponent is Pink/Green depending on mode)
                final isPlayerCell = cellOwner == widget.playerColor.toLowerCase();

                Color ownerColor = Colors.transparent;
                if (cellVal > 0) {
                  if (isPlayerCell) {
                    ownerColor = widget.playerColor.toLowerCase() == 'blue' 
                        ? (widget.isCompeteMode ? Colors.cyan : const Color(0xFF1565C0)) // Darker elegant blue overlay in Combine Solving Mode!
                        : Colors.redAccent;
                  } else {
                    ownerColor = widget.isCompeteMode ? Colors.pink : Colors.green; // Pink for Duel, Green for Co-op
                  }
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
              Text(
                widget.isCompeteMode 
                    ? "RIVAL $_opponentNickname LIVE STATE".toUpperCase() 
                    : "PARTNER $_opponentNickname LIVE STATE".toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.isCompeteMode 
              ? "Status: $_opponentStatus"
              : "Status: Linked & Solving shared deck collaboratively! 🔗",
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
      // Combine Solving Mode: Only show end game
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _showExitConfirmation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2.5),
                boxShadow: const [BoxShadow(color: AppColors.navyBlue, offset: Offset(3, 3))],
              ),
              child: const Row(
                children: [
                  Icon(Icons.power_settings_new_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    "END GAME",
                    style: TextStyle(
                      fontFamily: 'DynaPuff', 
                      fontSize: 13, 
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
    final playerWon = _playerScore > _opponentScore;
    final winnerTitle = playerWon ? "CHAMPION OF MARGINS!" : "DEFEATED IN DUEL!";
    final winnerSubtitle = playerWon 
        ? "You outperformed $_opponentNickname in the series race!" 
        : "$_opponentNickname claimed the trophy! Rematch to secure revenge.";

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
                        playerWon ? Icons.emoji_events_rounded : Icons.sentiment_very_dissatisfied_rounded,
                        size: 80,
                        color: playerWon ? AppColors.gold : Colors.redAccent,
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
