import 'dart:async';
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
  Timer? _analysisTimer;
  BoardData? _realtimeBoard;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium, // Medium is faster for real-time
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      _startRealtimeAnalysis();
    });
  }

  void _startRealtimeAnalysis() {
    _analysisTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (_isAnalyzing || !mounted) return;
      
      try {
        _isAnalyzing = true;
        final image = await _controller.takePicture();
        final boardData = await BoardProcessor.processImage(image.path, 8);
        
        if (mounted) {
          setState(() {
            _realtimeBoard = boardData;
          });
        }
      } catch (e) {
        debugPrint('Real-time analysis error: $e');
      } finally {
        _isAnalyzing = false;
      }
    });
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Real-time Scanner',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navyBlue),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppColors.navyBlue),
        elevation: 0,
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                CameraPreview(_controller),
                
                // Scanning Overlay with Live Grid
                Center(
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.navyBlue.withOpacity(0.5), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        if (_realtimeBoard != null)
                          Opacity(
                            opacity: 0.4,
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 8,
                              ),
                              itemCount: 64,
                              itemBuilder: (context, index) {
                                int r = index ~/ 8;
                                int c = index % 8;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: _realtimeBoard!.grid[r][c],
                                    border: Border.all(color: Colors.white24, width: 0.5),
                                  ),
                                );
                              },
                            ),
                          ),
                        _buildCorner(top: 0, left: 0),
                        _buildCorner(top: 0, right: 0, angle: 90),
                        _buildCorner(bottom: 0, left: 0, angle: -90),
                        _buildCorner(bottom: 0, right: 0, angle: 180),
                      ],
                    ),
                  ),
                ),

                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _realtimeBoard == null ? 'Analyzing Board...' : 'Board Locked!',
                          style: const TextStyle(color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _realtimeBoard == null ? null : () => _confirmResult(),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _realtimeBoard == null ? Colors.grey : AppColors.navyBlue, 
                              width: 4
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _realtimeBoard == null ? Colors.grey : AppColors.navyBlue,
                              ),
                              child: const Icon(Icons.check, color: Colors.white, size: 35),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  void _confirmResult() {
    if (_realtimeBoard == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(boardData: _realtimeBoard!),
      ),
    );
  }

  Widget _buildCorner({double? top, double? bottom, double? left, double? right, double angle = 0}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.rotate(
        angle: angle * 3.14159 / 180,
        child: Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.gold, width: 5),
              left: BorderSide(color: AppColors.gold, width: 5),
            ),
          ),
        ),
      ),
    );
  }
}
