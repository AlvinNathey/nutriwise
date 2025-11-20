import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<Map<String, dynamic>> _getUserInfo(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data();
      if (data == null) {
        // Defensive: doc exists but no data
        return {'name': 'User', 'dailyCalories': 0};
      }
      return {
        'name': data['name'] ?? 'User',
        'dailyCalories': data['dailyCalories'] ?? 0,
      };
    }
    return {'name': 'User', 'dailyCalories': 0};
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user != null) {
          // Always check if user document exists first - this determines if signup is complete
          // Use a key to prevent unnecessary rebuilds
          return FutureBuilder<DocumentSnapshot>(
            key: ValueKey('user_doc_${user.uid}'),
            future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
            builder: (context, docSnapshot) {
              if (docSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              
              // If document doesn't exist, user is in signup flow
              // CRITICAL: Never show HomeScreen if document doesn't exist, regardless of email verification status
              if (!docSnapshot.hasData || !docSnapshot.data!.exists) {
                // Always show loading during signup flow - EmailVerificationScreen will handle navigation
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              
              // Document exists - signup is complete, check email verification
              if (!user.emailVerified) {
                // Document exists but email not verified - show verification screen
                return EmailNotVerifiedScreen(user: user);
              }
              
              // User is verified and document exists - show HomeScreen
              return FutureBuilder<Map<String, dynamic>>(
                future: _getUserInfo(user.uid),
                builder: (context, infoSnapshot) {
                  if (infoSnapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(body: Center(child: CircularProgressIndicator()));
                  }
                  if (infoSnapshot.hasError) {
                    return HomeScreen();
                  }
                  return HomeScreen();
                },
              );
            },
          );
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class EmailNotVerifiedScreen extends StatelessWidget {
  final User user;
  const EmailNotVerifiedScreen({Key? key, required this.user}) : super(key: key);

  Future<void> _refresh(BuildContext context) async {
    await user.reload();
    final updatedUser = FirebaseAuth.instance.currentUser;
    if (updatedUser != null && updatedUser.emailVerified) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email not verified yet. Please check your inbox and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Email'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.email, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Please verify your email address to continue.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'A verification link has been sent to:\n${user.email}\n\nCheck your inbox and spam folder. After verifying, click the button below.',
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _refresh(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('I have verified my email', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                await user.sendEmailVerification();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Verification email resent!')),
                );
              },
              child: const Text('Resend verification email'),
            ),
          ],
        ),
      ),
    );
  }
}