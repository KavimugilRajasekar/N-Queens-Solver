import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants/colors.dart';
import '../constants/region_colors.dart';
import '../utils/board_processor.dart';
import '../utils/storage_manager.dart';
import '../widgets/notebook_painter.dart';

import 'package:permission_handler/permission_handler.dart';

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

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required to scan QR codes')),
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
    setState(() => _isProcessing = true);

    try {
      final List<dynamic> data = jsonDecode(rawData);
      int importedCount = 0;
      int existingCount = 0;

      final existingBoards = await StorageManager.loadBoards();

      for (var item in data) {
        final String name = item['name'];
        final int size = item['size'];
        final List<dynamic> regionIdsRaw = item['regionIds'];
        final List<List<int>> regionIds = regionIdsRaw.map((row) => List<int>.from(row)).toList();

        // Check if already exists
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

        if (!exists) {
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
          );

          await StorageManager.saveBoard(board, name: name);
          importedCount++;
        } else {
          existingCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $importedCount boards. ($existingCount already in library)'),
            backgroundColor: AppColors.navyBlue,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR Data'), backgroundColor: Colors.red),
        );
        setState(() => _isProcessing = false);
      }
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
                      const Text('Scan QR Code', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 24, color: AppColors.navyBlue, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Container(
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
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Text(
                    'Point your camera at an N-Queens QR code to import shared boards.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Comfortaa', fontSize: 14, color: AppColors.secondaryText),
                  ),
                ),
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
