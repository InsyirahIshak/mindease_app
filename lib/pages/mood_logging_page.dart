import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';

class MoodLoggingPage extends StatefulWidget {
  const MoodLoggingPage({super.key});

  @override
  State<MoodLoggingPage> createState() => _MoodLoggingPageState();
}

class _MoodLoggingPageState extends State<MoodLoggingPage> {
  int _selectedMood = 3;
  bool _logged = false;
  bool _alreadyLoggedToday = false;
  bool _isLoading = true;
  Map<String, dynamic>? _todayMoodData;

  final List<Map<String, dynamic>> moods = [
    {'value': 1, 'emoji': '😞', 'label': 'Very Unpleasant', 'color': Color(0xFFE57373)},
    {'value': 2, 'emoji': '😕', 'label': 'Unpleasant', 'color': Color(0xFFFFB74D)},
    {'value': 3, 'emoji': '😐', 'label': 'Neutral', 'color': Color(0xFFFFD54F)},
    {'value': 4, 'emoji': '😊', 'label': 'Pleasant', 'color': Color(0xFF81C784)},
    {'value': 5, 'emoji': '😄', 'label': 'Very Pleasant', 'color': Color(0xFF4DB6AC)},
  ];

  Map<String, dynamic> get currentMood =>
      moods.firstWhere((m) => m['value'] == _selectedMood);

  @override
  void initState() {
    super.initState();
    _checkTodayMood();
  }

