import 'package:flutter/material.dart';
import 'package:mindease_app/theme/app_theme.dart';
import 'package:mindease_app/widgets/support_illustration.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final availableHeight = screenHeight - topPad - bottomPad;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Section (Illustration + App Name) ──
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: availableHeight * 0.04),
              decoration: const BoxDecoration(
                gradient: AppTheme.headerGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(48),
                  bottomRight: Radius.circular(48),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SupportIllustration(width: 220, height: availableHeight * 0.22),
                  const SizedBox(height: 6),
                  const Text("MindEase",
                      style: TextStyle(
                          color: Colors.white, fontSize: 28,
                          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  const Text("Mental Health Support System",
                      style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 0.5)),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _featureChip(Icons.self_improvement, "Mindfulness"),
                        const SizedBox(width: 8),
                        _featureChip(Icons.favorite, "Wellbeing"),
                        const SizedBox(width: 8),
                        _featureChip(Icons.spa, "Calm"),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom Section (Buttons) ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Your mental health journey\nstarts here",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold,
                          color: AppTheme.textDark, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Track your mood, assess stress, and\nget the support you deserve.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppTheme.textGrey, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    // Login button
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.buttonGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(
                            color: AppTheme.primary.withOpacity(0.3),
                            blurRadius: 12, offset: const Offset(0, 6))],
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Login",
                            style: TextStyle(color: Colors.white,
                                fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Register button
                    OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        side: const BorderSide(color: AppTheme.primary, width: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Register",
                          style: TextStyle(color: AppTheme.primary,
                              fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 12),
                    Text("A safe space for your mental wellbeing 💙",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}