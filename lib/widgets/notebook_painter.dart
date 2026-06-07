import 'package:flutter/material.dart';
import '../constants/colors.dart';

class NotebookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.paperLine
      ..strokeWidth = 1.0;

    // Draw horizontal lines
    for (double i = 0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), linePaint);
    }

    // Draw vertical margin line
    final marginPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.15)
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(60, 0), Offset(60, size.height), marginPaint);

    // Draw some subtle "doodles" or artifacts
    final doodlePaint = Paint()
      ..color = AppColors.navyBlue.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // A small spiral in top-right
    canvas.drawCircle(Offset(size.width - 40, 40), 20, doodlePaint);
    canvas.drawCircle(Offset(size.width - 40, 40), 10, doodlePaint);

    // Some "scribbles" in bottom-left
    canvas.drawLine(Offset(20, size.height - 40), Offset(80, size.height - 20), doodlePaint);
    canvas.drawLine(Offset(30, size.height - 50), Offset(70, size.height - 10), doodlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
