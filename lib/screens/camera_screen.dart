import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../widgets/error_dialog.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import 'n_queens_board.dart';

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isProcessing = false;
  bool _showFlash = false;
  String? _capturedImagePath;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessing) return;

    try {
      setState(() => _showFlash = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showFlash = false);
      });

      final image = await _controller.takePicture();
      
      // Perform local crop immediately
      await BoardProcessor.cropImage(image.path);
      
      setState(() {
        _isProcessing = true;
        _capturedImagePath = image.path;
      });

      // Process with N=8 as default
      final boardData = await BoardProcessor.processImage(image.path, 8);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => NQueensBoardScreen(boardData: boardData),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = 0.0;
              const end = 1.0;
              const curve = Curves.easeInOutBack;
              var zoomTween = Tween(begin: 1.2, end: 1.0).chain(CurveTween(curve: curve));
              var fadeTween = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
              
              return FadeTransition(
                opacity: animation.drive(fadeTween),
                child: ScaleTransition(
                  scale: animation.drive(zoomTween),
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _capturedImagePath = null;
        });
        FunkyErrorDialog.show(context,
          title: 'Scan Failed!',
          message: 'Could not process the board image. Try again with better lighting and alignment.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && _controller.value.isInitialized) {
            final previewSize = _controller.value.previewSize;
            if (previewSize == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.navyBlue));
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: previewSize.height,
                      height: previewSize.width,
                      child: CameraPreview(_controller),
                    ),
                  ),
                ),

                if (_isProcessing && _capturedImagePath != null && File(_capturedImagePath!).existsSync())
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(40),
                          child: SizedBox(
                            width: 280,
                            height: 280,
                            child: Image.file(
                              File(_capturedImagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (_isProcessing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 120,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: AppColors.gold, width: 3),
                                  boxShadow: [
                                    BoxShadow(color: AppColors.navyBlue.withOpacity(0.3), offset: const Offset(4, 4)),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: AppColors.navyBlue, strokeWidth: 3),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'ANALYZING BOARD...',
                                      style: TextStyle(
                                        fontFamily: 'DynaPuff',
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.navyBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_showFlash)
                  Positioned.fill(
                    child: Container(color: Colors.white),
                  ),

                _buildViewfinderOverlay(),
                if (!_isProcessing) ...[
                  _buildFunkyTopUI(),
                  _buildFunkyBottomUI(),
                ],
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator(color: AppColors.navyBlue));
          }
        },
      ),
    );
  }

  Widget _buildFunkyTopUI() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Transform.rotate(
          angle: -0.1,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: AppColors.navyBlue, size: 30),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(12),
              elevation: 8,
              shadowColor: AppColors.navyBlue.withOpacity(0.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFunkyBottomUI() {
    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: Column(
        children: [
          _isProcessing
              ? const CircularProgressIndicator(color: AppColors.gold)
              : _buildFunkyCaptureButton(),
        ],
      ),
    );
  }

  Widget _buildViewfinderOverlay() {
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.srcOut),
          child: Stack(
            children: [
              Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40)),
                ),
              ),
            ],
          ),
        ),
        Center(
          child: SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              children: [
                _buildFunkyCorner(top: 0, left: 0),
                _buildFunkyCorner(top: 0, right: 0, angle: 90),
                _buildFunkyCorner(bottom: 0, left: 0, angle: -90),
                _buildFunkyCorner(bottom: 0, right: 0, angle: 180),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFunkyCorner({double? top, double? bottom, double? left, double? right, double angle = 0}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.rotate(
        angle: angle * 3.14159 / 180,
        child: Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.gold, width: 12),
              left: BorderSide(color: AppColors.gold, width: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFunkyCaptureButton() {
    return GestureDetector(
      onTap: _captureAndProcess,
      child: Transform.rotate(
        angle: -0.05,
        child: Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.navyBlue.withOpacity(0.3),
                offset: const Offset(10, 10),
                blurRadius: 0,
              ),
            ],
            border: Border.all(color: AppColors.navyBlue, width: 4),
          ),
          child: Center(
            child: Container(
              width: 85,
              height: 85,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold,
              ),
              child: const Icon(Icons.camera_alt_rounded, color: AppColors.navyBlue, size: 45),
            ),
          ),
        ),
      ),
    );
  }
}
