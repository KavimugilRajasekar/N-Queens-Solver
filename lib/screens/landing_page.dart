import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import 'camera_screen.dart';

class LandingPage extends StatelessWidget {
  final List<CameraDescription> cameras;

  const LandingPage({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Notebook Lining Background
          Positioned.fill(
            child: CustomPaint(
              painter: NotebookPainter(),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Circular Cropped Logo
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icons/n_queen_logo.png',
                          fit: BoxFit.cover, // Ensures it fills the circle
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.grid_4x4_rounded,
                            color: AppColors.navyBlue,
                            size: 60,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    Text(
                      'N-Queens Solver',
                      style: Theme.of(context).textTheme.displayLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 80,
                      height: 2,
                      color: AppColors.navyBlue.withOpacity(0.3),
                    ),
                    const SizedBox(height: 60),
                    
                    // Minimal Info Section
                    _buildMinimalCard(
                      context,
                      title: 'The Mission',
                      content: 'Strategically place N queens on an N×N board so they peacefully coexist without conflict.',
                      icon: Icons.auto_awesome_outlined,
                    ),
                    const SizedBox(height: 24),
                    _buildMinimalCard(
                      context,
                      title: 'Computer Science',
                      content: 'A fundamental challenge illustrating backtracking and constraint satisfaction algorithms.',
                      icon: Icons.lightbulb_outline,
                    ),
                    
                    const SizedBox(height: 80),
                    
                    // Funky Sticker-Style Action Button
                    Transform.rotate(
                      angle: -0.03, // Slight funky tilt
                      child: Container(
                        width: double.infinity,
                        height: 65,
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navyBlue.withOpacity(0.15),
                              offset: const Offset(4, 4),
                              blurRadius: 0, // Sharp funky shadow
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (cameras.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No camera detected')),
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CameraScreen(camera: cameras.first),
                              ),
                            );
                          },
                          icon: const Icon(Icons.camera_alt_rounded, size: 28),
                          label: const Text(
                            'Scan Chessboard',
                            style: TextStyle(
                              fontFamily: 'DynaPuff',
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: AppColors.navyBlue,
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalCard(BuildContext context, {required String title, required String content, required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.navyBlue, size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 36),
          child: Text(
            content,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16),
          ),
        ),
      ],
    );
  }
}
