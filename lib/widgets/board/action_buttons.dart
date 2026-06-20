import 'package:flutter/material.dart';
import '../../constants/colors.dart';

class ActionButtons extends StatelessWidget {
  final bool isManualMode;
  final bool isPaused;
  final bool isSolving;
  final bool isEditing;
  final bool hasConflicts;
  final String formattedTime;
  final VoidCallback onTogglePause;
  final VoidCallback onQuitManual;
  final VoidCallback onToggleEdit;
  final VoidCallback onSolve;
  final VoidCallback onSaveEdits;
  final VoidCallback onStartManual;

  /// When true, this screen is showing a server-issued Daily Quest and the
  /// user can only solve manually. We force the manual-mode branch and
  /// disable Edit + Solve + Do-it entirely.
  final bool isDailyQuest;

  /// Daily-quiz-only: true once the user has tapped REVEAL QUIZ. Gates the
  /// bottom REVEAL → GIVE UP transition.
  final bool isRevealed;

  /// Daily-quiz-only: true once the user has burned all 3 attempts.
  /// Renders a locked-out message instead of any other button.
  final bool isFailed;

  /// Daily-quiz-only: user-facing label for the attempts counter, e.g.
  /// "Attempt 1 of 3". Empty for non-daily boards.
  final String attemptLabel;

  /// Tapped from the daily-quiz REVEAL QUIZ button. Drives the confirmation
  /// dialog (handled by the parent screen, since it owns the result).
  final VoidCallback onReveal;

  /// Tapped from the daily-quiz GIVE UP button. Counts as a failed attempt.
  final VoidCallback onGiveUp;

  const ActionButtons({
    super.key,
    required this.isManualMode,
    required this.isPaused,
    required this.isSolving,
    required this.isEditing,
    required this.hasConflicts,
    required this.formattedTime,
    required this.onTogglePause,
    required this.onQuitManual,
    required this.onToggleEdit,
    required this.onSolve,
    required this.onSaveEdits,
    required this.onStartManual,
    this.isDailyQuest = false,
    this.isRevealed = false,
    this.isFailed = false,
    this.attemptLabel = '',
    this.onReveal = _noop,
    this.onGiveUp = _noop,
  });

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    // ── Daily Quest branch ──────────────────────────────────────────────
    // Three discrete sub-states:
    //   1. !isRevealed                 → REVEAL QUIZ button only
    //   2. isRevealed && !isFailed     → GIVE UP button only (no Pause)
    //   3. isFailed                    → "Today's quest is locked" message
    if (isDailyQuest) {
      if (isFailed) return _buildLocked();
      if (!isRevealed) return _buildReveal();
      return _buildGiveUp();
    }

    // For non-daily boards we still respect the existing manual branch.
    final bool showManualBranch = isManualMode;
    bool canSolve = !hasConflicts && !isSolving && !isEditing && !isManualMode;

