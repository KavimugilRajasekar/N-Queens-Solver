import '../widgets/board/victory_dialog.dart';
import '../widgets/board/algorithm_flow.dart';
import '../widgets/board/board_grid.dart';
import '../widgets/board/board_palette.dart';
import '../widgets/board/board_header.dart';
import '../widgets/board/action_buttons.dart';
import '../widgets/help_card.dart';
import '../widgets/notebook_painter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/error_dialog.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../constants/region_colors.dart';
import '../utils/solver_logic.dart';
import '../utils/storage_manager.dart';

class NQueensBoardScreen extends StatefulWidget {
  final BoardData boardData;
  final bool isAlreadySaved;
  final int? boardId;

  /// True when this screen is being opened from a Daily Quest entry.
  /// In that case we auto-start manual mode, hide the AI solver and the
  /// Edit button, and skip the "Save to Library" button since the entry
  /// is already persisted server-side.
  final bool isDailyQuest;

  const NQueensBoardScreen({
    super.key,
    required this.boardData,
    this.isAlreadySaved = false,
    this.boardId,
    this.isDailyQuest = false,
  });

  @override
  State<NQueensBoardScreen> createState() => _NQueensBoardScreenState();
}

class _NQueensBoardScreenState extends State<NQueensBoardScreen> {
  Map<int, Point> _queenPositions = {};
  final List<SolverStep> _solverSteps = [];
  bool _isSolving = false;
  bool _isEditing = false;
  List<List<int>>? _tempGrid;
  int? _selectedRegionId;
  final ScrollController _logScrollController = ScrollController();

  bool _isFastForward = false;
  late bool _isSaved;
  int? _boardId;

  // Manual Mode State
  bool _isManualMode = false;
  bool _isPaused = false;
  int _secondsElapsed = 0;
  Timer? _timer;
  final Map<String, int> _manualGrid = {}; // "r,c" -> 0: empty, 1: X, 2: Queen

  // ── Daily-Quest reveal / attempt state ─────────────────────────────────
  // Mirrors BoardData.isRevealed / attemptsUsed / isFailed so the screen
  // can react instantly to user input. Persisted back to the same fields
  // on every state change.
  bool _isRevealed = false;
  bool _isFailed = false;
  int _attemptsUsed = 0;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isAlreadySaved;
    _boardId = widget.boardId;
    // Puzzles should start empty for the user to solve!
    _queenPositions = {};

    // Hydrate the daily-quiz reveal / attempt state from the persisted
    // BoardData so a crash mid-attempt still shows the revealed board
    // (or the locked tile) on the next open.
    if (widget.isDailyQuest) {
      _isRevealed = widget.boardData.isRevealed;
      _isFailed = widget.boardData.isFailed;
      _attemptsUsed = widget.boardData.attemptsUsed;
    }

