import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';

class StressAssessmentPage extends StatefulWidget {
  const StressAssessmentPage({super.key});

  @override
  State<StressAssessmentPage> createState() => _StressAssessmentPageState();
}

class _StressAssessmentPageState extends State<StressAssessmentPage> {
  late List<int> answers;
  bool _done = false;
  bool _isLoading = false;
  bool _alreadyAssessedThisWeek = false;
  Map<String, dynamic>? _latestAssessment;

  final List<Map<String, dynamic>> questions = [
    {'text': 'I couldn\'t seem to experience any positive feeling at all.', 'category': 'Depression'},
    {'text': 'I found it difficult to work up the initiative to do things.', 'category': 'Depression'},
    {'text': 'I felt that I had nothing to look forward to.', 'category': 'Depression'},
    {'text': 'I felt down-hearted and blue.', 'category': 'Depression'},
    {'text': 'I was unable to become enthusiastic about anything.', 'category': 'Depression'},
    {'text': 'I felt I wasn\'t worth much as a person.', 'category': 'Depression'},
    {'text': 'I felt that life was meaningless.', 'category': 'Depression'},
    {'text': 'I was aware of dryness of my mouth.', 'category': 'Anxiety'},
    {'text': 'I experienced breathing difficulty (e.g., excessively rapid breathing, breathlessness in the absence of physical exertion).', 'category': 'Anxiety'},
    {'text': 'I experienced trembling (e.g., in the hands).', 'category': 'Anxiety'},
    {'text': 'I was worried about situations in which I might panic and make a fool of myself.', 'category': 'Anxiety'},
    {'text': 'I felt I was close to panic.', 'category': 'Anxiety'},
    {'text': 'I was aware of the action of my heart in the absence of physical exertion (e.g., sense of heart rate increase, heart missing a beat).', 'category': 'Anxiety'},
    {'text': 'I felt scared without any good reason.', 'category': 'Anxiety'},
    {'text': 'I found it hard to wind down.', 'category': 'Stress'},
    {'text': 'I tended to over-react to situations.', 'category': 'Stress'},
    {'text': 'I felt that I was using a lot of nervous energy.', 'category': 'Stress'},
    {'text': 'I found myself getting agitated.', 'category': 'Stress'},
    {'text': 'I found it difficult to relax.', 'category': 'Stress'},
    {'text': 'I was intolerant of anything that kept me from getting on with what I was doing.', 'category': 'Stress'},
    {'text': 'I felt that I was rather touchy.', 'category': 'Stress'},
  ];

  final List<Map<String, dynamic>> options = [
    {'v': 0, 'label': 'Never'},
    {'v': 1, 'label': 'Sometimes'},
    {'v': 2, 'label': 'Often'},
    {'v': 3, 'label': 'Almost Always'},
  ];

  @override
  void initState() {
    super.initState();
    answers = List.filled(questions.length, -1);
    _checkThisWeekAssessment();
  }

  int get depressionRaw => answers.sublist(0, 7).fold(0, (s, a) => s + (a < 0 ? 0 : a));
  int get anxietyRaw => answers.sublist(7, 14).fold(0, (s, a) => s + (a < 0 ? 0 : a));
  int get stressRaw => answers.sublist(14, 21).fold(0, (s, a) => s + (a < 0 ? 0 : a));
  int get depressionScore => depressionRaw * 2;
  int get anxietyScore => anxietyRaw * 2;
  int get stressScore => stressRaw * 2;

  Map<String, dynamic> interpretDepression(int score) {
    if (score <= 9) return {'label': 'Normal', 'color': const Color(0xFF4DB6AC), 'bg': const Color(0xFFE0F7F6)};
    if (score <= 13) return {'label': 'Mild', 'color': const Color(0xFF81C784), 'bg': const Color(0xFFE8F5E9)};
    if (score <= 20) return {'label': 'Moderate', 'color': const Color(0xFFFFB74D), 'bg': const Color(0xFFFFF3E0)};
    if (score <= 27) return {'label': 'Severe', 'color': const Color(0xFFFF7043), 'bg': const Color(0xFFFBE9E7)};
    return {'label': 'Extremely Severe', 'color': const Color(0xFFE57373), 'bg': const Color(0xFFFFEBEE)};
  }

