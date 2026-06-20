import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFFCFCFC);
  static const Color paperLine = Color(0xFFE3F2FD); // Light Blue for notebook lines
  static const Color navyBlue = Color(0xFF3F51B5); // Softer Indigo-Blue
  static const Color gold = Color(0xFFFFD54F); // Light Amber/Gold
  static const Color darkText = Color(0xFF424242);
  static const Color secondaryText = Color(0xFF9E9E9E);

  // ── Daily Quest palette ─────────────────────────────────────────────────
  // Light blue distinguishes Daily Quest cards from regular (white) and
  // mastered (gold) entries. The darker accent is used for the unseen
  // notification state so the user can spot fresh quests at a glance.
  static const Color dailyQuestBlue = Color(0xFFE3F2FD);
  static const Color dailyQuestBlueAccent = Color(0xFF64B5F6);
  static const Color dailyQuestBlueDeep = Color(0xFF1976D2);

  // ── Daily Quest failed palette ──────────────────────────────────────────
  // Soft red takes over once the user burns all [kMaxDailyAttempts] attempts.
  // Background is a near-white pink so the card still feels pastel/on-theme,
  // while the border deepens just enough to read as "locked".
  static const Color dailyQuestFailedBg = Color(0xFFFFEBEE);
  static const Color dailyQuestFailedBorder = Color(0xFFE57373);
  static const Color dailyQuestFailedAccent = Color(0xFFB71C1C);

  // ── Fog overlay for hidden Daily Quiz ───────────────────────────────────
  // Solid navy translucent layer painted over the grid before REVEAL.
  static const Color dailyQuizFog = Color(0xCC1A237E);
}
