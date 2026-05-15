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
        // Fix orientation based on EXIF
        img.Image fixedImage = img.bakeOrientation(originalImage);
        
        // Square crop to match viewfinder (Center of the image)
        int width = fixedImage.width;
        int height = fixedImage.height;
        int side = width < height ? width : height;
        int xOffset = (width - side) ~/ 2;
        int yOffset = (height - side) ~/ 2;

        img.Image squareImage = img.copyCrop(
          fixedImage, 
          x: xOffset, 
          y: yOffset, 
          width: side, 
          height: side
        );

        // Optional: If the user reports a "left turn", we can rotate CW
        // But bakeOrientation usually solves this. We'll stick to bakeOrientation + Crop.
        
        final processedBytes = img.encodeJpg(squareImage, quality: 90);
        await File(imagePath).writeAsBytes(processedBytes);
        debugPrint('Image orientation fixed and square-cropped.');
      }
      
      // 2. Create Multipart Request
      var request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      String fileName = path.basename(imagePath);
      
      request.files.add(await http.MultipartFile.fromPath(
        'file', 
        imagePath,
        filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      ));

      debugPrint('Uploading square-cropped image to API...');
      var streamedResponse = await request.send().timeout(const Duration(seconds: 45));
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint('API Status Code: ${response.statusCode}');
      debugPrint('API Raw Response: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server Error (${response.statusCode}):\n${response.body}');
      }

      // 3. Parse Response
      String responseBody = response.body;
      Map<int, List<Point>> regionMap = _parseApiResponse(responseBody);

      if (regionMap.isEmpty) {
        throw Exception('API succeeded but returned no region data.\nResponse: $responseBody');
      }

      // 4. Robust Indexing Detection
      // Check the maximum coordinate value in the response
      int maxCoord = 0;
      for (var coords in regionMap.values) {
        for (var pt in coords) {
          if (pt.x > maxCoord) maxCoord = pt.x;
          if (pt.y > maxCoord) maxCoord = pt.y;
        }
      }
      
      // If max coordinate is exactly 'size' (e.g. 8), it must be 1-based.
      // If max coordinate is less than 'size' (e.g. 7), it's 0-based.
      bool isZeroBased = maxCoord < size;
      debugPrint('Max coordinate seen: $maxCoord. Detected: ${isZeroBased ? "0-based" : "1-based"}');

      // 5. Construct BoardData
      final grid = List.generate(size, (_) => List.filled(size, Colors.white));
      final regions = <int, BoardRegion>{};

      regionMap.forEach((id, coords) {
        Color color = _regionPalette[(id - 1) % _regionPalette.length];
        
        regions[id] = BoardRegion(
          id: id,
          color: color,
          coordinates: coords,
        );

        for (var pt in coords) {
          int gridX = isZeroBased ? pt.x : pt.x - 1;
          int gridY = isZeroBased ? pt.y : pt.y - 1;

          if (gridX >= 0 && gridX < size && gridY >= 0 && gridY < size) {
            grid[gridY][gridX] = color;
          }
        }
      });

      return BoardData(
        size: size,
        grid: grid,
        regions: regions,
        rawResponse: responseBody,
      );
    } catch (e) {
      debugPrint('Fatal Error in BoardProcessor: $e');
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
          int? x = int.tryParse(pMatch.group(1) ?? '');
          int? y = int.tryParse(pMatch.group(2) ?? '');
          if (x != null && y != null) {
            coords.add(Point(x, y));
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
            final keyMatch = RegExp(r'Q(\d+)', caseSensitive: false).firstMatch(key.toString());
            if (keyMatch != null && value is List) {
              int? id = int.tryParse(keyMatch.group(1) ?? '');
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