  Map<String, dynamic> interpretAnxiety(int score) {
    if (score <= 7) return {'label': 'Normal', 'color': const Color(0xFF4DB6AC), 'bg': const Color(0xFFE0F7F6)};
    if (score <= 9) return {'label': 'Mild', 'color': const Color(0xFF81C784), 'bg': const Color(0xFFE8F5E9)};
    if (score <= 14) return {'label': 'Moderate', 'color': const Color(0xFFFFB74D), 'bg': const Color(0xFFFFF3E0)};
    if (score <= 19) return {'label': 'Severe', 'color': const Color(0xFFFF7043), 'bg': const Color(0xFFFBE9E7)};
    return {'label': 'Extremely Severe', 'color': const Color(0xFFE57373), 'bg': const Color(0xFFFFEBEE)};
  }

  Map<String, dynamic> interpretStress(int score) {
    if (score <= 14) return {'label': 'Normal', 'color': const Color(0xFF4DB6AC), 'bg': const Color(0xFFE0F7F6)};
    if (score <= 18) return {'label': 'Mild', 'color': const Color(0xFF81C784), 'bg': const Color(0xFFE8F5E9)};
    if (score <= 25) return {'label': 'Moderate', 'color': const Color(0xFFFFB74D), 'bg': const Color(0xFFFFF3E0)};
    if (score <= 33) return {'label': 'Severe', 'color': const Color(0xFFFF7043), 'bg': const Color(0xFFFBE9E7)};
    return {'label': 'Extremely Severe', 'color': const Color(0xFFE57373), 'bg': const Color(0xFFFFEBEE)};
  }

  String get overallLevel {
    final dep = interpretDepression(depressionScore)['label'];
    final anx = interpretAnxiety(anxietyScore)['label'];
    final str = interpretStress(stressScore)['label'];
    final levels = [dep, anx, str];
    if (levels.contains('Extremely Severe') || levels.contains('Severe')) return 'High';
    if (levels.contains('Moderate')) return 'Moderate';
    if (levels.contains('Mild')) return 'Mild';
    return 'Low';
  }

  String _getCurrentWeek() {
    final now = DateTime.now();
    final firstDayOfYear = DateTime(now.year, 1, 1);
    final weekNumber = ((now.difference(firstDayOfYear).inDays + firstDayOfYear.weekday) / 7).ceil();
    return "${now.year}-W$weekNumber";
  }

