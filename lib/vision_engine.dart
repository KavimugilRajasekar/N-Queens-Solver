import 'package:flutter/services.dart';

class VisionEngine {
  static const MethodChannel _channel =
      MethodChannel('com.example.n_queens_solver/vision');

  /// Calls the Android‑only Chaquopy Python engine.
  /// Returns a map with "size" (int) and "regions" (Map<String, List<List<int>>>).
  static Future<Map<String, dynamic>> run(String imagePath) async {
    final result = await _channel.invokeMethod<Map>('runVisionEngine', {
      'path': imagePath,
    });
    return Map<String, dynamic>.from(result!);
  }
}
