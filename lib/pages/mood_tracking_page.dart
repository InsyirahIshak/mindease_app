import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:math' as math;

class MoodTrackingPage extends StatefulWidget {
  const MoodTrackingPage({super.key});

  @override
  State<MoodTrackingPage> createState() => _MoodTrackingPageState();
}

class _MoodTrackingPageState extends State<MoodTrackingPage> {
  String _filter = '7';
  bool isLoading = true;
  List<Map<String, dynamic>> _allMoods = [];
  String? _savedThreshold; // from moodAnalysis collection

  @override
  void initState() {
    super.initState();
    _loadMoodHistory();
    _loadSavedThreshold();
  }

  Future<void> _loadSavedThreshold() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (studentQuery.docs.isEmpty) return;
      final studId = studentQuery.docs.first.id;

      // Load from moodAnalysis — only exists after Railway aggregation
      final analysisQuery = await FirebaseFirestore.instance
          .collection('moodAnalysis')
          .where('stud_id', isEqualTo: studId)
          .where('type', isEqualTo: 'weekly')
          .orderBy('analysis_date', descending: true)
          .limit(1)
          .get();

      if (analysisQuery.docs.isNotEmpty) {
        final threshold = analysisQuery.docs.first.data()['risk_level'] as String?;
        if (threshold != null) {
          setState(() => _savedThreshold = threshold);
        }
      }
    } catch (e) {
      print("Error loading threshold: $e");
    }
  }

  final List<Map<String, dynamic>> moodMeta = [
    {'value': 1, 'emoji': '😞', 'label': 'Very Unpleasant', 'color': Color(0xFFE57373)},
    {'value': 2, 'emoji': '😕', 'label': 'Unpleasant', 'color': Color(0xFFFFB74D)},
    {'value': 3, 'emoji': '😐', 'label': 'Neutral', 'color': Color(0xFFFFD54F)},
    {'value': 4, 'emoji': '😊', 'label': 'Pleasant', 'color': Color(0xFF81C784)},
    {'value': 5, 'emoji': '😄', 'label': 'Very Pleasant', 'color': Color(0xFF4DB6AC)},
  ];

  Future<void> _loadMoodHistory() async {
    try {
      setState(() => isLoading = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

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
          .orderBy('log_date', descending: false)
          .get();

      setState(() {
        _allMoods = moodQuery.docs.map((d) => d.data()).toList();
      });
    } catch (e) {
      print("Error loading mood history: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Generate full date range with mood data ──
  List<Map<String, dynamic>> _buildDateRange(int days) {
    final now = DateTime.now();
    final moodMap = <String, int>{};
    for (final m in _allMoods) {
      moodMap[m['log_date'] as String] = m['mood_level'] as int;
    }
    final result = <Map<String, dynamic>>[];
    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      result.add({'date': dateStr, 'mood_level': moodMap[dateStr]});
    }
    return result;
  }

  // New student (< 7 days) → start from first log date
  // Existing student (7+ days) → show last 7 days ending today
  List<Map<String, dynamic>> _buildWeekRange() {
    final now = DateTime.now();
    final moodMap = <String, int>{};
    for (final m in _allMoods) {
      moodMap[m['log_date'] as String] = m['mood_level'] as int;
    }

    DateTime startDate;
    if (_allMoods.isEmpty) {
      startDate = now.subtract(const Duration(days: 6));
    } else {
      final firstLog = DateTime.parse(_allMoods.first['log_date'] as String);
      final daysPassed = now.difference(firstLog).inDays;
      if (daysPassed < 7) {
        startDate = firstLog;
      } else {
        startDate = now.subtract(const Duration(days: 6));
      }
    }

    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final date = startDate.add(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      result.add({'date': dateStr, 'mood_level': moodMap[dateStr]});
    }
    return result;
  }
  List<Map<String, dynamic>> get chartData {
    if (_filter == '7') return _buildWeekRange(); // Mon–Sun of current week
    if (_filter == '30') return _buildDateRange(30);
    if (_allMoods.isEmpty) return [];
    final first = DateTime.parse(_allMoods.first['log_date']);
    final days = DateTime.now().difference(first).inDays + 1;
    return _buildDateRange(days);
  }

  List<Map<String, dynamic>> get filteredData {
    if (_filter == '7') {
      // Last 7 days ending today
      final now = DateTime.now();
      final last7Dates = List.generate(7, (i) =>
        now.subtract(Duration(days: 6 - i)).toIso8601String().substring(0, 10));
      return _allMoods.where((m) => last7Dates.contains(m['log_date'])).toList();
    }
    if (_filter == '30') {
      return _allMoods.length > 30 ? _allMoods.sublist(_allMoods.length - 30) : _allMoods;
    }
    return _allMoods;
  }

  double get average {
    final valid = filteredData.where((m) => m['mood_level'] != null).toList();
    if (valid.isEmpty) return 0;
    return valid.fold(0.0, (s, m) => s + (m['mood_level'] as int)) / valid.length;
  }

  int get minMood {
    final valid = filteredData.where((m) => m['mood_level'] != null).toList();
    if (valid.isEmpty) return 0;
    return valid.map((m) => m['mood_level'] as int).reduce((a, b) => a < b ? a : b);
  }

  int get maxMood {
    final valid = filteredData.where((m) => m['mood_level'] != null).toList();
    if (valid.isEmpty) return 0;
    return valid.map((m) => m['mood_level'] as int).reduce((a, b) => a > b ? a : b);
  }

  int get mostFrequentMood {
    final valid = filteredData.where((m) => m['mood_level'] != null).toList();
    if (valid.isEmpty) return 0;
    final freq = <int, int>{};
    for (final m in valid) {
      final v = m['mood_level'] as int;
      freq[v] = (freq[v] ?? 0) + 1;
    }
    return freq.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Map<String, dynamic> get stressLevel {
    if (average >= 3.5) {
      return {
        'label': 'Normal', 'color': const Color(0xFF4DB6AC),
        'bg': const Color(0xFFE0F7F6), 'emoji': '😊',
        'weekSentence': 'Your mood has been mostly positive this week. Keep it up!',
        'monthSentence': 'You have maintained a healthy mood pattern this month. Great work!',
      };
    } else if (average >= 2.5) {
      return {
        'label': 'Moderate', 'color': const Color(0xFFFFB74D),
        'bg': const Color(0xFFFFF3E0), 'emoji': '😐',
        'weekSentence': 'Your mood has been mixed this week. Consider taking some time to relax.',
        'monthSentence': 'Your mood has had some ups and downs this month. Try to maintain healthy habits.',
      };
    } else {
      return {
        'label': 'Critical', 'color': const Color(0xFFE57373),
        'bg': const Color(0xFFFFEBEE), 'emoji': '😟',
        'weekSentence': 'Your mood has been low this week. Please consider reaching out for support.',
        'monthSentence': 'Your mood has been consistently low this month. We strongly encourage you to seek help.',
      };
    }
  }

  // Use saved threshold for display, fallback to live stressLevel
  // Returns 'none' map if less than 7 days
  Map<String, dynamic> get displayLevel {
    final t = effectiveThreshold;
    if (t == 'Critical') {
      return {
        'label': 'Critical', 'color': const Color(0xFFE57373),
        'bg': const Color(0xFFFFEBEE), 'emoji': '😟',
        'weekSentence': 'Your mood has been low this week. Please consider reaching out for support.',
        'monthSentence': 'Your mood has been consistently low this month. We strongly encourage you to seek help.',
      };
    } else if (t == 'Moderate') {
      return {
        'label': 'Moderate', 'color': const Color(0xFFFFB74D),
        'bg': const Color(0xFFFFF3E0), 'emoji': '😐',
        'weekSentence': 'Your mood has been mixed this week. Consider taking some time to relax.',
        'monthSentence': 'Your mood has had some ups and downs this month. Try to maintain healthy habits.',
      };
    } else {
      return {
        'label': 'Normal', 'color': const Color(0xFF4DB6AC),
        'bg': const Color(0xFFE0F7F6), 'emoji': '😊',
        'weekSentence': 'Your mood has been mostly positive this week. Keep it up!',
        'monthSentence': 'You have maintained a healthy mood pattern this month. Great work!',
      };
    }
  }

  // Only show week data if 7 days have passed since first log
  bool get hasWeekData {
    if (_allMoods.isEmpty) return false;
    final firstLog = DateTime.parse(_allMoods.first['log_date'] as String);
    final daysPassed = DateTime.now().difference(firstLog).inDays;
    return daysPassed >= 7;
  }

  bool get hasMonthData {
    if (_allMoods.isEmpty) return false;
    final firstLog = DateTime.parse(_allMoods.first['log_date'] as String);
    final daysPassed = DateTime.now().difference(firstLog).inDays;
    return daysPassed >= 30;
  }

  // Use saved threshold from moodAnalysis, fallback to live calculation
  // Only return 'none' if student has never had 7 days of logging
  String get effectiveThreshold {
    if (_allMoods.isEmpty) return 'none';
    final firstLog = DateTime.parse(_allMoods.first['log_date'] as String);
    final daysPassed = DateTime.now().difference(firstLog).inDays;
    if (daysPassed < 7) return 'none';
    if (_savedThreshold != null) return _savedThreshold!;
    return 'none'; // no aggregation yet
  }

  bool get isModeratOrCritical =>
      effectiveThreshold == 'Moderate' || effectiveThreshold == 'Critical';
  bool get isCritical => effectiveThreshold == 'Critical';

  Map<String, dynamic> moodById(int value) =>
      moodMeta.firstWhere((m) => m['value'] == value, orElse: () => moodMeta[2]);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    const Text("Mood Tracking",
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text("Visualise your wellbeing journey",
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),

                    // Filter Tabs
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Row(children: [
                        _filterTab('7', '7 Days'),
                        _filterTab('30', '30 Days'),
                        _filterTab('all', 'All Time'),
                      ]),
                    ),

                    const SizedBox(height: 16),

                    // Line Chart Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("MOOD TREND",
                                  style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                              if (filteredData.isNotEmpty && _savedThreshold != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: displayLevel['bg'],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(displayLevel['emoji'], style: const TextStyle(fontSize: 14)),
                                      const SizedBox(width: 4),
                                      Text(displayLevel['label'],
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: displayLevel['color'])),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text("${filteredData.where((d) => d['mood_level'] != null).length} entries logged",
                              style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                          const SizedBox(height: 20),
                          _allMoods.isNotEmpty ? _buildLineChart() : Container(
                            height: 180,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("🌤️", style: TextStyle(fontSize: 40)),
                                const SizedBox(height: 8),
                                Text("Log moods to see your trend", style: TextStyle(color: AppTheme.textGrey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (filteredData.isNotEmpty) ...[
                      _buildAggregationSummary(),
                      const SizedBox(height: 16),
                    ],

                    if (_savedThreshold != null) ...[
                      _buildAnalysisCard(),
                      const SizedBox(height: 16),
                    ],

                    if (filteredData.isNotEmpty) ...[
                      _buildBreakdownChart(),
                      const SizedBox(height: 16),
                    ],

                    // ── Relaxation Corner — only after first weekly aggregation ──
                    if (_savedThreshold != null) ...[
                      _buildRelaxationCorner(),
                    ],

                    if (_allMoods.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            const Text("📊", style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 12),
                            const Text("No mood data yet",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                            const SizedBox(height: 6),
                            Text("Start logging your mood daily to see your tracking chart and analysis here.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                          ],
                        ),
                      ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterTab(String id, String label) {
    final isSelected = _filter == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected ? AppTheme.buttonGradient : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.textGrey)),
        ),
      ),
    );
  }

  Widget _buildLineChart() {
    final data = chartData;
    if (data.isEmpty) return const SizedBox();

    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      final moodLevel = data[i]['mood_level'];
      if (moodLevel != null) spots.add(FlSpot(i.toDouble(), (moodLevel as int).toDouble()));
    }

    return SizedBox(
      height: 200,
      child: LineChart(LineChartData(
        minY: 1, maxY: 5, minX: 0, maxX: (data.length - 1).toDouble(),
        gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: const Color(0xFFE8EDF2), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, interval: 1,
            getTitlesWidget: (value, meta) {
              final m = moodMeta.firstWhere((m) => m['value'] == value.toInt(), orElse: () => {'emoji': ''});
              return Text(m['emoji'] ?? '', style: const TextStyle(fontSize: 12));
            },
            reservedSize: 28,
          )),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < data.length) {
                final step = data.length <= 7 ? 1 : data.length <= 14 ? 2 : data.length <= 30 ? 5 : 7;
                if (index % step == 0 || index == data.length - 1) {
                  return Padding(padding: const EdgeInsets.only(top: 6),
                      child: Text(data[index]['date'].toString().substring(5),
                          style: TextStyle(fontSize: 9, color: AppTheme.textGrey)));
                }
              }
              return const Text('');
            },
            reservedSize: 28,
          )),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final mood = moodById(spot.y.toInt());
              return LineTooltipItem('${mood['emoji']} ${mood['label']}',
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold));
            }).toList(),
          ),
        ),
        lineBarsData: spots.isEmpty ? [] : [
          LineChartBarData(
            spots: spots, isCurved: true, color: AppTheme.primary, barWidth: 3,
            dotData: FlDotData(show: true,
                getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
                    radius: 5, color: AppTheme.secondary, strokeWidth: 2, strokeColor: Colors.white)),
            belowBarData: BarAreaData(show: true,
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [AppTheme.primary.withOpacity(0.3), AppTheme.primary.withOpacity(0.0)])),
          ),
        ],
      )),
    );
  }

  Widget _buildAggregationSummary() {
    if (filteredData.isEmpty) return const SizedBox();
    final minM = moodById(minMood);
    final maxM = moodById(maxMood);
    final freqM = moodById(mostFrequentMood);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("SUMMARY", style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(children: [
          _summaryItem("Lowest", minM['emoji'], minM['label'], minM['color']),
          _divider(),
          _summaryItem("Highest", maxM['emoji'], maxM['label'], maxM['color']),
          _divider(),
          _summaryItem("Most Frequent", freqM['emoji'], freqM['label'], freqM['color']),
        ]),
      ]),
    );
  }

  Widget _summaryItem(String title, String emoji, String label, Color color) {
    return Expanded(
      child: Column(children: [
        Text(title, style: TextStyle(fontSize: 10, color: AppTheme.textGrey), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ),
      ]),
    );
  }

  Widget _divider() => Container(width: 1, height: 60, color: const Color(0xFFE8EDF2));

  Widget _buildAnalysisCard() {
    final sentence = hasMonthData ? displayLevel['monthSentence'] : displayLevel['weekSentence'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(hasMonthData ? "MONTHLY ANALYSIS" : "WEEKLY ANALYSIS",
            style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: displayLevel['bg'], borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(displayLevel['emoji'], style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text(displayLevel['label'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: displayLevel['color'])),
          ]),
        ),
        const SizedBox(height: 14),
        Text(sentence, style: const TextStyle(fontSize: 14, color: AppTheme.textDark, height: 1.5)),
      ]),
    );
  }

  Widget _buildBreakdownChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("MOOD BREAKDOWN", style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: filteredData.length.toDouble(),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final mood = moodMeta[group.x.toInt()];
                  return BarTooltipItem('${mood['emoji']} ${rod.toY.toInt()} days',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold));
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  final mood = moodMeta[value.toInt()];
                  return SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(mood['emoji'], style: const TextStyle(fontSize: 22)),
                    ),
                  );
                },
              )),
            ),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            barGroups: moodMeta.asMap().entries.map((e) {
              final count = filteredData.where((d) => d['mood_level'] == e.value['value']).length;
              return BarChartGroupData(x: e.key, barRods: [
                BarChartRodData(toY: count.toDouble(), color: e.value['color'], width: 28, borderRadius: BorderRadius.circular(8))
              ]);
            }).toList(),
          )),
        ),
      ]),
    );
  }

  // ── Relaxation Corner ──
  Widget _buildRelaxationCorner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.secondarySoft, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.spa, color: AppTheme.secondary, size: 20),
              ),
              const SizedBox(width: 10),
              const Text("Relaxation Corner",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            ],
          ),
          const SizedBox(height: 16),

          // ── Daily Quote (enlarged, cheerful) ──
          _relaxQuoteCard(),
          const SizedBox(height: 12),

          // ── Self Care Tip (enlarged, cheerful) ──
          _relaxTipCard(),

          // ── Calming exercises for moderate/critical ──
          if (isModeratOrCritical) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Container(width: 3, height: 16,
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text("CALMING EXERCISES",
                    style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            const _BreathingExerciseWidget(),
            const SizedBox(height: 12),
            const _ButterflyHugWidget(),
            const SizedBox(height: 12),
            const _GroundingExerciseWidget(),
          ],
        ],
      ),
    );
  }

  // ── Quote card with mascot, dialog bubble and music ──
  Widget _relaxQuoteCard() {
    final threshold = effectiveThreshold;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('relaxationContent')
          .where('type', isEqualTo: 'quote')
          .where('risk_level', whereIn: ['all', threshold.toLowerCase()])
          .snapshots(),
      builder: (context, snapshot) {
        String quote = 'You don\'t have to be positive all the time. It\'s perfectly okay to feel what you feel.';
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = snapshot.data!.docs;
          final index = DateTime.now().day % docs.length;
          quote = docs[index]['description'];
        }
        return _MascotQuoteCard(quote: quote);
      },
    );
  }

  // ── Self-Care Tip card — live from Firestore ──
  Widget _relaxTipCard() {
    final threshold = effectiveThreshold;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('relaxationContent')
          .where('type', isEqualTo: 'tip')
          .where('risk_level', whereIn: ['all', threshold.toLowerCase()])
          .snapshots(),
      builder: (context, snapshot) {
        String tip = 'Drink a glass of water and take 3 deep breaths. Small steps matter.';
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = snapshot.data!.docs;
          final index = (DateTime.now().day + 1) % docs.length;
          tip = docs[index]['description'];
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppTheme.primary.withOpacity(0.12), AppTheme.primary.withOpacity(0.04)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Text("🌿", style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 10),
                  Text("SELF-CARE TIP",
                      style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 14),
              Text(tip,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textDark, height: 1.5)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text("💚 Try this today!",
                    style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }
} // end of _MoodTrackingPageState

// ── Mascot Quote Card with floating character + dialog + music ──
class _MascotQuoteCard extends StatefulWidget {
  final String quote;
  const _MascotQuoteCard({required this.quote});

  @override
  State<_MascotQuoteCard> createState() => _MascotQuoteCardState();
}

class _MascotQuoteCardState extends State<_MascotQuoteCard>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _blinkController;
  late Animation<double> _floatAnim;
  late Animation<double> _blinkAnim;

  bool _isPlaying = false;
  bool _initialized = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _blinkAnim = Tween<double>(begin: 1, end: 0.1).animate(_blinkController);
    _scheduleBlink();
    setState(() => _initialized = true);
  }

  void _scheduleBlink() {
    Future.delayed(Duration(milliseconds: 2500 + math.Random().nextInt(3000)), () async {
      if (!mounted) return;
      await _blinkController.forward();
      if (!mounted) return;
      await _blinkController.reverse();
      _scheduleBlink();
    });
  }

  @override
  void dispose() {
    _floatController.dispose();
    _blinkController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleMusic() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    } else {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('audio/calm_piano.mp3'));
        setState(() => _isPlaying = true);
        // Auto stop after 30 seconds
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted && _isPlaying) {
            _audioPlayer.stop();
            setState(() => _isPlaying = false);
          }
        });
      } catch (e) {
        print("Error playing music: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppTheme.secondary.withOpacity(0.15), AppTheme.secondary.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.secondary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text("💭", style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 8),
              Text("DAILY QUOTE",
                  style: TextStyle(fontSize: 11, letterSpacing: 1.5,
                      color: AppTheme.secondary, fontWeight: FontWeight.w700)),
            ],
          ),

          const SizedBox(height: 12),

          // ── Dialog bubble above mascot ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '"${widget.quote}"',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textDark,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Floating mascot centered ──
          AnimatedBuilder(
            animation: Listenable.merge([_floatAnim, _blinkAnim]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatAnim.value),
                child: CustomPaint(
                  size: const Size(80, 80),
                  painter: _MiniHeartPainter(blinkValue: _blinkAnim.value),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // ── Play Music button below mascot ──
          GestureDetector(
            onTap: _toggleMusic,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _isPlaying
                    ? AppTheme.secondary.withOpacity(0.15)
                    : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: _isPlaying
                      ? AppTheme.secondary
                      : AppTheme.secondary.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPlaying ? Icons.stop_rounded : Icons.music_note_rounded,
                    size: 16,
                    color: AppTheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isPlaying ? "Stop Music" : "Play Music 🎵",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// BREATHING EXERCISE WIDGET
// ═══════════════════════════════════════════════
class _BreathingExerciseWidget extends StatefulWidget {
  const _BreathingExerciseWidget();

  @override
  State<_BreathingExerciseWidget> createState() => _BreathingExerciseWidgetState();
}

class _BreathingExerciseWidgetState extends State<_BreathingExerciseWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isAnimating = false;

  final List<Map<String, dynamic>> phases = [
    {'label': 'Breathe In', 'duration': 4, 'expand': true},
    {'label': 'Hold', 'duration': 7, 'expand': false},
    {'label': 'Breathe Out', 'duration': 8, 'expand': false},
  ];

  int _currentPhase = 0;
  int _countdown = 4;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startBreathing() {
    setState(() { _isAnimating = true; _currentPhase = 0; _countdown = phases[0]['duration']; });
    _runPhase(0);
  }

  void _stopBreathing() {
    _controller.stop();
    setState(() => _isAnimating = false);
  }

  Future<void> _runPhase(int phaseIndex) async {
    if (!mounted || !_isAnimating) return;
    final phase = phases[phaseIndex];
    final duration = phase['duration'] as int;
    final expand = phase['expand'] as bool;
    setState(() { _currentPhase = phaseIndex; _countdown = duration; });
    _controller.duration = Duration(seconds: duration);
    if (expand) { _controller.forward(from: 0.0); }
    else if (phaseIndex == 2) { _controller.reverse(from: 1.0); }
    for (int i = duration; i > 0; i--) {
      if (!mounted || !_isAnimating) return;
      setState(() => _countdown = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted || !_isAnimating) return;
    _runPhase((phaseIndex + 1) % phases.length);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
          gradient: AppTheme.headerGradient, borderRadius: BorderRadius.all(Radius.circular(16))),
      child: Column(children: [
        const Row(children: [
          Icon(Icons.air, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text("Breathing Exercise", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 4),
        const Text("4-7-8 Calming Breath", style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 12),
        // Pulsing text animation - no overflow risk
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final scale = 0.85 + (_animation.value * 0.3);
            return Center(
              child: Transform.scale(
                scale: scale.clamp(0.85, 1.15),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15 + (_animation.value * 0.1)),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isAnimating) ...[
                        Text(
                          "$_countdown",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          phases[_currentPhase]['label'],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else
                        const Text(
                          "Ready",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        if (_isAnimating)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: phases.asMap().entries.map((e) {
            final isActive = e.key == _currentPhase;
            return Container(margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 24 : 8, height: 8,
                decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(4)));
          }).toList()),
        const SizedBox(height: 16),
        // Always show instructions regardless of animation state
        _breathStep("1", "Breathe in through nose for 4 seconds"),
        _breathStep("2", "Hold breath for 7 seconds"),
        _breathStep("3", "Exhale through mouth for 8 seconds"),
        _breathStep("4", "Repeat 4 times 🌬️"),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _isAnimating ? _stopBreathing : _startBreathing,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
            child: Text(_isAnimating ? "Stop" : "Start Exercise",
                style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ]),
      ), // Container
    ); // ClipRRect
  }

  Widget _breathStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("$num. ", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════
// BUTTERFLY HUG WIDGET
// ═══════════════════════════════════════════════
class _ButterflyHugWidget extends StatefulWidget {
  const _ButterflyHugWidget();

  @override
  State<_ButterflyHugWidget> createState() => _ButterflyHugWidgetState();
}

class _ButterflyHugWidgetState extends State<_ButterflyHugWidget>
    with TickerProviderStateMixin {
  bool _isActive = false;
  bool _tapLeft = true;
  bool _animatingLeft = false; // tracks which wing is currently moving
  int _totalTaps = 0;
  static const int _totalRounds = 12;
  final FlutterTts _tts = FlutterTts();

  late AnimationController _leftWingController;
  late AnimationController _rightWingController;
  late Animation<double> _leftWingAnim;
  late Animation<double> _rightWingAnim;

  @override
  void initState() {
    super.initState();
    _leftWingController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _rightWingController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _leftWingAnim = Tween<double>(begin: 0.0, end: -0.3).animate(
        CurvedAnimation(parent: _leftWingController, curve: Curves.easeInOut));
    _rightWingAnim = Tween<double>(begin: 0.0, end: 0.3).animate(
        CurvedAnimation(parent: _rightWingController, curve: Curves.easeInOut));
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.42); // slower, calmer pace
    await _tts.setPitch(0.95);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      // Fail silently if TTS unavailable on device
    }
  }

  @override
  void dispose() {
    _leftWingController.dispose();
    _rightWingController.dispose();
    _tts.stop();
    super.dispose();
  }

  void _start() {
    setState(() { _isActive = true; _tapLeft = true; _totalTaps = 0; });
    _speak("Cross your arms over your chest like butterfly wings. Hook your thumbs together. Now breathe slowly.");
    Future.delayed(const Duration(milliseconds: 7000), () {
      if (mounted && _isActive) _runTap();
    });
  }

  void _stop() {
    _leftWingController.reset();
    _rightWingController.reset();
    _tts.stop();
    setState(() { _isActive = false; _tapLeft = true; _totalTaps = 0; _animatingLeft = false; });
  }

  Future<void> _runTap() async {
    if (!mounted || !_isActive) return;

    if (_totalTaps >= _totalRounds) {
      if (mounted) {
        setState(() { _isActive = false; _totalTaps = 0; });
        _speak("Well done. Take a moment to notice how you feel.");
        _showDoneMessage();
      }
      return;
    }

    // Capture current side BEFORE any state change
    final isLeft = _tapLeft;

    // Update UI text/progress immediately
    setState(() { _tapLeft = !_tapLeft; _totalTaps++; });

    // Speak first
    if (isLeft) {
      _speak("Tap left shoulder");
    } else {
      _speak("Tap right shoulder");
    }

    // Small delay so voice starts before animation
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || !_isActive) return;

    // Set which side is animating so TAP text syncs with wing
    setState(() => _animatingLeft = isLeft);

    // Arms NOT crossed for display — left wing = left hand, right wing = right hand
    if (isLeft) {
      _leftWingController.forward(from: 0.0).then((_) {
        if (mounted) {
          _leftWingController.reverse().then((_) {
            if (mounted) setState(() => _animatingLeft = false);
          });
        }
      });
    } else {
      _rightWingController.forward(from: 0.0).then((_) {
        if (mounted) {
          _rightWingController.reverse().then((_) {
            if (mounted) setState(() => _animatingLeft = false);
          });
        }
      });
    }

    // Wait before next cycle
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted && _isActive) _runTap();
  }

  void _showDoneMessage() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("🦋", style: TextStyle(fontSize: 60)),
          const SizedBox(height: 12),
          const Text("Well done!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text("You've completed your butterfly hug. Take a moment to notice how you feel. 💙",
              style: TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4), textAlign: TextAlign.center),
        ]),
        actions: [
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(12)),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
                child: const Text("Thank you 🌿", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xFF9B59B6).withOpacity(0.8), const Color(0xFF6C3483)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        const Row(children: [
          Text("🦋", style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text("Butterfly Hug", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 4),
        const Text("A gentle self-soothing technique", style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 20),

        // Butterfly animation - single butterfly with animated wings
        AnimatedBuilder(
          animation: Listenable.merge([_leftWingAnim, _rightWingAnim]),
          builder: (context, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final wingW = (constraints.maxWidth / 2 - 14).clamp(60.0, 110.0);
                return Column(
                  children: [
                    SizedBox(
                      height: 130,
                      width: constraints.maxWidth,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left wing
                          Transform(
                            alignment: Alignment.centerRight,
                            transform: Matrix4.identity()..rotateY(_leftWingAnim.value),
                            child: CustomPaint(
                              size: Size(wingW, 110),
                              painter: _ButterflyWingPainter(isLeft: true),
                            ),
                          ),
                          // Body
                          Container(
                            width: 12,
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A2C0A),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          // Right wing
                          Transform(
                            alignment: Alignment.centerLeft,
                            transform: Matrix4.identity()..rotateY(_rightWingAnim.value),
                            child: CustomPaint(
                              size: Size(wingW, 110),
                              painter: _ButterflyWingPainter(isLeft: false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // TAP indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedOpacity(
                          opacity: _isActive && _animatingLeft ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: const Text("👈 TAP",
                                style: TextStyle(color: Color(0xFF6C3483), fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 50),
                        AnimatedOpacity(
                          opacity: _isActive && !_animatingLeft ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: const Text("TAP 👉",
                                style: TextStyle(color: Color(0xFF6C3483), fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),

        const SizedBox(height: 16),

        // Always show instructions
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            _hugStep("1", "Cross your arms over your chest 🤗"),
            _hugStep("2", "Tap your left shoulder, then right"),
            _hugStep("3", "Breathe slowly and think of a calm place 🌅"),
            _hugStep("4", "Continue tapping gently, left then right"),
          ]),
        ),
        const SizedBox(height: 12),

        if (_isActive) ...[
          Text(!_tapLeft ? "← Tap left shoulder" : "Tap right shoulder →",
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Breathe slowly... ${_totalRounds - _totalTaps} taps remaining",
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _totalTaps / _totalRounds,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
        ],

        GestureDetector(
          onTap: _isActive ? _stop : _start,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
            child: Text(_isActive ? "Stop" : "Start Butterfly Hug",
                style: const TextStyle(color: Color(0xFF6C3483), fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  Widget _hugStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("$num. ", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════
// 5-4-3-2-1 GROUNDING EXERCISE WIDGET
// ═══════════════════════════════════════════════
class _GroundingExerciseWidget extends StatefulWidget {
  const _GroundingExerciseWidget();

  @override
  State<_GroundingExerciseWidget> createState() => _GroundingExerciseWidgetState();
}

class _GroundingExerciseWidgetState extends State<_GroundingExerciseWidget> {
  bool _isActive = false;
  int _currentStep = 0;
  bool _canProceed = false;

  final List<Map<String, String>> _steps = [
    {
      'emoji': '👀',
      'number': '5',
      'sense': 'SEE',
      'prompt': 'Look around you. Notice 5 things you can see.',
      'hint': 'Or simply notice the colours and shapes around you.',
    },
    {
      'emoji': '✋',
      'number': '4',
      'sense': 'TOUCH',
      'prompt': 'Notice 4 things you can touch.',
      'hint': 'Your phone, your clothes, the surface you\'re sitting on.',
    },
    {
      'emoji': '👂',
      'number': '3',
      'sense': 'HEAR',
      'prompt': 'Notice 3 things you can hear.',
      'hint': 'Even silence counts — notice the quiet, or your own breathing.',
    },
    {
      'emoji': '👃',
      'number': '2',
      'sense': 'SMELL',
      'prompt': 'Notice 2 things you can smell.',
      'hint': 'If you can\'t smell anything, just take 2 slow breaths instead.',
    },
    {
      'emoji': '👅',
      'number': '1',
      'sense': 'TASTE',
      'prompt': 'Notice 1 thing you can taste.',
      'hint': 'Or simply notice the feeling inside your mouth right now.',
    },
  ];

  void _start() {
    setState(() {
      _isActive = true;
      _currentStep = 0;
      _canProceed = false;
    });
    _startStepTimer();
  }

  void _stop() {
    setState(() {
      _isActive = false;
      _currentStep = 0;
      _canProceed = false;
    });
  }

  Future<void> _startStepTimer() async {
    setState(() => _canProceed = false);
    await Future.delayed(const Duration(seconds: 12));
    if (mounted && _isActive) {
      setState(() => _canProceed = true);
    }
  }

  void _nextStep() {
    if (!_canProceed) return;

    if (_currentStep >= _steps.length - 1) {
      // Finished all steps
      setState(() {
        _isActive = false;
        _currentStep = 0;
        _canProceed = false;
      });
      _showDoneMessage();
      return;
    }

    setState(() {
      _currentStep++;
      _canProceed = false;
    });
    _startStepTimer();
  }

  void _showDoneMessage() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("🌿", style: TextStyle(fontSize: 60)),
          const SizedBox(height: 12),
          const Text("Well done!",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            "You're here, you're safe. Take a moment to notice how you feel. 💙",
            style: TextStyle(fontSize: 13, color: AppTheme.textGrey, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ]),
        actions: [
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(12)),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text("Thank you 🌿", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = _isActive ? _steps[_currentStep] : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF52B788).withOpacity(0.85), const Color(0xFF2D6A4F)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Row(children: [
            Text("🌿", style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text("5-4-3-2-1 Grounding", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          const Text("A gentle way to feel present and calm", style: TextStyle(color: Colors.white70, fontSize: 12)),

          const SizedBox(height: 20),

          // Always show steps list
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: _steps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${s['emoji']} ", style: const TextStyle(fontSize: 14)),
                    Expanded(
                      child: Text(
                        "${s['number']} things you can ${s['sense']!.toLowerCase()}",
                        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 16),

          if (_isActive && step != null) ...[
            // Big number + emoji circle
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
                border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(step['emoji']!, style: const TextStyle(fontSize: 34)),
                  Text(step['number']!, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Text(
              step['prompt']!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              step['hint']!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4, fontStyle: FontStyle.italic),
            ),

            const SizedBox(height: 16),

            // Progress dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (i) {
                final isActive = i == _currentStep;
                final isDone = i < _currentStep;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isDone || isActive ? Colors.white : Colors.white.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 18),
          ],

          // Start/Next/Stop button
          GestureDetector(
            onTap: !_isActive
                ? _start
                : (_canProceed ? _nextStep : null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: (!_isActive || _canProceed) ? Colors.white : Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                !_isActive
                    ? "Start Grounding"
                    : (_canProceed
                        ? (_currentStep >= _steps.length - 1 ? "Finish" : "Next")
                        : "Take your time..."),
                style: const TextStyle(color: Color(0xFF2D6A4F), fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
              ),
            ),
          ),

          if (_isActive) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined, size: 16, color: Colors.white70),
              label: const Text(
                "Stop",
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// CALM SPACE WIDGET — interactive heart mascot
// ═══════════════════════════════════════════════

class _MiniHeartPainter extends CustomPainter {
  final double blinkValue;
  _MiniHeartPainter({required this.blinkValue});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bodyPaint = Paint()..color = const Color(0xFFFF8FA3);
    final darkAccent = Paint()..color = Colors.black.withOpacity(0.75);
    final cheekPaint = Paint()..color = Colors.white.withOpacity(0.35);

    final path = Path();
    final cx = w / 2;
    final topY = h * 0.28;
    final lobeR = w * 0.28;

    path.moveTo(cx, h * 0.92);
    path.cubicTo(cx - lobeR * 2.1, h * 0.62, cx - lobeR * 2.0, topY - lobeR * 0.3, cx - lobeR * 0.15, topY);
    path.cubicTo(cx - lobeR * 0.15, topY - lobeR * 0.05, cx, topY - lobeR * 0.05, cx, topY);
    path.cubicTo(cx, topY - lobeR * 0.05, cx + lobeR * 0.15, topY - lobeR * 0.05, cx + lobeR * 0.15, topY);
    path.cubicTo(cx + lobeR * 2.0, topY - lobeR * 0.3, cx + lobeR * 2.1, h * 0.62, cx, h * 0.92);
    path.close();

    canvas.drawShadow(path, Colors.black.withOpacity(0.15), 4, false);
    canvas.drawPath(path, bodyPaint);

    canvas.drawCircle(Offset(cx - w * 0.22, h * 0.56), w * 0.07, cheekPaint);
    canvas.drawCircle(Offset(cx + w * 0.22, h * 0.56), w * 0.07, cheekPaint);

    final eyeY = h * 0.46;
    final eyeOffsetX = w * 0.14;
    final eyeHeight = (h * 0.10 * blinkValue).clamp(1.5, h * 0.10);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx - eyeOffsetX, eyeY), width: w * 0.07, height: eyeHeight),
        Radius.circular(w * 0.035),
      ),
      darkAccent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + eyeOffsetX, eyeY), width: w * 0.07, height: eyeHeight),
        Radius.circular(w * 0.035),
      ),
      darkAccent,
    );

    final smilePath = Path();
    final smileY = h * 0.58;
    smilePath.moveTo(cx - w * 0.10, smileY);
    smilePath.quadraticBezierTo(cx, smileY + h * 0.07, cx + w * 0.10, smileY);
    canvas.drawPath(
      smilePath,
      Paint()
        ..color = Colors.black.withOpacity(0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025
        ..strokeCap = StrokeCap.round,
    );

    final armPaint = Paint()..color = const Color(0xFFFF8FA3);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - w * 0.42, h * 0.7), width: w * 0.18, height: h * 0.12), armPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + w * 0.42, h * 0.7), width: w * 0.18, height: h * 0.12), armPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniHeartPainter oldDelegate) => oldDelegate.blinkValue != blinkValue;
}


// ── Butterfly Wing Painter ──
class _ButterflyWingPainter extends CustomPainter {
  final bool isLeft;
  _ButterflyWingPainter({required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Upper wing paint - orange gradient
    final upperPaint = Paint()
      ..shader = LinearGradient(
        begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
        end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
        colors: [const Color(0xFFFF8C00), const Color(0xFFFF5500)],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.6));

    // Lower wing paint - darker orange
    final lowerPaint = Paint()
      ..shader = LinearGradient(
        begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
        end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
        colors: [const Color(0xFFFF6B00), const Color(0xFFCC4400)],
      ).createShader(Rect.fromLTWH(0, h * 0.5, w, h * 0.5));

    // Upper wing path
    final upperPath = Path();
    if (isLeft) {
      upperPath.moveTo(w * 0.95, h * 0.42);
      upperPath.cubicTo(w, 0, w * 0.1, 0, 0, h * 0.22);
      upperPath.cubicTo(0, h * 0.46, w * 0.5, h * 0.52, w * 0.95, h * 0.42);
    } else {
      upperPath.moveTo(w * 0.05, h * 0.42);
      upperPath.cubicTo(0, 0, w * 0.9, 0, w, h * 0.22);
      upperPath.cubicTo(w, h * 0.46, w * 0.5, h * 0.52, w * 0.05, h * 0.42);
    }
    upperPath.close();
    canvas.drawPath(upperPath, upperPaint);

    // Lower wing path
    final lowerPath = Path();
    if (isLeft) {
      lowerPath.moveTo(w * 0.95, h * 0.48);
      lowerPath.cubicTo(w * 0.8, h * 0.6, w * 0.2, h * 0.55, 0, h * 0.72);
      lowerPath.cubicTo(0, h * 1.0, w * 0.7, h * 0.95, w * 0.95, h * 0.48);
    } else {
      lowerPath.moveTo(w * 0.05, h * 0.48);
      lowerPath.cubicTo(w * 0.2, h * 0.6, w * 0.8, h * 0.55, w, h * 0.72);
      lowerPath.cubicTo(w, h * 1.0, w * 0.3, h * 0.95, w * 0.05, h * 0.48);
    }
    lowerPath.close();
    canvas.drawPath(lowerPath, lowerPaint);

    // Black wing borders
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(upperPath, borderPaint);
    canvas.drawPath(lowerPath, borderPaint);

    // White spots on wings
    final spotPaint = Paint()..color = Colors.white.withOpacity(0.7);
    if (isLeft) {
      canvas.drawCircle(Offset(w * 0.25, h * 0.18), 4, spotPaint);
      canvas.drawCircle(Offset(w * 0.45, h * 0.28), 3, spotPaint);
      canvas.drawCircle(Offset(w * 0.2, h * 0.65), 3.5, spotPaint);
    } else {
      canvas.drawCircle(Offset(w * 0.75, h * 0.18), 4, spotPaint);
      canvas.drawCircle(Offset(w * 0.55, h * 0.28), 3, spotPaint);
      canvas.drawCircle(Offset(w * 0.8, h * 0.65), 3.5, spotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ButterflyWingPainter old) => false;
}