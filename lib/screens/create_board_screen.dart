import 'package:flutter/material.dart';
import '../widgets/error_dialog.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../constants/region_colors.dart';
import '../utils/storage_manager.dart';
import '../widgets/notebook_painter.dart';
import 'n_queens_board.dart';

class CreateBoardScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CreateBoardScreen({super.key, required this.cameras});

  @override
  State<CreateBoardScreen> createState() => _CreateBoardScreenState();
}

class _CreateBoardScreenState extends State<CreateBoardScreen> {
  int _size = 8;
  int _currentStep = 0;
  List<List<int>>? _grid;
  int? _selectedRegionId;

  void _initializeGrid() {
    _grid = List.generate(_size, (_) => List.generate(_size, (_) => 0));
    setState(() {
      _currentStep = 1;
      _selectedRegionId = 1;
    });
  }

  void _handleCellTap(int r, int c) {
    if (_selectedRegionId == null) return;
    setState(() {
      _grid![r][c] = _selectedRegionId!;
    });
  }

  Future<void> _saveAndOpen() async {
    // 1. Validate: Every cell must have a region
    bool allFilled = _grid!.every((row) => row.every((id) => id != 0));
    if (!allFilled) {
      FunkyErrorDialog.show(context,
        title: 'Hold on!',
        message: 'Every cell needs a region color! Paint all the empty cells before saving.',
      );
      return;
    }

    // Build regions map for validation and saving
    final regions = <int, BoardRegion>{};
    for (int r = 0; r < _size; r++) {
      for (int c = 0; c < _size; c++) {
        final id = _grid![r][c];
        final color = RegionColors.getRegionColor(id, _size);
        regions.putIfAbsent(id, () => BoardRegion(id: id, color: color, coordinates: [])).coordinates.add(Point(r + 1, c + 1));
      }
    }

    // 2. Validate: Every region must be contiguous (connected)
    for (var entry in regions.entries) {
      if (!_isRegionContiguous(entry.value)) {
        FunkyErrorDialog.show(context,
          title: 'Disconnected!',
          message: 'Region ${entry.key} is split apart! Each region must be one connected group.',
        );
        return;
      }
    }

    final board = BoardData(
      size: _size, 
      regionIds: List.generate(_size, (r) => List.from(_grid![r])), 
      regions: regions,
      rawResponse: "Manually Created Board",
    );
    final id = await StorageManager.saveBoard(board, name: 'Custom ${_size}x$_size');
    
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => NQueensBoardScreen(boardData: board, isAlreadySaved: true, boardId: id)));
    }
  }

  bool _isRegionContiguous(BoardRegion region) {
    if (region.coordinates.isEmpty) return true;

    final Set<String> regionPoints = region.coordinates.map((p) => "${p.x},${p.y}").toSet();
    final List<Point> queue = [region.coordinates.first];
    final Set<String> visited = {"${queue.first.x},${queue.first.y}"};

    int index = 0;
    while (index < queue.length) {
      final current = queue[index++];
      
      final neighbors = [
        Point(current.x + 1, current.y),
        Point(current.x - 1, current.y),
        Point(current.x, current.y + 1),
        Point(current.x, current.y - 1),
      ];

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _currentStep == 0 ? _buildSizeSelector() : _buildRegionPainter()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Text(_currentStep == 0 ? 'Create Board' : 'Define Regions', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)),
    );
  }

  Widget _buildSizeSelector() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Choose Board Size (N)', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 22, color: AppColors.navyBlue)),
            const SizedBox(height: 40),
            Text('$_size x $_size', style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 48, color: AppColors.navyBlue, fontWeight: FontWeight.bold)),
            Slider(
              value: _size.toDouble(),
              min: 4,
              max: 12,
              divisions: 8,
              activeColor: AppColors.gold,
              onChanged: (val) => setState(() => _size = val.toInt()),
            ),
            const SizedBox(height: 60),
            Row(
              children: [
                _buildFunkyBack(() => Navigator.pop(context)),
                const SizedBox(width: 16),
                Expanded(child: _buildActionBtn('Next Step', _initializeGrid)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionPainter() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(_size, (i) => _buildPaletteItem(i + 1)),
          ),
        ),
        const SizedBox(height: 40),
        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.navyBlue, width: 3),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(8, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _size),
                    itemCount: _size * _size,
                    itemBuilder: (context, index) {
                      int r = index ~/ _size;
                      int c = index % _size;
                      int id = _grid![r][c];
                      Color color = RegionColors.getRegionColor(id, _size);
                      return GestureDetector(
                        onTap: () => _handleCellTap(r, c),
                        child: Container(
                          decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5)),
                          child: id > 0 
                            ? Center(
                                child: Text(
                                  '$id', 
                                  style: TextStyle(
                                    fontFamily: 'DynaPuff', 
                                    fontSize: (MediaQuery.of(context).size.width * 0.8 * 0.3) / _size, 
                                    color: Colors.black.withValues(alpha: 0.15), 
                                    fontWeight: FontWeight.bold
                                  )
                                )
                              ) 
                            : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              _buildFunkyBack(() => setState(() => _currentStep = 0)),
              const SizedBox(width: 16),
              Expanded(child: _buildActionBtn('Save & Solve', _saveAndOpen)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFunkyBack(VoidCallback onTap) {
    return Transform.rotate(
      angle: 0.05,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 65,
          height: 65,
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.navyBlue, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.navyBlue.withValues(alpha: 0.3),
                offset: const Offset(5, 5),
                blurRadius: 0,
              )
            ],
          ),
          child: const Icon(Icons.arrow_back_rounded, color: AppColors.navyBlue, size: 32),
        ),
      ),
    );
  }

  Widget _buildPaletteItem(int id) {
    bool isSelected = _selectedRegionId == id;
    Color color = RegionColors.getRegionColor(id, _size);
    return GestureDetector(
      onTap: () => setState(() => _selectedRegionId = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? AppColors.navyBlue : Colors.white, width: isSelected ? 3 : 2),
          boxShadow: [if (isSelected) BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), blurRadius: 8)],
        ),
        child: Center(child: Text('$id', style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? AppColors.navyBlue : Colors.black54))),
      ),
    );
  }

  Widget _buildActionBtn(String label, VoidCallback onTap) {
    return Transform.rotate(
      angle: -0.02,
      child: Container(
        width: double.infinity,
        height: 65,
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(5, 5))],
          border: Border.all(color: AppColors.navyBlue, width: 2),
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: AppColors.navyBlue, shadowColor: Colors.transparent, elevation: 0),
          child: Text(label, style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20)),
        ),
      ),
    );
  }
}
