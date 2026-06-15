import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import '../utils/storage_manager.dart';
import 'saved_boards_screen.dart';

import 'package:lottie/lottie.dart';
import '../utils/board_processor.dart';
import '../utils/shortcut_manager.dart';
import 'compete_mode_screen.dart';
import '../utils/firebase_game_manager.dart';
import '../utils/update_service.dart';
import 'peers_play_screen.dart';
import 'screenshot_solver_setup_screen.dart';
import '../utils/screenshot_solver_service.dart';

class LandingPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const LandingPage({super.key, required this.cameras});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with WidgetsBindingObserver {
  int _totalSolved = 0;
  // Quick Access live status
  bool _qaAllSet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
    _checkQuickAccessStatus();
    // Initialize Home Screen Shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppShortcutManager.init(context, widget.cameras);
    });
    
    // Register invite listener
    FirebaseGameManager.instance.incomingInviteNotifier.addListener(_handleIncomingInviteListener);
    
    // Process any pending invite loaded during startup/boot phase immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FirebaseGameManager.instance.incomingInviteNotifier.value != null) {
        _handleIncomingInviteListener();
      }
      // Check GitHub for a newer release and notify the user if one exists
      UpdateService.checkAndNotify(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FirebaseGameManager.instance.incomingInviteNotifier.removeListener(_handleIncomingInviteListener);
    super.dispose();
  }

  /// Re-check Quick Access status when returning from the setup screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkQuickAccessStatus();
    }
  }

  Future<void> _checkQuickAccessStatus() async {
    final proj = await ScreenshotSolverService.instance.hasMediaProjectionPermission();
    final overlay = await ScreenshotSolverService.instance.hasOverlayPermission();
    if (mounted) {
      setState(() => _qaAllSet = proj && overlay);
    }
  }

  void _handleIncomingInviteListener() {
    final invite = FirebaseGameManager.instance.incomingInviteNotifier.value;
    if (invite == null) return;
    
    // Reset the value so we don't trigger multiple popups
    FirebaseGameManager.instance.incomingInviteNotifier.value = null;

    if (!mounted) return;

    final isCompete = invite['isCompeteMode'] == true;
    final rivalName = invite['fromNickname'];
    final matchCount = invite['matchCount'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: const BorderSide(color: AppColors.navyBlue, width: 3),
        ),
        backgroundColor: isCompete ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        title: Row(
          children: [
            Icon(
              isCompete ? Icons.sports_esports_rounded : Icons.group_work_rounded,
              color: isCompete ? Colors.redAccent.shade700 : Colors.green.shade700,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              isCompete ? "DUEL CHALLENGE!" : "CO-OP SYNC CHALLENGE!",
              style: TextStyle(
                fontFamily: 'DynaPuff',
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isCompete ? Colors.redAccent.shade700 : Colors.green.shade700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "INCOMING CHALLENGE",
              style: TextStyle(fontFamily: 'DynaPuff', fontSize: 12, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Player '$rivalName' has invited you to a ${isCompete ? 'Compete Duel' : 'Co-op Sync'} series ($matchCount ${matchCount == 1 ? 'Match' : 'Matches'}).\n\nDo you want to accept and connect?",
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.darkText, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    "Challenge declined!",
                    style: TextStyle(fontFamily: 'DynaPuff', color: Colors.white, fontSize: 16),
                  ),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.navyBlue,
                  margin: const EdgeInsets.only(bottom: 105, left: 40, right: 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: Colors.white24, width: 1),
                  ),
                ),
              );
            },
            child: const Text("DECLINE", style: TextStyle(fontFamily: 'DynaPuff', color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);

              // Reconstruct boards
              final boards = FirebaseGameManager.deserializeBoards(invite['matchBoards']);

              // Show loading dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (loadCtx) => const Center(
                  child: Card(
                    color: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.navyBlue),
                          SizedBox(height: 15),
                          Text("Connecting to Game Room...", style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue)),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              try {
                // Initialize Joiner Connection
                await FirebaseGameManager.instance.joinConnection(invite);

                // Save host to recent opponents so they appear in the guest's history too
                final hostId       = invite['fromPlayerId'] as String? ?? '';
                final hostNickname = invite['fromNickname'] as String? ?? 'Player';
                final hostIcon     = invite['fromIcon']     as String? ?? 'assets/player_icons/crown.png';
                await FirebaseGameManager.saveRecentOpponent(hostId, hostNickname, hostIcon);
                
                if (mounted) {
                  Navigator.pop(context); // Dismiss loading dialog

                  // Derive joiner colour as the complement of what the host chose.
                  // Co-op  : blue ↔ green
                  // Compete: blue ↔ red
                  final hostColor = invite['hostColor'] as String? ?? 'blue';
                  String joinerColor;
                  if (isCompete) {
                    joinerColor = hostColor.toLowerCase() == 'blue' ? 'red' : 'blue';
                  } else {
                    joinerColor = hostColor.toLowerCase() == 'blue' ? 'green' : 'blue';
                  }

                  // Navigate to play screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PeersPlayScreen(
                        isCompeteMode: isCompete,
                        opponentId: invite['fromPlayerId'],
                        playerColor: joinerColor,
                        matchCount: matchCount,
                        matchBoards: boards,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context); // Dismiss loading dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Failed to connect to game room: $e",
                        style: const TextStyle(fontFamily: 'DynaPuff', color: Colors.white, fontSize: 16),
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.navyBlue,
                      margin: const EdgeInsets.only(bottom: 105, left: 40, right: 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: const BorderSide(color: Colors.white24, width: 1),
                      ),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("ACCEPT & PLAY", style: TextStyle(fontFamily: 'DynaPuff')),
          ),
        ],
      ),
    );
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
                    const SizedBox(height: 25),
                    _buildQuickAccessButton(context),
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
            BoxShadow(color: AppColors.gold.withValues(alpha: 0.2), offset: const Offset(6, 6)),
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
                BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.3), offset: const Offset(10, 10)),
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
            BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(6, 6)),
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

  Widget _buildQuickAccessButton(BuildContext context) {
    return Transform.rotate(
      angle: -0.01,
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ScreenshotSolverSetupScreen(),
            ),
          );
          // Refresh status when user returns from the setup screen
          _checkQuickAccessStatus();
        },
        child: Container(
          width: double.infinity,
          height: 75,
          decoration: BoxDecoration(
            color: const Color(0xFF1DE9B6), // Teal / mint accent
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.navyBlue, width: 3),
            boxShadow: const [
              BoxShadow(color: AppColors.navyBlue, offset: Offset(8, 8)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _qaAllSet
                    ? Icons.check_circle_rounded
                    : Icons.screenshot_monitor_rounded,
                size: 30,
                color: AppColors.navyBlue,
              ),
              const SizedBox(width: 15),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QUICK ACCESS',
                    style: TextStyle(
                      fontFamily: 'DynaPuff',
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: AppColors.navyBlue,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    _qaAllSet ? 'All set! Tile is active ✓' : 'Tap to set up',
                    style: TextStyle(
                      fontFamily: 'Comfortaa',
                      fontSize: 11,
                      color: AppColors.navyBlue.withValues(alpha: 0.75),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
