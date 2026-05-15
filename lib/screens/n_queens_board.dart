import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../widgets/error_dialog.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../constants/region_colors.dart';
import '../utils/solver_logic.dart';
import '../utils/storage_manager.dart';
import '../widgets/notebook_painter.dart';

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
  int? _lastSwipedR, _lastSwipedC;

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

    // Check for invalid regions (ID > N)
    bool hasInvalidRegions = false;
    for (int r = 0; r < widget.boardData.size; r++) {
      for (int c = 0; c < widget.boardData.size; c++) {
        if (widget.boardData.regionIds[r][c] > widget.boardData.size) {
          hasInvalidRegions = true;
          break;
        }
      }
    }

    if (hasInvalidRegions) {
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
        // Very tiny delay to allow UI to breathe but feel "instant"
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }
    setState(() {
      _isSolving = false;
      _isFastForward = false;
      // Automatically save the solution to the board data and storage if successful
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

    // 1. Check for solvability (silent)
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

    // 2. Initialize Manual Mode
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

  void _handleManualSwipe(int r, int c) {
    if (_isPaused || (_lastSwipedR == r && _lastSwipedC == c)) return;
    _lastSwipedR = r;
    _lastSwipedC = c;
    String key = "$r,$c";
    setState(() {
      // Swipe only marks X
      if ((_manualGrid[key] ?? 0) != 2) {
        _manualGrid[key] = 1;
      }
    });
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
      // Check if all queens follow rules
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
        
        // Neighborhood check
        _queenPositions.values.forEach((p2) {
          if (p == p2) return;
          if ((p.x - p2.x).abs() <= 1 && (p.y - p2.y).abs() <= 1) conflict = true;
        });
      });

      if (!conflict && regions.length == widget.boardData.size) {
        _timer?.cancel();
        
        // Mark as manually solved and save
        widget.boardData.isManuallySolved = true;
        if (widget.isAlreadySaved && widget.boardId != null) {
          StorageManager.updateBoard(widget.boardId!, widget.boardData);
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => VictoryDialog(time: formatTime(_secondsElapsed)),
        );
      }
    }
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

      // Clear previous solution as the board configuration has changed
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
                    _buildHeader(),
                    const SizedBox(height: 30),
                    if (_isEditing) _buildPalette(),
                    const SizedBox(height: 20),
                    _buildMainBoard(boardScale),
                    const SizedBox(height: 30),
                    _buildActionButtons(),
                    if (!_isManualMode) ...[
                      const SizedBox(height: 30),
                      if (!_isEditing && _solverSteps.isNotEmpty) _buildAlgorithmFlow(),
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

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Transform.rotate(
          angle: 0.02,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.navyBlue, width: 2), boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(4, 4))]),
            child: Text(
              _isManualMode 
                  ? (_isPaused ? 'Paused' : 'Solving...')
                  : (_isEditing ? 'Correcting Regions...' : 'N-Queens Board'), 
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24, fontFamily: 'DynaPuff')
            ),
          ),
        ),
        if (_isManualMode)
          Transform.rotate(
            angle: -0.01,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.navyBlue, width: 2), boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(4, 4))]),
              child: Text(
                formatTime(_secondsElapsed),
                style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
              ),
            ),
          ),
        if (_isSolving) ...[
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => setState(() => _isFastForward = true),
            icon: Icon(
              Icons.fast_forward_rounded, 
              color: _isFastForward ? AppColors.gold : AppColors.navyBlue, 
              size: 32
            ),
            tooltip: 'Fast Forward Solution',
          ),
        ],
      ],
    );
  }

  Widget _buildPalette() {
    return Center(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: List.generate(widget.boardData.size, (i) => _buildPaletteItem(i + 1)),
      ),
    );
  }

  Widget _buildPaletteItem(int id) {
    bool isSelected = _selectedRegionId == id;
    Color color = RegionColors.getRegionColor(id, widget.boardData.size);
    return GestureDetector(
      onTap: () => setState(() => _selectedRegionId = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? AppColors.navyBlue : Colors.white, width: isSelected ? 3 : 1.5),
          boxShadow: [if (isSelected) BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), blurRadius: 8)],
        ),
        child: Center(child: Text('$id', style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? AppColors.navyBlue : Colors.black54, fontSize: 12))),
      ),
    );
  }

  Widget _buildMainBoard(double boardScale) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _isEditing ? AppColors.gold : AppColors.navyBlue, width: 3), boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(8, 8))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * boardScale,
            height: MediaQuery.of(context).size.width * boardScale,
            child: GestureDetector(
              onPanUpdate: _isManualMode ? (details) {
                RenderBox box = context.findRenderObject() as RenderBox;
                Offset localOffset = box.globalToLocal(details.globalPosition);
                // Adjust for padding and container
                double cellSize = (MediaQuery.of(context).size.width * boardScale) / widget.boardData.size;
                int c = (localOffset.dx / cellSize).floor();
                int r = (localOffset.dy / cellSize).floor();
                if (r >= 0 && r < widget.boardData.size && c >= 0 && c < widget.boardData.size) {
                  _handleManualSwipe(r, c);
                }
              } : null,
              onPanEnd: _isManualMode ? (_) => setState(() { _lastSwipedR = null; _lastSwipedC = null; }) : null,
              child: GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.boardData.size),
                itemCount: widget.boardData.size * widget.boardData.size,
                itemBuilder: (context, index) {
                  int r = index ~/ widget.boardData.size;
                  int c = index % widget.boardData.size;
                  
                  bool hasQueen = _isManualMode 
                      ? (_manualGrid["$r,$c"] == 2)
                      : _queenPositions.values.any((p) => p.x - 1 == r && p.y - 1 == c);
                  
                  bool hasX = _isManualMode && (_manualGrid["$r,$c"] == 1);
                  
                  int id = _isEditing ? _tempGrid![r][c] : widget.boardData.regionIds[r][c];
                  bool isInvalid = id > widget.boardData.size;
  
                  return GestureDetector(
                    onTap: _isManualMode ? () => _handleManualTap(r, c) : () => _handleCellTap(r, c),
                    child: Container(
                      decoration: BoxDecoration(
                        color: RegionColors.getRegionColor(id, widget.boardData.size), 
                        border: Border.all(color: Colors.black.withOpacity(0.05), width: 0.5)
                      ),
                      child: Stack(
                        children: [
                          if (hasQueen) 
                            Center(child: Icon(Icons.stars_rounded, color: AppColors.navyBlue, size: (MediaQuery.of(context).size.width * boardScale * 0.8) / widget.boardData.size)),
                          if (hasX)
                            Center(child: Text('x', style: TextStyle(fontFamily: 'Comfortaa', fontSize: (MediaQuery.of(context).size.width * boardScale * 0.5) / widget.boardData.size, color: AppColors.navyBlue.withOpacity(0.4), fontWeight: FontWeight.bold))),
                          if (!hasQueen && !hasX && isInvalid)
                            Center(
                              child: Transform.rotate(
                                angle: 0.1,
                                child: Icon(
                                  Icons.close_rounded, 
                                  color: AppColors.navyBlue.withOpacity(0.3), 
                                  size: (MediaQuery.of(context).size.width * boardScale * 0.6) / widget.boardData.size
                                ),
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
      ),
    );
  }

  Widget _buildActionButtons() {
    bool hasConflicts = false;
    for (int r = 0; r < widget.boardData.size; r++) {
      for (int c = 0; c < widget.boardData.size; c++) {
        if (widget.boardData.regionIds[r][c] > widget.boardData.size) {
          hasConflicts = true;
          break;
        }
      }
    }

    bool canSolve = !hasConflicts && !_isSolving && !_isEditing && !_isManualMode;

    return Column(
      children: [
        if (_isManualMode) ...[
          Transform.rotate(
            angle: 0.01,
            child: Container(
              width: double.infinity,
              height: 65,
              decoration: BoxDecoration(
                color: _isPaused ? AppColors.gold : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(4, 4))],
              ),
              child: ElevatedButton.icon(
                onPressed: _togglePause,
                icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: AppColors.navyBlue),
                label: Text(
                  _isPaused ? 'Resume (${formatTime(_secondsElapsed)})' : 'Pause',
                  style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Transform.rotate(
            angle: -0.01,
            child: Container(
              width: double.infinity,
              height: 65,
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.redAccent, width: 2),
              ),
              child: ElevatedButton.icon(
                onPressed: () => setState(() { _isManualMode = false; _timer?.cancel(); }),
                icon: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
                label: const Text('Quit Manual Mode', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.redAccent)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
              ),
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Transform.rotate(
                  angle: 0.02,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.navyBlue, width: 2), boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(4, 4))]),
                    child: ElevatedButton.icon(
                      onPressed: _isSolving ? null : _toggleEditMode,
                      icon: Icon(_isEditing ? Icons.close_rounded : Icons.edit_note_rounded, color: _isEditing ? Colors.red : AppColors.navyBlue),
                      label: Text(_isEditing ? 'Cancel' : 'Edit', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: _isEditing ? Colors.red : AppColors.navyBlue)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Transform.rotate(
                  angle: -0.01,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: _isSolving 
                          ? Colors.grey.shade300 
                          : (hasConflicts ? Colors.grey.shade200 : AppColors.gold), 
                      borderRadius: BorderRadius.circular(15), 
                      border: Border.all(color: AppColors.navyBlue.withOpacity(hasConflicts ? 0.3 : 1.0), width: 2), 
                      boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(hasConflicts ? 0.05 : 0.2), offset: const Offset(4, 4))]
                    ),
                    child: ElevatedButton.icon(
                      onPressed: canSolve ? _startSolving : (_isEditing ? _saveEdits : null),
                      icon: _isSolving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyBlue)) 
                          : Icon(_isEditing ? Icons.check_circle_rounded : Icons.auto_fix_high_rounded, color: AppColors.navyBlue.withOpacity(hasConflicts && !_isEditing ? 0.4 : 1.0)),
                      label: Text(_isSolving ? 'Solving...' : (_isEditing ? 'Save' : 'Solve'), style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue.withOpacity(hasConflicts && !_isEditing ? 0.4 : 1.0))),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Transform.rotate(
            angle: 0.01,
            child: Container(
              width: double.infinity,
              height: 65,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(4, 4))],
              ),
              child: ElevatedButton.icon(
                onPressed: canSolve ? _startManualMode : null,
                icon: Icon(Icons.videogame_asset_rounded, color: canSolve ? AppColors.navyBlue : Colors.grey),
                label: Text(
                  'Do it',
                  style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20, color: canSolve ? AppColors.navyBlue : Colors.grey),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
              ),
            ),
          ),
        ],
        if (hasConflicts && !_isEditing && !_isManualMode) ...[
          const SizedBox(height: 24),
          _buildFunkyConflictPrompt(),
        ],
      ],
    );
  }

  Widget _buildFunkyConflictPrompt() {
    return Transform.rotate(
      angle: -0.01,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9C4), // Soft Lemon Yellow
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.gold, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4))],
        ),
        child: const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: AppColors.navyBlue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "Whoops! Some regions are messy. Tap 'Edit' to fix the Funky-X marks!",
                style: TextStyle(fontFamily: 'DynaPuff', fontSize: 14, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlgorithmFlow() {
    return Transform.rotate(
      angle: 0.01,
      child: Container(
        width: double.infinity,
        height: 450,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: AppColors.navyBlue.withOpacity(0.5), width: 2.5), boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.1), offset: const Offset(6, 6))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.history_edu_rounded, color: AppColors.navyBlue), SizedBox(width: 10), Text('Solving Timeline', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, color: AppColors.navyBlue, fontSize: 20))]),
            const Divider(thickness: 1.5),
            Expanded(child: ListView.builder(controller: _logScrollController, itemCount: _solverSteps.length, itemBuilder: (context, index) => _buildStepItem(_solverSteps[index]))),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(SolverStep step) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(15), border: Border.all(color: step.isBacktrack ? Colors.red.withOpacity(0.3) : AppColors.navyBlue.withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), offset: const Offset(2, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.navyBlue, width: 2), borderRadius: BorderRadius.circular(8)),
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.boardData.size),
                  itemCount: widget.boardData.size * widget.boardData.size,
                  itemBuilder: (context, i) {
                    int r = i ~/ widget.boardData.size;
                    int c = i % widget.boardData.size;
                    bool hasQueen = step.queenPositions.values.any((p) => p.x - 1 == r && p.y - 1 == c);
                    bool isValidDomain = false;
                    for (var entry in widget.boardData.regions.entries) {
                      if (entry.value.coordinates.any((p) => p.x - 1 == r && p.y - 1 == c)) {
                        isValidDomain = step.domains[entry.key]?.any((p) => p.x - 1 == r && p.y - 1 == c) ?? false;
                        break;
                      }
                    }
                    Color cellColor = RegionColors.getRegionColor(widget.boardData.regionIds[r][c], widget.boardData.size);
                    return Container(
                      decoration: BoxDecoration(
                        color: isValidDomain ? cellColor : cellColor.withOpacity(0.15), 
                        border: Border.all(color: Colors.black.withOpacity(0.03), width: 0.2)
                      ), 
                      child: hasQueen ? const Center(child: Icon(Icons.stars_rounded, size: 10, color: AppColors.navyBlue)) : null
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.isBacktrack ? "RETREATING" : "ACTION", style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: step.isBacktrack ? Colors.red : Colors.green, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(step.message, style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.darkText, height: 1.4, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
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
                      // ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Board saved to library!')));
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

class VictoryDialog extends StatelessWidget {
  final String time;
  const VictoryDialog({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.navyBlue, width: 3),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(8, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 200,
              child: Lottie.asset(
                'assets/json/trophy.json',
                repeat: true,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'VICTORY!',
              style: TextStyle(fontFamily: 'DynaPuff', fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
            ),
            const SizedBox(height: 10),
            Text(
              'You mastered the board in $time!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.darkText),
            ),
            const SizedBox(height: 30),
            Transform.rotate(
              angle: -0.02,
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(4, 4))],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Back to Library
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
                  child: const Text(
                    'CELEBRATE & EXIT',
                    style: TextStyle(fontFamily: 'DynaPuff', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
