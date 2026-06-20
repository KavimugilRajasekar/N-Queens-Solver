import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'board_processor.dart';
import '../constants/colors.dart';
import '../constants/region_colors.dart';
import 'storage_manager.dart';

/// DailyQuestManager — synchronises the server-side Daily Quest puzzle into
/// the local library and persists it as a read-only entry.
///
/// Triggers:
///   - `checkForNewQuest()` from `FirebaseGameManager.initializeFirebase()`
///     on app start, and from `SavedBoardsScreen.initState` whenever the
///     library is opened. Reads `/daily_quests/latest` and downloads
///     `/daily_quests/{date}` if newer than the local copy.
///   - `handleFcm()` from the FCM listener when `type=daily_quest` arrives
///     in foreground, background, or initial-launch payload. Skips silent
///     when the device is offline (the in-app startup check is the safety
///     net for missed notifications).
class DailyQuestManager {
  static final DailyQuestManager instance = DailyQuestManager._internal();
  DailyQuestManager._internal();

  /// Same RTDB URL as `FirebaseGameManager`. Kept here so this module is
  /// self-contained and testable without the rest of the game manager.
  static const String _rtdbUrl =
      'https://kavi-workspace-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// SharedPreferences key used to remember the date of the most recent
  /// daily-quest download. Lets us avoid a network round-trip when the
  /// server pointer hasn't moved.
  static const String _kLastSeenQuestDate = 'daily_quest_last_seen_date';

  /// Fires (true) whenever a new Daily Quest is downloaded and persisted
  /// to disk. The SavedBoardsScreen listens to this so the library list
  /// refreshes without the user having to back out and re-enter.
  final ValueNotifier<bool> newQuestAvailable = ValueNotifier(false);