    // Daily Quest entries are server-issued; the user only solves them
    // by hand. Previously we auto-started manual mode here, which leaked
    // the board's colored grid before the user tapped REVEAL QUIZ. The
    // new flow waits for an explicit reveal, unless the board was already
    // revealed in a prior session (so the user can resume mid-attempt).
    if (widget.isDailyQuest && _isRevealed && !_isFailed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startManualMode(resuming: true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // Daily-Quest reveal / give-up flow
  // ─────────────────────────────────────────────────────────────────────

  /// Confirmation dialog that fires before the user burns an attempt on
  /// REVEAL QUIZ. Cancel returns to the foggy library card; confirm flips
  /// `_isRevealed`, bumps `_attemptsUsed`, and drops into manual mode.
  Future<void> _onRevealPressed() async {
    if (_isRevealed) return; // Defensive: button only shows in pre-reveal state.
    if (_isFailed) return; // Defensive: locked quests can't be revealed.

    final nextAttempt = _attemptsUsed + 1;
    final remaining = BoardData.kMaxDailyAttempts - _attemptsUsed;
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.navyBlue, width: 2.5),
        ),
        title: const Text(
          'Reveal Today\'s Quiz?',
          style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue),
        ),
        content: Text(
          remaining == 1
              ? "This is your LAST attempt — there are no do-overs once you reveal the board."
              : "Revealing starts attempt $nextAttempt of ${BoardData.kMaxDailyAttempts}. You have $remaining attempts left today.",
          style: const TextStyle(fontFamily: 'Comfortaa'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'NOT YET',
              style: TextStyle(fontFamily: 'DynaPuff', color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'REVEAL',
              style: TextStyle(
                fontFamily: 'DynaPuff',
                color: AppColors.navyBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm != true) return;

    // Persist the reveal + attempt bump first so a crash mid-board never
    // leaves the user with a hidden card but a running timer.
    setState(() {
      _isRevealed = true;
      _attemptsUsed = nextAttempt;
      widget.boardData.isRevealed = true;
      widget.boardData.attemptsUsed = nextAttempt;
    });
    await _persistDailyBoard();
    if (!mounted) return;
    await _startManualMode();
  }

  /// GIVE UP — user walks out of the running attempt. Counts as one failed
  /// attempt. If this pushes `attemptsUsed` to `kMaxDailyAttempts`, flip
  /// `isFailed` so the card goes light-red and the lock screen renders.
  Future<void> _onGiveUpPressed() async {
    if (!_isRevealed || _isFailed) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 2.5),
        ),
        title: const Text(
          'Give Up?',
          style: TextStyle(fontFamily: 'DynaPuff', color: Colors.redAccent),
        ),
        content: Text(
          _attemptsUsed >= BoardData.kMaxDailyAttempts
              ? "This is your final attempt. Backing out now locks today's quiz."
              : "Backing out counts as a failed attempt. You'll have ${BoardData.kMaxDailyAttempts - _attemptsUsed - 1} attempt(s) left after this.",
          style: const TextStyle(fontFamily: 'Comfortaa'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'KEEP PLAYING',
              style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'GIVE UP',
              style: TextStyle(
                fontFamily: 'DynaPuff',
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm != true) return;

    await _finalizeDailyAttempt(success: false);
  }

  /// Persist the daily-quest attempt result and pop back to the library
  /// when the user gives up. On success (solved) the existing
  /// `_checkWinCondition` path already handles persistence; on failure we
  /// bump the attempt counter and lock if the cap is hit.
  Future<void> _finalizeDailyAttempt({required bool success}) async {
    _timer?.cancel();
    final attemptsBefore = _attemptsUsed;
    final shouldLock = !success && attemptsBefore >= BoardData.kMaxDailyAttempts;
    setState(() {
      if (!success) {
        _attemptsUsed = attemptsBefore + 1;
        widget.boardData.attemptsUsed = _attemptsUsed;
      }
      if (shouldLock) {
        _isFailed = true;
        widget.boardData.isFailed = true;
      }
      _isManualMode = false;
    });
    // Wipe the in-progress manual grid so a re-open (which won't be
    // possible while locked) doesn't accidentally restore stale marks.
    _manualGrid.clear();
    _secondsElapsed = 0;
    await _persistDailyBoard();
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Persist the current daily-quest BoardData back to disk + (re)write
  /// its row in saved_boards.json. No-op for non-daily boards.
  Future<void> _persistDailyBoard() async {
    if (!widget.isDailyQuest) return;
    if (_boardId == null || !_isSaved) {
      // Edge case: a non-saved daily quest (shouldn't happen in normal
      // flow but guard against it so we don't silently lose state).
      final id = await StorageManager.saveBoard(widget.boardData);
      if (mounted) {
        setState(() {
          _isSaved = true;
          _boardId = id;
        });
      }
      return;
    }
    await StorageManager.updateBoard(_boardId!, widget.boardData);
  }

  Future<void> _startSolving() async {
    if (_isSolving || _isEditing) return;

    if (_hasConflicts()) {
      FunkyErrorDialog.show(context,
        title: 'Oops!',
        message: 'Some regions are invalid! Fix the Funky-X marks using Edit before solving.',
      );
      return;
    }

    setState(() {
      _isSolving = true;
      _isFastForward = false;
      _queenPositions.clear();
      _solverSteps.clear();
    });
    final solver = NQueensSolver(widget.boardData);
    await for (final step in solver.solve()) {
      if (!mounted) break;
      setState(() {
        _queenPositions = step.queenPositions;
        _solverSteps.add(step);
      });
      _scrollToBottom();
      
      if (!_isFastForward) {
        int delay = step.isBacktrack ? 400 : 600;
        await Future.delayed(Duration(milliseconds: delay));
      } else {
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }
    setState(() {
      _isSolving = false;
      _isFastForward = false;
      if (_queenPositions.length == widget.boardData.size) {
        widget.boardData.solution = Map.from(_queenPositions);
        if (widget.isAlreadySaved && widget.boardId != null) {
          StorageManager.updateBoard(widget.boardId!, widget.boardData);
        }
      }
    });
  }

  Future<void> _startManualMode({bool resuming = false}) async {
    if (_isSolving || _isEditing) return;

    final solver = NQueensSolver(widget.boardData);
    bool hasSolution = false;
    await for (final step in solver.solve()) {
      if (step.message.contains("found")) {
        hasSolution = true;
        break;
      }
    }

    if (!hasSolution) {
      if (mounted) {
        FunkyErrorDialog.show(context,
          title: "Impossible!",
          message: "This board doesn't have a solution! Correct the regions first.",
        );
      }
      return;
    }

    // ── Resume an in-progress game? ──────────────────────────────────────
    // If we have a boardId, ask StorageManager whether the user previously
    // quit mid-game. If so, offer to resume — silently overwriting their
    // work-in-progress is what made the old code feel "broken" when the
    // user backed out and re-entered. We only do this when the saved grid
    // actually has marks; an empty saved grid means a stale / no-op entry.
    if (_boardId != null) {
      final saved = await StorageManager.loadManualProgress(_boardId!);
      if (saved != null && saved.manualGrid.isNotEmpty) {
        if (!mounted) return;
        final resume = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.navyBlue, width: 2.5),
            ),
            title: const Text(
              'Resume your game?',
              style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue),
            ),
            content: Text(
              'You have an in-progress game with ${saved.manualGrid.length} marks and ${formatTime(saved.secondsElapsed)} on the clock. Pick up where you left off?',
              style: const TextStyle(fontFamily: 'Comfortaa'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Start fresh',
                  style: TextStyle(fontFamily: 'DynaPuff', color: Colors.redAccent),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Resume',
                  style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue),
                ),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (resume == true) {
          setState(() {
            _isManualMode = true;
            _isPaused = saved.isPaused;
            _secondsElapsed = saved.secondsElapsed;
            _manualGrid
              ..clear()
              ..addAll(saved.manualGrid);
            _queenPositions.clear();
          });
          _updateQueenPositionsFromManual();
          if (!_isPaused) _startTimer();
          return;
        }
        // "Start fresh" — drop the stale entry.
        await StorageManager.saveManualProgress(
          _boardId!,
          manualGrid: const {},
          secondsElapsed: 0,
          isPaused: false,
          clear: true,
        );
      }
    }

    setState(() {
      _isManualMode = true;
      _isPaused = false;
      _secondsElapsed = 0;
      _manualGrid.clear();
      _queenPositions.clear();
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && mounted) {
        setState(() => _secondsElapsed++);
      }
    });
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
    // Mirror the timer state to disk so a resume picks up "paused" if the
    // user backs out while paused.
    if (_boardId != null && _isManualMode) {
      StorageManager.saveManualProgress(
        _boardId!,
        manualGrid: Map<String, int>.from(_manualGrid),
        secondsElapsed: _secondsElapsed,
        isPaused: _isPaused,
      );
    }
  }

