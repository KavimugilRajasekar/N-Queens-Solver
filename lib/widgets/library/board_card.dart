import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../constants/colors.dart';
import '../../constants/region_colors.dart';
import '../../utils/board_processor.dart';
import '../../screens/n_queens_board.dart';

class LibraryBoardCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  final int? selectionIndex;

  final bool isRenameMode;

  /// Pass true when this entry came from the server-side Daily Quest pipeline.
  /// The card then renders in light blue with a 🔔 badge and hides its
  /// rename/delete buttons so the user can't mutate server-picked content.
  final bool isDailyQuest;

  /// When true (and the quest is unsolved), paint the bell in the accent
  /// colour so the user can spot fresh quests in their library.
  final bool hasUnseenNotification;

  const LibraryBoardCard({
    super.key,
    required this.data,
    required this.isSelectionMode,
    required this.isSelected,
    this.selectionIndex,
    this.isRenameMode = false,
    this.isDailyQuest = false,
    this.hasUnseenNotification = false,
    required this.onToggleSelection,
    required this.onRename,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final BoardData board = data['board'];
    // A board is solvable if it has a solution OR if it was manually solved
    final bool isSolvable = board.solution != null || board.isManuallySolved;

    // ── Theme selection ────────────────────────────────────────────────
    // Priority (high → low):
    //   1. Manually solved  → gold (trophy badge stays).
    //   2. Daily quest failed (3 attempts burned) → light-red + lock badge.
    //   3. Daily quest (still hidden) → blue, foggy "?" preview tile.
    //   4. Daily quest (revealed)     → blue, normal region grid.
    //   5. Regular board → white.
    final Color cardBg;
    final Color borderColor;
    if (board.isManuallySolved) {
      cardBg = const Color(0xFFFFFDE7);
      borderColor = AppColors.gold.withValues(alpha: 0.5);
    } else if (isDailyQuest && board.isFailed) {
      cardBg = AppColors.dailyQuestFailedBg;
      borderColor = AppColors.dailyQuestFailedBorder.withValues(alpha: 0.6);
    } else if (isDailyQuest) {
      cardBg = AppColors.dailyQuestBlue;
      borderColor = AppColors.dailyQuestBlueAccent.withValues(alpha: 0.6);
    } else {
      cardBg = Colors.white;
      borderColor = AppColors.navyBlue.withValues(alpha: 0.2);
    }
    final double borderWidth = board.isManuallySolved ? 2 : 1.5;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: (board.isManuallySolved
                    ? AppColors.gold
                    : (isDailyQuest && board.isFailed
                        ? AppColors.dailyQuestFailedBorder
                        : (isDailyQuest
                            ? AppColors.dailyQuestBlueAccent
                            : AppColors.navyBlue)))
                .withValues(alpha: (isDailyQuest && board.isFailed) ? 0.15 : 0.05),
            offset: const Offset(4, 4),
          )
        ],
      ),
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              // Daily quest that hasn't been revealed yet → foggy "?" tile
              // instead of the colored region grid. Daily quests that are
              // revealed-but-unsolved still show the region colors so the
              // user can review their progress.
              leading: isDailyQuest && !board.isRevealed && !board.isManuallySolved
                  ? _buildMysteryPreview(board.size)
                  : _buildBoardPreview(board),
              title: Row(
                children: [
                  if (isDailyQuest) ...[
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: AppColors.dailyQuestBlueDeep,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      data['name'],
                      style: const TextStyle(
                        fontFamily: 'DynaPuff',
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _buildSubtitle(board, data, isDailyQuest),
                      style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 12),
                    ),
                    if (isDailyQuest)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${board.questTitle ?? "Daily Quest"}  •  ${_difficultyLabel(board.size)}',
                          style: TextStyle(
                            fontFamily: 'Comfortaa',
                            fontSize: 11,
                            color: AppColors.dailyQuestBlueDeep,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              onTap: () async {
                if (isSelectionMode) {
                  // Daily quests are non-exportable — never let them enter QR share.
                  if (isSolvable && !isDailyQuest) onToggleSelection();
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NQueensBoardScreen(
                        boardData: board,
                        isAlreadySaved: true,
                        boardId: data['id'],
                        isDailyQuest: isDailyQuest,
                      ),
                    ),
                  );
                  onRefresh();
                }
              },
            ),
          ),

          // Lock overlay for non-solvable boards in selection mode.
          if (isSelectionMode && !isSolvable)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Icon(Icons.lock_outline_rounded, color: Colors.grey, size: 30),
                ),
              ),
            ),

          if (isSelectionMode && isSolvable && !isDailyQuest)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.navyBlue : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  boxShadow: isSelected
                      ? [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(2, 2))]
                      : null,
                ),
                child: Center(
                  child: isSelected
                      ? Text(
                          selectionIndex != null ? (selectionIndex! + 1).toString() : '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'DynaPuff',
                          ),
                        )
                      : null,
                ),
              ),
            ),

          // Trophy for solved boards — applies to both regular and daily.
          if (board.isManuallySolved)
            Positioned(
              top: 2,
              left: 2,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Lottie.asset('assets/json/winner_badge.json', repeat: true),
              ),
            ),

          // Notification bell — daily quest only, and only while unsolved.
          if (isDailyQuest && !board.isManuallySolved)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: board.isFailed
                      ? AppColors.dailyQuestFailedAccent
                      : (hasUnseenNotification
                          ? AppColors.dailyQuestBlueDeep
                          : Colors.white.withValues(alpha: 0.85)),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: board.isFailed
                        ? AppColors.dailyQuestFailedAccent
                        : AppColors.dailyQuestBlueDeep,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  board.isFailed
                      ? Icons.lock_rounded
                      : (hasUnseenNotification
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded),
                  size: 16,
                  color: (hasUnseenNotification || board.isFailed)
                      ? Colors.white
                      : AppColors.dailyQuestBlueDeep,
                ),
              ),
            ),

          // "ALL 3 ATTEMPTS USED" pill — daily quest that exhausted its
          // attempts today. Sits in the bottom-right of the card.
          if (isDailyQuest && board.isFailed)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.dailyQuestFailedAccent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      offset: const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: const Text(
                  'ALL 3 USED',
                  style: TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),

          // Attempts-left pill — daily quest that has been revealed but is
          // still in the running. Hidden when the user has solved it OR
          // burned all 3 attempts.
          if (isDailyQuest && board.isRevealed && !board.isManuallySolved && !board.isFailed)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.dailyQuestBlueDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      offset: const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  '${BoardData.kMaxDailyAttempts - board.attemptsUsed} LEFT',
                  style: const TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),

          // Rename/delete button — hidden for Daily Quest (read-only).
          if (!isSelectionMode && !isDailyQuest)
            Positioned(
              bottom: 4,
              right: 4,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: IconButton(
                  key: ValueKey(isRenameMode),
                  icon: Icon(
                    isRenameMode ? Icons.edit_outlined : Icons.delete_outline_rounded,
                    color: isRenameMode ? AppColors.navyBlue : Colors.redAccent,
                    size: 18,
                  ),
                  onPressed: isRenameMode ? onRename : onDelete,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoardPreview(BoardData board) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.navyBlue.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: board.size),
          itemCount: board.size * board.size,
          itemBuilder: (context, i) {
            int r = i ~/ board.size;
            int c = i % board.size;
            int id = board.regionIds[r][c];
            bool hasQueen = board.solution?.values.any((p) => p.x - 1 == r && p.y - 1 == c) ?? false;
            bool isInvalid = id > board.size;

            return Container(
              color: RegionColors.getRegionColor(id, board.size),
              child: Stack(
                children: [
                  if (hasQueen)
                    const Center(child: Icon(Icons.stars_rounded, size: 6, color: AppColors.navyBlue)),
                  if (isInvalid && !hasQueen)
                    const Center(child: Icon(Icons.close_rounded, size: 8, color: Colors.black26)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Foggy "?" tile shown in the library when a daily quest is still
  /// unrevealed. Pairs with the [dailyQuizFog] overlay on the quiz screen
  /// so the user never sees the colored region grid until they tap REVEAL.
  Widget _buildMysteryPreview(int boardSize) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.dailyQuizFog,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.dailyQuestBlueDeep, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.dailyQuestBlueDeep.withValues(alpha: 0.25),
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          '?',
          style: TextStyle(
            fontFamily: 'DynaPuff',
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
      ),
    );
  }

  /// Build the secondary subtitle shown under each library card.
  ///
  /// For Daily Quests we deliberately suppress the local save date — the
  /// server already stamps each quest with a canonical `questDate`, so
  /// printing both produced visually-duplicate entries like
  /// `7x7 • 2026-06-17 • 2026-06-17`. We keep the server date and add the
  /// local save date only when it actually differs (e.g. an out-of-date
  /// device, or a clock-skew edge case).
  ///
  /// Daily quests also get a status suffix that doubles as a CTA:
  /// `TAP TO REVEAL` (never-revealed), `TAP TO RETRY` (some attempts
  /// burned), `SOLVED` (gold), `FAILED — try again tomorrow` (locked).
  static String _buildSubtitle(
    BoardData board,
    Map<String, dynamic> data,
    bool isDailyQuest,
  ) {
    final date = data['date'] as DateTime;
    final localStamp =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    if (isDailyQuest && board.questDate != null) {
      final showLocal = board.questDate != localStamp;
      String statusSuffix;
      if (board.isFailed) {
        statusSuffix = 'FAILED — try again tomorrow';
      } else if (board.isManuallySolved) {
        statusSuffix = 'SOLVED';
      } else if (board.isRevealed && board.attemptsUsed > 0) {
        statusSuffix = 'TAP TO RETRY';
      } else {
        statusSuffix = 'TAP TO REVEAL';
      }
      final datePart = showLocal
          ? '${board.size}x${board.size}  •  ${board.questDate}  •  saved $localStamp'
          : '${board.size}x${board.size}  •  ${board.questDate}';
      return '$datePart  •  $statusSuffix';
    }
    return '${board.size}x${board.size}  •  $localStamp';
  }

  /// Map the daily-quest board size to the same difficulty labels the
  /// server uses. Local-only — no network round-trip.
  static String _difficultyLabel(int size) {
    switch (size) {
      case 4:
        return 'Easy';
      case 5:
        return 'Easy';
      case 6:
        return 'Medium';
      case 7:
        return 'Hard';
      default:
        return 'Medium';
    }
  }
}
