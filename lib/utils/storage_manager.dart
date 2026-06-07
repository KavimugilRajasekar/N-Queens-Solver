import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'board_processor.dart';

class StorageManager {
  static const String _fileName = 'saved_boards.json';

  static Future<File> _getStorageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(path.join(directory.path, _fileName));
  }

  static Future<int> saveBoard(BoardData board, {String? name}) async {
    final file = await _getStorageFile();
    List<dynamic> saved = [];
    
    if (await file.exists()) {
      final content = await file.readAsString();
      saved = jsonDecode(content);
    }

    final id = DateTime.now().millisecondsSinceEpoch;
    final boardJson = {
      'id': id,
      'name': name ?? 'Board ${saved.length + 1}',
      'size': board.size,
      'regionIds': board.regionIds,
      'regions': board.regions.map((id, region) => MapEntry(
        id.toString(),
        {
          'id': region.id,
          'color': region.color.toARGB32(),
          'coords': region.coordinates.map((p) => {'x': p.x, 'y': p.y}).toList(),
        }
      )),
      'rawResponse': board.rawResponse,
      'solution': board.solution?.map((id, p) => MapEntry(id.toString(), {'x': p.x, 'y': p.y})),
      'isManuallySolved': board.isManuallySolved,
      'date': DateTime.now().toIso8601String(),
    };

    saved.add(boardJson);
    await file.writeAsString(jsonEncode(saved));
    return id;
  }

  static Future<List<Map<String, dynamic>>> loadBoards() async {
    final file = await _getStorageFile();
    if (!await file.exists()) return [];

    final content = await file.readAsString();
    List<dynamic> saved = jsonDecode(content);
    
    return saved.map((item) {
      final regions = <int, BoardRegion>{};
      (item['regions'] as Map).forEach((id, data) {
        regions[int.parse(id)] = BoardRegion(
          id: data['id'],
          color: Color(data['color']),
          coordinates: (data['coords'] as List).map((p) => Point(p['x'], p['y'])).toList(),
        );
      });
      
      final solution = <int, Point>{};
      if (item['solution'] != null) {
        (item['solution'] as Map).forEach((id, p) {
          solution[int.parse(id)] = Point(p['x'], p['y']);
        });
      }

      return {
        'id': item['id'],
        'name': item['name'],
        'date': DateTime.parse(item['date']),
        'board': BoardData(
          size: item['size'],
          regionIds: (item['regionIds'] as List).map((row) => (row as List).map((id) => id as int).toList()).toList(),
          regions: regions,
          rawResponse: item['rawResponse'] ?? '',
          solution: solution.isEmpty ? null : solution,
          isManuallySolved: item['isManuallySolved'] ?? false,
        ),
      };
    }).toList();
  }

  static Future<void> deleteBoard(int id) async {
    final file = await _getStorageFile();
    if (!await file.exists()) return;

    final content = await file.readAsString();
    List<dynamic> saved = jsonDecode(content);
    saved.removeWhere((b) => b['id'] == id);
    await file.writeAsString(jsonEncode(saved));
  }

  static Future<void> renameBoard(int id, String newName) async {
    final file = await _getStorageFile();
    if (!await file.exists()) return;

    final content = await file.readAsString();
    List<dynamic> saved = jsonDecode(content);
    final index = saved.indexWhere((b) => b['id'] == id);
    if (index != -1) {
      saved[index]['name'] = newName;
      await file.writeAsString(jsonEncode(saved));
    }
  }

  static Future<void> updateBoard(int id, BoardData board) async {
    final file = await _getStorageFile();
    if (!await file.exists()) return;

    final content = await file.readAsString();
    List<dynamic> saved = jsonDecode(content);
    final index = saved.indexWhere((b) => b['id'] == id);
    
    if (index != -1) {
      saved[index]['size'] = board.size;
      saved[index]['regionIds'] = board.regionIds;
      saved[index]['regions'] = board.regions.map((id, region) => MapEntry(
        id.toString(),
        {
          'id': region.id,
          'color': region.color.toARGB32(),
          'coords': region.coordinates.map((p) => {'x': p.x, 'y': p.y}).toList(),
        }
      ));
      saved[index]['solution'] = board.solution?.map((id, p) => MapEntry(id.toString(), {'x': p.x, 'y': p.y}));
      saved[index]['isManuallySolved'] = board.isManuallySolved;
      saved[index]['date'] = DateTime.now().toIso8601String();
      await file.writeAsString(jsonEncode(saved));
    }
  }
}
