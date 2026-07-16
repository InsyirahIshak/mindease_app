import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindease_app/theme/app_theme.dart';

class PACounsellorsPage extends StatelessWidget {
  const PACounsellorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
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
                      "Counsellors",
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Wellness team for referrals",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // ── Counsellor Cards (LIVE from Firestore) ──
              Padding(
                padding: const EdgeInsets.all(20),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('counsellors').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            Icon(Icons.local_hospital_outlined, color: AppTheme.textGrey, size: 36),
                            const SizedBox(height: 8),
                            Text("No counsellors available yet", style: TextStyle(color: AppTheme.textGrey)),
                          ],
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;

                    return Column(
                      children: [
                        const SizedBox(height: 4),
                        ...docs.map((doc) {
                          final c = doc.data() as Map<String, dynamic>;
                          final name = c['fullName'] ?? '-';
                          final position = c['position'] ?? '';
                          final phone = c['phone'] ?? '-';
                          final email = c['email'] ?? '-';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
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

                                  // Avatar + Name + Position
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: AppTheme.secondarySoft,
                                        child: Text(
                                          name.toString().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join(),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.secondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: AppTheme.textDark,
                                              ),
                                            ),
                                            if (position.toString().isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.secondarySoft,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  position,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.secondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 14),
                                  const Divider(height: 1),
                                  const SizedBox(height: 14),

                                  // Phone
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primarySoft,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.phone, color: AppTheme.primary, size: 16),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(phone, style: const TextStyle(fontSize: 13, color: AppTheme.textDark)),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  // Email
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.secondarySoft,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.email, color: AppTheme.secondary, size: 16),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          email,
                                          style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}