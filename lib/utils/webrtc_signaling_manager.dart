import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'board_processor.dart';
import '../constants/region_colors.dart';

class WebRTCSignalingManager {
  static final WebRTCSignalingManager instance = WebRTCSignalingManager._internal();

  WebRTCSignalingManager._internal() {
    connectionState.addListener(() {
      if (connectionState.value == 'connected' || connectionState.value == 'failed') {
        stopMailboxPolling();
      }
    });
  }

  // API base URL for signaling
  static const String _serverUrl = 'https://nqueensserver.vercel.app';

  // Firebase Messaging
  String? fcmToken;
  bool isFirebaseInitialized = false;

  // Connection State
  final ValueNotifier<String> connectionState = ValueNotifier('idle'); // 'idle', 'connecting', 'connected', 'failed'
  
  // Active Challenge / Invitation
  final ValueNotifier<Map<String, dynamic>?> incomingInviteNotifier = ValueNotifier(null);

  // WebRTC Peer Connection and Data Channel
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final List<Map<String, dynamic>> _iceCandidatesQueue = [];
  Timer? _iceCandidatesTimer;
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];

  // Stream controller to broadcast received game messages to PeerPlayScreen
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dataMessageStream => _messageController.stream;

  // Peer metadata
  String? activePeerId;
  String? activePeerNickname;
  String? activePeerIcon;

  // Is this device the Host (Maker) or Joiner
  bool isHost = false;

  // Initialize Firebase and Setup Push Listeners
  Future<void> initializeFirebase() async {
    if (isFirebaseInitialized) return;
    try {
      debugPrint("Initializing Firebase Core...");
      await Firebase.initializeApp();
      isFirebaseInitialized = true;

      // Request Push Notification Permissions
      final messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint("Notification Permission: ${settings.authorizationStatus}");

      // Get FCM Token
      fcmToken = await messaging.getToken();
      debugPrint("FCM Token: $fcmToken");

      // Configure foreground presentation options to show system banners while app is open!
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

      // Listen for foreground FCM messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final type = message.data['type'];
        debugPrint("Received Foreground FCM Wakeup Trigger of type '$type': ${message.data}");
        
        if (type == 'invite') {
          // Skip immediate mailbox pull. Let the OS display the notification banner first!
          // When the user taps the banner, it triggers onMessageOpenedApp to show the popup!
          debugPrint("FCM Foreground invite: System notification will show. Waiting for user tap.");
        } else {
          // For answers/candidates, pull instantly in the background
          await fetchFullSignalsFromMailbox();
        }
      });

      // Listen when the app is opened from a background or foreground state via notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        debugPrint("App opened/foreground tapped via FCM notification: ${message.data}");
        await fetchFullSignalsFromMailbox();
      });

      // Check if the app was launched from a completely terminated/killed state via notification tap
      RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint("App launched from terminated state via FCM notification tap: ${initialMessage.data}");
        await fetchFullSignalsFromMailbox();
      }

      isFirebaseInitialized = true;
      // Auto-register player on start if they already have an ID
      await registerPlayerProfile();
    } catch (e) {
      debugPrint("Firebase/FCM Initialization failed (Development Mode active): $e");
    }
  }

  Timer? _mailboxPollTimer;

  void startMailboxPolling() async {
    // Disabled! We are running on a pure, event-driven, high-speed FCM silent push signaling pipeline.
    // This completely eliminates repetitive polling HTTP requests, saving 100% of server costs and battery!
    debugPrint("Mailbox Polling: Bypass active (Pure silent FCM pipeline in charge).");
  }

  void stopMailboxPolling() {
    // Disabled! Pure FCM runs on incoming push streams without active polling.
  }

  Future<void> fetchFullSignalsFromMailbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myPlayerId = prefs.getString('player_unique_id_v2');
      if (myPlayerId == null) return;
      
      final cleanId = myPlayerId.trim();
      final normalizedId = cleanId.startsWith('NQ-') ? cleanId : 'NQ-$cleanId';
      
      final url = Uri.parse('$_serverUrl/mailbox/$normalizedId');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        final List<dynamic>? signals = resData['signals'];
        if (signals != null && signals.isNotEmpty) {
          for (var signal in signals) {
            debugPrint("FCM Wake-Up Hook: Pulled full signaling packet from mailbox: $signal");
            _handleIncomingFCM(Map<String, dynamic>.from(signal));
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to pull signaling payload on FCM hook: $e");
    }
  }

  void _queueIceCandidate(String targetPeerId, RTCIceCandidate candidate) {
    _iceCandidatesQueue.add({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
    
    _iceCandidatesTimer?.cancel();
    _iceCandidatesTimer = Timer(const Duration(milliseconds: 400), () async {
      if (_iceCandidatesQueue.isEmpty) return;
      final batch = List<Map<String, dynamic>>.from(_iceCandidatesQueue);
      _iceCandidatesQueue.clear();
      
      debugPrint("WebRTC: Dispatching batch of ${batch.length} ICE candidates to $targetPeerId.");
      await _sendSignal(targetPeerId, 'candidate', {
        'candidate': batch,
      });
    });
  }

  // Register Player FCM Token and ID with Vercel signaling server
  Future<bool> registerPlayerProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final playerId = prefs.getString('player_unique_id_v2');
      final nickname = prefs.getString('player_nickname') ?? 'Guest';
      final icon = prefs.getString('player_icon') ?? 'assets/player_icons/crown.png';

      if (playerId == null || fcmToken == null) {
        debugPrint("Cannot register player yet: PlayerId=$playerId, FCMToken=${fcmToken != null ? 'OK' : 'NULL'}");
        return false;
      }

      final url = Uri.parse('$_serverUrl/register-player');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'playerId': playerId,
          'fcmToken': fcmToken,
          'nickname': nickname,
          'icon': icon,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("Successfully registered Player $playerId on signaling server.");
        return true;
      } else {
        debugPrint("Failed to register player on server: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("Signaling server registration failed: $e");
    }
    return false;
  }

  // Validate if Peer ID exists on Server
  Future<Map<String, dynamic>?> checkPeerValid(String peerId) async {
    try {
      String formattedId = peerId.trim();
      if (!formattedId.startsWith('NQ-')) {
        formattedId = 'NQ-$formattedId';
      }
      final url = Uri.parse('$_serverUrl/player/$formattedId');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint("Validate Peer failed: $e");
    }
    return null;
  }

  // Route signal payloads via Vercel server
  Future<bool> _sendSignal(String toPeerId, String type, Map<String, dynamic> extraData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fromPlayerId = prefs.getString('player_unique_id_v2') ?? 'Unknown';
      final fromNickname = prefs.getString('player_nickname') ?? 'Rival';
      final fromIcon = prefs.getString('player_icon') ?? 'assets/player_icons/crown.png';

      final url = Uri.parse('$_serverUrl/send-signal');
      final payload = {
        'toPlayerId': toPeerId,
        'fromPlayerId': fromPlayerId,
        'fromNickname': fromNickname,
        'fromIcon': fromIcon,
        'type': type,
        ...extraData
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint("Signal '$type' successfully sent to $toPeerId.");
        return true;
      } else {
        debugPrint("Failed to send signal '$type': ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("Error sending signaling HTTP request: $e");
    }
    return false;
  }

  // Handle Incoming FCM payload
  void _handleIncomingFCM(Map<String, dynamic> data, {bool appOpened = false}) async {
    final type = data['type'];
    final fromPlayerId = data['fromPlayerId'];
    
    if (fromPlayerId == null || type == null) return;

    if (type == 'invite') {
      // 5-Minute Timeout / Invite Expiration Check
      final inviteTimestampStr = data['timestamp'];
      if (inviteTimestampStr != null) {
        final inviteTimestamp = int.tryParse(inviteTimestampStr) ?? 0;
        final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
        if (currentTimestamp - inviteTimestamp > 300000) { // 300,000 ms = 5 minutes
          debugPrint("FCM invite skipped: Challenge has expired (> 5 minutes old).");
          return;
        }
      }

      // Incoming Duel/Coop Challenge!
      final isCompeteMode = data['isCompeteMode'] == 'true';
      final int matchCount = int.parse(data['matchCount'] ?? '3');
      final matchBoardsJson = data['matchBoards'] ?? '[]';
      final sdp = data['sdp'] ?? '';

      incomingInviteNotifier.value = {
        'fromPlayerId': fromPlayerId,
        'fromNickname': data['fromNickname'] ?? 'Rival',
        'fromIcon': data['fromIcon'] ?? 'assets/player_icons/unicorn.png',
        'isCompeteMode': isCompeteMode,
        'matchCount': matchCount,
        'matchBoards': matchBoardsJson,
        'sdp': sdp,
        'appOpened': appOpened,
      };
    } else if (type == 'answer') {
      // Received SDP answer
      final sdp = data['sdp'];
      if (sdp != null && _peerConnection != null) {
        debugPrint("WebRTC: Received Answer! Setting remote description.");
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
        
        // Process any queued remote candidates now that the description is set!
        if (_remoteCandidatesQueue.isNotEmpty) {
          debugPrint("WebRTC: Processing ${_remoteCandidatesQueue.length} queued remote candidates after setting answer SDP.");
          for (var candidate in _remoteCandidatesQueue) {
            try {
              await _peerConnection!.addCandidate(candidate);
            } catch (e) {
              debugPrint("Failed to add queued remote candidate: $e");
            }
          }
          _remoteCandidatesQueue.clear();
        }
      }
    } else if (type == 'candidate') {
      // Received ICE candidate (Supports both single maps and batched lists!)
      final candidateStr = data['candidate'];
      if (candidateStr != null && _peerConnection != null) {
        try {
          final decoded = jsonDecode(candidateStr);
          final List<RTCIceCandidate> candidatesToProcess = [];

          if (decoded is List) {
            for (var candidateData in decoded) {
              candidatesToProcess.add(
                RTCIceCandidate(
                  candidateData['candidate'],
                  candidateData['sdpMid'],
                  candidateData['sdpMLineIndex'],
                ),
              );
            }
          } else {
            candidatesToProcess.add(
              RTCIceCandidate(
                decoded['candidate'],
                decoded['sdpMid'],
                decoded['sdpMLineIndex'],
              ),
            );
          }

          final remoteDesc = await _peerConnection!.getRemoteDescription();
          if (remoteDesc == null) {
            debugPrint("WebRTC: Remote description is not set yet. Queueing ${candidatesToProcess.length} remote candidates.");
            _remoteCandidatesQueue.addAll(candidatesToProcess);
          } else {
            debugPrint("WebRTC: Processing ${candidatesToProcess.length} remote candidates instantly.");
            for (var candidate in candidatesToProcess) {
              await _peerConnection!.addCandidate(candidate);
            }
          }
        } catch (e) {
          debugPrint("Failed to parse remote ICE candidates: $e");
        }
      }
    }
  }

  // Host WebRTC Setup Flow
  Future<void> hostConnection(String peerId, bool isCompeteMode, int matchCount, List<BoardData> matchBoards) async {
    isHost = true;
    activePeerId = peerId;
    connectionState.value = 'connecting';

    // 1. Fetch Peer Profile info (Validates peer is online/valid)
    final peerProfile = await checkPeerValid(peerId);
    if (peerProfile == null) {
      connectionState.value = 'failed';
      throw Exception("Rival ID '$peerId' is invalid or not registered in the arena! Check with them.");
    }
    
    activePeerNickname = peerProfile['nickname'];
    activePeerIcon = peerProfile['icon'];

    // 2. Setup RTCPeerConnection
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };
    
    _peerConnection = await createPeerConnection(config);

    // 3. Create WebRTC Data Channel (Reliable channel for gameplay states)
    final init = RTCDataChannelInit()..ordered = true;
    _dataChannel = await _peerConnection!.createDataChannel('game_channel', init);
    _setupDataChannelListeners();

    // 4. Handle ICE Candidates and route them via server (Batched for zero network clutter)
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint("Host: Local ICE Candidate gathered. Queueing to peer...");
      _queueIceCandidate(peerId, candidate);
    };

    _peerConnection!.onConnectionState = (state) async {
      debugPrint("Host Peer Connection State changed: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        connectionState.value = 'connected';
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Protect timing: only fail if the remote description has been set (meaning partner accepted)!
        final remoteDesc = await _peerConnection?.getRemoteDescription();
        if (remoteDesc != null) {
          connectionState.value = 'failed';
        } else {
          debugPrint("Host: Early failed state ignored because handshake has not started yet.");
        }
      }
    };

    // 5. Create Offer and Transmit Invitation via FCM
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // Serialize boards to lightweight string
    final serializedBoards = serializeBoards(matchBoards);

    await _sendSignal(peerId, 'invite', {
      'isCompeteMode': isCompeteMode.toString(),
      'matchCount': matchCount.toString(),
      'matchBoards': serializedBoards,
      'sdp': offer.sdp,
    });
    
    debugPrint("Host: Invite with offer SDP transmitted successfully to $peerId.");
  }

  // Joiner WebRTC Setup Flow
  Future<void> joinConnection(Map<String, dynamic> invitePayload) async {
    isHost = false;
    final hostId = invitePayload['fromPlayerId'];
    activePeerId = hostId;
    activePeerNickname = invitePayload['fromNickname'];
    activePeerIcon = invitePayload['fromIcon'];
    final sdpOffer = invitePayload['sdp'];

    connectionState.value = 'connecting';

    // 1. Setup RTCPeerConnection
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };
    
    _peerConnection = await createPeerConnection(config);

    // 2. Set incoming data channel handler
    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      debugPrint("Joiner: Incoming Data Channel received from Host.");
      _dataChannel = channel;
      _setupDataChannelListeners();
    };

    // 3. Handle ICE Candidates and route them via server (Batched for zero network clutter)
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint("Joiner: Local ICE Candidate gathered. Queueing to host...");
      _queueIceCandidate(hostId, candidate);
    };

    _peerConnection!.onConnectionState = (state) async {
      debugPrint("Joiner Peer Connection State changed: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        connectionState.value = 'connected';
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Protect timing: only fail if the remote description has been set (meaning partner accepted)!
        final remoteDesc = await _peerConnection?.getRemoteDescription();
        if (remoteDesc != null) {
          connectionState.value = 'failed';
        } else {
          debugPrint("Joiner: Early failed state ignored because handshake has not started yet.");
        }
      }
    };

    // 4. Set Remote Description (Host's offer)
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdpOffer, 'offer'));

    // 5. Create Answer and Send Back
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await _sendSignal(hostId, 'answer', {
      'sdp': answer.sdp,
    });

    debugPrint("Joiner: Answer SDP transmitted back to Host $hostId.");
  }

  // Send real-time game message over WebRTC
  bool sendMessage(Map<String, dynamic> payload) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      final msg = jsonEncode(payload);
      _dataChannel!.send(RTCDataChannelMessage(msg));
      debugPrint("WebRTC: Sent message over DataChannel: $msg");
      return true;
    }
    debugPrint("WebRTC: Failed to send message. DataChannel is closed or NULL.");
    return false;
  }

  // Listen to WebRTC DataChannel Events
  void _setupDataChannelListeners() {
    if (_dataChannel == null) return;

    _dataChannel!.onMessage = (RTCDataChannelMessage data) {
      try {
        final Map<String, dynamic> payload = jsonDecode(data.text);
        debugPrint("WebRTC: Received Message over DataChannel: ${data.text}");
        _messageController.add(payload);
      } catch (e) {
        debugPrint("Error parsing incoming WebRTC data: $e");
      }
    };

    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      debugPrint("WebRTC: Data Channel State changed: $state");
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        connectionState.value = 'connected';
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        connectionState.value = 'failed';
      }
    };
  }

  // Clean up WebRTC session
  void disconnect() {
    debugPrint("WebRTC: Disconnecting session and freeing resources.");
    _dataChannel?.close();
    _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _iceCandidatesTimer?.cancel();
    _iceCandidatesTimer = null;
    _iceCandidatesQueue.clear();
    _remoteCandidatesQueue.clear();
    activePeerId = null;
    activePeerNickname = null;
    activePeerIcon = null;
    isHost = false;
    connectionState.value = 'idle';
  }

  // Serializes a list of BoardData to a lightweight string representation
  static String serializeBoards(List<BoardData> boards) {
    final list = boards.map((b) => {
      'size': b.size,
      'grid': b.regionIds,
    }).toList();
    return jsonEncode(list);
  }

  // Deserializes a lightweight string back to a list of BoardData
  static List<BoardData> deserializeBoards(String jsonStr) {
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((item) {
      final int size = item['size'];
      final List<dynamic> gridRaw = item['grid'];
      final List<List<int>> regionIds = gridRaw.map((row) => List<int>.from(row)).toList();
      
      // Reconstruct regions coordinates & colors
      final Map<int, BoardRegion> regions = {};
      for (int r = 0; r < size; r++) {
        for (int c = 0; c < size; c++) {
          final int id = regionIds[r][c];
          if (id > 0) {
            if (!regions.containsKey(id)) {
              regions[id] = BoardRegion(
                id: id,
                color: RegionColors.getRegionColor(id, size),
                coordinates: [],
              );
            }
            regions[id]!.coordinates.add(Point(r + 1, c + 1));
          }
        }
      }
      
      return BoardData(
        size: size,
        regionIds: regionIds,
        regions: regions,
        rawResponse: "Reconstructed from WebRTC Signaling",
      );
    }).toList();
  }
}

// Background FCM Handler
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint("Handling background message: ${message.messageId}");
}
