import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import 'result_screen.dart';

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isProcessing = false;

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

    setState(() {
      _isProcessing = true;
    });

    try {
      final image = await _controller.takePicture();
      final boardData = await BoardProcessor.processImage(image.path, 8);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(boardData: boardData),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.navyBlue,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
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
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller.value.previewSize!.height,
                      height: _controller.value.previewSize!.width,
                      child: CameraPreview(_controller),
                    ),
                  ),
                ),

                _buildViewfinderOverlay(),

                _buildFunkyTopUI(),

                _buildFunkyBottomUI(),
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
