import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../constants/colors.dart';

class VictoryDialog extends StatelessWidget {
  final String time;
  const VictoryDialog({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.navyBlue, width: 3),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(8, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 200,
              child: Lottie.asset(
                'assets/json/trophy.json',
                repeat: true,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'VICTORY!',
              style: TextStyle(fontFamily: 'DynaPuff', fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
            ),
            const SizedBox(height: 10),
            Text(
              'You mastered the board in $time!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.darkText),
            ),
            const SizedBox(height: 30),
            Transform.rotate(
              angle: -0.02,
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(4, 4))],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Back to Library
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0),
                  child: const Text(
                    'CELEBRATE & EXIT',
                    style: TextStyle(fontFamily: 'DynaPuff', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