  /// Quit manual mode but KEEP the in-progress grid + timer so the user can
  /// resume next time they open this board. Without this, the old code did
  /// ``setState(manual = false)`` which wiped nothing in memory but also
  /// offered no resume on the next ``Do it`` tap.
  void _quitManualMode() {
    // Daily Quests don't have a "save & quit" path — backing out counts
    // as a failed attempt. Delegate to the give-up flow which handles
    // attempt bookkeeping + (optionally) lock state.
    if (widget.isDailyQuest && _isRevealed && !widget.boardData.isManuallySolved) {
      _onGiveUpPressed();
      return;
    }
    _timer?.cancel();
    setState(() {
      _isManualMode = false;
    });
    if (_boardId != null) {
      StorageManager.saveManualProgress(
        _boardId!,
        manualGrid: Map<String, int>.from(_manualGrid),
        secondsElapsed: _secondsElapsed,
        isPaused: false,
      );
    }
  }

  void _handleManualTap(int r, int c) {
    if (_isPaused) return;
    String key = "$r,$c";
    setState(() {
      int current = _manualGrid[key] ?? 0;
      _manualGrid[key] = (current + 1) % 3;
      _updateQueenPositionsFromManual();
    });
    // Persist after every tap so an unexpected kill (background process
    // trim, OS reboot, etc.) never loses more than one mark.
    if (_boardId != null) {
      StorageManager.saveManualProgress(
        _boardId!,
        manualGrid: Map<String, int>.from(_manualGrid),
        secondsElapsed: _secondsElapsed,
        isPaused: _isPaused,
      );
    }
    _checkWinCondition();
  }


