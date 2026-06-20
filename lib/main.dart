import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'constants/colors.dart';
import 'screens/landing_page.dart';

import 'utils/daily_quest_manager.dart';
import 'utils/firebase_game_manager.dart';
import 'utils/notification_channel_service.dart';
import 'utils/screenshot_solver_service.dart';
import 'utils/share_handler_service.dart';

/// Global navigator key — lets [ShareHandlerService] push routes without a
/// BuildContext (the shared image can arrive before any widget is on screen).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and FCM
  await FirebaseGameManager.instance.initializeFirebase();

  // Wire the global navigator key into DailyQuestManager so its foreground
  // FCM handler can pop a snackbar (FCM does not show a tray alert while
  // the app is in the foreground by default).
  DailyQuestManager.navigatorKey = appNavigatorKey;

  // Create the Android notification channels the FCM payloads target so
  // daily-quest + invite tray alerts actually render on Android 8+.
  await NotificationChannelService.bootstrap();

  // Initialize the screenshot solver event channel listener
  ScreenshotSolverService.instance.initialize();

  // Initialize the share handler so images shared from other apps are caught
  ShareHandlerService.instance.initialize(appNavigatorKey);

  // Obtain a list of the available cameras on the device.
  final cameras = await availableCameras();

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'N-Queens Solver',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Comfortaa',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navyBlue,
          primary: AppColors.navyBlue,
          secondary: AppColors.gold,
          brightness: Brightness.light,
          surface: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: AppColors.navyBlue,
            fontWeight: FontWeight.bold,
            fontSize: 34,
            fontFamily: 'PlaywriteUSModern',
          ),
          titleLarge: TextStyle(
            color: AppColors.darkText,
            fontWeight: FontWeight.w600,
            fontSize: 22,
            fontFamily: 'DynaPuff',
          ),
          bodyLarge: TextStyle(
            color: AppColors.darkText,
            fontSize: 17,
            height: 1.6,
          ),
          bodyMedium: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
      home: LandingPage(cameras: cameras),
    );
  }
}
