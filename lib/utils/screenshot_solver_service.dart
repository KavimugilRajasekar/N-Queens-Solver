import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'board_processor.dart';
import 'solver_logic.dart';
import 'storage_manager.dart';
import '../constants/region_colors.dart';

/// Flutter-side service that bridges the native screenshot-capture pipeline
/// to the Dart solver (solver_logic.dart) and the native overlay.
///
/// Flow:
///  1. Native [ProjectionSessionService] captures + uploads → parses board JSON
///     → broadcasts it via [_eventChannel].
///  2. Flutter reconstructs [BoardData] and runs [NQueensSolver] (solver_logic.dart).
///  3. On success → saves to library + calls "showSolvedOverlay" with the solution.
///  4. On failure → calls "showSolvedOverlay" with null solution + a human-readable
///     [failReason] so the overlay can explain why it couldn't be solved.
///  5. In all cases "dismissLoadingOverlay" is called so the native spinner clears.
class ScreenshotSolverService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final ScreenshotSolverService instance = ScreenshotSolverService._();
  ScreenshotSolverService._();

  // ── Platform channels ─────────────────────────────────────────────────────
  static const _methodChannel = MethodChannel(
    'com.example.n_queens_solver/screenshot_solver',
  );
  static const _eventChannel = EventChannel(
    'com.example.n_queens_solver/board_results',
  );

  // ── Internal state ────────────────────────────────────────────────────────
  StreamSubscription? _boardResultSub;
  bool _isInitialized = false;

  /// Call once from main() or LandingPage.initState().
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _boardResultSub = _eventChannel
        .receiveBroadcastStream()
        .listen(_onBoardResultReceived, onError: _onBoardResultError);
  }

  void dispose() {
    _boardResultSub?.cancel();
    _boardResultSub = null;
    _isInitialized = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permission helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> requestMediaProjection() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('requestMediaProjection');
      return result ?? false;
    } catch (e) {
      debugPrint('ScreenshotSolverService: requestMediaProjection error: $e');
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _methodChannel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('ScreenshotSolverService: requestOverlayPermission error: $e');
    }
  }

  Future<bool> hasOverlayPermission() async {
    try {
      return await _methodChannel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns true only when BOTH the pref flag is set AND
  /// the ProjectionSessionService is actually running (live session).
  /// The setup screen uses this so "All set" only shows when the session
  /// is genuinely alive — not just a stale pref from a previous install.
  Future<bool> hasMediaProjectionPermission() async {
    try {
      final hasPref = await _methodChannel.invokeMethod<bool>('hasMediaProjectionPermission') ?? false;
      if (!hasPref) return false;
      // Also verify the service is alive
      final alive = await _methodChannel.invokeMethod<bool>('isSessionAlive') ?? false;
      return alive;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismissOverlay() async {
    try {
      await _methodChannel.invokeMethod('dismissOverlay');
    } catch (_) {}
  }

  Future<bool> isOverlayVisible() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isOverlayVisible') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Board result pipeline
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onBoardResultReceived(dynamic event) async {
    if (event is! String) return;

    String? failReason;
    BoardData? boardData;

    try {
      final json = jsonDecode(event) as Map<String, dynamic>;
      boardData = _reconstructBoardData(json);

      if (boardData == null) {
        failReason = 'Board data could not be reconstructed from the server response. The image may be unclear or partially outside the frame.';
        debugPrint('ScreenshotSolverService: boardData reconstruction failed');
      } else {
        // Run the full solver_logic.dart solver
        final solveResult = await _solveBoardAsync(boardData);
        if (solveResult.solution != null) {
          boardData.solution = solveResult.solution;
          // Auto-save to library
          try {
            final boardId = await StorageManager.saveBoard(
              boardData,
              name: 'Quick Scan ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            );
            debugPrint('ScreenshotSolverService: saved board id=$boardId');
          } catch (e) {
            debugPrint('ScreenshotSolverService: save error: $e');
          }
        } else {
          failReason = solveResult.failReason;
        }
      }
    } catch (e) {
      final msg = e.toString();
      failReason = 'An unexpected error occurred while processing the board: ${msg.length > 120 ? msg.substring(0, 120) : msg}';
      debugPrint('ScreenshotSolverService: pipeline error: $e');
    }

    // Always call showSolvedOverlay so the native loading spinner is dismissed
    // and the overlay (solved or error panel) is shown.
    await _showOverlay(boardData, failReason);
  }

  void _onBoardResultError(dynamic error) {
    debugPrint('ScreenshotSolverService: event channel error: $error');
    // Dismiss the loading spinner even on channel error
    _methodChannel.invokeMethod('dismissLoadingOverlay').catchError((_) {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Board reconstruction from native JSON
  // ─────────────────────────────────────────────────────────────────────────

  BoardData? _reconstructBoardData(Map<String, dynamic> json) {
    try {
      final int size = json['size'] as int;
      final String rawResponse = json['rawResponse'] as String? ?? '';
      final regionIdsRaw = json['regionIds'] as List<dynamic>;

      final regionIds = regionIdsRaw
          .map((row) => (row as List<dynamic>).map((c) => c as int).toList())
          .toList();

      final regions = <int, BoardRegion>{};
      for (int r = 0; r < size; r++) {
        for (int c = 0; c < size; c++) {
          final id = regionIds[r][c];
          if (id <= 0 || id > size) continue;
          final color = RegionColors.getRegionColor(id, size);
          regions
              .putIfAbsent(id, () => BoardRegion(id: id, color: color, coordinates: []))
              .coordinates
              .add(Point(r + 1, c + 1));
        }
      }

      return BoardData(
        size: size,
        regionIds: regionIds,
        regions: regions,
        rawResponse: rawResponse,
      );
    } catch (e) {
      debugPrint('_reconstructBoardData error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Solve using solver_logic.dart (NQueensSolver — MRV + backtracking)
  // ─────────────────────────────────────────────────────────────────────────

  Future<_SolveResult> _solveBoardAsync(BoardData board) async {
    try {
      final solver = NQueensSolver(board);

      // Detect which regions have zero cells (empty domain = impossible)
      final emptyRegions = board.regions.entries
          .where((e) => e.value.coordinates.isEmpty)
          .map((e) => e.key)
          .toList();
      if (emptyRegions.isNotEmpty) {
        return _SolveResult(
          null,
          'Region${emptyRegions.length > 1 ? 's' : ''} '
          '${emptyRegions.join(', ')} '
          '${emptyRegions.length > 1 ? 'have' : 'has'} no cells assigned. '
          'The board scan may be incomplete — try capturing again with the full board visible.',
        );
      }

      await for (final step in solver.solve()) {
        if (step.message.contains('SUCCESS') &&
            step.queenPositions.length == board.size) {
          return _SolveResult(Map.from(step.queenPositions), null);
        }
        if (step.message.contains('FAILURE')) {
          // Extract a human-readable reason from the solver's last message
          final reason = _buildFailureReason(board);
          return _SolveResult(null, reason);
        }
      }

      return _SolveResult(
        null,
        'The solver exhausted all possibilities without finding a valid queen placement. '
        'This usually means the board regions overlap or were not scanned correctly.',
      );
    } catch (e) {
      debugPrint('_solveBoardAsync error: $e');
      final msg = e.toString();
      return _SolveResult(
        null,
        'Solver crashed unexpectedly: ${msg.length > 100 ? msg.substring(0, 100) : msg}',
      );
    }
  }

  /// Produce a concise, user-friendly explanation of why the board has no solution.
  String _buildFailureReason(BoardData board) {
    final n = board.size;

    // Check: number of regions != board size
    if (board.regions.length != n) {
      return 'Expected $n colour regions for a ${n}×$n board, '
          'but found ${board.regions.length}. '
          'The scan may have merged or missed some regions.';
    }

    // Check: any region with only 1 cell that shares a row/col with another single-cell region
    final singleCellRegions = board.regions.entries
        .where((e) => e.value.coordinates.length == 1)
        .toList();
    if (singleCellRegions.length > 1) {
      final rows = singleCellRegions.map((e) => e.value.coordinates.first.x).toSet();
      final cols = singleCellRegions.map((e) => e.value.coordinates.first.y).toSet();
      if (rows.length < singleCellRegions.length || cols.length < singleCellRegions.length) {
        return 'Multiple single-cell regions share the same row or column, '
            'making it impossible to place queens without conflict.';
      }
    }

    return 'No valid queen placement exists for this board. '
        'Queens must be placed one per row, one per column, '
        'one per region, and no two queens can touch — '
        'even diagonally. The current region layout has no solution.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Native overlay display
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showOverlay(BoardData? board, String? failReason) async {
    // If we have no board at all, just dismiss the loading spinner
    if (board == null) {
      try {
        await _methodChannel.invokeMethod('dismissLoadingOverlay');
      } catch (_) {}
      return;
    }

    final Map<String, List<int>>? solutionMap = board.solution?.map(
      (regionId, point) => MapEntry(regionId.toString(), [point.x, point.y]),
    );

    try {
      await _methodChannel.invokeMethod('showSolvedOverlay', {
        'size': board.size,
        'regionIds': board.regionIds,
        'solution': solutionMap,
        if (failReason != null) 'failReason': failReason,
      });
    } catch (e) {
      debugPrint('ScreenshotSolverService: showSolvedOverlay error: $e');
      // Ensure loading overlay is always dismissed even if showSolvedOverlay fails
      try { await _methodChannel.invokeMethod('dismissLoadingOverlay'); } catch (_) {}
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal result container
// ─────────────────────────────────────────────────────────────────────────────

class _SolveResult {
  final Map<int, Point>? solution;
  final String? failReason;
  const _SolveResult(this.solution, this.failReason);
}
