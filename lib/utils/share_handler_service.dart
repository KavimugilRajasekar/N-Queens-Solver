import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../screens/n_queens_board.dart';
import '../widgets/notebook_painter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ShareHandlerService
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton that wires the native share-handler channel.
///
/// When Android delivers a shared image (ACTION_SEND), MainActivity copies the
/// image to a temp file and calls [onSharedImage] on this channel with the
/// absolute path. The service then navigates to [SharedImageProcessingScreen].
class ShareHandlerService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final ShareHandlerService instance = ShareHandlerService._();
  ShareHandlerService._();

  static const _channel =
      MethodChannel('com.example.n_queens_solver/share_handler');

  bool _initialized = false;

  /// Call once from main() — pass the same [navigatorKey] used in [MaterialApp].
  void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (_initialized) return;
    _initialized = true;

    // Listen for images pushed by native while the app is already running.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedImage') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          _navigate(navigatorKey, path);
        }
      }
    });

    // Poll for an image that arrived before the channel was registered
    // (e.g., cold-start via the share sheet).
    _channel.invokeMethod<String?>('getPendingSharedImage').then((path) {
      if (path != null && path.isNotEmpty) {
        _navigate(navigatorKey, path);
      }
    });
  }

  void _navigate(GlobalKey<NavigatorState> key, String imagePath) {
    // Small delay so the navigator is fully mounted before we push.
    Future.delayed(const Duration(milliseconds: 300), () {
      key.currentState?.push(
        MaterialPageRoute(
          builder: (_) => SharedImageProcessingScreen(imagePath: imagePath),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SharedImageProcessingScreen
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen page shown while a shared image is being analysed.
/// On success it replaces itself with [NQueensBoardScreen].
/// On failure it shows an inline error and a Go Back button.
class SharedImageProcessingScreen extends StatefulWidget {
  final String imagePath;
  const SharedImageProcessingScreen({super.key, required this.imagePath});

  @override
  State<SharedImageProcessingScreen> createState() =>
      _SharedImageProcessingScreenState();
}

class _SharedImageProcessingScreenState
    extends State<SharedImageProcessingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  String _statusText = 'Preparing image…';
  bool _failed = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _process();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _process() async {
    try {
      _setStatus('Cropping board area…');
      await BoardProcessor.cropImage(widget.imagePath);

      _setStatus('Analysing grid…');
      final boardData = await BoardProcessor.processImage(widget.imagePath, 8);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => NQueensBoardScreen(boardData: boardData),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final err = e.toString();
      final isNetwork = err.contains('Network') ||
          err.contains('SocketException') ||
          err.contains('Connection failed');

      setState(() {
        _failed = true;
        _pulseCtrl.stop();
        _errorMessage = isNetwork
            ? 'No internet connection.\nPlease connect and try again.'
            : 'Couldn\'t recognise an N-Queens board in this image.\nTry a clearer, well-lit photo.';
      });
    }
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _statusText = text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.navyBlue, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navyBlue.withValues(alpha: 0.3),
                            offset: const Offset(4, 4),
                          )
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.navyBlue, size: 26),
                    ),
                  ),

                  const Spacer(),

                  Center(
                    child: _failed ? _buildError() : _buildLoading(),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing image preview
        ScaleTransition(
          scale: _pulse,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.navyBlue, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.navyBlue,
                  offset: Offset(6, 6),
                )
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.file(
              File(widget.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.image_rounded,
                size: 64,
                color: AppColors.navyBlue,
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),

        // Spinner
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            color: AppColors.navyBlue,
            strokeWidth: 3.5,
          ),
        ),
        const SizedBox(height: 24),

        // Title
        const Text(
          'Processing Board',
          style: TextStyle(
            fontFamily: 'DynaPuff',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.navyBlue,
          ),
        ),
        const SizedBox(height: 8),

        // Dynamic status
        Text(
          _statusText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Comfortaa',
            fontSize: 14,
            color: AppColors.secondaryText,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error icon card
        Transform.rotate(
          angle: -0.03,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE4EC),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.navyBlue, width: 3),
              boxShadow: const [
                BoxShadow(color: AppColors.navyBlue, offset: Offset(6, 6))
              ],
            ),
            child: const Icon(Icons.sentiment_dissatisfied_rounded,
                size: 64, color: AppColors.navyBlue),
          ),
        ),
        const SizedBox(height: 32),

        const Text(
          'Could Not Process',
          style: TextStyle(
            fontFamily: 'DynaPuff',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.navyBlue,
          ),
        ),
        const SizedBox(height: 10),

        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Comfortaa',
            fontSize: 14,
            color: AppColors.secondaryText,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),

        // Go back button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Transform.rotate(
            angle: 0.01,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppColors.navyBlue, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                      color: AppColors.navyBlue, offset: Offset(4, 4))
                ],
              ),
              child: const Text(
                'Go Back',
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyBlue,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
