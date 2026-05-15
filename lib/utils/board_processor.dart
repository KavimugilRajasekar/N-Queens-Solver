import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/region_colors.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;
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
  final List<List<int>> regionIds; // 1-based region IDs
  final Map<int, BoardRegion> regions;
  final String rawResponse;
  Map<int, Point>? solution;

  BoardData({
    required this.size,
    required this.regionIds,
    required this.regions,
    required this.rawResponse,
    this.solution,
  });
}

class BoardProcessor {
  static const String _apiUrl = 'https://image-processor-livid.vercel.app/process-image';

  static Color getRegionColor(int id, int n) {
    return RegionColors.getRegionColor(id, n);
  }

  static Future<BoardData> processImage(String imagePath, int size) async {
    try {
      debugPrint('Processing image for upload: $imagePath');

      // 1. Image Preprocessing (Orientation + Square Crop)
      final bytes = await File(imagePath).readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage != null) {
        img.Image fixedImage = img.bakeOrientation(originalImage);
        int width = fixedImage.width;
        int height = fixedImage.height;
        int side = width < height ? width : height;
        img.Image squareImage = img.copyCrop(
          fixedImage, 
          x: (width - side) ~/ 2, 
          y: (height - side) ~/ 2, 
          width: side, 
          height: side
        );
        await File(imagePath).writeAsBytes(img.encodeJpg(squareImage, quality: 90));
      }
      
      // 2. Upload to API
      var request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.files.add(await http.MultipartFile.fromPath(
        'file', 
        imagePath,
        filename: path.basename(imagePath),
        contentType: MediaType('image', 'jpeg'),
      ));

      var streamedResponse = await request.send().timeout(const Duration(seconds: 45));
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint('API Status: ${response.statusCode}');
      debugPrint('API Raw Response: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server Error (${response.statusCode}):\n${response.body}');
      }

      // 3. Parse and Dynamic Size Detection
      String responseBody = response.body;
      Map<int, List<Point>> regionMap = _parseApiResponse(responseBody);

      if (regionMap.isEmpty) {
        throw Exception('No region data extracted.\nResponse: $responseBody');
      }

      // Determine dynamic board size N based on coordinates (assuming 1-based from server)
      int maxVal = 0;
      for (var coords in regionMap.values) {
        for (var pt in coords) {
          if (pt.x > maxVal) maxVal = pt.x;
          if (pt.y > maxVal) maxVal = pt.y;
        }
      }
      
      // Since server is 1-based, the maximum coordinate value IS the board size N
      int detectedN = maxVal > 0 ? maxVal : size; 
      if (detectedN > 12) detectedN = 12; // CAP at 12x12
      debugPrint('Detected Board Size (N): $detectedN');

      // 4. Construct BoardData (Map 1-based to 0-based)
      final regionIds = List.generate(detectedN, (_) => List.filled(detectedN, 0));
      final regions = <int, BoardRegion>{};

      // Normalize IDs to be 1..N to avoid gaps and ensure Region 1 always gets Color 1
      int normalizedId = 1;
      final Map<int, int> idMapping = {};
      
      // SORT the keys so that original Q1 maps to normalized 1, Q2 to 2, etc.
      final sortedKeys = regionMap.keys.toList()..sort();

      for (var originalId in sortedKeys) {
        final coords = regionMap[originalId]!;
        int id = normalizedId++; // We assign sequential IDs starting from 1
        
        Color color = getRegionColor(id, detectedN);
        regions[id] = BoardRegion(id: id, color: color, coordinates: coords);

        for (var pt in coords) {
          int row = pt.x - 1;
          int col = pt.y - 1;

          if (row >= 0 && row < detectedN && col >= 0 && col < detectedN) {
            regionIds[row][col] = id;
          }
        }
      }

      return BoardData(
        size: detectedN,
        regionIds: regionIds,
        regions: regions,
        rawResponse: response.body,
      );
    } catch (e) {
      debugPrint('Fatal Error: $e');
      rethrow;
    }
  }

  static Map<int, List<Point>> _parseApiResponse(String body) {
    final Map<int, List<Point>> result = {};
    final regionRegex = RegExp(r'Q(\d+)\s*[:=]\s*\[(.*?)\]', caseSensitive: false);
    final matches = regionRegex.allMatches(body);

    for (final match in matches) {
      int? id = int.tryParse(match.group(1) ?? '');
      String? coordsStr = match.group(2);

      if (id != null && coordsStr != null) {
        final List<Point> coords = [];
        final pointRegex = RegExp(r'\((\d+)\s*,\s*(\d+)\)');
        final pointMatches = pointRegex.allMatches(coordsStr);

        for (final pMatch in pointMatches) {
          int? v1 = int.tryParse(pMatch.group(1) ?? '');
          int? v2 = int.tryParse(pMatch.group(2) ?? '');
          if (v1 != null && v2 != null) {
            coords.add(Point(v1, v2));
          }
        }
        result[id] = coords;
      }
    }

    if (result.isEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final idMatch = RegExp(r'Q(\d+)', caseSensitive: false).firstMatch(key.toString());
            if (idMatch != null && value is List) {
              int? id = int.tryParse(idMatch.group(1) ?? '');
              if (id != null) {
                final List<Point> coords = [];
                for (var p in value) {
                  if (p is List && p.length >= 2) {
                    coords.add(Point(p[0], p[1]));
                  }
                }
                result[id] = coords;
              }
            }
          });
        }
      } catch (_) {}
    }
    return result;
  }
}