  /// Set once at app startup. Required by [handleFcm] so foreground
  /// notifications can find the active [ScaffoldMessenger] to show a
  /// snackbar (FCM does not show a tray alert while the app is open).
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  GlobalKey<NavigatorState> get _navigatorKey => navigatorKey;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _rtdbUrl,
      );

  // ───────────────────────────────────────────────────────────────────────
  // Public entry points
  // ───────────────────────────────────────────────────────────────────────

  /// Called on app start and on every library refresh.
  /// Idempotent — if today's quest is already local, it returns quickly.
  Future<void> checkForNewQuest() async {
    try {
      final pointerSnap = await _db.ref('daily_quests/latest').get();
      if (!pointerSnap.exists) return;
      final pointer = Map<String, dynamic>.from(pointerSnap.value as Map);
      final date = pointer['date'] as String?;
      if (date == null) return;

      // Skip the network round-trip when we already have this date.
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getString(_kLastSeenQuestDate);
      if (lastSeen == date) return;

      // Download the full payload (board, regions, etc.) and persist.
      await _downloadAndPersist(date);
      await prefs.setString(_kLastSeenQuestDate, date);
      newQuestAvailable.value = true;
    } catch (e) {
      // Silent — startup and refresh paths should never throw to the UI.
      debugPrint('DailyQuestManager.checkForNewQuest: $e');
    }
  }

  /// Triggered by FCM `type=daily_quest` payloads. The payload itself
  /// only carries `{type, date, title}`; we still have to fetch the
  /// full board from RTDB.
  ///
  /// For foreground deliveries FCM does NOT show a system tray alert
  /// (that's by design — Android/iOS suppress tray notifications while
  /// the app is in the foreground). To compensate, after a successful
  /// persist we surface an in-app snackbar via the global navigator so
  /// the user sees "🧩 Daily Quest Available!" while the app is open.
  Future<void> handleFcm(Map<String, dynamic> data) async {
    try {
      final date = data['date'] as String?;
      if (date == null || date.isEmpty) {
        debugPrint('DailyQuestManager.handleFcm: missing date in payload.');
        return;
      }
      final wasAlreadySeen = await _hasLocalQuest(date);
      await _downloadAndPersist(date);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastSeenQuestDate, date);
      newQuestAvailable.value = true;
      // Only show the in-app banner when this delivery actually brings
      // something new. Otherwise opening the app to an existing quest
      // (e.g. from a re-delivered push) would spam a banner.
      if (!wasAlreadySeen) {
        _showInAppBanner(date, data['title'] as String?);
      }
    } catch (e) {
      debugPrint('DailyQuestManager.handleFcm: $e');
    }
  }

  Future<bool> _hasLocalQuest(String date) async {
    final id = await StorageManager.findDailyQuestIdByDate(date);
    return id != null;
  }

  /// Pop a friendly snackbar so the user knows a new Daily Quest landed
  /// while the app was in the foreground. The snackbar lives on whatever
  /// [ScaffoldMessenger] is closest to the global navigator key, which
  /// means it works regardless of which screen is currently on top.
  void _showInAppBanner(String date, String? title) {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return; // App still booting — the startup check covers us.
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.dailyQuestBlueDeep,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title ?? '🧩 Daily Quest Available!',
                    style: const TextStyle(
                      fontFamily: 'DynaPuff',
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    "Open your library to play today's quest.",
                    style: TextStyle(
                      fontFamily: 'Comfortaa',
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              date,
              style: const TextStyle(
                fontFamily: 'Comfortaa',
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: AppColors.gold,
          onPressed: () {
            // The library's daily-quest card will refresh automatically
            // via newQuestAvailable, so the user just needs to navigate
            // to the library manually. Showing a hint here is enough.
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Internal pipeline
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _downloadAndPersist(String date) async {
    final snap = await _db.ref('daily_quests/$date').get();
    if (!snap.exists) {
      debugPrint('DailyQuestManager: no entry for $date in RTDB.');
      return;
    }
    final raw = Map<String, dynamic>.from(snap.value as Map);
    await _persistQuest(raw, date);
  }

  /// Map an RTDB payload to a `BoardData`, then either insert a new
  /// library entry or update the existing one for this date.
  Future<void> _persistQuest(Map<String, dynamic> raw, String date) async {
    final boardData = _decodePayload(raw, date);
    final existingId = await StorageManager.findDailyQuestIdByDate(date);
    if (existingId == null) {
      await StorageManager.saveBoard(
        boardData,
        name: boardData.questTitle ?? 'Daily Quest',
      );
      debugPrint('DailyQuestManager: saved new Daily Quest for $date');
    } else {
      // Preserve user's existing `isManuallySolved` if they've already
      // conquered today's puzzle; otherwise mirror the server payload.
      final previous = await StorageManager.loadBoards();
      final prev = previous.firstWhere(
        (e) => e['id'] == existingId,
        orElse: () => {'board': boardData},
      );
      final prevBoard = prev['board'] as BoardData?;
      if (prevBoard?.isManuallySolved == true) {
        boardData.isManuallySolved = true;
      }
      await StorageManager.updateBoard(existingId, boardData);
      debugPrint('DailyQuestManager: updated Daily Quest $existingId for $date');
    }
  }

  /// Convert the RTDB JSON shape into a `BoardData` with all daily-quest
  /// metadata attached. Region colours are recomputed locally from the
  /// existing palette so the server only has to send region IDs.
  BoardData _decodePayload(Map<String, dynamic> raw, String date) {
    final size = raw['boardSize'] as int;
    final regionIds = (raw['board'] as List<dynamic>)
        .map((row) => List<int>.from(row as List))
        .toList();

    final Map<int, BoardRegion> regions = {};
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        final id = regionIds[r][c];
        if (id > 0) {
          regions.putIfAbsent(
            id,
            () => BoardRegion(
              id: id,
              color: RegionColors.getRegionColor(id, size),
              coordinates: <Point>[],
            ),
          );
          regions[id]!.coordinates.add(Point(r + 1, c + 1));
        }
      }
    }

    return BoardData(
      size: size,
      regionIds: regionIds,
      regions: regions,
      rawResponse: 'Daily Quest from server: $date',
      isDailyQuest: true,
      questDate: date,
      questTitle: raw['title'] as String?,
    );
  }

  /// For testing only — exposes the payload decoder without hitting RTDB.
  @visibleForTesting
  BoardData debugDecode(Map<String, dynamic> raw, String date) =>
      _decodePayload(raw, date);
}