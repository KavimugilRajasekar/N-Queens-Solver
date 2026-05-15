import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/colors.dart';
import '../constants/region_colors.dart';
import '../utils/board_processor.dart';
import '../utils/storage_manager.dart';
import '../widgets/notebook_painter.dart';
import '../widgets/error_dialog.dart';
import '../widgets/success_dialog.dart';
import '../widgets/library/board_card.dart';
import '../utils/qr_crypto.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isProcessing = false;
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  List<Map<String, dynamic>> _pendingBoards = [];
  Set<int> _selectedIndices = {};
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied && mounted) {
      FunkyErrorDialog.show(context, 
        title: 'Camera Needed',
        message: 'We need camera access to scan those funky QR codes! Please enable it in settings.'
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _processQR(String rawData) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      await _controller.stop();
    } catch (_) {}

    setState(() {});

    try {
      final String decryptedData = QRCrypto.decrypt(rawData);
      final List<dynamic> data = jsonDecode(decryptedData);
      final existingBoards = await StorageManager.loadBoards();
      List<Map<String, dynamic>> pending = [];

      for (var item in data) {
        final String name = item['name'];
        final int size = item['size'];
        final List<dynamic> regionIdsRaw = item['regionIds'];
        final List<List<int>> regionIds = regionIdsRaw.map((row) => List<int>.from(row)).toList();

        bool exists = existingBoards.any((eb) {
          final BoardData eBoard = eb['board'];
          if (eBoard.size != size) return false;
          for (int r = 0; r < size; r++) {
            for (int c = 0; c < size; c++) {
              if (eBoard.regionIds[r][c] != regionIds[r][c]) return false;
            }
          }
          return true;
        });

        // Reconstruct BoardData for preview
        final regions = <int, BoardRegion>{};
        for (int r = 0; r < size; r++) {
          for (int c = 0; c < size; c++) {
            final id = regionIds[r][c];
            final color = RegionColors.getRegionColor(id, size);
            regions.putIfAbsent(id, () => BoardRegion(id: id, color: color, coordinates: [])).coordinates.add(Point(r + 1, c + 1));
          }
        }

        final board = BoardData(
          size: size,
          regionIds: regionIds,
          regions: regions,
          rawResponse: "Imported via QR",
          solution: {0: Point(1, 1)}, // Dummy solution to make it selectable in the preview card
        );

        pending.add({
          'name': name,
          'board': board,
          'exists': exists,
        });
      }

      if (mounted) {
        setState(() {
          _pendingBoards = pending;
          _selectedIndices = pending
              .asMap()
              .entries
              .where((e) => !e.value['exists'])
              .map((e) => e.key)
              .toSet();
          _hasScanned = true;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        await FunkyErrorDialog.show(context, message: 'Invalid QR Data');
        _isProcessing = false;
        await _controller.start();
        setState(() {});
      }
    }
  }

  Future<void> _importSelected() async {
    setState(() => _isProcessing = true);
    int importedCount = 0;
    List<String> importedNames = [];

    for (int i in _selectedIndices) {
      final item = _pendingBoards[i];
      final BoardData board = item['board'];
      
      // Create a clean version without the dummy solution for the library
      final cleanBoard = BoardData(
        size: board.size,
        regionIds: board.regionIds,
        regions: board.regions,
        rawResponse: board.rawResponse,
        solution: null, // Keep it unsolved for the new user
        isManuallySolved: false,
      );

      await StorageManager.saveBoard(cleanBoard, name: item['name']);
      importedCount++;
      importedNames.add(item['name']);
    }

    if (mounted) {
      await FunkySuccessDialog.show(
        context,
        title: 'Import Complete!',
        message: 'Successfully added $importedCount boards to your library.',
        importedNames: importedNames,
      );
      Navigator.pop(context, true);
    }
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
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      _buildFunkyBack(() => Navigator.pop(context)),
                      const SizedBox(width: 16),
                      Text(
                        _hasScanned ? 'Confirm Import' : 'Scan QR Code',
                        style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 24, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _hasScanned ? _buildPendingList() : _buildScannerView(),
                ),
                if (_hasScanned) _buildBottomActions(),
              ],
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.navyBlue, width: 4),
            boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(8, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _processQR(barcode.rawValue!);
                    break;
                  }
                }
              },
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(40.0),
          child: Text(
            'Point your camera at an N-Queens QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Comfortaa', fontSize: 14, color: AppColors.secondaryText),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _pendingBoards.length,
      itemBuilder: (context, index) {
        final item = _pendingBoards[index];
        final bool exists = item['exists'];
        final bool isSelected = _selectedIndices.contains(index);

        return Opacity(
          opacity: exists ? 0.6 : 1.0,
          child: LibraryBoardCard(
            data: {
              'id': index,
              'name': item['name'],
              'board': item['board'],
              'date': DateTime.now(),
            },
            isSelectionMode: true,
            isSelected: isSelected,
            onToggleSelection: () {
              if (exists) return;
              setState(() {
                if (isSelected) {
                  _selectedIndices.remove(index);
                } else {
                  _selectedIndices.add(index);
                }
              });
            },
            onRename: () {}, // Not needed here
            onDelete: () {}, // Not needed here
            onRefresh: () {}, // Not needed here
          ),
        );
      },
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              label: 'Rescan',
              color: Colors.white,
              onTap: () async {
                setState(() {
                  _hasScanned = false;
                  _pendingBoards = [];
                  _selectedIndices = {};
                });
                await _controller.start();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildActionButton(
              label: 'Import (${_selectedIndices.length})',
              color: AppColors.gold,
              onTap: _selectedIndices.isEmpty ? null : _importSelected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required String label, required Color color, required VoidCallback? onTap}) {
    return Transform.rotate(
      angle: label == 'Rescan' ? -0.02 : 0.02,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.navyBlue, width: 2),
            boxShadow: [
              BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(4, 4))
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyBlue),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFunkyBack(VoidCallback onTap) {
    return Transform.rotate(
      angle: 0.05,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 55,
          height: 55,
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.navyBlue, width: 2.5),
            boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.3), offset: const Offset(4, 4))],
          ),
          child: const Icon(Icons.arrow_back_rounded, color: AppColors.navyBlue, size: 28),
        ),
      ),
    );
  }
}
