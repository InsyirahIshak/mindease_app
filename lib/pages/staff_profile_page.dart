import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mindease_app/theme/app_theme.dart';

class StaffProfilePage extends StatefulWidget {
  final String collection; // 'personalAdvisor', 'counsellors', 'admins'
  final String role;       // 'PA', 'Counsellor', 'Admin'

  const StaffProfilePage({
    super.key,
    required this.collection,
    required this.role,
  });

  @override
  State<StaffProfilePage> createState() => _StaffProfilePageState();
}

class _StaffProfilePageState extends State<StaffProfilePage> {
  Map<String, dynamic>? staffData;
  String? docId;
  bool isLoading = true;
  bool isSaving = false;
  File? _selectedImage;

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _showPasswordSection = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final query = await FirebaseFirestore.instance
          .collection(widget.collection)
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return;

      docId = query.docs.first.id;
      final data = query.docs.first.data();

      setState(() {
        staffData = data;
        _emailController.text = data['email'] ?? '';
        _phoneController.text = data['phone'] ?? '';
      });
    } catch (e) {
      print("Error loading profile: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ── Pick image ──
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() => _selectedImage = File(picked.path));
      }
    } catch (e) {
      print("Error picking image: $e");
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Choose Photo",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _imageOption(
                    icon: Icons.photo_library,
                    label: "Gallery",
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _imageOption(
                    icon: Icons.camera_alt,
                    label: "Camera",
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _imageOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Upload image to Firebase Storage ──
  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_pictures')
          .child('${widget.collection}_$docId.jpg');
      await ref.putFile(_selectedImage!);
      return await ref.getDownloadURL();
    } catch (e) {
      print("Error uploading image: $e");
      return null;
    }
  }

  // ── Save profile ──
  Future<void> _saveProfile() async {
    if (docId == null) return;
    setState(() => isSaving = true);

    try {
      String? photoUrl;
      if (_selectedImage != null) {
        photoUrl = await _uploadImage();
      }

      final updates = <String, dynamic>{
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
      };

      if (photoUrl != null) updates['photoUrl'] = photoUrl;

      await FirebaseFirestore.instance
          .collection(widget.collection)
          .doc(docId)
          .update(updates);

      // Update email in Firebase Auth if changed
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _emailController.text.trim() != user.email) {
        await user.verifyBeforeUpdateEmail(_emailController.text.trim());
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile updated successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      await _loadProfile();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => isSaving = false);
    }
  }

  // ── Change password ──
  Future<void> _changePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("New passwords don't match!")),
      );
      return;
    }

    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Password must be at least 6 characters")),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newPasswordController.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password changed successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() => _showPasswordSection = false);
    } on FirebaseAuthException catch (e) {
      String message = "Error changing password";
      if (e.code == 'wrong-password') message = "Current password is incorrect";
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final fullName = staffData?['fullName'] ?? '-';
    final staffId = docId ?? '-';
    final photoUrl = staffData?['photoUrl'] as String?;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [

              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                decoration: const BoxDecoration(
                  gradient: AppTheme.headerGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios,
                                color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text("Back",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Profile picture
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: Colors.white,
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : (photoUrl != null
                                  ? NetworkImage(photoUrl)
                                  : null) as ImageProvider?,
                          child: (_selectedImage == null && photoUrl == null)
                              ? Text(
                                  fullName.isNotEmpty
                                      ? fullName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showImageSourceDialog,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  color: AppTheme.primary, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Text(
                      fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.role,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── View Only Info ──
                    _sectionTitle("PERSONAL INFORMATION"),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _viewRow(Icons.badge, "UITM ID", staffId),
                          const Divider(height: 20),
                          _viewRow(Icons.person, "Full Name", fullName),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Editable Fields ──
                    _sectionTitle("EDIT PROFILE"),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _editField(
                            icon: Icons.email,
                            label: "Email",
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          _editField(
                            icon: Icons.phone,
                            label: "Phone",
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Save Button ──
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.buttonGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text(
                                "Save Changes",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Change Password ──
                    _sectionTitle("SECURITY"),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primarySoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.lock_outline,
                                  color: AppTheme.primary, size: 20),
                            ),
                            title: const Text(
                              "Change Password",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppTheme.textDark,
                              ),
                            ),
                            trailing: Icon(
                              _showPasswordSection
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: AppTheme.textGrey,
                            ),
                            onTap: () => setState(() =>
                                _showPasswordSection = !_showPasswordSection),
                          ),
                          if (_showPasswordSection) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _passwordField(
                                    label: "Current Password",
                                    controller: _currentPasswordController,
                                    obscure: _obscureCurrent,
                                    onToggle: () => setState(() =>
                                        _obscureCurrent = !_obscureCurrent),
                                  ),
                                  const SizedBox(height: 12),
                                  _passwordField(
                                    label: "New Password",
                                    controller: _newPasswordController,
                                    obscure: _obscureNew,
                                    onToggle: () => setState(
                                        () => _obscureNew = !_obscureNew),
                                  ),
                                  const SizedBox(height: 12),
                                  _passwordField(
                                    label: "Confirm New Password",
                                    controller: _confirmPasswordController,
                                    obscure: _obscureConfirm,
                                    onToggle: () => setState(() =>
                                        _obscureConfirm = !_obscureConfirm),
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton(
                                    onPressed:
                                        isSaving ? null : _changePassword,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize:
                                          const Size(double.infinity, 48),
                                      side: const BorderSide(
                                          color: AppTheme.primary),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      "Update Password",
                                      style: TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
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
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 1,
        color: AppTheme.textGrey,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _viewRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textGrey,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon:
            const Icon(Icons.lock_outline, color: AppTheme.primary),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: AppTheme.textGrey,
          ),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}