  void _updateQueenPositionsFromManual() {
    _queenPositions.clear();
    int qIdx = 0;
    _manualGrid.forEach((key, val) {
      if (val == 2) {
        final parts = key.split(',');
        int r = int.parse(parts[0]);
        int c = int.parse(parts[1]);
        _queenPositions[qIdx++] = Point(r + 1, c + 1);
      }
    });
  }

  void _checkWinCondition() {
    if (_queenPositions.length == widget.boardData.size) {
      Map<int, int> rows = {}, cols = {}, regions = {};
      bool conflict = false;

      for (var p in _queenPositions.values) {
        int r = p.x - 1;
        int c = p.y - 1;
        int regId = widget.boardData.regionIds[r][c];

        rows[r] = (rows[r] ?? 0) + 1;
        cols[c] = (cols[c] ?? 0) + 1;
        regions[regId] = (regions[regId] ?? 0) + 1;

        if (rows[r]! > 1 || cols[c]! > 1 || regions[regId]! > 1) conflict = true;
        
        for (var p2 in _queenPositions.values) {
          if (p == p2) continue;
          if ((p.x - p2.x).abs() <= 1 && (p.y - p2.y).abs() <= 1) conflict = true;
        }
      }

      if (!conflict && regions.length == widget.boardData.size) {
        _timer?.cancel();

        // Solved — drop the resume snapshot so the next manual session
        // starts fresh.
        if (_boardId != null) {
          StorageManager.saveManualProgress(
            _boardId!,
            manualGrid: const {},
            secondsElapsed: 0,
            isPaused: false,
            clear: true,
          );
        }

        widget.boardData.isManuallySolved = true;
        // A win resets the attempt counter for completeness, even though
        // the card's gold theme + trophy badge is the main signal.
        if (widget.isDailyQuest) {
          widget.boardData.attemptsUsed = _attemptsUsed;
          widget.boardData.isFailed = false;
        }
        if (_isSaved && _boardId != null) {
          StorageManager.updateBoard(_boardId!, widget.boardData);
        } else {
          // Auto-save if not already saved in library
          StorageManager.saveBoard(widget.boardData).then((id) {
            if (mounted) {
              setState(() {
                _isSaved = true;
                _boardId = id;
              });
            }
          });
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => VictoryDialog(time: formatTime(_secondsElapsed)),
        );
      }
    }
  }

