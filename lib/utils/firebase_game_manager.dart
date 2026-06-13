import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'board_processor.dart';
import '../constants/region_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FirebaseGameManager
//
// Responsibilities
//   • Player registration / peer lookup  →  Vercel server (HTTP)
//   • Room creation                      →  Vercel server  POST /create-room
//   • Room deletion (leave / end game)   →  Vercel server  DELETE /room/{id}
//   • In-game real-time state            →  Firebase RTDB directly
//   • FCM invite delivery                →  Vercel server → FCM
//
// Flutter clients NEVER write to /rooms directly.
// ─────────────────────────────────────────────────────────────────────────────
class FirebaseGameManager {
  static final FirebaseGameManager instance = FirebaseGameManager._internal();
  FirebaseGameManager._internal();

  // ── Vercel server ────────────────────────────────────────────────────────
  static const String _serverUrl = 'https://nqueensserver.vercel.app';

  // ── Firebase RTDB URL ────────────────────────────────────────────────────
  // Must match the FIREBASE_DB_URL env var on the Vercel project.
  static const String _rtdbUrl =
      'https://kavi-workspace-default-rtdb.asia-southeast1.firebasedatabase.app';

  // ── Public state ─────────────────────────────────────────────────────────
  String? fcmToken;
  bool isFirebaseInitialized = false;

  /// 'idle' | 'connecting' | 'connected' | 'failed'
  final ValueNotifier<String> connectionState = ValueNotifier('idle');

  /// Fires when an incoming invite arrives via FCM.
  final ValueNotifier<Map<String, dynamic>?> incomingInviteNotifier =
      ValueNotifier(null);

  /// Fires (set to true) when the active room is deleted by the other player.
  /// The UI listens to this and navigates back to the lobby.
  /// Reset to false by disconnect() so it is safe across sessions.
  final ValueNotifier<bool> roomDeletedNotifier = ValueNotifier(false);

  // ── Session ──────────────────────────────────────────────────────────────
  String? _activeRoomId;
  bool isHost = false;
  String? activePeerId;
  String? activePeerNickname;
  String? activePeerIcon;

  // ── Internal guards ──────────────────────────────────────────────────────
  // Prevents the guest-join handler from running more than once per session.
  bool _guestJoinHandled = false;
  // Prevents disconnect() from being called re-entrantly.
  bool _disconnecting = false;

  // ── RTDB subscriptions ───────────────────────────────────────────────────
  StreamSubscription<DatabaseEvent>? _roomSubscription;
  StreamSubscription<DatabaseEvent>? _gameStateSubscription;

  // ── Game message stream ──────────────────────────────────────────────────
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dataMessageStream =>
      _messageController.stream;

  // ── Cached player ID ─────────────────────────────────────────────────────
  String? _cachedMyId;

  // ─────────────────────────────────────────────────────────────────────────
  // Firebase / FCM initialisation
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> initializeFirebase() async {
    if (isFirebaseInitialized) return;
    try {
      debugPrint('FirebaseGameManager: initialising Firebase...');
      await Firebase.initializeApp();
      isFirebaseInitialized = true;

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
          alert: true, badge: true, sound: true, provisional: false);

      fcmToken = await messaging.getToken();
      debugPrint('FCM token obtained.');

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);

      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

