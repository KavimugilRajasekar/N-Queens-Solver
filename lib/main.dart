import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'constants/colors.dart';
import 'screens/landing_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
