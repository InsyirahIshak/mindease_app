import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:mindease_app/services/notification_service.dart';

class PAStudentDetail extends StatefulWidget {
  const PAStudentDetail({super.key});

  @override
  State<PAStudentDetail> createState() => _PAStudentDetailState();
}

class _PAStudentDetailState extends State<PAStudentDetail> {
  String _selectedCounsellor = '';
  String _selectedCounsellorId = '';
  bool isLoading = true;
  String _filter = '7';
  String? _studId;
  List<Map<String, dynamic>> allMoodData = [];
  Map<String, dynamic>? latestStress;
  List<Map<String, dynamic>> counsellors = [];

  // Cache of counsellor names so we don't re-fetch on every stream tick
  final Map<String, String> _counsellorNameCache = {};

  final List<Map<String, dynamic>> moodMeta = [
    {'value': 1, 'emoji': '😞', 'label': 'Very Unpleasant', 'color': Color(0xFFE57373)},
    {'value': 2, 'emoji': '😕', 'label': 'Unpleasant', 'color': Color(0xFFFFB74D)},
    {'value': 3, 'emoji': '😐', 'label': 'Neutral', 'color': Color(0xFFFFD54F)},
    {'value': 4, 'emoji': '😊', 'label': 'Pleasant', 'color': Color(0xFF81C784)},
    {'value': 5, 'emoji': '😄', 'label': 'Very Pleasant', 'color': Color(0xFF4DB6AC)},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  List<Map<String, dynamic>> get filteredMoodData {
    if (_filter == '7') {
      return allMoodData.length > 7 ? allMoodData.sublist(allMoodData.length - 7) : allMoodData;
    }
    if (_filter == '30') {
      return allMoodData.length > 30 ? allMoodData.sublist(allMoodData.length - 30) : allMoodData;
    }
    return allMoodData;
  }

  List<Map<String, dynamic>> buildChartData(int days) {
    final now = DateTime.now();
    final moodMap = <String, int>{};
    for (final m in allMoodData) {
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

  List<Map<String, dynamic>> get chartData {
    if (_filter == '7') return buildChartData(7);
    if (_filter == '30') return buildChartData(30);
    if (allMoodData.isEmpty) return [];
    final first = DateTime.parse(allMoodData.first['log_date']);
    final days = DateTime.now().difference(first).inDays + 1;
    return buildChartData(days);
  }

  double get average {
    if (filteredMoodData.isEmpty) return 0;
    return filteredMoodData.fold(0.0, (s, m) => s + ((m['mood_level'] as int?) ?? 3)) / filteredMoodData.length;
  }

  // ── One-time loads: mood history, stress, counsellor list ──
  // (Analysis + referral are now handled live via StreamBuilder in build())
  Future<void> _loadData() async {
    final student = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (student == null) return;

    final studId = student['uitm_id'] as String;
    _studId = studId;

    try {
      final moodQuery = await FirebaseFirestore.instance
          .collection('moodLogs')
          .where('stud_id', isEqualTo: studId)
          .orderBy('log_date', descending: false)
          .get();

      setState(() {
        allMoodData = moodQuery.docs.map((d) => d.data()).toList();
      });

      final stressQuery = await FirebaseFirestore.instance
          .collection('stressAssessments')
          .where('stud_id', isEqualTo: studId)
          .orderBy('assessment_date', descending: true)
          .limit(1)
          .get();

      if (stressQuery.docs.isNotEmpty) {
        setState(() => latestStress = stressQuery.docs.first.data());
      }

      final counsellorQuery = await FirebaseFirestore.instance.collection('counsellors').get();

      setState(() {
        counsellors = counsellorQuery.docs.map((d) {
          return {'id': d.id, 'name': d.data()['fullName'] ?? '-'};
        }).toList();
        // Prime the name cache too
        for (var c in counsellors) {
          _counsellorNameCache[c['id'] as String] = c['name'] as String;
        }
      });
    } catch (e) {
      print("Error loading student detail: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Resolve counsellor name, using cache first, falling back to a fetch ──
  Future<String> _resolveCounsellorName(String counsellorId) async {
    if (_counsellorNameCache.containsKey(counsellorId)) {
      return _counsellorNameCache[counsellorId]!;
    }
    final doc = await FirebaseFirestore.instance.collection('counsellors').doc(counsellorId).get();
    final name = doc.data()?['fullName'] as String? ?? counsellorId;
    _counsellorNameCache[counsellorId] = name;
    return name;
  }

  Map<String, dynamic> moodById(int value) =>
      moodMeta.firstWhere((m) => m['value'] == value, orElse: () => moodMeta[2]);

  // ── Threshold info derived from whatever analysis data is passed in ──
  Map<String, dynamic> thresholdInfoFor(Map<String, dynamic>? analysisData) {
    if (analysisData == null) {
      return {
        'label': 'No Data',
        'color': Colors.grey,
        'bg': const Color(0xFFF0F0F0),
        'emoji': '❓',
        'sentence': 'Student needs at least 7 mood logs for analysis.',
      };
    }

    final risk = analysisData['risk_level'] ?? 'Normal';
    switch (risk) {
      case 'Normal':
        return {'label': 'Normal', 'color': const Color(0xFF4DB6AC), 'bg': const Color(0xFFE0F7F6), 'emoji': '😊', 'sentence': 'Wellbeing within healthy range.'};
      case 'Moderate':
        return {'label': 'Moderate', 'color': const Color(0xFFFFB74D), 'bg': const Color(0xFFFFF3E0), 'emoji': '😐', 'sentence': 'Monitor closely; consider referral.'};
      case 'Critical':
        return {'label': 'Critical', 'color': const Color(0xFFE57373), 'bg': const Color(0xFFFFEBEE), 'emoji': '😟', 'sentence': 'Immediate referral recommended.'};
      default:
        return {'label': 'Normal', 'color': const Color(0xFF4DB6AC), 'bg': const Color(0xFFE0F7F6), 'emoji': '😊', 'sentence': 'Wellbeing within healthy range.'};
    }
  }

  Future<void> _downloadPDF(
    Map<String, dynamic> student,
    Map<String, dynamic>? liveAnalysis,
    Map<String, dynamic>? liveReferral,
    String? referredCounsellorName,
  ) async {
    final pdf = pw.Document();

    final filterLabel = _filter == '7'
        ? 'Last 7 Days'
        : _filter == '30'
            ? 'Last 30 Days'
            : 'All Time';

    final moodDataForPDF = filteredMoodData;

    final thresholdLabel = liveAnalysis == null ? 'No Data Yet' : liveAnalysis['risk_level'] ?? '-';

    final stressDate = latestStress?['assessment_date'] ?? '-';

    final referralStatus = liveReferral?['status'] ?? 'No referral';
    final referralDate = liveReferral?['referral_date'] ?? '-';
    final counsellorDisplay = referredCounsellorName ?? liveReferral?['counsellor_id'] ?? '-';

    final generatedDate = DateTime.now().toIso8601String().substring(0, 10);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#5B9BD5'),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('MindEase - Student Report',
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Generated on $generatedDate · Filter: $filterLabel',
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _pdfSection('STUDENT INFORMATION'),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(children: [
              _pdfRow('Name', student['name'] ?? '-'),
              _pdfDivider(),
              _pdfRow('UITM ID', student['uitm_id'] ?? '-'),
              _pdfDivider(),
              _pdfRow('Email', student['email'] ?? '-'),
              _pdfDivider(),
              _pdfRow('Phone', student['phone'] ?? '-'),
              _pdfDivider(),
              _pdfRow('Gender', student['gender'] ?? '-'),
              _pdfDivider(),
              _pdfRow('Semester', '${student['semester'] ?? '-'}'),
            ]),
          ),
          pw.SizedBox(height: 20),
          _pdfSection('MOOD SUMMARY ($filterLabel)'),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(children: [
              _pdfRow('Total Entries', '${moodDataForPDF.length} logs'),
              _pdfDivider(),
              _pdfRow('Weekly Level', thresholdLabel),
              _pdfDivider(),
              pw.SizedBox(height: 8),
              pw.Text('Mood Log Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0')),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F4F6F9')),
                    children: [
                      _pdfTableCell('Date', isHeader: true),
                      _pdfTableCell('Mood', isHeader: true),
                    ],
                  ),
                  ...moodDataForPDF.map((m) => pw.TableRow(children: [
                        _pdfTableCell(m['log_date'] ?? '-'),
                        _pdfTableCell(m['mood_label'] ?? '-'),
                      ])),
                ],
              ),
            ]),
          ),
          pw.SizedBox(height: 20),
          _pdfSection('WEEKLY ANALYSIS'),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: thresholdLabel == 'Normal'
                  ? PdfColor.fromHex('#E0F7F6')
                  : thresholdLabel == 'Moderate'
                      ? PdfColor.fromHex('#FFF3E0')
                      : thresholdLabel == 'Critical'
                          ? PdfColor.fromHex('#FFEBEE')
                          : PdfColor.fromHex('#F0F0F0'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(thresholdLabel,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                      color: thresholdLabel == 'Normal'
                          ? PdfColor.fromHex('#4DB6AC')
                          : thresholdLabel == 'Moderate'
                              ? PdfColor.fromHex('#FFB74D')
                              : thresholdLabel == 'Critical'
                                  ? PdfColor.fromHex('#E57373')
                                  : PdfColors.grey,
                    )),
                if (liveAnalysis != null && liveAnalysis['summary'] != null) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(liveAnalysis['summary'], style: const pw.TextStyle(fontSize: 11)),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          // ── Keep stress assessment on same page as its content ──
          pw.Container(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('STRESS ASSESSMENT',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#5B9BD5'),
                      letterSpacing: 1,
                    )),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(children: [
                    _pdfRow('Depression Level', latestStress?['depression_level'] ?? 'No assessment yet'),
                    _pdfDivider(),
                    _pdfRow('Anxiety Level', latestStress?['anxiety_level'] ?? 'No assessment yet'),
                    _pdfDivider(),
                    _pdfRow('Stress Level', latestStress?['stress_level'] ?? 'No assessment yet'),
                    _pdfDivider(),
                    _pdfRow('Assessment Date', stressDate),
                  ]),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _pdfSection('REFERRAL STATUS'),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(children: [
              _pdfRow('Status', referralStatus.toString().toUpperCase()),
              if (liveReferral != null) ...[
                _pdfDivider(),
                _pdfRow('Counsellor', counsellorDisplay),
                _pdfDivider(),
                _pdfRow('Referral Date', referralDate),
              ],
            ]),
          ),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text('MindEase - Mental Health Support System - $generatedDate',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: '${student['name']}_report_$generatedDate.pdf',
    );
  }

  pw.Widget _pdfSection(String title) {
    return pw.Text(title,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#5B9BD5'), letterSpacing: 1));
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  pw.Widget _pdfDivider() => pw.Divider(color: PdfColor.fromHex('#E2E8F0'), height: 1);

  pw.Widget _pdfTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: isHeader ? pw.FontWeight.bold : null)),
    );
  }

  Future<void> _submitReferral(Map<String, dynamic> student, String paUitmId) async {
    if (_selectedCounsellorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a counsellor")));
      return;
    }

    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);

      await FirebaseFirestore.instance.collection('referrals').add({
        'stud_id': student['uitm_id'],
        'pa_id': paUitmId,
        'counsellor_id': _selectedCounsellorId,
        'status': 'pending',
        'referral_date': today,
        'created_at': FieldValue.serverTimestamp(),
        'done': false,
      });

      // ── Notify counsellor via OneSignal ──
      try {
        final counsellorDoc = await FirebaseFirestore.instance
            .collection('counsellors')
            .doc(_selectedCounsellorId)
            .get();
        final playerId = counsellorDoc.data()?['playerId'];
        if (playerId != null) {
          await NotificationService.sendPushNotification(
            playerIds: [playerId],
            title: "New Referral 📋",
            body: "${student['name']} has been referred to you by their PA",
            type: 'new_referral',
            recipientUitmId: _selectedCounsellorId,
          );
        } else {
          print("Counsellor has no playerId — notification not sent");
        }
      } catch (e) {
        print("OneSignal notify counsellor error: $e");
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Referral sent to $_selectedCounsellor!"),
        backgroundColor: AppTheme.secondary,
      ));
      // No need to call _loadData() — referral status is now a live stream!
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final bool isFromCounsellor = student?['isFromCounsellor'] == true;

    if (student == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Student not found."),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Back")),
            ],
          ),
        ),
      );
    }

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('personalAdvisor')
              .where('uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
              .limit(1)
              .get(),
          builder: (context, paSnapshot) {
            String paUitmId = '';
            if (paSnapshot.hasData && paSnapshot.data!.docs.isNotEmpty) {
              paUitmId = paSnapshot.data!.docs.first.id;
            }

            // ── LIVE: mood analysis stream ──
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('moodAnalysis')
                  .where('stud_id', isEqualTo: _studId)
                  .orderBy('analysis_date', descending: true)
                  .limit(1)
                  .snapshots(),
              builder: (context, analysisSnapshot) {
                Map<String, dynamic>? liveAnalysis;
                if (analysisSnapshot.hasData && analysisSnapshot.data!.docs.isNotEmpty) {
                  liveAnalysis = analysisSnapshot.data!.docs.first.data() as Map<String, dynamic>;
                }
                final threshold = thresholdInfoFor(liveAnalysis);

                // ── LIVE: referral stream ──
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('referrals')
                      .where('stud_id', isEqualTo: _studId)
                      .orderBy('referral_date', descending: true)
                      .limit(1)
                      .snapshots(),
                  builder: (context, referralSnapshot) {
                    Map<String, dynamic>? liveReferral;
                    if (referralSnapshot.hasData && referralSnapshot.data!.docs.isNotEmpty) {
                      liveReferral = referralSnapshot.data!.docs.first.data() as Map<String, dynamic>;
                    }

                    final counsellorId = liveReferral?['counsellor_id'] as String?;

                    // ── Resolve counsellor name (async, but cached) ──
                    return FutureBuilder<String?>(
                      future: counsellorId != null ? _resolveCounsellorName(counsellorId) : Future.value(null),
                      builder: (context, nameSnapshot) {
                        final referredCounsellorName = nameSnapshot.data;

                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            children: [

                              // ── Header ──
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
                                      child: const Row(children: [
                                        Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                                        SizedBox(width: 4),
                                        Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
                                      ]),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 32,
                                          backgroundColor: Colors.white,
                                          child: Text(
                                            student['name'].toString().split(' ').map((w) => w[0]).take(2).join(),
                                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: threshold['color']),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(student['name'],
                                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                                    maxLines: 1),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: liveAnalysis == null ? Colors.grey : threshold['color'],
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  liveAnalysis == null ? "NO DATA YET" : threshold['label'].toString().toUpperCase(),
                                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [

                                    // ── Student Info ──
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("STUDENT INFORMATION",
                                              style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 12),
                                          _infoRow(Icons.badge, "UITM ID", student['uitm_id'] ?? '-'),
                                          const Divider(height: 20),
                                          _infoRow(Icons.phone, "Phone", student['phone'] ?? '-'),
                                          const Divider(height: 20),
                                          _infoRow(Icons.email, "Email", student['email'] ?? '-'),
                                          const Divider(height: 20),
                                          _infoRow(Icons.person, "Gender", student['gender'] ?? '-'),
                                          const Divider(height: 20),
                                          _infoRow(Icons.school, "Semester", "Semester ${student['semester'] ?? '-'}"),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    if (allMoodData.isEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                                        child: Column(
                                          children: [
                                            const Text("📊", style: TextStyle(fontSize: 36)),
                                            const SizedBox(height: 8),
                                            const Text("No mood logs yet",
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark)),
                                            const SizedBox(height: 4),
                                            Text("Mood chart and analysis will appear after student starts logging.",
                                                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
                                          ],
                                        ),
                                      ),

                                    if (allMoodData.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text("MOOD CHART",
                                                style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 12),
                                            Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(12)),
                                              child: Row(children: [
                                                _filterTab('7', '7 Days'),
                                                _filterTab('30', '30 Days'),
                                                _filterTab('all', 'All Time'),
                                              ]),
                                            ),
                                            const SizedBox(height: 12),
                                            Text("${filteredMoodData.length} mood entries logged",
                                                style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                                            const SizedBox(height: 12),
                                            Builder(builder: (context) {
                                              final data = chartData;
                                              final spots = <FlSpot>[];
                                              for (int i = 0; i < data.length; i++) {
                                                final ml = data[i]['mood_level'];
                                                if (ml != null) spots.add(FlSpot(i.toDouble(), (ml as int).toDouble()));
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
                                            }),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 16),

                                      // ── Analysis / Threshold (LIVE) ──
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text("WEEKLY ANALYSIS",
                                                style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 12),
                                            liveAnalysis == null
                                                ? Container(
                                                    padding: const EdgeInsets.all(14),
                                                    decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(12)),
                                                    child: Row(children: [
                                                      const Text("❓", style: TextStyle(fontSize: 28)),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            const Text("No Analysis Yet",
                                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                                                            Text("Student needs at least 7 mood logs for analysis.",
                                                                style: TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                                                            Text("${allMoodData.length}/7 logs",
                                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                                          ],
                                                        ),
                                                      ),
                                                    ]),
                                                  )
                                                : Container(
                                                    padding: const EdgeInsets.all(14),
                                                    decoration: BoxDecoration(color: threshold['bg'], borderRadius: BorderRadius.circular(12)),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(children: [
                                                          Text(threshold['emoji'], style: const TextStyle(fontSize: 28)),
                                                          const SizedBox(width: 12),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text("Threshold: ${threshold['label']}",
                                                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: threshold['color'])),
                                                                Text(threshold['sentence'],
                                                                    style: const TextStyle(fontSize: 12, color: AppTheme.textDark)),
                                                              ],
                                                            ),
                                                          ),
                                                        ]),
                                                        const SizedBox(height: 8),
                                                        Text(
                                                          "Week: ${liveAnalysis['week']}",
                                                          style: TextStyle(fontSize: 11, color: AppTheme.textGrey),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 16),

                                      if (latestStress != null)
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text("LATEST DASS-21 ASSESSMENT",
                                                  style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                                              const SizedBox(height: 12),
                                              Text("Assessed: ${latestStress!['assessment_date'] ?? '-'}",
                                                  style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                                              const SizedBox(height: 10),
                                              _stressScoreRow("Depression", latestStress!['depression_score'] ?? 0, latestStress!['depression_level'] ?? '-'),
                                              const SizedBox(height: 8),
                                              _stressScoreRow("Anxiety", latestStress!['anxiety_score'] ?? 0, latestStress!['anxiety_level'] ?? '-'),
                                              const SizedBox(height: 8),
                                              _stressScoreRow("Stress", latestStress!['stress_score'] ?? 0, latestStress!['stress_level'] ?? '-'),
                                            ],
                                          ),
                                        ),

                                      const SizedBox(height: 16),
                                    ],

                                    // ── Download PDF Button ──
                                    DecoratedBox(
                                      decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(12)),
                                      child: ElevatedButton(
                                        onPressed: () => _downloadPDF(student, liveAnalysis, liveReferral, referredCounsellorName),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          minimumSize: const Size(double.infinity, 48),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.download, color: Colors.white, size: 18),
                                            SizedBox(width: 8),
                                            Text("Download Report (PDF)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // ── Assign to Counsellor (PA only, LIVE referral) ──
                                    if (!isFromCounsellor)
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text("ASSIGN TO COUNSELLOR",
                                                style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppTheme.textGrey, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 12),

                                            if (liveReferral != null)
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                margin: const EdgeInsets.only(bottom: 12),
                                                decoration: BoxDecoration(
                                                  color: liveReferral['status'] == 'declined'
                                                      ? const Color(0xFFFFEBEE)
                                                      : AppTheme.secondarySoft,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(children: [
                                                      Icon(
                                                        liveReferral['status'] == 'accepted' || liveReferral['status'] == 'done'
                                                            ? Icons.check_circle
                                                            : Icons.hourglass_empty,
                                                        color: AppTheme.secondary,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          "Referred to: ${referredCounsellorName ?? liveReferral['counsellor_id']}",
                                                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textDark),
                                                        ),
                                                      ),
                                                    ]),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      "Status: ${liveReferral['status'].toString().toUpperCase()}",
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: liveReferral['status'] == 'accepted'
                                                            ? AppTheme.secondary
                                                            : liveReferral['status'] == 'done'
                                                                ? AppTheme.primary
                                                                : const Color(0xFFFFB74D),
                                                      ),
                                                    ),
                                                    Text("Date: ${liveReferral['referral_date']}",
                                                        style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                                                    if (liveReferral['status'] == 'declined') ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        "You may select another counsellor below.",
                                                        style: TextStyle(fontSize: 11, color: AppTheme.textGrey, fontStyle: FontStyle.italic),
                                                      ),
                                                    ],
                                                    if (liveReferral['status'] == 'done' &&
                                                        (liveReferral['counsellor_comment'] as String? ?? '').isNotEmpty) ...[
                                                      const SizedBox(height: 10),
                                                      Container(
                                                        padding: const EdgeInsets.all(10),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Row(children: [
                                                              Icon(Icons.comment, size: 14, color: AppTheme.primary),
                                                              const SizedBox(width: 6),
                                                              Text(
                                                                "Counsellor's Note",
                                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                                              ),
                                                            ]),
                                                            const SizedBox(height: 6),
                                                            Text(
                                                              liveReferral['counsellor_comment'],
                                                              style: const TextStyle(fontSize: 12, color: AppTheme.textDark, height: 1.4),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),

                                            if (liveReferral == null || 
                                                liveReferral['status'] == 'declined' ||
                                                (liveReferral['status'] == 'done' && 
                                                (threshold['label'] == 'Critical' || threshold['label'] == 'Moderate'))) ...[
                                              DropdownButtonFormField<String>(
                                                isExpanded: true,
                                                initialValue: _selectedCounsellorId.isEmpty ? null : _selectedCounsellorId,
                                                decoration: InputDecoration(
                                                  hintText: "Choose counsellor",
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                                  ),
                                                  enabledBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                                  ),
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                ),
                                                items: counsellors.map((c) {
                                                  return DropdownMenuItem(
                                                    value: c['id'] as String,
                                                    child: Text(
                                                      c['name'] as String,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: (val) {
                                                  setState(() {
                                                    _selectedCounsellorId = val ?? '';
                                                    _selectedCounsellor = counsellors.firstWhere((c) => c['id'] == val)['name'] as String;
                                                  });
                                                },
                                              ),
                                              const SizedBox(height: 12),
                                              DecoratedBox(
                                                decoration: BoxDecoration(gradient: AppTheme.buttonGradient, borderRadius: BorderRadius.circular(12)),
                                                child: ElevatedButton(
                                                  onPressed: _selectedCounsellorId.isEmpty ? null : () => _submitReferral(student, paUitmId),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.transparent,
                                                    shadowColor: Colors.transparent,
                                                    minimumSize: const Size(double.infinity, 48),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.send, color: Colors.white, size: 16),
                                                      SizedBox(width: 8),
                                                      Text("Submit Referral", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),

                                    const SizedBox(height: 30),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected ? AppTheme.buttonGradient : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppTheme.textGrey)),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 16),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textGrey)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textDark), textAlign: TextAlign.end),
        ),
      ],
    );
  }

  Widget _stressScoreRow(String category, int score, String level) {
    Color levelColor() {
      switch (level) {
        case 'Normal': return const Color(0xFF4DB6AC);
        case 'Mild': return const Color(0xFF81C784);
        case 'Moderate': return const Color(0xFFFFB74D);
        case 'Severe': return const Color(0xFFFF7043);
        default: return const Color(0xFFE57373);
      }
    }

    Color levelBg() {
      switch (level) {
        case 'Normal': return const Color(0xFFE0F7F6);
        case 'Mild': return const Color(0xFFE8F5E9);
        case 'Moderate': return const Color(0xFFFFF3E0);
        case 'Severe': return const Color(0xFFFBE9E7);
        default: return const Color(0xFFFFEBEE);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: levelBg(), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
              Text("$category ($level)", style: TextStyle(fontSize: 11, color: levelColor(), fontWeight: FontWeight.w600)),
            ],
          ),
          Text("$score", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: levelColor())),
        ],
      ),
    );
  }
}