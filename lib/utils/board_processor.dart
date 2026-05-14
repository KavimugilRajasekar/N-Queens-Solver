import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class BoardRegion {
  final int id;
  final Color color;
  final List<Point> coordinates;

  BoardRegion({required this.id, required this.color, required this.coordinates});
}

class Point {
  final int x;
  final int y;

  Point(this.x, this.y);

  @override
  String toString() => '($x,$y)';
}

class BoardData {
  final int size;
  final List<List<Color>> grid;
  final Map<int, BoardRegion> regions;

  BoardData({required this.size, required this.grid, required this.regions});
}

class BoardProcessor {
  static Future<BoardData> processImage(String imagePath, int size) async {
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) throw Exception('Could not decode image');

    // Square crop
    int width = image.width;
    int height = image.height;
    int side = width < height ? width : height;
    int xOffset = (width - side) ~/ 2;
    int yOffset = (height - side) ~/ 2;

    final cropped = img.copyCrop(image, x: xOffset, y: yOffset, width: side, height: side);
    
    // 1. Collect all sample colors
    int cellSide = side ~/ size;
    List<Color> sampleColors = [];
    List<Point> points = [];
    
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        int centerX = c * cellSide + cellSide ~/ 2;
        int centerY = r * cellSide + cellSide ~/ 2;
        final pixel = cropped.getPixel(centerX, centerY);
        sampleColors.add(Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()));
        points.add(Point(c + 1, r + 1));
      }
    }

    // 2. Cluster colors into exactly 'size' (N) regions
    // We'll use a simple iterative approach to find N representative colors
    List<Color> centroids = [];
    if (sampleColors.isNotEmpty) {
      centroids.add(sampleColors[0]);
      while (centroids.length < size && centroids.length < sampleColors.length) {
        // Find the color furthest from existing centroids
        Color? bestColor;
        double maxDist = -1;
        
        for (var color in sampleColors) {
          double minDistToCentroid = centroids.map((c) => _colorDistance(color, c)).reduce((a, b) => a < b ? a : b);
          if (minDistToCentroid > maxDist) {
            maxDist = minDistToCentroid;
            bestColor = color;
          }
        }
        if (bestColor != null) centroids.add(bestColor);
      }
    }

    // 3. Map each cell to the nearest centroid
    final grid = List.generate(size, (_) => List.filled(size, Colors.white));
    final Map<int, List<Point>> regionCoordinates = {};
    final Map<int, Color> regionColors = {};

    for (int i = 0; i < sampleColors.length; i++) {
      Color color = sampleColors[i];
      Point pt = points[i];
      
      int bestCentroidIdx = 0;
      double minDist = double.infinity;
      
      for (int j = 0; j < centroids.length; j++) {
        double dist = _colorDistance(color, centroids[j]);
        if (dist < minDist) {
          minDist = dist;
          bestCentroidIdx = j;
        }
      }

      int regionId = bestCentroidIdx + 1;
      grid[pt.y - 1][pt.x - 1] = centroids[bestCentroidIdx];
      regionColors[regionId] = centroids[bestCentroidIdx];
      regionCoordinates.putIfAbsent(regionId, () => []).add(pt);
    }

    final regions = <int, BoardRegion>{};
    regionCoordinates.forEach((id, coords) {
      regions[id] = BoardRegion(
        id: id,
        color: regionColors[id]!,
        coordinates: coords,
      );
    });

    return BoardData(size: size, grid: grid, regions: regions);
  }

  static double _colorDistance(Color c1, Color c2) {
    return (c1.red - c2.red).abs().toDouble() + 
           (c1.green - c2.green).abs().toDouble() + 
           (c1.blue - c2.blue).abs().toDouble();
  }
}
