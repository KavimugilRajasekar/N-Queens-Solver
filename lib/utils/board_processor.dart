import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  final List<List<Color>> grid;
  final Map<int, BoardRegion> regions;
  final String rawResponse;

  BoardData({
    required this.size,
    required this.grid,
    required this.regions,
    required this.rawResponse,
  });
}

class BoardProcessor {
  static const String _apiUrl = 'https://image-processor-livid.vercel.app/process-image';

  static final List<Color> _regionPalette = [
    Colors.blue.shade100,
    Colors.green.shade100,
    Colors.orange.shade100,
    Colors.purple.shade100,
    Colors.pink.shade100,
    Colors.teal.shade100,
    Colors.amber.shade100,
    Colors.cyan.shade100,
    Colors.indigo.shade100,
    Colors.lime.shade100,
    Colors.brown.shade100,
    Colors.deepOrange.shade100,
  ];

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

      // Determine dynamic board size N based on the number of regions (Qi)
      // or the highest region ID found
      int detectedN = 0;
      regionMap.keys.forEach((id) {
        if (id > detectedN) detectedN = id;
      });
      
      if (detectedN == 0) detectedN = size; // Fallback to provided size
      debugPrint('Dynamic Board Size Detected: $detectedN x $detectedN');

      // Detect if 0-based or 1-based
      bool hasZero = false;
      for (var coords in regionMap.values) {
        for (var pt in coords) {
          if (pt.x == 0 || pt.y == 0) {
            hasZero = true;
            break;
          }
        }
        if (hasZero) break;
      }

      // 4. Construct BoardData using the dynamic size
      final grid = List.generate(detectedN, (_) => List.filled(detectedN, Colors.white));
      final regions = <int, BoardRegion>{};

      regionMap.forEach((id, coords) {
        Color color = _regionPalette[(id - 1) % _regionPalette.length];
        regions[id] = BoardRegion(id: id, color: color, coordinates: coords);

        for (var pt in coords) {
          int row = hasZero ? pt.x : pt.x - 1;
          int col = hasZero ? pt.y : pt.y - 1;

          if (row >= 0 && row < detectedN && col >= 0 && col < detectedN) {
            grid[row][col] = color;
          }
        }
      });

      return BoardData(
        size: detectedN,
        grid: grid,
        regions: regions,
        rawResponse: responseBody,
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
