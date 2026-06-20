import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
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
    final boardJson = _encodeBoardJson(id, name ?? 'Board ${saved.length + 1}', board);
    saved.add(boardJson);
    await file.writeAsString(jsonEncode(saved));
    return id;
  }

  static Future<List<Map<String, dynamic>>> loadBoards() async {
    final file = await _getStorageFile();
    if (!await file.exists()) return [];

    final content = await file.readAsString();
    List<dynamic> saved = jsonDecode(content);

    return saved.map((item) => _decodeBoardEntry(item)).toList();
  }

  static Future<void> deleteBoard(int id) async {
    final file = await _getStorageFile();
    if (!await file.exists()) return;

    final content = await file.readAsString();
    List<dynamic> saved = jsonDecode(content);

    // Daily Quest entries are read-only — never delete from disk.
    final doomed = saved.firstWhere(
      (b) => b['id'] == id,
      orElse: () => null,
    );
    if (doomed is Map && doomed['isDailyQuest'] == true) {
      debugPrint('StorageManager: refusing to delete Daily Quest ${doomed['questDate']}');
      return;
    }

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
      // Daily Quest titles are server-picked and immutable on-device.
      if (saved[index]['isDailyQuest'] == true) {
        debugPrint(
          'StorageManager: refusing to rename Daily Quest ${saved[index]['questDate']}',
        );
        return;
      }
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
      // Preserve daily-quest metadata so updates don't strip server-picked fields.
      saved[index]['isDailyQuest'] = board.isDailyQuest;
      saved[index]['questDate'] = board.questDate;
      saved[index]['questTitle'] = board.questTitle;
      // Daily-quest attempt state — round-trip so the lock survives an
      // app restart. Defaults (0 / false / false) apply to non-daily boards.
      saved[index]['attemptsUsed'] = board.attemptsUsed;
      saved[index]['isRevealed'] = board.isRevealed;
      saved[index]['isFailed'] = board.isFailed;
      saved[index]['date'] = DateTime.now().toIso8601String();
      await file.writeAsString(jsonEncode(saved));
    }
  }

  // -------------------------------------------------------------------------
  // Daily Quest helpers
  // -------------------------------------------------------------------------

  /// Look up the local library id for a previously downloaded Daily Quest,
  /// keyed by its server-issued date string. Returns null when the user
  /// has never downloaded (or has cleared) that day's quest.
  static Future<int?> findDailyQuestIdByDate(String date) async {
    final boards = await loadBoards();
    for (final entry in boards) {
      final board = entry['board'] as BoardData;
      if (board.isDailyQuest && board.questDate == date) {
        return entry['id'] as int;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Manual-mode progress  (so a Quit+re-enter doesn't wipe the board)
  // -------------------------------------------------------------------------
  //
  // Stored in SharedPreferences as a single JSON blob keyed by board id.
  // We deliberately keep this OUT of saved_boards.json so renaming,
  // deleting or sharing a board never touches the in-progress timer.

  static const String _kManualProgressPrefix = 'manual_progress_';

  /// Persist the in-progress manual grid + timer for [boardId]. Pass
  /// [clear] = true to remove the entry once the puzzle is solved or the
  /// user explicitly resets.
  static Future<void> saveManualProgress(
    int boardId, {
    required Map<String, int> manualGrid,
    required int secondsElapsed,
    required bool isPaused,
    bool clear = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kManualProgressPrefix$boardId';
    if (clear) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode({
        'manualGrid': manualGrid,
        'secondsElapsed': secondsElapsed,
        'isPaused': isPaused,
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Read previously-saved manual progress for [boardId]. Returns null
  /// when there's no in-progress game for this board.
  static Future<({Map<String, int> manualGrid, int secondsElapsed, bool isPaused, DateTime savedAt})?>
      loadManualProgress(int boardId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kManualProgressPrefix$boardId');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final grid = <String, int>{};
      (map['manualGrid'] as Map).forEach((k, v) {
        grid[k.toString()] = v as int;
      });
      return (
        manualGrid: grid,
        secondsElapsed: (map['secondsElapsed'] as num).toInt(),
        isPaused: map['isPaused'] as bool? ?? false,
        savedAt: DateTime.parse(map['savedAt'] as String),
      );
    } catch (_) {
      // Corrupt entry — drop it so we don't repeatedly fail.
      await prefs.remove('$_kManualProgressPrefix$boardId');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Private serialisation — shared by saveBoard + updateBoard
  // -------------------------------------------------------------------------

  static Map<String, dynamic> _encodeBoardJson(int id, String name, BoardData board) {
    return {
      'id': id,
      'name': name,
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
      'isDailyQuest': board.isDailyQuest,
      'questDate': board.questDate,
      'questTitle': board.questTitle,
      // Daily-quest attempt state. Encoded even on non-daily boards so the
      // round-trip is symmetric; values stay at their defaults (0/false).
      'attemptsUsed': board.attemptsUsed,
      'isRevealed': board.isRevealed,
      'isFailed': board.isFailed,
      'date': DateTime.now().toIso8601String(),
    };
  }

  static Map<String, dynamic> _decodeBoardEntry(dynamic item) {
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

    final board = BoardData(
      size: item['size'],
      regionIds: (item['regionIds'] as List).map((row) => (row as List).map((id) => id as int).toList()).toList(),
      regions: regions,
      rawResponse: item['rawResponse'] ?? '',
      solution: solution.isEmpty ? null : solution,
      isManuallySolved: item['isManuallySolved'] ?? false,
      isDailyQuest: item['isDailyQuest'] ?? false,
      questDate: item['questDate'],
      questTitle: item['questTitle'],
      attemptsUsed: item['attemptsUsed'] ?? 0,
      isRevealed: item['isRevealed'] ?? false,
      isFailed: item['isFailed'] ?? false,
    );

    return {
      'id': item['id'],
      'name': item['name'],
      'date': DateTime.parse(item['date']),
      'board': board,
    };
  }
}
