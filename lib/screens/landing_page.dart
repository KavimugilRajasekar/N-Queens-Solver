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
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
                child: Column(
                  children: [
                    _buildLogo(context),
                    const SizedBox(height: 60),
                    _buildSectionHeader(context, "The Puzzle", "An Ancient Challenge"),
                    _buildMinimalCard(
                      context,
                      title: 'The N-Queens Problem',
                      content: 'The classic goal is to place N queens on an N×N board so no two queens threaten each other. This app solves a specialized variant often found in modern logic puzzles.',
                      icon: Icons.grid_view_rounded,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader(context, "The Rules", "Universal Constraints"),
                    _buildMinimalCard(
                      context,
                      title: 'Row & Column Logic',
                      content: 'Exactly one queen must exist in every horizontal row and every vertical column. No overlaps allowed!',
                      icon: Icons.straighten_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildMinimalCard(
                      context,
                      title: 'The Region (\$Q_i\$) Rule',
                      content: 'The board is divided into distinct colored regions. Each region must contain exactly one queen, regardless of its shape or size.',
                      icon: Icons.category_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildMinimalCard(
                      context,
                      title: 'The 8-Neighbor Rule',
                      content: 'Queens are "anti-social." No queen can touch another queen in any of its 8 surrounding cells (Up, Down, Left, Right, and all Diagonals).',
                      icon: Icons.do_not_disturb_on_outlined,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader(context, "The AI Solver", "How it Thinks"),
                    _buildMinimalCard(
                      context,
                      title: 'Backtracking AI',
                      content: 'The solver uses a depth-first search. If it hits a dead end where no more queens can be placed, it "backtracks" to the previous step and tries a different path.',
                      icon: Icons.psychology_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildMinimalCard(
                      context,
                      title: 'Forward Checking',
                      content: 'To find solutions faster, the AI uses "Confinement Logic." Every time a queen is placed, it immediately eliminates impossible cells from other regions to narrow the search space.',
                      icon: Icons.visibility_outlined,
                    ),
                    const SizedBox(height: 80),
                    _buildActionButton(context),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, spreadRadius: 2)],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/icons/n_queen_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.grid_4x4_rounded, color: AppColors.navyBlue, size: 50),
            ),
          ),
        ),
        const SizedBox(height: 30),
        Text('N-Queens Solver', style: Theme.of(context).textTheme.displayLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Container(width: 60, height: 2, color: AppColors.navyBlue.withOpacity(0.2)),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, String subtitle) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle.toUpperCase(), style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 10, letterSpacing: 2, color: AppColors.navyBlue, fontWeight: FontWeight.bold)),
          Text(title, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28, color: AppColors.darkText)),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    return Transform.rotate(
      angle: -0.02,
      child: Container(
        width: double.infinity,
        height: 70,
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(4, 4))],
        ),
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => SavedBoardsScreen(cameras: cameras)));
          },
          icon: const Icon(Icons.library_books_rounded, size: 28),
          label: const Text('Open Board', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 22)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: AppColors.navyBlue,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalCard(BuildContext context, {required String title, required String content, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.navyBlue.withOpacity(0.1), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), offset: const Offset(2, 2), blurRadius: 10)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.navyBlue, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
                const SizedBox(height: 8),
                Text(content, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
