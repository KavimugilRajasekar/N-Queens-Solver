import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bootstrap Android notification channels at app start.
///
/// The server broadcasts FCM daily-quest / match-invite payloads tagged with
/// a channel id (``daily_quest`` / ``n_queens_match_invite``). Android 8+
/// requires the channel to exist at runtime — without this bootstrap, the
/// tray alert is silently dropped.
///
/// On iOS / non-Android platforms the method-channel call is a no-op and we
/// silently swallow the [MissingPluginException].
class NotificationChannelService {
  static const _channel = MethodChannel(
    'com.example.n_queens_solver/screenshot_solver',
  );

  /// Idempotent — safe to call on every cold start.
  static Future<void> bootstrap() async {
    try {
      await _channel.invokeMethod<void>('createNotificationChannels');
    } on MissingPluginException {
      // iOS / test environment — nothing to do.
    } catch (e) {
      // Never let notification setup block app launch.
      debugPrint('NotificationChannelService.bootstrap: $e');
    }
  }
}
