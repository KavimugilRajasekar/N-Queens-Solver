import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UpdateService
//
// Checks the GitHub Releases API for a newer version of the app.
// Shows a stylish popup if a new version is available — but only once per
// new version (uses SharedPreferences to remember "already notified").
//
// Current app version must be kept in sync with pubspec.yaml.
// ─────────────────────────────────────────────────────────────────────────────

class UpdateService {
  // ── GitHub Releases API ────────────────────────────────────────────────────
  static const String _apiUrl =
      'https://api.github.com/repos/KavimugilRajasekar/N-Queens-Solver/releases/latest';

  // ── SharedPreferences key ──────────────────────────────────────────────────
  static const String _prefKeyLastNotified = 'update_last_notified_version';

  // ─────────────────────────────────────────────────────────────────────────
  // Public entry point — call this from LandingPage.initState()
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> checkAndNotify(BuildContext context) async {
    try {
      // Read the installed app version from the platform package metadata.
      // This always matches pubspec.yaml automatically — no manual updates needed.
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      final result = await _fetchLatestRelease();
      if (result == null) return;

      final latestVersion = result['version'] as String;
      final releaseUrl = result['url'] as String;

      // Skip if same as current
      if (!_isNewer(latestVersion, currentVersion)) return;

      // Skip if already notified for this exact version
      final prefs = await SharedPreferences.getInstance();
      final lastNotified = prefs.getString(_prefKeyLastNotified) ?? '';
      if (lastNotified == latestVersion) return;

      // Mark as notified
      await prefs.setString(_prefKeyLastNotified, latestVersion);

      // Show popup (must be on next frame to avoid context issues in initState)
      if (context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            _showUpdateDialog(context, currentVersion, latestVersion, releaseUrl);
          }
        });
      }
    } catch (e) {
      debugPrint('UpdateService: check failed — $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HTTP fetch
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Map<String, String>?> _fetchLatestRelease() async {
    try {
      final res = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
      final htmlUrl = json['html_url'] as String? ?? _apiUrl;

      if (tagName.isEmpty) return null;

      return {'version': tagName, 'url': htmlUrl};
    } catch (e) {
      debugPrint('UpdateService: HTTP error — $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Semantic version comparison: returns true if `latest` > `current`
  // ─────────────────────────────────────────────────────────────────────────
  static bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();

      // Pad to same length
      while (l.length < 3) { l.add(0); }
      while (c.length < 3) { c.add(0); }

      for (int i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
      return false; // same version
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stylish update popup
  // ─────────────────────────────────────────────────────────────────────────
  static void _showUpdateDialog(
    BuildContext context,
    String currentVersion,
    String latestVersion,
    String releaseUrl,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Transform.rotate(
          angle: -0.015,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4), // Sticky lemon yellow
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: AppColors.navyBlue, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.navyBlue,
                  offset: Offset(6, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icon badge ────────────────────────────────────────────
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.navyBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 3),
                    boxShadow: const [
                      BoxShadow(color: AppColors.navyBlue, offset: Offset(3, 3)),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: AppColors.gold,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Title ─────────────────────────────────────────────────
                const Text(
                  '✨ NEW VERSION!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyBlue,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Version pill ──────────────────────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.navyBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v$latestVersion is available!',
                    style: const TextStyle(
                      fontFamily: 'Comfortaa',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Body ──────────────────────────────────────────────────
                Text(
                  'A fresh update (v$latestVersion) just dropped on GitHub! Your current version is v$currentVersion. Grab the latest build for bug fixes & new features!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Comfortaa',
                    fontSize: 12,
                    color: AppColors.darkText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),

                // ── Download button ───────────────────────────────────────
                Transform.rotate(
                  angle: 0.01,
                  child: GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(releaseUrl);
                      try {
                        final launched = await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                        if (launched && dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                      } catch (e) {
                        debugPrint('UpdateService: launchUrl error — $e');
                        // Fallback: try platform default mode
                        try {
                          await launchUrl(uri, mode: LaunchMode.platformDefault);
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        } catch (_) {}
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(15),
                        border:
                            Border.all(color: AppColors.navyBlue, width: 2),
                        boxShadow: const [
                          BoxShadow(
                              color: AppColors.navyBlue,
                              offset: Offset(4, 4)),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_rounded,
                              color: AppColors.navyBlue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'DOWNLOAD NOW',
                            style: TextStyle(
                              fontFamily: 'DynaPuff',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Dismiss button ────────────────────────────────────────
                GestureDetector(
                  onTap: () => Navigator.pop(dialogCtx),
                  child: const Text(
                    'Maybe Later',
                    style: TextStyle(
                      fontFamily: 'Comfortaa',
                      fontSize: 12,
                      color: AppColors.secondaryText,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
