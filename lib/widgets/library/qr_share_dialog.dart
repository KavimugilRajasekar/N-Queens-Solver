import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../constants/colors.dart';
import '../error_dialog.dart';

class QRShareDialog extends StatefulWidget {
  final String qrData;

  const QRShareDialog({super.key, required this.qrData});

  @override
  State<QRShareDialog> createState() => _QRShareDialogState();

  static void show(BuildContext context, String data) {
    showDialog(
      context: context,
      builder: (context) => QRShareDialog(qrData: data),
    );
  }
}

class _QRShareDialogState extends State<QRShareDialog> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isSharing = false;

  Future<void> _shareQR() async {
    setState(() => _isSharing = true);
    try {
      // Small delay to ensure UI is settled
      await Future.delayed(const Duration(milliseconds: 100));
      final image = await _screenshotController.capture(
        pixelRatio: 3.0, // Ultra high quality for sharing
      );
      if (image != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/n_queens_share.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles([XFile(imagePath.path)], text: 'Try these N-Queens boards in the N-Queens Solver app!');
      }
    } catch (e) {
      if (mounted) {
        FunkyErrorDialog.show(context, message: 'Failed to capture and share the QR sticker.');
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main Tilted Dialog Container
          Transform.rotate(
            angle: -0.015,
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(35),
                border: Border.all(color: AppColors.navyBlue, width: 3),
                boxShadow: [
                  BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(10, 10))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, color: AppColors.navyBlue, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Text('Export Boards', style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // This is the part that gets screenshotted for sharing
                  Screenshot(
                    controller: _screenshotController,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: AppColors.navyBlue.withOpacity(0.15), width: 1.5),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Logo Row (For shared image)
                          Row(
                            children: [
                              Image.asset('assets/icons/n_queen_logo.png', width: 40, height: 40),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('N-Queens Solver', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
                                  Text('Interactive Puzzle Studio', style: TextStyle(fontFamily: 'Comfortaa', fontSize: 10, color: AppColors.secondaryText)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // QR Centered Area
                          Center(
                            child: Container(
                              width: 200,
                              height: 200,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: AppColors.navyBlue.withOpacity(0.1), width: 1.5),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(color: AppColors.navyBlue.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4)
                                ],
                              ),
                              child: PrettyQrView.data(
                                data: widget.qrData,
                                decoration: const PrettyQrDecoration(
                                  shape: PrettyQrSmoothSymbol(color: AppColors.navyBlue),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Puzzle shared via N-Queens Studio', style: TextStyle(fontFamily: 'Comfortaa', fontSize: 9, fontStyle: FontStyle.italic, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFunkyButton(
                        label: 'Cancel',
                        color: Colors.white,
                        onTap: () => Navigator.pop(context),
                        rotation: -0.04,
                      ),
                      _buildFunkyButton(
                        label: _isSharing ? 'Capturing...' : 'Share Sticker',
                        color: AppColors.gold,
                        onTap: _isSharing ? null : _shareQR,
                        rotation: 0.03,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunkyButton({required String label, required Color color, required VoidCallback? onTap, required double rotation}) {
    return Transform.rotate(
      angle: rotation,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.navyBlue, width: 2.5),
            boxShadow: [
              BoxShadow(color: AppColors.navyBlue.withOpacity(0.3), offset: const Offset(4, 4))
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyBlue),
          ),
        ),
      ),
    );
  }
}
