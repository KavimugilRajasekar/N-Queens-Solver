import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../utils/solver_logic.dart';
import '../widgets/notebook_painter.dart';

class ResultScreen extends StatefulWidget {
  final BoardData boardData;

  const ResultScreen({super.key, required this.boardData});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Map<int, Point> _queenPositions = {};
  final List<SolverStep> _solverSteps = [];
  bool _isSolving = false;
  bool _isEditing = false;
  List<List<Color>>? _tempGrid;
  Point? _selectedCell;
  final ScrollController _logScrollController = ScrollController();

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

    setState(() {
      _isSolving = true;
      _queenPositions.clear();
      _solverSteps.clear();
    });

    final solver = NQueensSolver(widget.boardData);
    
    await for (final step in solver.solve()) {
      setState(() {
        _queenPositions = step.queenPositions;
        _solverSteps.add(step);
      });
      _scrollToBottom();
      int delay = step.isBacktrack ? 400 : 600;
      await Future.delayed(Duration(milliseconds: delay));
    }

    setState(() {
      _isSolving = false;
    });
  }

  void _toggleEditMode() {
    setState(() {
      if (!_isEditing) {
        _isEditing = true;
        _selectedCell = null;
        _tempGrid = List.generate(widget.boardData.size, (r) => List.from(widget.boardData.grid[r]));
      } else {
        _isEditing = false;
        _tempGrid = null;
        _selectedCell = null;
      }
    });
  }

  void _saveEdits() {
    if (_tempGrid != null) {
      for (int r = 0; r < widget.boardData.size; r++) {
        for (int c = 0; c < widget.boardData.size; c++) {
          widget.boardData.grid[r][c] = _tempGrid![r][c];
        }
      }

      final Map<Color, List<Point>> colorToPoints = {};
      for (int r = 0; r < widget.boardData.size; r++) {
        for (int c = 0; c < widget.boardData.size; c++) {
          Color cellColor = widget.boardData.grid[r][c];
          if (cellColor != Colors.white) {
            colorToPoints.putIfAbsent(cellColor, () => []).add(Point(r + 1, c + 1));
          }
        }
      }

      final newRegions = <int, BoardRegion>{};
      widget.boardData.regions.forEach((id, originalRegion) {
        final newCoords = colorToPoints[originalRegion.color] ?? [];
        newRegions[id] = BoardRegion(id: id, color: originalRegion.color, coordinates: newCoords);
      });

      widget.boardData.regions.clear();
      widget.boardData.regions.addAll(newRegions);
    }
    setState(() {
      _isEditing = false;
      _tempGrid = null;
      _selectedCell = null;
    });
  }

  void _handleCellTap(int r, int c) {
    if (!_isEditing) return;
    setState(() {
      if (_selectedCell != null) {
        int sr = _selectedCell!.x - 1;
        int sc = _selectedCell!.y - 1;
        bool isNeighbor = (r == sr && (c == sc - 1 || c == sc + 1)) || (c == sc && (r == sr - 1 || r == sr + 1));
        if (isNeighbor) {
          _tempGrid![r][c] = _tempGrid![sr][sc];
          _selectedCell = Point(r + 1, c + 1);
        } else {
          _selectedCell = Point(r + 1, c + 1);
        }
      } else {
        _selectedCell = Point(r + 1, c + 1);
      }
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 30),
                  _buildMainBoard(boardScale),
                  const SizedBox(height: 30),
                  _buildActionButtons(),
                  const SizedBox(height: 30),
                  if (!_isEditing && _solverSteps.isNotEmpty) _buildAlgorithmFlow(),
                  const SizedBox(height: 30),
                  if (!_isEditing) _buildScanAnotherButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Transform.rotate(
      angle: 0.02,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.navyBlue, width: 2),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(4, 4))],
        ),
        child: Text(
          _isEditing ? 'Editing Board...' : 'N-Queens Board',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24, fontFamily: 'DynaPuff'),
        ),
      ),
    );
  }

  Widget _buildMainBoard(double boardScale) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isEditing ? AppColors.gold : AppColors.navyBlue, width: 3),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(8, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * boardScale,
            height: MediaQuery.of(context).size.width * boardScale,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.boardData.size),
              itemCount: widget.boardData.size * widget.boardData.size,
              itemBuilder: (context, index) {
                int r = index ~/ widget.boardData.size;
                int c = index % widget.boardData.size;
                bool isSelected = _selectedCell != null && _selectedCell!.x - 1 == r && _selectedCell!.y - 1 == c;
                bool hasQueen = _queenPositions.values.any((p) => p.x - 1 == r && p.y - 1 == c);

                return GestureDetector(
                  onTap: () => _handleCellTap(r, c),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isEditing ? _tempGrid![r][c] : widget.boardData.grid[r][c],
                      border: Border.all(color: isSelected ? Colors.black : Colors.black.withOpacity(0.05), width: isSelected ? 2 : 0.5),
                    ),
                    child: hasQueen ? Center(child: Icon(Icons.stars_rounded, color: AppColors.navyBlue, size: (MediaQuery.of(context).size.width * boardScale * 0.8) / widget.boardData.size)) : null,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: Transform.rotate(
            angle: 0.02,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(4, 4))],
              ),
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
                color: _isSolving ? Colors.grey.shade300 : AppColors.gold,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(4, 4))],
              ),
              child: ElevatedButton.icon(
                onPressed: _isSolving ? null : (_isEditing ? _saveEdits : _startSolving),
                icon: _isSolving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyBlue)) : Icon(_isEditing ? Icons.check_circle_rounded : Icons.auto_fix_high_rounded, color: AppColors.navyBlue),
                label: Text(_isSolving ? 'Solving...' : (_isEditing ? 'Save' : 'Solve'), style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlgorithmFlow() {
    return Transform.rotate(
      angle: 0.01,
      child: Container(
        width: double.infinity,
        height: 450, 
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.navyBlue.withOpacity(0.5), width: 2.5),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.1), offset: const Offset(6, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history_edu_rounded, color: AppColors.navyBlue),
                SizedBox(width: 10),
                Text('Solving Timeline', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, color: AppColors.navyBlue, fontSize: 20)),
              ],
            ),
            const Divider(thickness: 1.5),
            Expanded(
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _solverSteps.length,
                itemBuilder: (context, index) => _buildStepItem(_solverSteps[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(SolverStep step) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: step.isBacktrack ? Colors.red.withOpacity(0.3) : AppColors.navyBlue.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), offset: const Offset(2, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Large Miniature Board
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.boardData.size),
                  itemCount: widget.boardData.size * widget.boardData.size,
                  itemBuilder: (context, i) {
                    int r = i ~/ widget.boardData.size;
                    int c = i % widget.boardData.size;
                    
                    bool hasQueen = step.queenPositions.values.any((p) => p.x - 1 == r && p.y - 1 == c);
                    
                    // Confinement / Reduction Logic:
                    // Check if this cell is still in the domain of its region
                    bool isValidDomain = false;
                    for (var entry in widget.boardData.regions.entries) {
                      if (entry.value.coordinates.any((p) => p.x - 1 == r && p.y - 1 == c)) {
                        isValidDomain = step.domains[entry.key]?.any((p) => p.x - 1 == r && p.y - 1 == c) ?? false;
                        break;
                      }
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: isValidDomain 
                            ? widget.boardData.grid[r][c] 
                            : widget.boardData.grid[r][c].withOpacity(0.15), // Grey out reduced cells
                        border: Border.all(color: Colors.black.withOpacity(0.03), width: 0.2),
                      ),
                      child: hasQueen ? const Center(child: Icon(Icons.stars_rounded, size: 10, color: AppColors.navyBlue)) : null,
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              // Narrative Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.isBacktrack ? "RETREATING" : "ACTION",
                      style: TextStyle(
                        fontFamily: 'DynaPuff',
                        fontSize: 10,
                        color: step.isBacktrack ? Colors.red : Colors.green,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.message,
                      style: TextStyle(
                        fontFamily: 'Comfortaa',
                        fontSize: 13,
                        color: AppColors.darkText,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanAnotherButton() {
    return Transform.rotate(
      angle: -0.02,
      child: Container(
        width: double.infinity,
        height: 65,
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(5, 5))],
          border: Border.all(color: AppColors.navyBlue, width: 2.5),
        ),
        child: ElevatedButton.icon(
          onPressed: _isSolving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.refresh_rounded, size: 28),
          label: const Text('Scan Another', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: AppColors.navyBlue, shadowColor: Colors.transparent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        ),
      ),
    );
  }
}
