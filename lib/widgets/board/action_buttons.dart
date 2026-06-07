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
  });

  @override
  Widget build(BuildContext context) {
    bool canSolve = !hasConflicts && !isSolving && !isEditing && !isManualMode;

    return Column(
      children: [
        if (isManualMode) ...[
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
        if (hasConflicts && !isEditing && !isManualMode) ...[
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
}
