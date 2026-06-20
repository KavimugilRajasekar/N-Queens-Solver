import 'package:flutter/material.dart';
import '../../utils/board_processor.dart';
import '../../constants/colors.dart';
import '../../constants/region_colors.dart';

class BoardGrid extends StatelessWidget {
  final double boardScale;
  final BoardData boardData;
  final bool isEditing;
  final bool isManualMode;
  final bool isPaused;
  final Map<int, Point> queenPositions;
  final Map<String, int> manualGrid;
  final List<List<int>>? tempGrid;
  final Map<String, dynamic> conflicts;
  final Function(int, int) onCellTap;
  final VoidCallback onPanEnd;

  /// True when the parent has already revealed a daily-quest board.
  /// When false on a daily quest we paint a navy fog + "?" sticker over
  /// the entire grid so the puzzle stays hidden until the user opts in.
  final bool isRevealed;

  /// True when this entry came from the server-side Daily Quest pipeline.
  /// Gates the fog overlay — non-daily boards always show their layout.
  final bool isDailyQuest;

  const BoardGrid({
    super.key,
    required this.boardScale,
    required this.boardData,
    required this.isEditing,
    required this.isManualMode,
    required this.isPaused,
    required this.queenPositions,
    required this.manualGrid,
    required this.tempGrid,
    required this.conflicts,
    required this.onCellTap,
    required this.onPanEnd,
    this.isRevealed = true,
    this.isDailyQuest = false,
  });

  @override
  Widget build(BuildContext context) {
    // Daily-Quest fog: until the user taps REVEAL, the grid sits underneath
    // a translucent navy layer with a centered "?" sticker. Non-daily boards
    // always render the colored grid (isRevealed defaults to true).
    final bool fogActive = isDailyQuest && !isRevealed;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isEditing ? AppColors.gold : AppColors.navyBlue, width: 3),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(8, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * boardScale,
            height: MediaQuery.of(context).size.width * boardScale,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onPanEnd: isManualMode ? (_) => onPanEnd() : null,
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: boardData.size),
                    itemCount: boardData.size * boardData.size,
                    itemBuilder: (context, index) {
                      int r = index ~/ boardData.size;
                      int c = index % boardData.size;

                      bool hasQueen = isManualMode
                          ? (manualGrid["$r,$c"] == 2)
                          : queenPositions.values.any((p) => p.x - 1 == r && p.y - 1 == c);

                      bool hasX = isManualMode && (manualGrid["$r,$c"] == 1);

                      int id = isEditing ? tempGrid![r][c] : boardData.regionIds[r][c];
                      bool isInvalid = id > boardData.size;

                      final Set<int> rowConflicts = conflicts['rows'] as Set<int>;
                      final Set<int> colConflicts = conflicts['cols'] as Set<int>;
                      final Set<int> regionConflicts = conflicts['regions'] as Set<int>;
                      final Set<String> queenConflicts = conflicts['queens'] as Set<String>;

                      bool isRowConflict = rowConflicts.contains(r);
                      bool isColConflict = colConflicts.contains(c);
                      bool isRegionConflict = regionConflicts.contains(id);
                      bool isQueenConflict = queenConflicts.contains("$r,$c");
                      bool isNeighborhoodConflict = (conflicts['neighborhood'] as Set<String>).contains("$r,$c");

                      return GestureDetector(
                        onTap: () => onCellTap(r, c),
                        child: Container(
                          decoration: BoxDecoration(
                            color: RegionColors.getRegionColor(id, boardData.size),
                            border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5)
                          ),
                          child: Stack(
                            children: [
                              // Conflict Tints
                              if (isRowConflict || isColConflict)
                                Container(color: Colors.red.withValues(alpha: 0.1)),

                              if (isRegionConflict || isRowConflict || isColConflict || isQueenConflict || isNeighborhoodConflict)
                                Center(
                                  child: Opacity(
                                    opacity: 0.2,
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.red.shade900,
                                      size: (MediaQuery.of(context).size.width * boardScale) / boardData.size
                                    ),
                                  ),
                                ),

                              if (isEditing && id > 0)
                                Center(
                                  child: Text(
                                    '$id',
                                    style: TextStyle(
                                      fontFamily: 'DynaPuff',
                                      fontSize: (MediaQuery.of(context).size.width * boardScale * 0.3) / boardData.size,
                                      color: Colors.black.withValues(alpha: 0.15),
                                      fontWeight: FontWeight.bold
                                    )
                                  )
                                ),
                              if (hasQueen)
                                Center(
                                  child: Icon(
                                    Icons.stars_rounded,
                                    color: isQueenConflict ? Colors.red.shade900 : AppColors.navyBlue,
                                    size: (MediaQuery.of(context).size.width * boardScale * 0.8) / boardData.size
                                  ),
                                ),
                              if (hasX)
                                Center(child: Text('x', style: TextStyle(fontFamily: 'Comfortaa', fontSize: (MediaQuery.of(context).size.width * boardScale * 0.5) / boardData.size, color: AppColors.navyBlue.withValues(alpha: 0.4), fontWeight: FontWeight.bold))),
                              if (!hasQueen && !hasX && isInvalid)
                                Center(
                                  child: Transform.rotate(
                                    angle: 0.1,
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: AppColors.navyBlue.withValues(alpha: 0.3),
                                      size: (MediaQuery.of(context).size.width * boardScale * 0.6) / boardData.size
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // ── Fog overlay (daily quest, pre-reveal only) ─────────────
                if (fogActive)
                  const _DailyQuizFogOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Translucent navy panel with a centred "?" sticker that sits on top of
/// the live grid until the user taps REVEAL QUIZ. Keeps the puzzle layout
/// fully hidden — only the silhouette of the board outline is visible.
class _DailyQuizFogOverlay extends StatelessWidget {
  const _DailyQuizFogOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true, // Let the bottom REVEAL QUIZ button (and Back) stay tappable.
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.dailyQuizFog,
          // Subtle diagonal stripes give the fog a "secret dossier" feel
          // without resorting to a heavy image asset.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.dailyQuizFog,
              AppColors.dailyQuizFog.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: Center(
          child: Transform.rotate(
            angle: -0.05,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    offset: const Offset(6, 6),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Text(
                '?',
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyBlue,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
