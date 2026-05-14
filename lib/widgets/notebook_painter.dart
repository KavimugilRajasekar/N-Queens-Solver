import 'package:flutter/material.dart';
import '../constants/colors.dart';

class NotebookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.paperLine
      ..strokeWidth = 1.0;

    // Draw horizontal lines
    for (double i = 0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    // Draw vertical margin line
    final marginPaint = Paint()
      ..color = Colors.red.withOpacity(0.1)
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(50, 0), Offset(50, size.height), marginPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
