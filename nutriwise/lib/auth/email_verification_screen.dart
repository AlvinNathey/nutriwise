import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:local_auth/local_auth.dart';
import '../services/auth_services.dart';
import '../home/home_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic> userData;

  const EmailVerificationScreen({
    Key? key,
    required this.user,
    required this.userData,
  }) : super(key: key);

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();
  bool _isChecking = false;
  bool _isProcessingBiometrics = false;

  Future<void> _checkEmailVerification() async {
    setState(() {
      _isChecking = true;
    });

    try {
      // Reload user to get latest verification status
      await widget.user.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;

      if (updatedUser != null && updatedUser.emailVerified) {
        // Email is verified, now prompt for biometrics
        await _promptBiometrics();
      } else {
        setState(() {
          _isChecking = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Email not verified yet. Please check your inbox and try again.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isChecking = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking verification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _promptBiometrics() async {
    setState(() {
      _isProcessingBiometrics = true;
    });

    try {
      final LocalAuthentication auth = LocalAuthentication();
      bool isSupported = await auth.isDeviceSupported();
      final biometrics = await auth.getAvailableBiometrics();
      bool didAuthenticate = false;

      if (isSupported && biometrics.isNotEmpty) {
        try {
          didAuthenticate = await auth.authenticate(
            localizedReason:
                'Please use fingerprint or Face ID to complete your account setup.',
            options: const AuthenticationOptions(biometricOnly: true),
          );
        } catch (e) {
          print('[DEBUG] Biometric authentication error: $e');
        }
      } else {
        // Biometrics not available on device, proceed without them
        didAuthenticate = true;
      }

      if (!didAuthenticate) {
        setState(() {
          _isProcessingBiometrics = false;
          _isChecking = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Biometric authentication required. Please use fingerprint or Face ID.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Biometrics successful (or not available), now save user data
      await _saveUserDataAndComplete();
    } catch (e) {
      setState(() {
        _isProcessingBiometrics = false;
        _isChecking = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during biometric authentication: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveUserDataAndComplete() async {
    try {
      final user = widget.user;
      final data = widget.userData;

      // Calculate final BMR if not already calculated
      int dailyCalories = data['dailyCalories'] ?? 2000;

      // Store height and weight in both user units and metric for consistency
      final double heightToStore = data['height'];
      final double weightToStore = data['weight'];
      final double heightMetric = data['heightMetric'] ?? heightToStore;
      final double weightMetric = data['weightMetric'] ?? weightToStore;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': data['name'],
        'email': data['email'],
        'gender': data['gender'],
        'dateOfBirth': data['dateOfBirth'],
        'height': heightToStore,
        'weight': weightToStore,
        'exerciseFrequency': data['exerciseFrequency'],
        'cardioLevel': data['cardioLevel'],
        'dailyCalories': dailyCalories,
        'createdAt': FieldValue.serverTimestamp(),
        'profileComplete': true,
        'isMetric': data['isMetric'] ?? true,
        'isWeightMetric': data['isWeightMetric'] ?? true,
        // Store metric for calculations
        'heightMetric': heightMetric,
        'weightMetric': weightMetric,
      });

      // Save initial weight entry for trend
      await _authService.saveWeightEntry(
        user.uid,
        weightToStore,
        isMetric: data['isWeightMetric'] ?? true,
      );

      // Navigate to home screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _isProcessingBiometrics = false;
        _isChecking = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving user data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    try {
      await widget.user.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email resent!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resending email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
            Icon(
              _isProcessingBiometrics ? Icons.fingerprint : Icons.email,
              size: 80,
              color: _isProcessingBiometrics ? Colors.green : Colors.blue,
            ),
            const SizedBox(height: 24),
            Text(
              _isProcessingBiometrics
                  ? 'Setting up biometric authentication...'
                  : 'Please verify your email address to continue.',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (!_isProcessingBiometrics)
              Text(
                'A verification link has been sent to:\n${widget.user.email}\n\nCheck your inbox and spam folder. After verifying, click the button below.',
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            if (_isProcessingBiometrics)
              const Text(
                'Please use your fingerprint or Face ID to complete account setup.',
                style: TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 32),
            if (!_isProcessingBiometrics)
              ElevatedButton(
                onPressed: _isChecking ? null : _checkEmailVerification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isChecking
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'I have verified my email',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            if (_isProcessingBiometrics)
              const Center(child: CircularProgressIndicator()),
            if (!_isProcessingBiometrics && !_isChecking) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: _resendVerificationEmail,
                child: const Text('Resend verification email'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
