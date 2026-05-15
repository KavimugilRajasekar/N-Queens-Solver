import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import '../utils/storage_manager.dart';
import 'saved_boards_screen.dart';
import 'camera_screen.dart';

class LandingPage extends StatelessWidget {
  final List<CameraDescription> cameras;

  const LandingPage({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                child: Column(
                  children: [
                    _buildHeroSection(context),
                    const SizedBox(height: 60),
                    _buildFunkyHeader(context, "The Puzzle", "Ancient logic"),
                    _buildStickerCard(
                      context,
                      title: 'The N-Queens Problem',
                      content: 'Place N queens on an N×N board so no two queens threaten each other. This is a special regional variant!',
                      icon: Icons.auto_awesome_mosaic_rounded,
                      rotation: -0.01,
                      color: const Color(0xFFFFF9C4), // Lemon
                    ),
                    const SizedBox(height: 40),
                    _buildFunkyHeader(context, "The Rules", "How to play"),
                    _buildStickerCard(
                      context,
                      title: 'Row & Column Logic',
                      content: 'Exactly one queen in every row and column. No overlaps allowed!',
                      icon: Icons.straighten_rounded,
                      rotation: 0.015,
                      color: const Color(0xFFE1F5FE), // Light Blue
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: 'The Region Rule',
                      content: 'The board has distinct colored regions. Each region must have exactly one queen.',
                      icon: Icons.category_outlined,
                      rotation: -0.01,
                      color: const Color(0xFFF1F8E9), // Light Green
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: '8-Neighbor Rule',
                      content: 'Queens are anti-social. They cannot touch each other in any surrounding cell.',
                      icon: Icons.do_not_disturb_on_outlined,
                      rotation: 0.02,
                      color: const Color(0xFFFCE4EC), // Light Pink
                    ),
                    const SizedBox(height: 60),
                    _buildFunkyHeader(context, "The Brains", "AI Engine"),
                    _buildStickerCard(
                      context,
                      title: 'Backtracking AI',
                      content: 'If it hits a dead end, it "backtracks" and tries a different path automatically.',
                      icon: Icons.psychology_outlined,
                      rotation: -0.015,
                      color: const Color(0xFFFFF3E0), // Light Orange
                    ),
                    const SizedBox(height: 80),
                    _buildMainActionButton(context),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Column(
      children: [
        Transform.rotate(
          angle: -0.05,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: AppColors.navyBlue, width: 3),
              boxShadow: [
                BoxShadow(color: AppColors.navyBlue.withOpacity(0.3), offset: const Offset(10, 10)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.asset(
                'assets/icons/n_queen_logo.png',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.grid_4x4_rounded, color: AppColors.navyBlue, size: 60),
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
        Text('N-Queens\nPuzzle Studio', 
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 38, height: 0.9), 
          textAlign: TextAlign.center
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildFunkyHeader(BuildContext context, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25, left: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle.toUpperCase(), style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 12, color: AppColors.navyBlue, fontWeight: FontWeight.bold, letterSpacing: 1)),
          Text(title, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, color: AppColors.darkText)),
        ],
      ),
    );
  }

  Widget _buildStickerCard(BuildContext context, {
    required String title, 
    required String content, 
    required IconData icon, 
    required double rotation,
    required Color color,
  }) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2),
          boxShadow: [
            BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(6, 6)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.navyBlue, width: 1.5),
              ),
              child: Icon(icon, color: AppColors.navyBlue, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
                  const SizedBox(height: 6),
                  Text(content, style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, height: 1.4, color: AppColors.darkText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainActionButton(BuildContext context) {
    return Transform.rotate(
      angle: -0.02,
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SavedBoardsScreen(cameras: cameras))),
        child: Container(
          width: double.infinity,
          height: 75,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.navyBlue, width: 3),
            boxShadow: [
              BoxShadow(color: AppColors.navyBlue, offset: const Offset(8, 8)),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.rocket_launch_rounded, size: 30, color: AppColors.navyBlue),
              SizedBox(width: 15),
              Text('ENTER STUDIO', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 24, color: AppColors.navyBlue)),
            ],
          ),
        ),
      ),
    );
  }
}