    return Column(
      children: [
        if (showManualBranch) ...[
          Transform.rotate(
            angle: 0.01,
            child: Container(
              width: double.infinity,
              height: 65,
              decoration: BoxDecoration(
                color: isPaused ? AppColors.gold : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(4, 4))],
              ),
              child: ElevatedButton.icon(
                onPressed: onTogglePause,
                icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: AppColors.navyBlue),
                label: Text(
                  isPaused ? 'Resume ($formattedTime)' : 'Pause',
                  style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Transform.rotate(
            angle: -0.01,
            child: Container(
              width: double.infinity,
              height: 65,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.redAccent, width: 2),
              ),
              child: ElevatedButton.icon(
                onPressed: onQuitManual,
                icon: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
                label: const Text('Quit Manual Mode', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.redAccent)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
              ),
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Transform.rotate(
                  angle: 0.02,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppColors.navyBlue, width: 2),
                      boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(4, 4))],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: isSolving ? null : onToggleEdit,
                      icon: Icon(isEditing ? Icons.close_rounded : Icons.edit_note_rounded, color: isEditing ? Colors.red : AppColors.navyBlue),
                      label: Text(isEditing ? 'Cancel' : 'Edit', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: isEditing ? Colors.red : AppColors.navyBlue)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Transform.rotate(
                  angle: -0.01,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: isSolving
                          ? Colors.grey.shade300
                          : (hasConflicts ? Colors.grey.shade200 : AppColors.gold),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppColors.navyBlue.withValues(alpha: hasConflicts ? 0.3 : 1.0), width: 2),
                      boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: hasConflicts ? 0.05 : 0.2), offset: const Offset(4, 4))]
                    ),
                    child: ElevatedButton.icon(
                      onPressed: canSolve ? onSolve : (isEditing ? onSaveEdits : null),
                      icon: isSolving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyBlue))
                          : Icon(isEditing ? Icons.check_circle_rounded : Icons.auto_fix_high_rounded, color: AppColors.navyBlue.withValues(alpha: hasConflicts && !isEditing ? 0.4 : 1.0)),
                      label: Text(isSolving ? 'Solving...' : (isEditing ? 'Save' : 'Solve'), style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyBlue.withValues(alpha: hasConflicts && !isEditing ? 0.4 : 1.0))),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Transform.rotate(
            angle: 0.01,
            child: Container(
              width: double.infinity,
              height: 65,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(4, 4))],
              ),
              child: ElevatedButton.icon(
                onPressed: canSolve ? onStartManual : null,
                icon: Icon(Icons.videogame_asset_rounded, color: canSolve ? AppColors.navyBlue : Colors.grey),
                label: Text(
                  'Do it',
                  style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20, color: canSolve ? AppColors.navyBlue : Colors.grey),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
              ),
            ),
          ),
        ],
        if (hasConflicts && !isEditing && !showManualBranch) ...[
          const SizedBox(height: 24),
          _buildFunkyConflictPrompt(),
        ],
      ],
    );
  }

  Widget _buildFunkyConflictPrompt() {
    return Transform.rotate(
      angle: -0.01,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9C4), // Soft Lemon Yellow
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.gold, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(4, 4))],
        ),
        child: const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: AppColors.navyBlue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "Whoops! Some regions are messy. Tap 'Edit' to fix the Funky-X marks!",
                style: TextStyle(fontFamily: 'DynaPuff', fontSize: 14, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Daily-Quest sub-renders
  // ─────────────────────────────────────────────────────────────────────

  /// REVEAL QUIZ — the only action on a daily quest that hasn't been
  /// revealed yet. Triggers a confirmation in the parent screen; on confirm
  /// the parent sets `isRevealed = true` and flips to manual mode.
  Widget _buildReveal() {
    return Column(
      children: [
        if (attemptLabel.isNotEmpty) ...[
          _buildAttemptPill(attemptLabel, AppColors.dailyQuestBlueDeep),
          const SizedBox(height: 16),
        ],
        Transform.rotate(
          angle: -0.02,
          child: Container(
            width: double.infinity,
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.navyBlue, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navyBlue.withValues(alpha: 0.3),
                  offset: const Offset(6, 6),
                  blurRadius: 0,
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.visibility_rounded, color: AppColors.navyBlue, size: 28),
              label: const Text(
                'REVEAL QUIZ',
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: AppColors.navyBlue,
                  letterSpacing: 1.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: AppColors.navyBlue,
                shadowColor: Colors.transparent,
                elevation: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// GIVE UP — once the user has revealed the board, this is the only
  /// action left (no Pause per the daily-quiz rules). Counts as one failed
  /// attempt; if it pushes `attemptsUsed` to 3 the parent flips `isFailed`.
  Widget _buildGiveUp() {
    return Column(
      children: [
        if (attemptLabel.isNotEmpty) ...[
          _buildAttemptPill(attemptLabel, AppColors.dailyQuestBlueDeep),
          const SizedBox(height: 16),
        ],
        Transform.rotate(
          angle: 0.02,
          child: Container(
            width: double.infinity,
            height: 65,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.redAccent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  offset: const Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: onGiveUp,
              icon: const Icon(Icons.flag_rounded, color: Colors.redAccent, size: 26),
              label: const Text(
                'GIVE UP',
                style: TextStyle(
                  fontFamily: 'DynaPuff',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.redAccent,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.redAccent,
                shadowColor: Colors.transparent,
                elevation: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// LOCKED — all 3 attempts burned. Renders a soft-pink notice + the
  /// Back to Library button so the user has a clear path back. The parent
  /// screen renders its own "Back to Library" tile too, so we keep this
  /// section as a status message only.
  Widget _buildLocked() {
    return Transform.rotate(
      angle: -0.01,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.dailyQuestFailedBg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.dailyQuestFailedBorder, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.dailyQuestFailedBorder.withValues(alpha: 0.25),
              offset: const Offset(6, 6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.dailyQuestFailedAccent, width: 2),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: AppColors.dailyQuestFailedAccent,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Today's quest is locked!",
                    style: TextStyle(
                      fontFamily: 'DynaPuff',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dailyQuestFailedAccent,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "You've used all 3 attempts. Come back tomorrow for a fresh puzzle!",
                    style: TextStyle(
                      fontFamily: 'Comfortaa',
                      fontSize: 12,
                      color: AppColors.darkText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Funky attempt-counter pill ("Attempt 1 of 3") shown above the
  /// REVEAL/GIVE UP buttons so the user always knows how many tries remain.
  Widget _buildAttemptPill(String label, Color accentColor) {
    return Transform.rotate(
      angle: 0.01,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.2),
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'DynaPuff',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: accentColor,
          ),
        ),
      ),
    );
  }
}