// lib/utils/mindease_helpers.dart
//
// Pure, standalone calculation functions extracted from the widget classes
// so they can be unit tested independently of the UI and Firestore.
//
// These functions contain NO Flutter widget code, NO Firestore calls —
// just plain Dart logic. Import this file wherever the calculation is
// needed (stress_assessment_page.dart, mood_logging_page.dart, etc.)
// instead of duplicating the logic inline.

class MindEaseHelpers {
  // ── DASS-21: Depression severity interpretation ──
  static String interpretDepression(int score) {
    if (score <= 9) return 'Normal';
    if (score <= 13) return 'Mild';
    if (score <= 20) return 'Moderate';
    if (score <= 27) return 'Severe';
    return 'Extremely Severe';
  }

  // ── DASS-21: Anxiety severity interpretation ──
  static String interpretAnxiety(int score) {
    if (score <= 7) return 'Normal';
    if (score <= 9) return 'Mild';
    if (score <= 14) return 'Moderate';
    if (score <= 19) return 'Severe';
    return 'Extremely Severe';
  }

  // ── DASS-21: Stress severity interpretation ──
  static String interpretStress(int score) {
    if (score <= 14) return 'Normal';
    if (score <= 18) return 'Mild';
    if (score <= 25) return 'Moderate';
    if (score <= 33) return 'Severe';
    return 'Extremely Severe';
  }

  // ── DASS-21: Overall severity level from 3 sub-scale labels ──
  static String overallLevel(String depLabel, String anxLabel, String strLabel) {
    final levels = [depLabel, anxLabel, strLabel];
    if (levels.contains('Extremely Severe') || levels.contains('Severe')) {
      return 'High';
    } else if (levels.contains('Moderate')) {
      return 'Moderate';
    } else if (levels.contains('Mild')) {
      return 'Mild';
    }
    return 'Low';
  }

  // ── Weekly mood threshold classification ──
  static String weeklyThreshold(double averageMood) {
    if (averageMood >= 3.5) return 'Normal';
    if (averageMood >= 2.5) return 'Moderate';
    return 'Critical';
  }

  // ── Extract display name (strips Bin/Binti) ──
  static String displayName(String fullName) {
    final parts = fullName.split(' ');
    for (int i = 0; i < parts.length; i++) {
      final word = parts[i].toLowerCase();
      if (word == 'bin' || word == 'binti' || word == 'bt' || word == 'bt.') {
        return parts.sublist(0, i).join(' ');
      }
    }
    return parts.first;
  }

  // ── Build a continuous date range with mood data (gaps as null) ──
  // moodMap: { "2026-06-20": 4, "2026-06-22": 2 }  (missing dates = no entry)
  // Returns a list of {date, mood_level} maps covering [days] days ending today.
  static List<Map<String, dynamic>> buildDateRange(
      int days, Map<String, int> moodMap, DateTime now) {
    final result = <Map<String, dynamic>>[];
    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      result.add({'date': dateStr, 'mood_level': moodMap[dateStr]});
    }
    return result;
  }
}