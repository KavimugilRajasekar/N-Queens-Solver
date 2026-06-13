import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../constants/colors.dart';

class FunkySuccessDialog {
  static Future<void> show(BuildContext context, {
    required String title, 
    required String message, 
    List<String> importedNames = const []
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Transform.rotate(
          angle: 0.02,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8E9), // Soft Green
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: AppColors.navyBlue, width: 2.5),
              boxShadow: [
                BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.2), offset: const Offset(8, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Lottie.asset('assets/json/success.json', repeat: false),
                ),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.darkText, height: 1.4),
                ),
                
                if (importedNames.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppColors.navyBlue.withValues(alpha: 0.1)),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: importedNames.map((name) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: AppColors.gold, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name, style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 13, color: AppColors.navyBlue))),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Transform.rotate(
                  angle: -0.015,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                        boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(4, 4))],
                      ),
                      child: const Center(
                        child: Text('Awesome!', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
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
