import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../constants/colors.dart';

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
        pixelRatio: 2.0, // High quality
      );
      if (image != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/n_queens_share.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles([XFile(imagePath.path)], text: 'Check out these N-Queens boards!');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share QR'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main Tilted Card
          Transform.rotate(
            angle: -0.02,
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.navyBlue, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navyBlue.withOpacity(0.2),
                    offset: const Offset(8, 8),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Scan to Share', style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // QR Area with Screenshot Controller
                  Screenshot(
                    controller: _screenshotController,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.navyBlue.withOpacity(0.1), width: 2),
                      ),
                      child: PrettyQrView.data(
                        data: widget.qrData,
                        decoration: const PrettyQrDecoration(
                          shape: PrettyQrSmoothSymbol(
                            color: AppColors.navyBlue,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  const Text('Share these solvable boards!', style: TextStyle(fontFamily: 'Comfortaa', fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
                  const Text('Only board regions are shared, not solutions.', style: TextStyle(fontFamily: 'Comfortaa', fontSize: 11, color: AppColors.secondaryText)),
                  const SizedBox(height: 30),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFunkyButton(
                        label: 'Close',
                        color: Colors.grey.shade200,
                        onTap: () => Navigator.pop(context),
                      ),
                      _buildFunkyButton(
                        label: _isSharing ? 'Sharing...' : 'Share Image',
                        color: AppColors.gold,
                        onTap: _isSharing ? null : _shareQR,
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

  Widget _buildFunkyButton({required String label, required Color color, required VoidCallback? onTap, double rotation = 0.03}) {
    return Transform.rotate(
      angle: rotation,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.navyBlue, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.navyBlue.withOpacity(0.2),
                offset: const Offset(4, 4),
              )
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navyBlue),
          ),
        ),
      ),
    );
  }
}