  Future<void> _checkTodayMood() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (studentQuery.docs.isEmpty) return;
      final studId = studentQuery.docs.first.id;
      final moodQuery = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .where('log_date', isEqualTo: today)
          .limit(1)
          .get();
      if (moodQuery.docs.isNotEmpty) {
        final data = moodQuery.docs.first.data();
        setState(() {
          _alreadyLoggedToday = true;
          _todayMoodData = {
            'value': data['mood_level'],
            'time': data['log_date'],
          };
          _selectedMood = data['mood_level'];
        });
      }
    } catch (e) {
      print("Error checking today mood: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitMood() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      setState(() => _isLoading = true);
      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (studentQuery.docs.isEmpty) return;
      final studId = studentQuery.docs.first.id;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Save mood log
      await FirebaseFirestore.instance.collection('moodLogs').add({
        'stud_id': studId,
        'mood_level': _selectedMood,
        'mood_label': currentMood['label'],
        'log_date': today,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Calculate weekly analysis only after 7 days from first log
      await _calculateWeeklyThreshold(studId);
      await _calculateMonthlyAnalysis(studId);

      setState(() {
        _logged = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save mood: $e")),
      );
    }
  }

  Future<void> _calculateWeeklyThreshold(String studId) async {
    try {
      final now = DateTime.now();
      final today = now.toIso8601String().substring(0, 10);

      // Get first mood log ever for this student
      final firstLogQuery = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .orderBy('log_date', descending: false)
          .limit(1)
          .get();

      if (firstLogQuery.docs.isEmpty) return;

      final firstLogDate = DateTime.parse(
          firstLogQuery.docs.first.data()['log_date'] as String);
      final daysSinceFirst = now.difference(firstLogDate).inDays;

      // Only calculate if 7 days have passed since first log
      if (daysSinceFirst < 7) {
        print('⏭️ Only $daysSinceFirst days since first log — skip weekly analysis');
        return;
      }

      // Get current week label
      final firstDayOfYear = DateTime(now.year, 1, 1);
      final weekNumber = ((now.difference(firstDayOfYear).inDays +
                  firstDayOfYear.weekday) /
              7)
          .ceil();
      final currentWeek = "${now.year}-W$weekNumber";

      // Check if analysis already done this week
      final existingAnalysis = await FirebaseFirestore.instance
          .collection('moodAnalysis')
          .where('stud_id', isEqualTo: studId)
          .where('week', isEqualTo: currentWeek)
          .where('type', isEqualTo: 'weekly')
          .limit(1)
          .get();

      if (existingAnalysis.docs.isNotEmpty) {
        print("✅ Weekly analysis already done for $currentWeek");
        return;
      }

      // Get last 7 days mood logs
      final last7Dates = List.generate(7, (i) =>
          now.subtract(Duration(days: 6 - i)).toIso8601String().substring(0, 10));

      final last7Moods = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .where('log_date', whereIn: last7Dates)
          .get();

      if (last7Moods.docs.isEmpty) return;

      final logsCount = last7Moods.docs.length;
      final avg = last7Moods.docs
              .map((d) => (d.data()['mood_level'] as int?) ?? 3)
              .reduce((a, b) => a + b) /
          logsCount;

      String riskLevel;
      if (avg >= 3.5) {
        riskLevel = 'Normal';
      } else if (avg >= 2.5) {
        riskLevel = 'Moderate';
      } else {
        riskLevel = 'Critical';
      }

      // Save to moodAnalysis
      await FirebaseFirestore.instance.collection('moodAnalysis').add({
        'stud_id': studId,
        'type': 'weekly',
        'risk_level': riskLevel,
        'average_mood': avg,
        'logs_count': logsCount,
        'week': currentWeek,
        'week_start': last7Dates.first,
        'analysis_date': today,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Update student threshold
      await FirebaseFirestore.instance
          .collection('students')
          .doc(studId)
          .update({
        'threshold': riskLevel,
        'threshold_week': currentWeek,
        'threshold_updated': today,
      });

      print("✅ Weekly analysis: $riskLevel (avg: $avg, logs: $logsCount)");
    } catch (e) {
      print("Error calculating weekly threshold: $e");
    }
  }

  Future<void> _calculateMonthlyAnalysis(String studId) async {
    try {
      final now = DateTime.now();
      final isLastDayOfMonth =
          now.day == DateTime(now.year, now.month + 1, 0).day;
      final currentMonth =
          "${now.year}-${now.month.toString().padLeft(2, '0')}";
      final startOfMonth =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-01";
      final today = now.toIso8601String().substring(0, 10);

      final existing = await FirebaseFirestore.instance
          .collection('moodAnalysis')
          .where('stud_id', isEqualTo: studId)
          .where('month', isEqualTo: currentMonth)
          .where('type', isEqualTo: 'monthly')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) return;

      final thisMonthMoods = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .where('log_date', isGreaterThanOrEqualTo: startOfMonth)
          .where('log_date', isLessThanOrEqualTo: today)
          .get();

      final logsThisMonth = thisMonthMoods.docs.length;
      final shouldCalculate =
          logsThisMonth >= 30 || (isLastDayOfMonth && logsThisMonth >= 1);

      if (!shouldCalculate) return;

      final avg = thisMonthMoods.docs
              .map((d) => (d.data()['mood_level'] as int?) ?? 3)
              .reduce((a, b) => a + b) /
          logsThisMonth;

      String riskLevel;
      if (avg >= 3.5) {
        riskLevel = 'Normal';
      } else if (avg >= 2.5) {
        riskLevel = 'Moderate';
      } else {
        riskLevel = 'Critical';
      }

      await FirebaseFirestore.instance.collection('moodAnalysis').add({
        'stud_id': studId,
        'type': 'monthly',
        'risk_level': riskLevel,
        'average_mood': avg,
        'logs_count': logsThisMonth,
        'month': currentMonth,
        'analysis_date': today,
        'created_at': FieldValue.serverTimestamp(),
      });

      print("✅ Monthly analysis: $riskLevel (avg: $avg, logs: $logsThisMonth)");
    } catch (e) {
      print("Error calculating monthly analysis: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_alreadyLoggedToday && _todayMoodData != null) {
      return _buildAlreadyLoggedScreen(context);
    }
    if (_logged) {
      return _buildSuccessScreen(context);
    }
    return _buildMoodScreen(context);
  }

  Widget _buildAlreadyLoggedScreen(BuildContext context) {
    final mood = moods.firstWhere(
        (m) => m['value'] == _todayMoodData!['value'],
        orElse: () => moods[2]);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Row(
                        children: [
                          Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("Mood Logging",
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.secondarySoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.secondary.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.secondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "You have already logged your mood today. See you tomorrow! 😊",
                              style: TextStyle(color: AppTheme.secondary, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        children: [
                          Text("TODAY'S MOOD",
                              style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          Text(mood['emoji'], style: const TextStyle(fontSize: 80)),
                          const SizedBox(height: 12),
                          Text(mood['label'],
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: mood['color'])),
                          const SizedBox(height: 8),
                          Text(_todayMoodData!['time'] ?? '',
                              style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    DecoratedBox(
                      decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(16)),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/dashboard'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Back to Dashboard",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(gradient: AppTheme.headerGradient, shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 44),
                  ),
                  const SizedBox(height: 16),
                  const Text("Mood Logged!",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                  const SizedBox(height: 6),
                  Text("Your mood has been saved successfully.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        Text("MOOD SAVED",
                            style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Text(currentMood['emoji'], style: const TextStyle(fontSize: 60)),
                        const SizedBox(height: 6),
                        Text(currentMood['label'],
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: currentMood['color'])),
                        const SizedBox(height: 4),
                        Text(DateTime.now().toIso8601String().substring(0, 10),
                            style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  DecoratedBox(
                    decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(16)),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/dashboard'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Back to Dashboard",
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMoodScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Row(
                        children: [
                          Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("How are you feeling?",
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text("Slide or tap to choose your current mood",
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        key: ValueKey(_selectedMood),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          children: [
                            Text(currentMood['emoji'], style: const TextStyle(fontSize: 80)),
                            const SizedBox(height: 12),
                            Text(currentMood['label'],
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: currentMood['color'])),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.primary,
                        inactiveTrackColor: AppTheme.primarySoft,
                        thumbColor: AppTheme.secondary,
                        overlayColor: AppTheme.secondary.withOpacity(0.2),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                        trackHeight: 6,
                      ),
                      child: Slider(
                        value: _selectedMood.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        onChanged: (val) => setState(() => _selectedMood = val.round()),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: moods.map((m) {
                        final isSelected = m['value'] == _selectedMood;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedMood = m['value']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primarySoft : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(m['emoji'],
                                style: TextStyle(fontSize: isSelected ? 28 : 22)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Very Unpleasant", style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                          Text("Very Pleasant", style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    DecoratedBox(
                      decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(16)),
                      child: ElevatedButton(
                        onPressed: _submitMood,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Submit Mood",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}