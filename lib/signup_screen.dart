import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:movie_app/database/auth_database.dart';
import 'package:movie_app/profile_selection_screen.dart';
import 'package:movie_app/signin_screen.dart';
import 'package:movie_app/user_manager.dart';
import 'package:movie_app/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  SignUpScreenState createState() => SignUpScreenState();
}

class SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isProcessing = false;

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _storeSession(String userId, String token) async {
    try {
      final expirationDate = DateTime.now().add(const Duration(days: 5));
      await _firestore.collection('sessions').doc(userId).set({
        'userId': userId,
        'token': token,
        'expiresAt': Timestamp.fromDate(expirationDate),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_user_id', userId);
      await prefs.setString('session_token', token);
      await prefs.setInt('session_expires_at', expirationDate.millisecondsSinceEpoch);
      debugPrint('✅ Session saved for user: $userId');
    } catch (e) {
      debugPrint('❌ Error storing session: $e');
      throw e;
    }
  }

  Future<void> _saveUserOffline(String userId, Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_$userId', userData.toString());
      debugPrint('✅ User data saved offline for user: $userId');
    } catch (e) {
      debugPrint('❌ Error saving user offline: $e');
      throw e;
    }
  }

  Future<void> _signUpEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final username = _usernameController.text.trim();

      final userCred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;

      final user = userCred.user;
      if (user != null) {
        final userData = {
          'id': user.uid,
          'username': username,
          'email': email,
          'status': 'Online',
          'auth_provider': 'firebase',
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        };

        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          await _firestore.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));
        }

        await AuthDatabase.instance.createUser({
          'id': user.uid,
          'username': username,
          'email': email,
          'password': password,
          'auth_provider': 'firebase',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        await _saveUserOffline(user.uid, userData);
        UserManager.instance.updateUser(userData);

        final token = await user.getIdToken();
        if (token != null) {
          await SessionManager.saveAuthToken(token);
          await _storeSession(user.uid, token);
        } else {
          throw Exception('Failed to obtain auth token');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sign up successful")),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSelectionScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Sign up failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isProcessing = true);
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Google sign-up cancelled")),
          );
        }
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _firebaseAuth.signInWithCredential(credential);
      final user = userCred.user;
      if (!mounted) return;

      if (user != null) {
        final userData = {
          'id': user.uid,
          'username': user.displayName ?? 'GoogleUser',
          'email': user.email ?? '',
          'status': 'Online',
          'auth_provider': 'google',
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        };

        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          await _firestore.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));
        }

        await AuthDatabase.instance.createUser({
          'id': user.uid,
          'username': user.displayName ?? 'GoogleUser',
          'email': user.email ?? '',
          'password': '',
          'auth_provider': 'google',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        await _saveUserOffline(user.uid, userData);
        UserManager.instance.updateUser({
          'id': user.uid,
          'username': user.displayName ?? 'GoogleUser',
          'email': user.email ?? '',
          'photoURL': user.photoURL,
        });

        final token = await user.getIdToken();
        if (token != null) {
          await SessionManager.saveAuthToken(token);
          await _storeSession(user.uid, token);
        } else {
          throw Exception('Failed to obtain auth token');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Google sign-up successful")),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSelectionScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google sign-up failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Sign Up"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple, Colors.black],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _isProcessing
                    ? const Center(child: CircularProgressIndicator())
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha((0.7 * 255).round()),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      "Create Account",
                                      style: TextStyle(
                                        fontSize: 24,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _usernameController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: "Username",
                                        labelStyle: const TextStyle(color: Colors.white70),
                                        filled: true,
                                        fillColor: Colors.white.withAlpha((0.1 * 255).round()),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      validator: (v) => v == null || v.isEmpty ? 'Enter username' : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _emailController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: "Email",
                                        labelStyle: const TextStyle(color: Colors.white70),
                                        filled: true,
                                        fillColor: Colors.white.withAlpha((0.1 * 255).round()),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) => v == null || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)
                                          ? 'Enter valid email'
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _passwordController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: "Password",
                                        labelStyle: const TextStyle(color: Colors.white70),
                                        filled: true,
                                        fillColor: Colors.white.withAlpha((0.1 * 255).round()),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      obscureText: true,
                                      validator: (v) => v == null || v.length < 6 ? 'Min 6 chars' : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _confirmPasswordController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: "Confirm Password",
                                        labelStyle: const TextStyle(color: Colors.white70),
                                        filled: true,
                                        fillColor: Colors.white.withAlpha((0.1 * 255).round()),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      obscureText: true,
                                      validator: (v) => v == _passwordController.text ? null : 'Passwords must match',
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton(
                                      onPressed: _signUpEmail,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text(
                                        'Sign Up',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: _signUpWithGoogle,
                                      icon: Image.asset(
                                        'assets/googlelogo1.png',
                                        height: 24,
                                        width: 24,
                                      ),
                                      label: const Text(
                                        'Sign Up with Google',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black87,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: () {
                                        if (!mounted) return;
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(builder: (_) => const SignInScreen()),
                                        );
                                      },
                                      child: const Text(
                                        'Already have an account? Sign In',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
