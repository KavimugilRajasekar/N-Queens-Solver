import 'package:flutter/material.dart';

class RegionColors {
  /// Shared Palette for all regions (N-Queens Board)
  static const List<Color> palette = [
    Color(0xFFFFB3B3), // Red 200
    Color(0xFFB3D9FF), // Blue 200
    Color(0xFFB3FFB3), // Green 200
    Color(0xFFFFD9B3), // Orange 200
    Color(0xFFE6B3FF), // Purple 200
    Color(0xFFB3FFFF), // Cyan 200
    Color(0xFFFFB3E6), // Pink 200
    Color(0xFFB3B3FF), // Indigo 200
    Color(0xFFFFE6B3), // Amber 200
    Color(0xFFB3FFE6), // Teal 200
    Color(0xFFE6FFB3), // Lime 200
    Color(0xFFD9B38C), // Brown 200
  ];

  /// Used for empty cells or unassigned regions
  static const Color emptyCell = Colors.white;

  /// Invalid region indicator - Uses Plain White to indicate it needs editing.
  static const Color errorCell = Colors.white;
  static const Color errorBorder = Color(0xFFEEEEEE);

  /// Returns the color for a given region ID based on the board size N.
  /// If id > n, it returns the [errorCell] indicating a conflict.
  static Color getRegionColor(int id, int n) {
    if (id <= 0) return emptyCell;
    if (id > n) return errorCell;
    return palette[(id - 1) % palette.length];
  }
}
