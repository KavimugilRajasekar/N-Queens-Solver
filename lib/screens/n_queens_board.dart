import '../widgets/board/victory_dialog.dart';
import '../widgets/board/algorithm_flow.dart';
import '../widgets/board/board_grid.dart';
import '../widgets/board/board_palette.dart';
import '../widgets/board/board_header.dart';
import '../widgets/board/action_buttons.dart';
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

  const NQueensBoardScreen({
    super.key, 
    required this.boardData, 
    this.isAlreadySaved = false,
    this.boardId,
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

  // Manual Mode State
  bool _isManualMode = false;
  bool _isPaused = false;
  int _secondsElapsed = 0;
  Timer? _timer;
  Map<String, int> _manualGrid = {}; // "r,c" -> 0: empty, 1: X, 2: Queen

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isAlreadySaved;
    if (widget.boardData.solution != null) {
      _queenPositions = Map.from(widget.boardData.solution!);
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

  Future<void> _startManualMode() async {
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
  }

  void _handleManualTap(int r, int c) {
    if (_isPaused) return;
    String key = "$r,$c";
    setState(() {
      int current = _manualGrid[key] ?? 0;
      _manualGrid[key] = (current + 1) % 3;
      _updateQueenPositionsFromManual();
    });
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

      _queenPositions.values.forEach((p) {
        int r = p.x - 1;
        int c = p.y - 1;
        int regId = widget.boardData.regionIds[r][c];

        rows[r] = (rows[r] ?? 0) + 1;
        cols[c] = (cols[c] ?? 0) + 1;
        regions[regId] = (regions[regId] ?? 0) + 1;

        if (rows[r]! > 1 || cols[c]! > 1 || regions[regId]! > 1) conflict = true;
        
        _queenPositions.values.forEach((p2) {
          if (p == p2) return;
          if ((p.x - p2.x).abs() <= 1 && (p.y - p2.y).abs() <= 1) conflict = true;
        });
      });

      if (!conflict && regions.length == widget.boardData.size) {
        _timer?.cancel();
        
        widget.boardData.isManuallySolved = true;
        if (_isSaved && widget.boardId != null) {
          StorageManager.updateBoard(widget.boardId!, widget.boardData);
        } else {
          // Auto-save if not already saved in library
          StorageManager.saveBoard(widget.boardData).then((_) {
            if (mounted) {
              setState(() => _isSaved = true);
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

      widget.boardData.regions.clear();
      widget.boardData.regions.addAll(newRegions);
      widget.boardData.solution = null;
      _queenPositions.clear();
      _solverSteps.clear();

      if (widget.isAlreadySaved && widget.boardId != null) {
        StorageManager.updateBoard(widget.boardId!, widget.boardData);
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
                      onTogglePause: _togglePause,
                      onQuitManual: () => setState(() { _isManualMode = false; _timer?.cancel(); }),
                      onToggleEdit: _toggleEditMode,
                      onSolve: _startSolving,
                      onSaveEdits: _saveEdits,
                      onStartManual: _startManualMode,
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
        if (!_isSaved)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Transform.rotate(
              angle: 0.01,
              child: Container(
                width: double.infinity,
                height: 65,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.1), offset: const Offset(4, 4))], border: Border.all(color: AppColors.navyBlue.withOpacity(0.3), width: 1.5)),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await StorageManager.saveBoard(widget.boardData);
                    if (mounted) {
                      setState(() => _isSaved = true);
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
            decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(5, 5))], border: Border.all(color: AppColors.navyBlue, width: 2.5)),
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
