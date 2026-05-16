import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import '../utils/storage_manager.dart';
import 'saved_boards_screen.dart';
import 'camera_screen.dart';

import 'package:lottie/lottie.dart';
import '../utils/board_processor.dart';
import '../utils/shortcut_manager.dart';
import 'compete_mode_screen.dart';

class LandingPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const LandingPage({super.key, required this.cameras});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  int _totalSolved = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
    // Initialize Home Screen Shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppShortcutManager.init(context, widget.cameras);
    });
  }

  Future<void> _loadStats() async {
    final boards = await StorageManager.loadBoards();
    if (mounted) {
      setState(() {
        _totalSolved = boards.where((b) => (b['board'] as BoardData).isManuallySolved).length;
      });
    }
  }

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
                    if (_totalSolved > 0) ...[
                      const SizedBox(height: 30),
                      _buildMasteryHall(context),
                    ],
                    const SizedBox(height: 60),
                    _buildFunkyHeader(context, "The Puzzle", "Ancient logic"),
                    _buildStickerCard(
                      context,
                      title: 'The N-Queens Origin',
                      content: 'First proposed in 1848 by Max Bezzel. The challenge? Place N queens on an N×N board with zero threats. It’s a legendary test of spatial logic!',
                      icon: Icons.history_edu_rounded,
                      rotation: -0.01,
                      color: const Color(0xFFFFF9C4), // Lemon
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: 'Mathematical Depth',
                      content: 'For a standard 8x8 board, there are 92 distinct solutions. In our regional variant, the possibilities are even more complex!',
                      icon: Icons.functions_rounded,
                      rotation: 0.01,
                      color: const Color(0xFFF3E5F5), // Light Purple
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
                      content: 'The board has distinct colored regions. Each region must have exactly one queen. This is what makes our version "Funky"!',
                      icon: Icons.category_outlined,
                      rotation: -0.01,
                      color: const Color(0xFFF1F8E9), // Light Green
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: '8-Neighbor Rule',
                      content: 'Queens are anti-social. They cannot touch each other in any surrounding cell—including diagonals.',
                      icon: Icons.do_not_disturb_on_outlined,
                      rotation: 0.02,
                      color: const Color(0xFFFCE4EC), // Light Pink
                    ),
                    const SizedBox(height: 60),
                    _buildFunkyHeader(context, "The Studio", "Feature Tour"),
                    _buildStickerCard(
                      context,
                      title: 'Digital Capture',
                      content: 'Saw a board in a book? Use your camera to scan and digitize it instantly. Our AI will handle the rest!',
                      icon: Icons.photo_camera_rounded,
                      rotation: -0.01,
                      color: const Color(0xFFEFEBE9), // Brown Wash
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: 'Manual Designer',
                      content: 'Unleash your inner architect! Paint your own regions and challenge your friends with custom-built levels.',
                      icon: Icons.brush_rounded,
                      rotation: 0.015,
                      color: const Color(0xFFE8F5E9), // Green Mint
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: 'AI Generation',
                      content: 'Feeling stuck? Let our AI engine generate unique, solvable puzzles of any size for you to solve!',
                      icon: Icons.auto_awesome_rounded,
                      rotation: -0.01,
                      color: const Color(0xFFE0F2F1), // Teal Mint
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: 'Secure QR Sharing',
                      content: 'Export your boards via encrypted QR codes. Only fellow Studio users can scan and solve your creations!',
                      icon: Icons.vibration_rounded,
                      rotation: 0.012,
                      color: const Color(0xFFE8EAF6), // Indigo Wash
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: 'Mastery Badges',
                      content: 'Solve a board manually to earn a golden trophy badge in your library. Can you master them all?',
                      icon: Icons.emoji_events_outlined,
                      rotation: -0.02,
                      color: const Color(0xFFFFF3E0), // Orange Cream
                    ),
                    const SizedBox(height: 60),
                    _buildFunkyHeader(context, "The Brains", "AI Engine"),
                    _buildStickerCard(
                      context,
                      title: 'Visual Reasoning',
                      content: 'Watch the AI think! Our real-time algorithm log shows every step the solver takes to find the perfect solution.',
                      icon: Icons.troubleshoot_rounded,
                      rotation: 0.01,
                      color: const Color(0xFFF5F5F5), // White Smoke
                    ),
                    const SizedBox(height: 20),
                    _buildStickerCard(
                      context,
                      title: 'Smart Backtracking',
                      content: 'Our solver uses a recursive backtracking algorithm that explores millions of possibilities in milliseconds.',
                      icon: Icons.psychology_outlined,
                      rotation: -0.015,
                      color: const Color(0xFFFAFAFA), // Grey White
                    ),
                    const SizedBox(height: 80),
                    _buildMainActionButton(context),
                    const SizedBox(height: 25),
                    _buildCompeteModeButton(context),
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

  Widget _buildMasteryHall(BuildContext context) {
    return Transform.rotate(
      angle: -0.01,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.gold, width: 3),
          boxShadow: [
            BoxShadow(color: AppColors.gold.withOpacity(0.2), offset: const Offset(6, 6)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Lottie.asset('assets/json/trophy.json', repeat: true),
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MASTERY HALL', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.gold)),
                Text('$_totalSolved Boards Mastered!', style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
              ],
            ),
          ],
        ),
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
        Text('N-Queens', 
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 38), 
          textAlign: TextAlign.center
        ),
        const SizedBox(height: 10),
        Text('Puzzle Studio', 
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 38), 
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SavedBoardsScreen(cameras: widget.cameras))),
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

  Widget _buildCompeteModeButton(BuildContext context) {
    return Transform.rotate(
      angle: 0.03, // More pronounced tilt for extra funkiness
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CompeteModeScreen()),
          );
        },
        child: Container(
          width: double.infinity,
          height: 75,
          decoration: BoxDecoration(
            color: const Color(0xFFFF4081), // Neon Pink "Funky" Sticker
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.navyBlue, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.navyBlue,
                offset: const Offset(10, 10), // Even deeper shadow
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events_rounded, size: 30, color: Colors.white),
              SizedBox(width: 15),
              Text(
                'COMPETE MODE',
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
