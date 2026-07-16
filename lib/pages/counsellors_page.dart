import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:mindease_app/services/notification_service.dart';

class CounsellorsPage extends StatefulWidget {
  const CounsellorsPage({super.key});

  @override
  State<CounsellorsPage> createState() => _CounsellorsPageState();
}

class _CounsellorsPageState extends State<CounsellorsPage> {
  List<Map<String, dynamic>> counsellors = [];
  Map<String, String?> requestStatuses = {};
  String? studId;
  String? studentName;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final studentQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (studentQuery.docs.isEmpty) return;

      studId = studentQuery.docs.first.id;
      studentName = studentQuery.docs.first.data()['fullName'] ?? '-';

      final counsellorQuery = await FirebaseFirestore.instance
          .collection('counsellors')
          .get();

      final List<Map<String, dynamic>> loadedCounsellors = counsellorQuery.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      Map<String, String?> statuses = {};
      for (var c in loadedCounsellors) {
        final requestQuery = await FirebaseFirestore.instance
            .collection('counsellorRequests')
            .where('stud_id', isEqualTo: studId)
            .where('counsellor_id', isEqualTo: c['id'])
            .orderBy('request_date', descending: true)
            .limit(1)
            .get();

        if (requestQuery.docs.isNotEmpty) {
          statuses[c['id']] = requestQuery.docs.first.data()['status'] as String?;
        } else {
          statuses[c['id']] = null;
        }
      }

      setState(() {
        counsellors = loadedCounsellors;
        requestStatuses = statuses;
      });
    } catch (e) {
      print("Error loading counsellors: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _connectWithCounsellor(Map<String, dynamic> counsellor) async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final counsellorId = counsellor['id'] as String;

      await FirebaseFirestore.instance.collection('counsellorRequests').add({
        'stud_id': studId,
        'student_name': studentName,
        'counsellor_id': counsellorId,
        'status': 'pending',
        'request_date': today,
        'source': 'student',
        'created_at': FieldValue.serverTimestamp(),
      });

      final playerId = counsellor['playerId'];
      if (playerId != null) {
        await NotificationService.sendPushNotification(
          playerIds: [playerId],
          title: "New Student Request 🙋",
          body: "$studentName would like to connect with you",
          type: 'student_request',
          recipientUitmId: counsellorId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Request sent to ${counsellor['fullName']}!"),
          backgroundColor: AppTheme.secondary,
        ),
      );

      await _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
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
                    child: const Row(
                      children: [
                        Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text("Back", style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Counsellor Information",
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Reach out — you're not alone",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          ...counsellors.map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildCounsellorCard(c),
                              )),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounsellorCard(Map<String, dynamic> c) {
    final counsellorId = c['id'] as String;
    final status = requestStatuses[counsellorId];

    String buttonText = "Connect with Counsellor";
    bool isDisabled = false;

    if (status == 'pending') {
      buttonText = "⏳ Request Pending";
      isDisabled = true;
    } else if (status == 'accepted') {
      buttonText = "✅ Connected";
      isDisabled = true;
    } else if (status == 'rejected') {
      buttonText = "Request Again";
      isDisabled = false;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [

          // Avatar + Name + Role
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.secondarySoft,
                child: Text(
                  (c['fullName'] ?? '-').toString().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c['fullName'] ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.secondarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        c['position'] ?? c['role'] ?? '-',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.secondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Phone
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.phone, color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c['phone'] ?? '-',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Email
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.email, color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c['email'] ?? '-',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Connect button
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDisabled ? null : AppTheme.buttonGradient,
              color: isDisabled ? Colors.grey.shade300 : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: isDisabled ? null : () => _connectWithCounsellor(c),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    status == 'accepted'
                        ? Icons.check_circle
                        : status == 'pending'
                            ? Icons.hourglass_empty
                            : Icons.connect_without_contact,
                    color: isDisabled ? Colors.grey : Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      buttonText,
                      style: TextStyle(
                        color: isDisabled ? Colors.grey : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
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