import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../constants/colors.dart';

class FunkyErrorDialog {
  static Future<void> show(BuildContext context, {String title = 'Oops!', String message = 'Something went wrong!'}) {
    return showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Transform.rotate(
          angle: -0.02,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE4EC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.navyBlue, width: 2.5),
              boxShadow: [
                BoxShadow(color: AppColors.navyBlue.withOpacity(0.25), offset: const Offset(8, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
                          const SizedBox(height: 6),
                          Text(
                            message,
                            style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.darkText, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: Lottie.asset('assets/json/error.json', repeat: true),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Transform.rotate(
                  angle: 0.01,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                        boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(4, 4))],
                      ),
                      child: const Center(
                        child: Text('Got it!', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
