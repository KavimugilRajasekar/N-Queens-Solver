import 'package:flutter/material.dart';
import '../../constants/colors.dart';

class BoardHeader extends StatelessWidget {
  final bool isManualMode;
  final bool isPaused;
  final bool isEditing;
  final bool isSolving;
  final bool isFastForward;
  final String formattedTime;
  final VoidCallback onFastForward;

  const BoardHeader({
    super.key,
    required this.isManualMode,
    required this.isPaused,
    required this.isEditing,
    required this.isSolving,
    required this.isFastForward,
    required this.formattedTime,
    required this.onFastForward,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Transform.rotate(
          angle: 0.02,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.navyBlue, width: 2),
              boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(4, 4))],
            ),
            child: Text(
              isManualMode 
                  ? (isPaused ? 'Paused' : 'Solving...')
                  : (isEditing ? 'Correcting Regions...' : 'N-Queens Board'), 
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24, fontFamily: 'DynaPuff'),
            ),
          ),
        ),
        if (isManualMode)
          Transform.rotate(
            angle: -0.01,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.navyBlue, width: 2),
                boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(4, 4))],
              ),
              child: Text(
                formattedTime,
                style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
              ),
            ),
          ),
        if (isSolving) ...[
          const SizedBox(width: 12),
          IconButton(
            onPressed: onFastForward,
            icon: Icon(
              Icons.fast_forward_rounded, 
              color: isFastForward ? AppColors.gold : AppColors.navyBlue, 
              size: 32,
            ),
            tooltip: 'Fast Forward Solution',
          ),
        ],
      ],
    );
  }
}
