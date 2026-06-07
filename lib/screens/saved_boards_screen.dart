import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:convert';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../utils/storage_manager.dart';
import '../widgets/notebook_painter.dart';
import 'camera_screen.dart';
import 'create_board_screen.dart';
import 'qr_scanner_screen.dart';
import '../widgets/library/board_card.dart';
import '../widgets/library/qr_share_dialog.dart';

import '../widgets/error_dialog.dart';
import 'generate_board_screen.dart';
import '../utils/qr_crypto.dart';
import 'package:shake/shake.dart';

class SavedBoardsScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const SavedBoardsScreen({super.key, required this.cameras});

  @override
  State<SavedBoardsScreen> createState() => _SavedBoardsScreenState();
}

class _SavedBoardsScreenState extends State<SavedBoardsScreen> {
  List<Map<String, dynamic>> _savedBoards = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  final List<int> _selectedIds = [];
  bool _isRenameMode = false;
  ShakeDetector? _shakeDetector;

  @override
  void initState() {
    super.initState();
    _refreshBoards();
    
    // Initialize Shake detector
    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: (_) {
        if (!_isSelectionMode) {
          setState(() => _isRenameMode = !_isRenameMode);
          
          // Provide Haptic Feedback
          Feedback.forLongPress(context);
          
          // Visual confirmation
          ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Remove existing if any
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isRenameMode ? 'Switch to ✏️' : 'Switch to 🗑️', 
                style: const TextStyle(fontFamily: 'DynaPuff', color: Colors.white, fontSize: 16)),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.navyBlue,
              margin: const EdgeInsets.only(bottom: 105, left: 40, right: 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: Colors.white24, width: 1),
              ),
            ),
          );
        }
      },
      shakeThresholdGravity: 2.5, // Increased threshold (harder to trigger)
      minimumShakeCount: 2,      // Requires a double-shake motion
    );
  }

  @override
  void dispose() {
    _shakeDetector?.stopListening();
    super.dispose();
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
    bool showScanSubOptions = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
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
              // Dynamic Scanning Option
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: showScanSubOptions ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: _buildOptionCard(
                  icon: Icons.camera_alt_rounded,
                  title: 'Start Scanning',
                  subtitle: 'Digitize a physical board',
                  onTap: () => setSheetState(() => showScanSubOptions = true),
                ),
                secondChild: Transform.rotate(
                  angle: -0.01,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.navyBlue.withValues(alpha: 0.1), width: 2),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt_rounded, color: AppColors.navyBlue, size: 24),
                        ),
                        const SizedBox(width: 16),
                        const Text('Scanning', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue)),
                        const Spacer(),
                        _buildMiniSubOption(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'QR',
                          angle: 0.08,
                          onTap: () async {
                            Navigator.pop(context);
                            final result = await Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (context) => const QRScannerScreen())
                            );
                            if (result == true) _refreshBoards();
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildMiniSubOption(
                          icon: Icons.photo_camera_rounded,
                          label: 'Camera',
                          angle: -0.05,
                          onTap: () async {
                            Navigator.pop(context);
                            await Navigator.push(context, MaterialPageRoute(builder: (context) => CameraScreen(camera: widget.cameras.first)));
                            _refreshBoards();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
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
              const SizedBox(height: 16),
              _buildOptionCard(
                icon: Icons.auto_awesome_rounded,
                title: 'Generate a Board',
                subtitle: 'Randomly generate solvable puzzle',
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(context, MaterialPageRoute(builder: (context) => const GenerateBoardScreen()));
                  _refreshBoards();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniSubOption({required IconData icon, required String label, required VoidCallback onTap, double angle = 0.0}) {
    return Transform.rotate(
      angle: angle,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navyBlue.withValues(alpha: 0.2),
                    offset: const Offset(4, 4),
                    blurRadius: 0,
                  )
                ],
              ),
              child: Icon(icon, color: AppColors.navyBlue, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              label, 
              style: const TextStyle(
                fontFamily: 'DynaPuff', 
                fontSize: 12, 
                fontWeight: FontWeight.bold, 
                color: AppColors.navyBlue
              )
            ),
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
          border: Border.all(color: AppColors.navyBlue.withValues(alpha: 0.1), width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(4, 4))],
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Board Library', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32)),
                      Transform.rotate(
                        angle: 0.1,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSelectionMode = !_isSelectionMode;
                              if (!_isSelectionMode) _selectedIds.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.navyBlue, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.navyBlue.withValues(alpha: 0.3),
                                  offset: const Offset(3, 3),
                                  blurRadius: 0,
                                )
                              ],
                            ),
                            child: Icon(_isSelectionMode ? Icons.close_rounded : Icons.ios_share_rounded, color: AppColors.navyBlue, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: AppColors.navyBlue))
                    : _savedBoards.isEmpty 
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _savedBoards.length,
                          itemBuilder: (context, index) {
                            final data = _savedBoards[index];
                            final selectionIndex = _selectedIds.indexOf(data['id']);
                            return LibraryBoardCard(
                              data: data,
                              isSelectionMode: _isSelectionMode,
                              isSelected: selectionIndex != -1,
                              selectionIndex: selectionIndex != -1 ? selectionIndex : null,
                              isRenameMode: _isRenameMode,
                              onToggleSelection: () {
                                setState(() {
                                  if (_selectedIds.contains(data['id'])) {
                                    _selectedIds.remove(data['id']);
                                  } else {
                                    if (_selectedIds.length >= 7) {
                                      FunkyErrorDialog.show(context, message: "Whoa! You can only share 7 boards at a time to keep the QR code easy to scan.");
                                      return;
                                    }
                                    _selectedIds.add(data['id']);
                                  }
                                });
                              },
                              onRename: () => _showRenameDialog(data['id'], data['name']),
                              onDelete: () => _confirmDelete(data['id']),
                              onRefresh: _refreshBoards,
                            );
                          },
                        ),
                ),
                if (!_isSelectionMode) _buildAddButton() else _buildQRButton(),
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
          Icon(Icons.library_books_rounded, size: 80, color: AppColors.navyBlue.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('Your library is empty', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 20, color: AppColors.secondaryText)),
          const Text('Scan or create your first board!', style: TextStyle(fontFamily: 'Comfortaa', color: AppColors.secondaryText)),
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

  Widget _buildQRButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Transform.rotate(
        angle: -0.02,
        child: Container(
          width: double.infinity,
          height: 65,
          decoration: BoxDecoration(
            color: _selectedIds.isEmpty ? Colors.grey.shade300 : AppColors.gold,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(5, 5))],
            border: Border.all(color: AppColors.navyBlue, width: 2),
          ),
          child: ElevatedButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _generateAndShowQR,
            icon: const Icon(Icons.qr_code_2_rounded, size: 28),
            label: Text('Generate QR (${_selectedIds.length})', style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: AppColors.navyBlue, shadowColor: Colors.transparent, elevation: 0),
          ),
        ),
      ),
    );
  }

  void _generateAndShowQR() {
    final List<Map<String, dynamic>> exportData = [];
    for (var boardData in _savedBoards) {
      if (_selectedIds.contains(boardData['id'])) {
        final BoardData board = boardData['board'];
        exportData.add({
          'name': boardData['name'],
          'size': board.size,
          'regionIds': board.regionIds,
        });
      }
    }
    
    final String jsonStr = jsonEncode(exportData);
    final String encryptedData = QRCrypto.encrypt(jsonStr);
    QRShareDialog.show(context, encryptedData);
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
                      color: AppColors.navyBlue.withValues(alpha: 0.3), 
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
                  boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(5, 5))],
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