  Map<String, dynamic> _getManualConflicts() {
    Map<String, dynamic> conflicts = {
      'rows': <int>{},
      'cols': <int>{},
      'regions': <int>{},
      'neighborhood': <String>{},
      'queens': <String>{},
    };
    
    if (!_isManualMode) return conflicts;

    List<Point> queens = [];
    _manualGrid.forEach((key, val) {
      if (val == 2) {
        final parts = key.split(',');
        queens.add(Point(int.parse(parts[0]) + 1, int.parse(parts[1]) + 1));
      }
    });

    for (int i = 0; i < queens.length; i++) {
      Point p1 = queens[i];
      int r1 = p1.x - 1;
      int c1 = p1.y - 1;
      int reg1 = widget.boardData.regionIds[r1][c1];

      for (int j = i + 1; j < queens.length; j++) {
        Point p2 = queens[j];
        int r2 = p2.x - 1;
        int c2 = p2.y - 1;
        int reg2 = widget.boardData.regionIds[r2][c2];

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
              if (nr >= 0 && nr < widget.boardData.size && nc >= 0 && nc < widget.boardData.size) {
                (conflicts['neighborhood'] as Set<String>).add("$nr,$nc");
              }
            }
          }
          // Add all neighbors of p2
          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              int nr = r2 + dr, nc = c2 + dc;
              if (nr >= 0 && nr < widget.boardData.size && nc >= 0 && nc < widget.boardData.size) {
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

  String formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  void _toggleEditMode() {
    setState(() {
      if (!_isEditing) {
        _isEditing = true;
        _selectedRegionId = 1;
        _tempGrid = List.generate(widget.boardData.size, (r) => List.from(widget.boardData.regionIds[r]));
      } else {
        _isEditing = false;
        _tempGrid = null;
      }
    });
  }

  void _saveEdits() {
    if (_tempGrid != null) {
      bool allFilled = _tempGrid!.every((row) => row.every((id) => id != 0));
      if (!allFilled) {
        FunkyErrorDialog.show(context,
          title: 'Hold on!',
          message: 'Every cell needs a region color! Paint all the empty cells before saving.',
        );
        return;
      }

      for (int r = 0; r < widget.boardData.size; r++) {
        for (int c = 0; c < widget.boardData.size; c++) {
          widget.boardData.regionIds[r][c] = _tempGrid![r][c];
        }
      }

      final Map<int, List<Point>> idToPoints = {};
      for (int r = 0; r < widget.boardData.size; r++) {
        for (int c = 0; c < widget.boardData.size; c++) {
          int id = widget.boardData.regionIds[r][c];
          idToPoints.putIfAbsent(id, () => []).add(Point(r + 1, c + 1));
        }
      }

      final newRegions = <int, BoardRegion>{};
      for (int id = 1; id <= widget.boardData.size; id++) {
        if (idToPoints.containsKey(id)) {
          newRegions[id] = BoardRegion(
            id: id, 
            color: RegionColors.getRegionColor(id, widget.boardData.size), 
            coordinates: idToPoints[id]!
          );
        }
      }

      for (var entry in newRegions.entries) {
        if (!_isRegionContiguous(entry.value)) {
          FunkyErrorDialog.show(context,
            title: 'Disconnected!',
            message: 'Region ${entry.key} is split apart! Each region must be one connected group.',
          );
          return;
        }
      }

      // Reject edits that produce 0 or 2+ solutions. The board invariant
      // is "exactly one solution exists", so silently accepting an
      // ambiguous edit would let the user break their own game.
      final candidate = BoardData(
        size: widget.boardData.size,
        regionIds: widget.boardData.regionIds,
        regions: newRegions,
        rawResponse: widget.boardData.rawResponse,
      );
      final uniquenessCheck = NQueensSolver(candidate).countSolutions(maxCount: 2);
      if (uniquenessCheck == 0) {
        FunkyErrorDialog.show(
          context,
          title: 'No Solution!',
          message:
              'Your new layout has no valid queen placement. Try repainting — usually one region is too big or two regions are too small.',
        );
        return;
      }
      if (uniquenessCheck > 1) {
        FunkyErrorDialog.show(
          context,
          title: 'Multiple Solutions!',
          message:
              'Your new layout has more than one valid answer. Add more region boundaries or shrink a region so only one placement works.',
        );
        return;
      }

      widget.boardData.regions.clear();
      widget.boardData.regions.addAll(newRegions);
      widget.boardData.solution = null;
      // Reset manual solver trophy badge since layout has been altered!
      widget.boardData.isManuallySolved = false;
      _queenPositions.clear();
      _solverSteps.clear();
      // Region layout changed — wipe any in-progress resume state since
      // the saved marks would no longer make sense on a new board.
      _manualGrid.clear();
      _secondsElapsed = 0;

      if (_isSaved && _boardId != null) {
        StorageManager.updateBoard(_boardId!, widget.boardData);
        StorageManager.saveManualProgress(
          _boardId!,
          manualGrid: const {},
          secondsElapsed: 0,
          isPaused: false,
          clear: true,
        );
      }
    }
    setState(() {
      _isEditing = false;
      _tempGrid = null;
    });
  }

  bool _isRegionContiguous(BoardRegion region) {
    if (region.coordinates.isEmpty) return true;
    final Set<String> regionPoints = region.coordinates.map((p) => "${p.x},${p.y}").toSet();
    final List<Point> queue = [region.coordinates.first];
    final Set<String> visited = {"${queue.first.x},${queue.first.y}"};
    int index = 0;
    while (index < queue.length) {
      final current = queue[index++];
      final neighbors = [Point(current.x + 1, current.y), Point(current.x - 1, current.y), Point(current.x, current.y + 1), Point(current.x, current.y - 1)];
      for (var n in neighbors) {
        String key = "${n.x},${n.y}";
        if (regionPoints.contains(key) && !visited.contains(key)) {
          visited.add(key);
          queue.add(n);
        }
      }
    }
    return visited.length == regionPoints.length;
  }

  void _handleCellTap(int r, int c) {
    if (!_isEditing || _selectedRegionId == null) return;
    setState(() {
      _tempGrid![r][c] = _selectedRegionId!;
    });
  }

  bool _hasConflicts() {
    for (int r = 0; r < widget.boardData.size; r++) {
      for (int c = 0; c < widget.boardData.size; c++) {
        if (widget.boardData.regionIds[r][c] > widget.boardData.size) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    double boardScale = _isEditing ? 0.9 : 0.75;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BoardHeader(
                      isManualMode: _isManualMode,
                      isPaused: _isPaused,
                      isEditing: _isEditing,
                      isSolving: _isSolving,
                      isFastForward: _isFastForward,
                      formattedTime: formatTime(_secondsElapsed),
                      onFastForward: () => setState(() => _isFastForward = true),
                    ),
                    const SizedBox(height: 30),
                    if (_isEditing) 
                      BoardPalette(
                        boardSize: widget.boardData.size, 
                        selectedRegionId: _selectedRegionId, 
                        onRegionSelected: (id) => setState(() => _selectedRegionId = id),
                      ),
                    const SizedBox(height: 20),
                    BoardGrid(
                      boardScale: boardScale,
                      boardData: widget.boardData,
                      isEditing: _isEditing,
                      isManualMode: _isManualMode,
                      isPaused: _isPaused,
                      // Daily Quest: paint fog until the user reveals.
                      isDailyQuest: widget.isDailyQuest,
                      isRevealed: widget.isDailyQuest ? _isRevealed : true,
                      queenPositions: _queenPositions,
                      manualGrid: _manualGrid,
                      tempGrid: _tempGrid,
                      conflicts: _getManualConflicts(),
                      onCellTap: (r, c) => _isManualMode ? _handleManualTap(r, c) : _handleCellTap(r, c),
                      onPanEnd: () => setState(() {}),
                    ),
                    const SizedBox(height: 30),
                    ActionButtons(
                      isManualMode: _isManualMode,
                      isPaused: _isPaused,
                      isSolving: _isSolving,
                      isEditing: _isEditing,
                      hasConflicts: _hasConflicts(),
                      formattedTime: formatTime(_secondsElapsed),
                      isDailyQuest: widget.isDailyQuest,
                      // Daily-quest flags — drive the REVEAL / GIVE UP /
                      // LOCKED branches in the action bar.
                      isRevealed: widget.isDailyQuest ? _isRevealed : true,
                      isFailed: widget.isDailyQuest ? _isFailed : false,
                      attemptLabel: widget.isDailyQuest && _isRevealed && !_isFailed
                          ? 'Attempt $_attemptsUsed of ${BoardData.kMaxDailyAttempts}'
                          : '',
                      onReveal: _onRevealPressed,
                      onGiveUp: _onGiveUpPressed,
                      onTogglePause: _togglePause,
                      onQuitManual: _quitManualMode,
                      onToggleEdit: widget.isDailyQuest ? () {} : _toggleEditMode,
                      onSolve: _startSolving,
                      onSaveEdits: _saveEdits,
                      onStartManual: _startManualMode,
                    ),
                    const SizedBox(height: 24),
                    HelpCard(
                      kind: _isManualMode
                          ? HelpKind.play
                          : (_isSolving ? HelpKind.aiSolver : HelpKind.play),
                      rotation: -0.008,
                      initiallyCollapsed: _isManualMode || _isSolving,
                    ),
                    if (!_isManualMode) ...[
                      const SizedBox(height: 30),
                      if (!_isEditing && _solverSteps.isNotEmpty)
                        AlgorithmFlow(
                          solverSteps: _solverSteps,
                          scrollController: _logScrollController,
                          boardData: widget.boardData,
                        ),
                      const SizedBox(height: 30),
                      if (!_isEditing) _buildLibraryButtons(),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryButtons() {
    return Column(
      children: [
        if (!_isSaved && !widget.isDailyQuest)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Transform.rotate(
              angle: 0.01,
              child: Container(
                width: double.infinity,
                height: 65,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.1), offset: const Offset(4, 4))], border: Border.all(color: AppColors.navyBlue.withValues(alpha: 0.3), width: 1.5)),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final id = await StorageManager.saveBoard(widget.boardData);
                    if (mounted) {
                      setState(() {
                        _isSaved = true;
                        _boardId = id;
                      });
                    }
                  },
                  icon: const Icon(Icons.bookmark_add_rounded, size: 24, color: AppColors.navyBlue),
                  label: const Text('Save to Library', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
                ),
              ),
            ),
          ),
        Transform.rotate(
          angle: -0.02,
          child: Container(
            width: double.infinity,
            height: 65,
            decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(5, 5))], border: Border.all(color: AppColors.navyBlue, width: 2.5)),
            child: ElevatedButton.icon(
              onPressed: _isSolving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.library_books_rounded, size: 28),
              label: const Text('Back to Library', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: AppColors.navyBlue, shadowColor: Colors.transparent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            ),
          ),
        ),
      ],
    );
  }
}
