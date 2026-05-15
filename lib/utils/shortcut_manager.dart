import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:camera/camera.dart';
import '../screens/saved_boards_screen.dart';
import '../screens/qr_scanner_screen.dart';
import '../screens/create_board_screen.dart';
import '../screens/generate_board_screen.dart';

class AppShortcutManager {
  static final QuickActions _quickActions = const QuickActions();

  static void init(BuildContext context, List<CameraDescription> cameras) {
    _quickActions.initialize((String shortcutType) {
      if (shortcutType == 'scan_qr') {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerScreen()));
      } else if (shortcutType == 'create_board') {
        Navigator.push(context, MaterialPageRoute(builder: (context) => CreateBoardScreen(cameras: cameras)));
      } else if (shortcutType == 'generate_board') {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const GenerateBoardScreen()));
      } else if (shortcutType == 'library') {
        Navigator.push(context, MaterialPageRoute(builder: (context) => SavedBoardsScreen(cameras: cameras)));
      }
    });

    _quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
        type: 'scan_qr',
        localizedTitle: 'Quick Scan',
        icon: 'icon_scan', // Needs to be added to Android/iOS native assets if we want custom icons
      ),
      const ShortcutItem(
        type: 'generate_board',
        localizedTitle: 'AI Generator',
        icon: 'icon_ai',
      ),
      const ShortcutItem(
        type: 'create_board',
        localizedTitle: 'Design Board',
        icon: 'icon_create',
      ),
      const ShortcutItem(
        type: 'library',
        localizedTitle: 'Board Library',
        icon: 'icon_library',
      ),
      const ShortcutItem(
        type: 'dont_delete',
        localizedTitle: "Please don't delete me! 👑",
        icon: 'icon_heart',
      ),
    ]);
  }
}
