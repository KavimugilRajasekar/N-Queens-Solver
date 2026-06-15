import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';
import '../utils/screenshot_solver_service.dart';
import '../widgets/notebook_painter.dart';

/// Guides the user through granting:
///  1. MediaProjection (screen capture) permission
///  2. SYSTEM_ALERT_WINDOW (overlay) permission
///
/// Once both are granted, the Quick Settings Tile is ready to use.
class ScreenshotSolverSetupScreen extends StatefulWidget {
  const ScreenshotSolverSetupScreen({super.key});

  @override
  State<ScreenshotSolverSetupScreen> createState() =>
      _ScreenshotSolverSetupScreenState();
}

class _ScreenshotSolverSetupScreenState
    extends State<ScreenshotSolverSetupScreen> with WidgetsBindingObserver {
  bool _hasProjection = false;
  bool _hasOverlay = false;
  bool _isCheckingProjection = false;
  // True when the pref flag exists but the ProjectionSessionService is dead
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check when the user returns from the system settings screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    // Check pref flag independently of service liveness
    final prefGranted = await _methodChannel_hasPref();
    final proj = prefGranted
        ? await ScreenshotSolverService.instance.hasMediaProjectionPermission()
        : false;
    final overlay = await ScreenshotSolverService.instance.hasOverlayPermission();
    if (mounted) {
      setState(() {
        _hasProjection = proj;
        _hasOverlay = overlay;
        // Show expired banner when pref exists but service is dead
        _sessionExpired = prefGranted && !proj;
      });
    }
  }

  Future<bool> _methodChannel_hasPref() async {
    try {
      final channel = MethodChannel('com.example.n_queens_solver/screenshot_solver');
      return await channel.invokeMethod<bool>('hasMediaProjectionPermission') ?? false;
    } catch (_) { return false; }
  }

  Future<void> _grantProjection() async {
    if (_isCheckingProjection) return;
    setState(() => _isCheckingProjection = true);
    final granted = await ScreenshotSolverService.instance.requestMediaProjection();
    if (mounted) {
      setState(() {
        _hasProjection = granted;
        _isCheckingProjection = false;
      });
    }
  }

  Future<void> _grantOverlay() async {
    await ScreenshotSolverService.instance.requestOverlayPermission();
    // Re-check after returning from settings
    await Future.delayed(const Duration(milliseconds: 400));
    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _hasProjection && _hasOverlay;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button
                  Transform.rotate(
                    angle: 0.05,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 55,
                        height: 55,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: AppColors.navyBlue, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navyBlue.withValues(alpha: 0.3),
                              offset: const Offset(4, 4),
                            )
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.navyBlue, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Header
                  const Text(
                    'QUICK ACCESS',
                    style: TextStyle(
                      fontFamily: 'DynaPuff',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyBlue,
                      letterSpacing: 2,
                    ),
                  ),
                  const Text(
                    'Screenshot Solver',
                    style: TextStyle(
                      fontFamily: 'DynaPuff',
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add the "NQ Solver" tile to your Quick Settings panel, then tap it to instantly capture and solve any N-Queens board visible on your screen.',
                    style: TextStyle(
                      fontFamily: 'Comfortaa',
                      fontSize: 13,
                      color: AppColors.secondaryText,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // How it works card
                  Transform.rotate(
                    angle: -0.008,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F8E9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navyBlue.withValues(alpha: 0.12),
                            offset: const Offset(5, 5),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bolt_rounded,
                                  color: AppColors.navyBlue, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'HOW IT WORKS',
                                style: TextStyle(
                                  fontFamily: 'DynaPuff',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._steps.map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: AppColors.gold,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: AppColors.navyBlue, width: 1.5),
                                      ),
                                      child: Center(
                                        child: Text(
                                          s.number,
                                          style: const TextStyle(
                                            fontFamily: 'DynaPuff',
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.navyBlue,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        s.text,
                                        style: const TextStyle(
                                          fontFamily: 'Comfortaa',
                                          fontSize: 12,
                                          color: AppColors.darkText,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Session expired warning ───────────────────────────
                  if (_sessionExpired) ...[
                    Transform.rotate(
                      angle: 0.008,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFF7043), width: 2),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33FF7043), offset: Offset(4, 4)),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFFF7043), size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Session Expired',
                                    style: TextStyle(
                                      fontFamily: 'DynaPuff',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFBF360C),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'The screen capture session ended (app was closed or phone restarted). Re-grant permission to activate the tile again.',
                                    style: TextStyle(
                                      fontFamily: 'Comfortaa',
                                      fontSize: 11,
                                      color: AppColors.darkText,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Permission 1: Screen Capture ─────────────────────────
                  _PermissionCard(
                    icon: Icons.screenshot_monitor_rounded,
                    title: 'Screen Capture',
                    description:
                        'Required once to let the tile capture your screen when activated from the notification shade.',
                    isGranted: _hasProjection,
                    isLoading: _isCheckingProjection,
                    onGrant: _grantProjection,
                    rotation: 0.01,
                  ),
                  const SizedBox(height: 16),

                  // ── Permission 2: Display Over Other Apps ────────────────
                  _PermissionCard(
                    icon: Icons.layers_rounded,
                    title: 'Display Over Other Apps',
                    description:
                        'Required to show the solved board as a floating window above any application.',
                    isGranted: _hasOverlay,
                    isLoading: false,
                    onGrant: _grantOverlay,
                    rotation: -0.01,
                  ),
                  const SizedBox(height: 32),

                  // ── Status / Done button ──────────────────────────────────
                  if (allGranted) ...[
                    Transform.rotate(
                      angle: -0.015,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.navyBlue, width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.navyBlue,
                              offset: Offset(5, 5),
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: AppColors.navyBlue, size: 40),
                            const SizedBox(height: 10),
                            const Text(
                              'All set! 🎉',
                              style: TextStyle(
                                fontFamily: 'DynaPuff',
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyBlue,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Pull down your notification shade and add the "NQ Solver" tile to Quick Settings. Tap it anytime to solve a board on your screen.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Comfortaa',
                                fontSize: 12,
                                color: AppColors.darkText,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.navyBlue,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black26,
                                        offset: Offset(3, 3))
                                  ],
                                ),
                                child: const Text(
                                  'DONE',
                                  style: TextStyle(
                                    fontFamily: 'DynaPuff',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _steps = [
    _Step('1', 'Pull down the notification shade and long-press a tile.'),
    _Step('2', 'Add "NQ Solver" to your Quick Settings panel.'),
    _Step('3', 'Open any app that shows an N-Queens board.'),
    _Step('4', 'Tap the tile — the board is captured, solved and shown as a floating overlay automatically.'),
  ];
}

class _Step {
  final String number;
  final String text;
  const _Step(this.number, this.text);
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable permission card widget
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final bool isLoading;
  final VoidCallback onGrant;
  final double rotation;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.isLoading,
    required this.onGrant,
    this.rotation = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isGranted ? const Color(0xFFF1F8E9) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isGranted ? Colors.green : AppColors.navyBlue.withValues(alpha: 0.4),
            width: isGranted ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.navyBlue.withValues(alpha: 0.1),
              offset: const Offset(4, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isGranted
                    ? Colors.green.withValues(alpha: 0.15)
                    : AppColors.gold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isGranted ? Colors.green : AppColors.navyBlue,
                  width: 2,
                ),
              ),
              child: Icon(
                isGranted ? Icons.check_rounded : icon,
                color: isGranted ? Colors.green : AppColors.navyBlue,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'DynaPuff',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: 'Comfortaa',
                      fontSize: 11,
                      color: AppColors.secondaryText,
                      height: 1.4,
                    ),
                  ),
                  if (!isGranted) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: isLoading ? null : onGrant,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.navyBlue,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black26, offset: Offset(2, 2))
                          ],
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Grant Permission',
                                style: TextStyle(
                                  fontFamily: 'DynaPuff',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
