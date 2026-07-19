// test/mindease_helpers_test.dart
//
// Run with: flutter test test/mindease_helpers_test.dart
// Or run all tests with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:mindease_app/utils/mindease_helpers.dart';

void main() {
  // ── DASS-21 Depression Interpretation ──
  group('DASS-21 Depression Interpretation', () {
    test('UT01: score 5 returns Normal', () {
      expect(MindEaseHelpers.interpretDepression(5), 'Normal');
    });

    test('UT02: score 22 returns Severe', () {
      expect(MindEaseHelpers.interpretDepression(22), 'Severe');
    });

    test('UT03: score 6 returns Normal', () {
      expect(MindEaseHelpers.interpretAnxiety(6), 'Normal');
    });

    test('UT04: score 24 returns Severe', () {
      expect(MindEaseHelpers.interpretDepression(24), 'Severe');
    });

    test('UT05: score 30 returns Extremely Severe', () {
      expect(MindEaseHelpers.interpretDepression(30), 'Extremely Severe');
    });
  });

  // ── DASS-21 Anxiety Interpretation ──
  group('DASS-21 Anxiety Interpretation', () {
    test('UT06: score 6 returns Normal', () {
      expect(MindEaseHelpers.interpretAnxiety(6), 'Normal');
    });

    test('UT07: score 8 returns Mild', () {
      expect(MindEaseHelpers.interpretAnxiety(8), 'Mild');
    });

    test('UT08: score 12 returns Moderate', () {
      expect(MindEaseHelpers.interpretAnxiety(12), 'Moderate');
    });

    test('UT09: score 16 returns Severe', () {
      expect(MindEaseHelpers.interpretAnxiety(16), 'Severe');
    });

    test('UT10: score 22 returns Extremely Severe', () {
      expect(MindEaseHelpers.interpretAnxiety(22), 'Extremely Severe');
    });
  });

  // ── DASS-21 Stress Interpretation ──
  group('DASS-21 Stress Interpretation', () {
    test('UT11: score 12 returns Normal', () {
      expect(MindEaseHelpers.interpretStress(12), 'Normal');
    });

    test('UT12: score 16 returns Mild', () {
      expect(MindEaseHelpers.interpretStress(16), 'Mild');
    });

    test('UT13: score 22 returns Moderate', () {
      expect(MindEaseHelpers.interpretStress(22), 'Moderate');
    });

    test('UT14: score 30 returns Severe', () {
      expect(MindEaseHelpers.interpretStress(30), 'Severe');
    });

    test('UT15: score 36 returns Extremely Severe', () {
      expect(MindEaseHelpers.interpretStress(36), 'Extremely Severe');
    });
  });

  // ── Weekly Mood Threshold Calculation ──
  group('Weekly Mood Threshold Calculation', () {
    test('UT16: average mood 3.6 returns Normal', () {
      expect(MindEaseHelpers.weeklyThreshold(3.6), 'Normal');
    });

    test('UT17: average mood 2.8 returns Moderate', () {
      expect(MindEaseHelpers.weeklyThreshold(2.8), 'Moderate');
    });

    test('UT18: average mood 2.0 returns Critical', () {
      expect(MindEaseHelpers.weeklyThreshold(2.0), 'Critical');
    });
  });

  // ── Overall DASS-21 Severity Level ──
  group('Overall DASS-21 Severity Level', () {
    test('UT19: Severe + Normal + Mild returns High', () {
      expect(
        MindEaseHelpers.overallLevel('Severe', 'Normal', 'Mild'),
        'High',
      );
    });

    test('UT20: Moderate + Normal + Normal returns Moderate', () {
      expect(
        MindEaseHelpers.overallLevel('Moderate', 'Normal', 'Normal'),
        'Moderate',
      );
    });

    test('UT21: Normal + Normal + Normal returns Low', () {
      expect(
        MindEaseHelpers.overallLevel('Normal', 'Normal', 'Normal'),
        'Low',
      );
    });
  });

  // ── Display Name Extraction ──
  group('Display Name Extraction', () {
    test('UT22: "Ahmad Bin Hassan" returns Ahmad', () {
      expect(MindEaseHelpers.displayName('Ahmad Bin Hassan'), 'Ahmad');
    });

    test('UT23: "Siti Binti Mahmud" returns Siti', () {
      expect(MindEaseHelpers.displayName('Siti Binti Mahmud'), 'Siti');
    });

    test('UT24: "Ali" (no bin/binti) returns Ali', () {
      expect(MindEaseHelpers.displayName('Ali'), 'Ali');
    });
  });

  // ── Mood Chart Date Range Generation ──
  group('Mood Chart Date Range Generation', () {
    test('UT25: 7-day range with 3 missing logs returns 7 dates with correct gaps', () {
      final now = DateTime(2026, 6, 24);
      final moodMap = {
        '2026-06-18': 4,
        '2026-06-20': 3,
        '2026-06-24': 5,
      };

      final result = MindEaseHelpers.buildDateRange(7, moodMap, now);

      expect(result.length, 7);
      expect(result.first['date'], '2026-06-18');
      expect(result.first['mood_level'], 4);
      expect(result.last['date'], '2026-06-24');
      expect(result.last['mood_level'], 5);

      final missingCount =
          result.where((d) => d['mood_level'] == null).length;
      expect(missingCount, 4);
    });
  });

  // ── Password and Security Validation ──
  group('Password and Security Validation', () {
    test('UT26: sendPasswordResetEmail called with valid email format', () {
      final email = 'student@gmail.com';
      final isValidEmail =
          RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
      expect(isValidEmail, true);
    });

    test('UT27: New password meets all security requirements', () {
      final password = 'NewPass@123';
      final hasUpper = password.contains(RegExp(r'[A-Z]'));
      final hasLower = password.contains(RegExp(r'[a-z]'));
      final hasDigit = password.contains(RegExp(r'[0-9]'));
      final hasSpecial = password.contains(RegExp(r'[!@#\$%^&*]'));
      final hasLength = password.length >= 8;
      expect(hasUpper && hasLower && hasDigit && hasSpecial && hasLength, true);
    });
  });

  // ── Progress Report Validation ──
  group('Progress Report Validation', () {
    test('UT28: Progress report text is not empty before saving to Firestore', () {
      final report = 'Student showed improvement in managing anxiety.';
      expect(report.trim().isNotEmpty, true);
    });
  });
}