  Future<void> _checkThisWeekAssessment() async {
    try {
      setState(() => _isLoading = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final studentQuery = await FirebaseFirestore.instance
          .collection('students').where('uid', isEqualTo: user.uid).limit(1).get();
      if (studentQuery.docs.isEmpty) return;
      final studId = studentQuery.docs.first.id;
      final currentWeek = _getCurrentWeek();
      final assessmentQuery = await FirebaseFirestore.instance
          .collection('stressAssessments')
          .where('stud_id', isEqualTo: studId)
          .where('week', isEqualTo: currentWeek)
          .limit(1).get();
      if (assessmentQuery.docs.isNotEmpty) {
        setState(() {
          _alreadyAssessedThisWeek = true;
          _latestAssessment = assessmentQuery.docs.first.data();
        });
      }
    } catch (e) {
      print("Error checking assessment: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAssessment() async {
    try {
      setState(() => _isLoading = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final studentQuery = await FirebaseFirestore.instance
          .collection('students').where('uid', isEqualTo: user.uid).limit(1).get();
      if (studentQuery.docs.isEmpty) return;
      final studId = studentQuery.docs.first.id;
      final currentWeek = _getCurrentWeek();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await FirebaseFirestore.instance.collection('stressAssessments').add({
        'stud_id': studId,
        'depression_score': depressionScore,
        'depression_level': interpretDepression(depressionScore)['label'],
        'anxiety_score': anxietyScore,
        'anxiety_level': interpretAnxiety(anxietyScore)['label'],
        'stress_score': stressScore,
        'stress_level': interpretStress(stressScore)['label'],
        'overall_level': overallLevel,
        'week': currentWeek,
        'assessment_date': today,
        'created_at': FieldValue.serverTimestamp(),
      });
      setState(() { _done = true; _isLoading = false; });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to save: $e")));
    }
  }

  bool get allAnswered => answers.every((a) => a >= 0);

  Widget _optionButton(Map<String, dynamic> o, int questionIndex) {
    final isSelected = answers[questionIndex] == o['v'];
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => answers[questionIndex] = o['v']),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primarySoft : const Color(0xFFF8F9FA),
            border: Border.all(
              color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(o['label'],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppTheme.primary : AppTheme.textGrey,
                )),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_alreadyAssessedThisWeek && _latestAssessment != null) return _buildAlreadyAssessedScreen(context);
    if (_done) return _buildResultScreen(context);
    return _buildQuestionScreen(context);
  }

  Widget _buildAlreadyAssessedScreen(BuildContext context) {
    final depScore = _latestAssessment!['depression_score'] ?? 0;
    final anxScore = _latestAssessment!['anxiety_score'] ?? 0;
    final strScore = _latestAssessment!['stress_score'] ?? 0;
    final depLevel = _latestAssessment!['depression_level'] ?? '-';
    final anxLevel = _latestAssessment!['anxiety_level'] ?? '-';
    final strLevel = _latestAssessment!['stress_level'] ?? '-';
    final date = _latestAssessment!['assessment_date'] ?? '-';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader("DASS-21 Assessment", showBack: true),
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
                              "You have completed this week's DASS-21 assessment.",
                              style: TextStyle(color: AppTheme.secondary, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("THIS WEEK'S DASS-21 RESULTS",
                              style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text("Assessed on $date", style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                          const SizedBox(height: 16),
                          _scoreRow("Depression", depScore, depLevel, interpretDepression(depScore)),
                          const SizedBox(height: 10),
                          _scoreRow("Anxiety", anxScore, anxLevel, interpretAnxiety(anxScore)),
                          const SizedBox(height: 10),
                          _scoreRow("Stress", strScore, strLevel, interpretStress(strScore)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
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
                        child: const Text("Back to Dashboard", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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

  // ── Result Screen — Overall Level REMOVED ──
  Widget _buildResultScreen(BuildContext context) {
    final depInterpret = interpretDepression(depressionScore);
    final anxInterpret = interpretAnxiety(anxietyScore);
    final strInterpret = interpretStress(stressScore);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader("Assessment Complete", showBack: false),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("DASS-21 RESULTS",
                              style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          // ── Only show 3 subscales, NO overall level ──
                          _scoreRow("Depression", depressionScore, depInterpret['label'], depInterpret),
                          const SizedBox(height: 10),
                          _scoreRow("Anxiety", anxietyScore, anxInterpret['label'], anxInterpret),
                          const SizedBox(height: 10),
                          _scoreRow("Stress", stressScore, strInterpret['label'], strInterpret),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() { answers = List.filled(questions.length, -1); _done = false; });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: AppTheme.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text("Retake", style: TextStyle(color: AppTheme.primary)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(14)),
                            child: ElevatedButton(
                              onPressed: () => Navigator.pushReplacementNamed(context, '/dashboard'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text("Back to Home", style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildQuestionScreen(BuildContext context) {
    String? currentCategory;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Row(children: [
                        Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const Text("Stress Assessment", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text("Depression Anxiety and Stress Scale 21 (DASS-21)", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: answers.where((a) => a >= 0).length / questions.length,
                        minHeight: 6,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text("${answers.where((a) => a >= 0).length} / ${questions.length} answered",
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text("Please rate how much each statement applied to you over the past week.",
                                style: TextStyle(fontSize: 12, color: AppTheme.textDark)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(questions.length, (i) {
                      final question = questions[i];
                      final category = question['category'] as String;
                      final showCategoryHeader = category != currentCategory;
                      currentCategory = category;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showCategoryHeader) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(8)),
                              child: Text(category.toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${i + 1}. ${question['text']}",
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
                                  const SizedBox(height: 10),
                                  Row(children: [_optionButton(options[0], i), const SizedBox(width: 6), _optionButton(options[1], i)]),
                                  const SizedBox(height: 6),
                                  Row(children: [_optionButton(options[2], i), const SizedBox(width: 6), _optionButton(options[3], i)]),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: allAnswered ? AppTheme.buttonGradient : const LinearGradient(colors: [Color(0xFFB0BEC5), Color(0xFFB0BEC5)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton(
                        onPressed: allAnswered ? _submitAssessment : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          allAnswered ? "Submit Assessment" : "Answer all questions to continue (${answers.where((a) => a >= 0).length}/${questions.length})",
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
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

  Widget _buildHeader(String title, {required bool showBack}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: const BoxDecoration(
        gradient: AppTheme.headerGradient,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack)
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Row(children: [
                Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
              ]),
            ),
          if (showBack) const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text("Depression Anxiety and Stress Scale 21 (DASS-21)", style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _scoreRow(String category, int score, String level, Map<String, dynamic> interpret) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: interpret['bg'], borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                Text(level, style: TextStyle(fontSize: 12, color: interpret['color'], fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text("$score", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: interpret['color'])),
        ],
      ),
    );
  }
}