      FirebaseMessaging.onMessage.listen((msg) async {
        if (msg.data['type'] == 'invite') await _handleInviteFromFCM(msg.data);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((msg) async {
        if (msg.data['type'] == 'invite') await _handleInviteFromFCM(msg.data);
      });

      final initial = await messaging.getInitialMessage();
      if (initial != null && initial.data['type'] == 'invite') {
        await _handleInviteFromFCM(initial.data);
      }

      await registerPlayerProfile();
    } catch (e) {
      debugPrint('Firebase init failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Incoming FCM invite → read room from RTDB → populate notifier
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _handleInviteFromFCM(Map<String, dynamic> data) async {
    final roomId = data['roomId'] as String?;
    if (roomId == null) return;

    // 5-minute expiry check
    final ts = int.tryParse(data['timestamp'] ?? '') ?? 0;
    if (ts > 0 && DateTime.now().millisecondsSinceEpoch - ts > 300000) {
      debugPrint('Invite expired, ignoring.');
      return;
    }

    // Read the full room document from RTDB (boards live there, not in FCM)
    try {
      final snapshot = await _db.ref('rooms/$roomId').get();
      if (!snapshot.exists) {
        debugPrint('Room $roomId not found in RTDB.');
        return;
      }
      final room = Map<String, dynamic>.from(snapshot.value as Map);

      incomingInviteNotifier.value = {
        'fromPlayerId':  data['fromPlayerId'] ?? room['hostId'],
        'fromNickname':  data['fromNickname'] ?? 'Rival',
        'fromIcon':      data['fromIcon'] ?? 'assets/player_icons/unicorn.png',
        'isCompeteMode': room['isCompeteMode'] ?? false,
        'matchCount':    room['matchCount']    ?? 3,
        'matchBoards':   room['matchBoards']   ?? '[]',
        'hostColor':     room['hostColor']     ?? 'blue',
        'roomId':        roomId,
      };
    } catch (e) {
      debugPrint('Failed to read room from RTDB: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lazy RTDB instance
  // ─────────────────────────────────────────────────────────────────────────
  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
      app: Firebase.app(), databaseURL: _rtdbUrl);

  // ─────────────────────────────────────────────────────────────────────────
  // Player registration & peer lookup  (Vercel server)
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> registerPlayerProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final playerId = prefs.getString('player_unique_id_v2');
      final nickname = prefs.getString('player_nickname') ?? 'Guest';
      final icon =
          prefs.getString('player_icon') ?? 'assets/player_icons/crown.png';

      if (playerId == null || fcmToken == null) return false;
      _cachedMyId = playerId;

      final res = await http.post(
        Uri.parse('$_serverUrl/register-player'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'playerId': playerId,
          'fcmToken': fcmToken,
          'nickname': nickname,
          'icon':     icon,
        }),
      );
      if (res.statusCode == 200) {
        debugPrint('Player $playerId registered.');
        return true;
      }
      debugPrint('Registration failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('registerPlayerProfile error: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> checkPeerValid(String peerId) async {
    try {
      String id = peerId.trim();
      if (!id.startsWith('NQ-')) id = 'NQ-$id';
      final res = await http
          .get(Uri.parse('$_serverUrl/player/$id'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('checkPeerValid error: $e');
    }
    return null;
  }

  /// Fetch the latest profile for a peer — useful for refreshing cached nicknames.
  Future<Map<String, dynamic>?> fetchPeerProfile(String peerId) =>
      checkPeerValid(peerId);

  /// Persist a player to the recent-opponents list in SharedPreferences.
  /// Called by both the host (after validation) and the guest (after accepting).
  /// Always normalizes IDs to bare digits for storage so duplicates are impossible.
  static Future<void> saveRecentOpponent(String id, String nickname, String icon) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('recent_opponents');
      List<Map<String, String>> list = [];
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as List<dynamic>;
        list = decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      }

      // Normalize to bare 6-digit key — strip any NQ- prefix for dedup
      final bareId = id.trim().replaceAll('NQ-', '').replaceAll('nq-', '');

      // Remove ALL existing entries that match, regardless of how they were stored
      list.removeWhere((o) {
        final storedBare = (o['id'] ?? '').replaceAll('NQ-', '').replaceAll('nq-', '');
        return storedBare == bareId;
      });

      // Store with the NQ- prefix for display
      list.insert(0, {'id': 'NQ-$bareId', 'nickname': nickname, 'icon': icon});
      if (list.length > 10) list = list.sublist(0, 10);
      await prefs.setString('recent_opponents', jsonEncode(list));
      debugPrint('Saved recent opponent: NQ-$bareId ($nickname)');
    } catch (e) {
      debugPrint('saveRecentOpponent error: $e');
    }
  }

  /// Update this player's own nickname on the server + locally in SharedPreferences.
  Future<bool> updatePlayerNickname(String newNickname) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final playerId = prefs.getString('player_unique_id_v2');
      if (playerId == null) return false;

      String id = playerId.trim();
      if (!id.startsWith('NQ-')) id = 'NQ-$id';

      final res = await http.patch(
        Uri.parse('$_serverUrl/player/$id/nickname'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': id, 'nickname': newNickname}),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        await prefs.setString('player_nickname', newNickname);
        debugPrint('Nickname updated to $newNickname.');
        return true;
      }
      debugPrint('Nickname update failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('updatePlayerNickname error: $e');
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HOST: ask server to create room + send FCM invite
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> hostConnection(
    String peerId,
    bool isCompeteMode,
    int matchCount,
    List<BoardData> matchBoards, {
    String hostColor = 'blue',
  }) async {
    isHost = true;
    activePeerId = peerId;
    _guestJoinHandled = false;
    connectionState.value = 'connecting';

    // Validate peer
    final peerProfile = await checkPeerValid(peerId);
    if (peerProfile == null) {
      connectionState.value = 'failed';
      throw Exception(
          "Rival ID '$peerId' is invalid or not registered in the arena!");
    }
    activePeerNickname = peerProfile['nickname'];
    activePeerIcon     = peerProfile['icon'];

    final prefs      = await SharedPreferences.getInstance();
    final myId       = prefs.getString('player_unique_id_v2') ?? 'Unknown';
    final myNickname = prefs.getString('player_nickname')     ?? 'Host';
    final myIcon     = prefs.getString('player_icon')         ?? 'assets/player_icons/crown.png';
    _cachedMyId = myId;

    String normalizedPeerId = peerId.trim();
    if (!normalizedPeerId.startsWith('NQ-')) {
      normalizedPeerId = 'NQ-$normalizedPeerId';
    }

    // Ask the server to create the room in RTDB and send the FCM invite.
    final res = await http.post(
      Uri.parse('$_serverUrl/create-room'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fromPlayerId':  myId,
        'fromNickname':  myNickname,
        'fromIcon':      myIcon,
        'toPlayerId':    normalizedPeerId,
        'isCompeteMode': isCompeteMode,
        'matchCount':    matchCount,
        'matchBoards':   serializeBoards(matchBoards),
        'hostColor':     hostColor,
      }),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      connectionState.value = 'failed';
      throw Exception(
          'Server failed to create room: ${res.statusCode} ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _activeRoomId = body['roomId'] as String;
    debugPrint('Room $_activeRoomId created by server. Waiting for guest...');

    _listenForGuestJoin();
  }

  // ── Host: watch for guest joining ────────────────────────────────────────
  void _listenForGuestJoin() {
    _roomSubscription?.cancel();
    final roomRef = _db.ref('rooms/$_activeRoomId');

    _roomSubscription = roomRef.onValue.listen((event) async {
      // Room deleted (e.g. server cleaned it up, or guest cancelled)
      if (!event.snapshot.exists) {
        if (connectionState.value == 'connecting') {
          connectionState.value = 'failed';
        }
        return;
      }

      final data   = Map<String, dynamic>.from(event.snapshot.value as Map);
      final joined = data['guestJoined'] == true;
      final status = data['status'] as String? ?? 'waiting';

      // Guard: only handle the first time the guest joins
      if (joined && !_guestJoinHandled && connectionState.value == 'connecting') {
        _guestJoinHandled = true;

        // Cancel the room listener before the async write so we don't
        // re-enter this block if the write triggers another onValue event.
        _roomSubscription?.cancel();
        _roomSubscription = null;

        // Await the RTDB write so the guest sees hostReady:true before we
        // declare ourselves connected.
        try {
          await roomRef.update({'hostReady': true, 'status': 'active'});
        } catch (e) {
          debugPrint('Host: failed to mark room active: $e');
          connectionState.value = 'failed';
          return;
        }

        debugPrint('Guest joined. Room marked active. Starting game sync.');
        _startGameStateSync();
        _watchRoomDeletion();
        connectionState.value = 'connected';

      } else if (status == 'cancelled' && connectionState.value == 'connecting') {
        connectionState.value = 'failed';
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GUEST: join an existing room
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> joinConnection(Map<String, dynamic> invitePayload) async {
    isHost = false;
    final roomId = invitePayload['roomId'] as String;
    _activeRoomId      = roomId;
    activePeerId       = invitePayload['fromPlayerId'];
    activePeerNickname = invitePayload['fromNickname'];
    activePeerIcon     = invitePayload['fromIcon'];
    _guestJoinHandled  = false;
    connectionState.value = 'connecting';

    final prefs = await SharedPreferences.getInstance();
    _cachedMyId = prefs.getString('player_unique_id_v2');

    final roomRef = _db.ref('rooms/$roomId');

    // Verify room still exists before subscribing
    final snapshot = await roomRef.get();
    if (!snapshot.exists) {
      connectionState.value = 'failed';
      throw Exception(
          'Room $roomId no longer exists. The invite may have expired.');
    }

    // ── Subscribe BEFORE writing guestJoined ─────────────────────────────
    // Firebase onValue fires immediately with the current snapshot, so even
    // if the host responds before our listener is registered we will still
    // see the 'active' status on the first event.
    _roomSubscription?.cancel();
    bool connectionCompleted = false;
    final completer = Completer<void>();

    _roomSubscription = roomRef.onValue.listen((event) {
      if (connectionCompleted) return; // guard against re-entry

      if (!event.snapshot.exists) {
        // Room deleted before we connected
        if (!completer.isCompleted) {
          completer.completeError(
              'Room was deleted before connection completed.');
        }
        return;
      }

      final data      = Map<String, dynamic>.from(event.snapshot.value as Map);
      final status    = data['status']    as String? ?? 'waiting';
      final hostReady = data['hostReady'] == true;

      if (status == 'active' || hostReady) {
        connectionCompleted = true;
        _roomSubscription?.cancel();
        _roomSubscription = null;
        if (!completer.isCompleted) completer.complete();
      } else if (status == 'cancelled') {
        if (!completer.isCompleted) {
          completer.completeError('Room cancelled by host.');
        }
      }
    });

    // Tell the host we are here — this triggers the host's onValue listener
    await roomRef.update({'guestJoined': true, 'guestReady': true});
    debugPrint('Guest joined room $roomId, waiting for host confirmation...');

    // Wait for host to mark room active (30-second timeout)
    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _roomSubscription?.cancel();
      _roomSubscription = null;
      connectionState.value = 'failed';
      throw TimeoutException('Host did not respond within 30 seconds.');
    } catch (e) {
      _roomSubscription?.cancel();
      _roomSubscription = null;
      connectionState.value = 'failed';
      rethrow;
    }

    _startGameStateSync();
    _watchRoomDeletion();
    connectionState.value = 'connected';
    debugPrint('Guest connected to room $roomId.');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // In-game: watch for room deletion (other player left)
  // ─────────────────────────────────────────────────────────────────────────
  void _watchRoomDeletion() {
    _roomSubscription?.cancel();
    _roomSubscription =
        _db.ref('rooms/$_activeRoomId').onValue.listen((event) {
      if (!event.snapshot.exists) {
        _handleRoomDeleted();
      }
    });
  }

  void _handleRoomDeleted() {
    // Guard: only fire once per session
    if (roomDeletedNotifier.value) return;

    debugPrint('Room $_activeRoomId was deleted remotely. Notifying UI.');
    _gameStateSubscription?.cancel();
    _gameStateSubscription = null;
    _roomSubscription?.cancel();
    _roomSubscription = null;
    connectionState.value = 'idle';
    roomDeletedNotifier.value = true; // UI listener picks this up
  }

  // ─────────────────────────────────────────────────────────────────────────
  // In-game: real-time game state via RTDB  (no server hop)
  // ─────────────────────────────────────────────────────────────────────────
  void _startGameStateSync() {
    _gameStateSubscription?.cancel();
    _gameStateSubscription =
        _db.ref('rooms/$_activeRoomId/gameState').onChildAdded.listen((event) {
      if (!event.snapshot.exists) return;
      try {
        final raw = event.snapshot.value;
        final Map<String, dynamic> msg = raw is Map
            ? Map<String, dynamic>.from(raw)
            : jsonDecode(raw as String) as Map<String, dynamic>;

        // Only forward messages from the other player
        final sender = msg['sender'] as String?;
        if (sender != null && sender != (_cachedMyId ?? '')) {
          _messageController.add(msg);
        }
      } catch (e) {
        debugPrint('Error parsing game state message: $e');
      }
    });
  }

  /// Push a game message directly to RTDB (no server hop).
  Future<bool> sendMessage(Map<String, dynamic> payload) async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      debugPrint('sendMessage: no active room.');
      return false;
    }
    try {
      final myId = _cachedMyId ??
          (await SharedPreferences.getInstance())
              .getString('player_unique_id_v2') ??
          'unknown';

      await _db
          .ref('rooms/$roomId/gameState')
          .push()
          .set({...payload, 'sender': myId});
      return true;
    } catch (e) {
      debugPrint('sendMessage error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Leave / disconnect  →  ask server to delete the room
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    // Re-entrancy guard: dispose() calls disconnect(), but _handleRoomDeleted
    // may have already started cleanup. We must not run twice.
    if (_disconnecting) return;
    _disconnecting = true;

    debugPrint('FirebaseGameManager: disconnecting.');

    // Cancel all RTDB listeners first so _handleRoomDeleted cannot fire
    // again while we are in the middle of cleanup.
    _roomSubscription?.cancel();
    _roomSubscription = null;
    _gameStateSubscription?.cancel();
    _gameStateSubscription = null;

    final roomId = _activeRoomId;
    final myId   = _cachedMyId;

    // Reset session state before the async server call so any re-entrant
    // code sees a clean state immediately.
    _activeRoomId      = null;
    activePeerId       = null;
    activePeerNickname = null;
    activePeerIcon     = null;
    isHost             = false;
    _guestJoinHandled  = false;
    connectionState.value     = 'idle';
    roomDeletedNotifier.value = false; // reset for next session

    // Ask the server to delete the room — this kicks the other player out
    // via their RTDB onValue listener seeing a null snapshot.
    if (roomId != null && myId != null) {
      try {
        await http.delete(
          Uri.parse('$_serverUrl/room/$roomId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'roomId':             roomId,
            'requestingPlayerId': myId,
          }),
        ).timeout(const Duration(seconds: 5));
        debugPrint('Room $roomId deletion requested from server.');
      } catch (e) {
        // Non-fatal: the room will be cleaned up by the server's stale-room
        // sweep after 1 hour.
        debugPrint('Room deletion request failed (non-fatal): $e');
      }
    }

    _disconnecting = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Polling stubs (API compatibility with old code)
  // ─────────────────────────────────────────────────────────────────────────
  void startMailboxPolling() {}
  void stopMailboxPolling() {}

  // ─────────────────────────────────────────────────────────────────────────
  // Board serialisation helpers
  // ─────────────────────────────────────────────────────────────────────────
  static String serializeBoards(List<BoardData> boards) {
    return jsonEncode(
        boards.map((b) => {'size': b.size, 'grid': b.regionIds}).toList());
  }

  static List<BoardData> deserializeBoards(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list.map((item) {
      final int size = item['size'] as int;
      final List<List<int>> regionIds = (item['grid'] as List<dynamic>)
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
                id:          id,
                color:       RegionColors.getRegionColor(id, size),
                coordinates: [],
              ),
            );
            regions[id]!.coordinates.add(Point(r + 1, c + 1));
          }
        }
      }

      return BoardData(
        size:        size,
        regionIds:   regionIds,
        regions:     regions,
        rawResponse: 'Reconstructed from Firebase RTDB',
      );
    }).toList();
  }
}

// ── Background FCM handler ────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint('Background FCM: ${message.messageId}');
}
