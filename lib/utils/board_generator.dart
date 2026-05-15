import 'dart:math';
import 'package:flutter/material.dart';
import 'board_processor.dart';
import 'storage_manager.dart';
import '../constants/region_colors.dart';

class BoardGenerator {
  static final Random _random = Random();

  /// Generates a new unique board of the given size.
  static Future<BoardData?> generateUniqueBoard(int size) async {
    final existingBoards = await StorageManager.loadBoards();
    
    // Attempt to generate a unique board (up to 20 attempts)
    for (int attempt = 0; attempt < 20; attempt++) {
      final board = _generateRandomBoard(size);
      
      // Check if this layout already exists
      bool exists = existingBoards.any((eb) {
        final eBoard = eb['board'] as BoardData;
        if (eBoard.size != size) return false;
        for (int r = 0; r < size; r++) {
          for (int c = 0; c < size; c++) {
            if (eBoard.regionIds[r][c] != board.regionIds[r][c]) return false;
          }
        }
        return true;
      });

      if (!exists) return board;
    }
    
    return null; // Could not generate a unique one in time
  }

  static BoardData _generateRandomBoard(int size) {
    // 1. Generate a random queen placement (one per row and column)
    // Diagonals don't matter in this specific game logic, only Row, Col, and Region.
    List<int> queenCols = List.generate(size, (i) => i)..shuffle(_random);
    Map<int, Point> solution = {};
    for (int r = 0; r < size; r++) {
      solution[r + 1] = Point(r + 1, queenCols[r] + 1);
    }

    // 2. Initialize regions with queens as seeds
    List<List<int>> regionIds = List.generate(size, (_) => List.filled(size, 0));
    List<List<Point>> seeds = List.generate(size, (_) => []);
    
    for (int r = 0; r < size; r++) {
      int c = queenCols[r];
      regionIds[r][c] = r + 1; // Region ID starts from 1 to N
      seeds[r].add(Point(r, c));
    }

    // 3. Grow regions using randomized BFS (Flood Fill)
    List<Point> available = [];
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (regionIds[r][c] == 0) available.add(Point(r, c));
      }
    }

    // Directions for expansion
    final dirs = [Point(0, 1), Point(0, -1), Point(1, 0), Point(-1, 0)];

    // Expansion queue: List of points that are adjacent to a colored region
    List<Map<String, dynamic>> frontiers = [];
    for (int r = 0; r < size; r++) {
      frontiers.add({
        'id': r + 1,
        'points': [Point(r, queenCols[r])]
      });
    }

    int remaining = size * size - size;
    while (remaining > 0) {
      frontiers.shuffle(_random);
      bool grown = false;
      
      for (var frontier in frontiers) {
        int id = frontier['id'];
        List<Point> points = frontier['points'];
        points.shuffle(_random);
        
        for (var p in points) {
          dirs.shuffle(_random);
          for (var d in dirs) {
            int nr = p.x + d.x;
            int nc = p.y + d.y;
            
            if (nr >= 0 && nr < size && nc >= 0 && nc < size && regionIds[nr][nc] == 0) {
              regionIds[nr][nc] = id;
              points.add(Point(nr, nc));
              remaining--;
              grown = true;
              break;
            }
          }
          if (grown) break;
        }
        if (grown) break;
      }
      
      // Safety break if stuck
      if (!grown) break;
    }

    // Final check for orphans (should not happen with BFS but safety first)
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (regionIds[r][c] == 0) {
          // Find any neighbor and take its ID
          for (var d in dirs) {
            int nr = r + d.x;
            int nc = c + d.y;
            if (nr >= 0 && nr < size && nc >= 0 && nc < size && regionIds[nr][nc] != 0) {
              regionIds[r][c] = regionIds[nr][nc];
              break;
            }
          }
        }
      }
    }

    // 4. Construct regions map
    final regions = <int, BoardRegion>{};
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        int id = regionIds[r][c];
        final color = RegionColors.getRegionColor(id, size);
        regions.putIfAbsent(id, () => BoardRegion(id: id, color: color, coordinates: [])).coordinates.add(Point(r + 1, c + 1));
      }
    }

    return BoardData(
      size: size,
      regionIds: regionIds,
      regions: regions,
      rawResponse: "AI Generated",
      solution: solution,
    );
  }
}
