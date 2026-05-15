import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../utils/storage_manager.dart';
import '../widgets/notebook_painter.dart';
import 'camera_screen.dart';
import 'create_board_screen.dart';
import 'n_queens_board.dart';

class SavedBoardsScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const SavedBoardsScreen({super.key, required this.cameras});

  @override
  State<SavedBoardsScreen> createState() => _SavedBoardsScreenState();
}

class _SavedBoardsScreenState extends State<SavedBoardsScreen> {
  List<Map<String, dynamic>> _savedBoards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshBoards();
  }

  Future<void> _refreshBoards() async {
    setState(() => _isLoading = true);
    final boards = await StorageManager.loadBoards();
    setState(() {
      _savedBoards = boards;
      _isLoading = false;
    });
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 30),
            _buildOptionCard(
              icon: Icons.camera_alt_rounded,
              title: 'Start Scanning',
              subtitle: 'Digitize a physical board',
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context, MaterialPageRoute(builder: (context) => CameraScreen(camera: widget.cameras.first)));
                _refreshBoards();
              },
            ),
            const SizedBox(height: 16),
            _buildOptionCard(
              icon: Icons.create_rounded,
              title: 'Create Board',
              subtitle: 'Build a custom NxN puzzle',
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context, MaterialPageRoute(builder: (context) => CreateBoardScreen(cameras: widget.cameras)));
                _refreshBoards();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue.withOpacity(0.1), width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.navyBlue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue)),
                  Text(subtitle, style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.secondaryText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Board Library', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
                ),
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: AppColors.navyBlue))
                    : _savedBoards.isEmpty 
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _savedBoards.length,
                          itemBuilder: (context, index) => _buildBoardCard(_savedBoards[index]),
                        ),
                ),
                _buildAddButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_rounded, size: 80, color: AppColors.navyBlue.withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text('Your library is empty', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 20, color: AppColors.secondaryText)),
          const Text('Scan or create your first board!', style: TextStyle(fontFamily: 'Comfortaa', color: AppColors.secondaryText)),
        ],
      ),
    );
  }

  Widget _buildBoardCard(Map<String, dynamic> data) {
    final BoardData board = data['board'];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.navyBlue.withOpacity(0.2), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.05), offset: const Offset(4, 4))],
      ),
      child: Stack(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.background, 
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.navyBlue.withOpacity(0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: board.size),
                  itemCount: board.size * board.size,
                  itemBuilder: (context, i) {
                    int r = i ~/ board.size;
                    int c = i % board.size;
                    int id = board.regionIds[r][c];
                    return Container(color: id == 0 ? Colors.white : BoardProcessor.getRegionColor(id));
                  },
                ),
              ),
            ),
            title: Text(data['name'], style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text('${board.size}x${board.size} • ${data['date'].year}-${data['date'].month.toString().padLeft(2, '0')}-${data['date'].day.toString().padLeft(2, '0')}', style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 12)),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (context) => NQueensBoardScreen(boardData: board, isAlreadySaved: true, boardId: data['id'])));
              _refreshBoards();
            },
          ),
          // Action Buttons at Bottom Right
          Positioned(
            bottom: 4,
            right: 4,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.navyBlue, size: 18),
                  onPressed: () => _showRenameDialog(data['id'], data['name']),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                  onPressed: () => _confirmDelete(data['id']),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(int id, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Board', style: TextStyle(fontFamily: 'DynaPuff')),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontFamily: 'Comfortaa'),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await StorageManager.renameBoard(id, controller.text);
                Navigator.pop(context);
                _refreshBoards();
              }
            }, 
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Board?', style: TextStyle(fontFamily: 'DynaPuff')),
        content: const Text('This action cannot be undone.', style: TextStyle(fontFamily: 'Comfortaa')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await StorageManager.deleteBoard(id);
              Navigator.pop(context);
              _refreshBoards();
            }, 
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        children: [
          // Funky Home Sticker
          Transform.rotate(
            angle: 0.05,
            child: GestureDetector(
              onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD), // Soft Light Blue
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.navyBlue, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navyBlue.withOpacity(0.3), 
                      offset: const Offset(5, 5),
                      blurRadius: 0, // Sharp shadow for sticker look
                    )
                  ],
                ),
                child: const Icon(Icons.home_rounded, color: AppColors.navyBlue, size: 32),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Add Board Button
          Expanded(
            child: Transform.rotate(
              angle: -0.02,
              child: Container(
                height: 65,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(5, 5))],
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                ),
                child: ElevatedButton.icon(
                  onPressed: _showAddOptions,
                  icon: const Icon(Icons.add_rounded, size: 28),
                  label: const Text('Add Board', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: AppColors.navyBlue, shadowColor: Colors.transparent, elevation: 0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
