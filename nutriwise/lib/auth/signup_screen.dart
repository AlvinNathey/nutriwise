import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutriwise/auth/goal_setup_screen.dart';
import 'package:nutriwise/auth/plan_setup.dart';
import 'package:nutriwise/services/auth_services.dart';
import 'package:nutriwise/auth/email_verification_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();

  int _wholeWeight = 170; // Whole number part
  int _decimalWeight = 0; // Decimal part (0-9)
  late FixedExtentScrollController _wholeController;
  late FixedExtentScrollController _decimalController;

  // Add state variables for feet/inches controllers
  late FixedExtentScrollController _feetController;
  late FixedExtentScrollController _inchesController;

  // Form controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // User data
  String _userName = '';
  String _userGender = '';
  DateTime? _dateOfBirth;
  double _height = 5.7; // Default to 5ft 7in
  bool _isMetric = true;
  double _weight = 70.0;
  int _exerciseFrequency = 0;
  String _cardioLevel = '';
  int _dailyCalories = 2636;

  // New state variables
  // Removed unused _mainGoal
  // Removed unused _targetWeight
  // Removed unused _pace

  int _currentStep = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isWeightMetric = true;

  @override
  void initState() {
    super.initState();
    // Default to 70.0 kg and kg unit
    _isWeightMetric = true;
    _weight = 70.0;
    // Set initial scroll position for weight wheel
    _wholeController = FixedExtentScrollController(
      initialItem: (_weight - 30).round(), // 70kg - 30kg = 40th item
    );
    _decimalController = FixedExtentScrollController(
      initialItem: 0, // 70.0, so decimal is 0
    );
    // Initialize feet/inches controllers
    _feetController = FixedExtentScrollController();
    _inchesController = FixedExtentScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update controllers to reflect the current _weight value
    _updateWeightControllers();
  }

  void _updateWeightControllers() {
    int whole, decimal;
    if (_isWeightMetric) {
      whole = _weight.floor();
      decimal = (((_weight - whole) * 10).round() % 10);
      _wholeController.jumpToItem((whole - 30).clamp(0, 170));
    } else {
      whole = _weight.floor();
      decimal = (((_weight - whole) * 10).round() % 10);
      _wholeController.jumpToItem((whole - 66).clamp(0, 374));
    }
    _decimalController.jumpToItem(decimal.clamp(0, 9));
  }

  @override
  void dispose() {
    _wholeController.dispose();
    _decimalController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // (removed) _showSuccessSnackBar was unused

  void _nextStep() {
    if (_currentStep < 10) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // --- Add these helper methods ---
  double _getHeightCm() {
    // Returns height in cm regardless of the UI unit toggle.
    // _height is always stored internally as feet (ft + in/12).
    return double.parse((_height * 30.48).toStringAsFixed(2));
  }

  double _getWeightKg() {
    // Returns weight in kg regardless of user selection
    if (_isWeightMetric) {
      return double.parse(_weight.toStringAsFixed(2));
    } else {
      // lbs to kg
      return double.parse((_weight / 2.20462).toStringAsFixed(2));
    }
  }

  // --- Update BMR calculation to always use metric ---
  double _calculateBMR() {
    if (_dateOfBirth == null) return 2000;
    int age = DateTime.now().year - _dateOfBirth!.year;
    double weightKg = _getWeightKg();
    double heightCm = _getHeightCm();
    double bmr;
    if (_userGender == 'Male') {
      bmr = 88.362 + (13.397 * weightKg) + (4.799 * heightCm) - (5.677 * age);
    } else {
      bmr = 447.593 + (9.247 * weightKg) + (3.098 * heightCm) - (4.330 * age);
    }
    // Activity factor: 0=1.2, 1=1.375, 2=1.55, 3=1.725, 4=1.9
    List<double> activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];
    int idx = _exerciseFrequency.clamp(0, 4);
    double tdee = bmr * activityFactors[idx];
    return tdee.roundToDouble();
  }

  Future<void> _completeSignup() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = await _authService.signUp(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
        if (user == null) {
          _showErrorSnackBar('Signup failed.');
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Calculate final BMR
        _dailyCalories = _calculateBMR().round();

        // Prepare user data to pass to verification screen
        final double heightToStore = _isMetric
            ? double.parse((_height * 30.48).toStringAsFixed(2)) // cm
            : double.parse(_height.toStringAsFixed(2)); // feet (e.g., 5.7)
        final double weightToStore = double.parse(_weight.toStringAsFixed(2));
        final double heightMetric = _getHeightCm();
        final double weightMetric = _getWeightKg();

        final userData = {
          'name': _userName,
          'email': _emailController.text.trim(),
          'gender': _userGender,
          'dateOfBirth': _dateOfBirth?.toIso8601String(),
          'height': heightToStore,
          'weight': weightToStore,
          'exerciseFrequency': _exerciseFrequency,
          'cardioLevel': _cardioLevel,
          'dailyCalories': _dailyCalories,
          'isMetric': _isMetric,
          'isWeightMetric': _isWeightMetric,
          'heightMetric': heightMetric,
          'weightMetric': weightMetric,
        };

        // Reset loading state before navigation
        setState(() {
          _isLoading = false;
        });

        // Navigate FIRST to prevent AuthWrapper from interfering
        // Then send email verification in the background
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => EmailVerificationScreen(
                user: user,
                userData: userData,
              ),
            ),
            (route) => false, // Remove all previous routes
          );
        }

        // Send email verification AFTER navigation to ensure it doesn't block
        // This happens in the background while EmailVerificationScreen is shown
        Future.microtask(() async {
          try {
            // Small delay to ensure user is fully created in Firebase
            await Future.delayed(const Duration(milliseconds: 300));
            
            // Reload user to get the latest state
            await user.reload();
            final currentUser = FirebaseAuth.instance.currentUser;
            
            // Use currentUser if available, otherwise use the original user object
            final userToUse = currentUser ?? user;
            
            // Send email verification
            await userToUse.sendEmailVerification();
            print('[DEBUG] Email verification sent successfully to ${userToUse.email}');
          } catch (e) {
            print('[DEBUG] Error sending email verification: $e');
            // Try one more time with the original user object as fallback
            try {
              await user.sendEmailVerification();
              print('[DEBUG] Email verification sent successfully (fallback method)');
            } catch (e2) {
              print('[DEBUG] Error sending email verification (fallback): $e2');
              // User can resend from verification screen if needed
            }
          }
        });
      } catch (e) {
        _showErrorSnackBar(e.toString());
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // (removed) _goToPlanSetup was unused

  void _goToGoalSetup() {
    final signupData = {
      'name': _userName,
      'gender': _userGender,
      'dateOfBirth': _dateOfBirth?.toIso8601String(),
      'height': _isMetric
          ? double.parse((_height * 30.48).toStringAsFixed(2))
          : double.parse(_height.toStringAsFixed(2)),
      'weight': double.parse(_weight.toStringAsFixed(2)),
      'exerciseFrequency': _exerciseFrequency,
      'cardioLevel': _cardioLevel,
      'isMetric': _isMetric,
      'isWeightMetric': _isWeightMetric,
      'email': _emailController.text.trim(),
    };
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GoalSetupScreen(
          weight: _weight,
          isWeightMetric: _isWeightMetric,
          previousCalories: _dailyCalories,
          signupData: signupData,
          onGoalComplete: (goalData) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PlanSetupScreen(
                  weight: _weight,
                  previousCalories: _dailyCalories,
                  signupData: signupData,
                  goalData: goalData,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(8, (index) {
          // 9 steps for account setup only
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: index <= _currentStep ? Colors.black : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Account Setup'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousStep,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildProgressBar(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildNameStep(),
                _buildGenderStep(),
                _buildDateOfBirthStep(),
                _buildHeightStep(),
                _buildWeightStep(),
                _buildExerciseStep(),
                _buildCardioStep(),
                _buildCaloriesStep(),
                _buildEmailPasswordStep(),
                _buildConfirmationStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'First, what should we call you?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Enter your name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _userName = value;
              });
            },
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _userName.isNotEmpty
                  ? () {
                      FocusScope.of(context).unfocus();
                      _nextStep();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            'Hey $_userName, what\'s your sex?',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 40),
          _buildGenderOption('Female', Icons.female),
          const SizedBox(height: 16),
          _buildGenderOption('Male', Icons.male),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildGenderOption(String gender, IconData icon) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _userGender = gender;
        });
        Future.delayed(const Duration(milliseconds: 200), _nextStep);
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(
              gender,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateOfBirthStep() {
    // Initialize default date if not set
    if (_dateOfBirth == null) {
      _dateOfBirth = DateTime(2000, 1, 1);
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'What\'s your date of birth?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 20),

          // Selected date display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Selected Date',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_getMonthName(_dateOfBirth!.month)} ${_dateOfBirth!.day}, ${_dateOfBirth!.year}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  // Month picker
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: const Text(
                            'Month',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            itemExtent: 50,
                            physics: const FixedExtentScrollPhysics(),
                            diameterRatio: 2.0,
                            perspective: 0.003,
                            controller: FixedExtentScrollController(
                              initialItem: (_dateOfBirth?.month ?? 1) - 1,
                            ),
                            onSelectedItemChanged: (index) {
                              setState(() {
                                _dateOfBirth = DateTime(
                                  _dateOfBirth!.year,
                                  index + 1,
                                  _dateOfBirth!.day >
                                          _getDaysInMonth(
                                            _dateOfBirth!.year,
                                            index + 1,
                                          )
                                      ? _getDaysInMonth(
                                          _dateOfBirth!.year,
                                          index + 1,
                                        )
                                      : _dateOfBirth!.day,
                                );
                              });
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              builder: (context, index) {
                                final months = [
                                  'Jan',
                                  'Feb',
                                  'Mar',
                                  'Apr',
                                  'May',
                                  'Jun',
                                  'Jul',
                                  'Aug',
                                  'Sep',
                                  'Oct',
                                  'Nov',
                                  'Dec',
                                ];
                                if (index < 0 || index >= 12) return null;

                                bool isSelected =
                                    _dateOfBirth!.month == index + 1;

                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      months[index],
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(width: 1, color: Colors.grey[300]),

                  // Day picker
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: const Text(
                            'Day',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            itemExtent: 50,
                            physics: const FixedExtentScrollPhysics(),
                            diameterRatio: 2.0,
                            perspective: 0.003,
                            controller: FixedExtentScrollController(
                              initialItem: (_dateOfBirth?.day ?? 1) - 1,
                            ),
                            onSelectedItemChanged: (index) {
                              setState(() {
                                _dateOfBirth = DateTime(
                                  _dateOfBirth!.year,
                                  _dateOfBirth!.month,
                                  index + 1,
                                );
                              });
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              builder: (context, index) {
                                int daysInMonth = _getDaysInMonth(
                                  _dateOfBirth!.year,
                                  _dateOfBirth!.month,
                                );
                                if (index < 0 || index >= daysInMonth)
                                  return null;

                                bool isSelected =
                                    _dateOfBirth!.day == index + 1;

                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _getDaysInMonth(
                                _dateOfBirth!.year,
                                _dateOfBirth!.month,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(width: 1, color: Colors.grey[300]),

                  // Year picker
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: const Text(
                            'Year',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            itemExtent: 50,
                            physics: const FixedExtentScrollPhysics(),
                            diameterRatio: 2.0,
                            perspective: 0.003,
                            controller: FixedExtentScrollController(
                              initialItem: (_dateOfBirth?.year ?? 2000) - 1950,
                            ),
                            onSelectedItemChanged: (index) {
                              setState(() {
                                int newYear = 1950 + index;
                                _dateOfBirth = DateTime(
                                  newYear,
                                  _dateOfBirth!.month,
                                  _dateOfBirth!.day >
                                          _getDaysInMonth(
                                            newYear,
                                            _dateOfBirth!.month,
                                          )
                                      ? _getDaysInMonth(
                                          newYear,
                                          _dateOfBirth!.month,
                                        )
                                      : _dateOfBirth!.day,
                                );
                              });
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              builder: (context, index) {
                                final year = 1950 + index;
                                if (year > DateTime.now().year) return null;

                                bool isSelected = _dateOfBirth!.year == year;

                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$year',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: DateTime.now().year - 1950 + 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for date picker
  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  int _getDaysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  Widget _buildHeightStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'And your height?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 40),

          // Unit toggle buttons
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _isMetric = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: !_isMetric ? Colors.black : Colors.grey[200],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    'ft in',
                    style: TextStyle(
                      color: !_isMetric ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => setState(() => _isMetric = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _isMetric ? Colors.black : Colors.grey[200],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Text(
                    'cm',
                    style: TextStyle(
                      color: _isMetric ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Height display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Your Height',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  !_isMetric
                      ? '${(_height.floor())}ft ${((_height % 1) * 12).round()}in'
                      : '${(_height * 30.48).round()} cm',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Height picker
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: !_isMetric ? _buildFeetInchPicker() : _buildCmPicker(),
            ),
          ),

          const SizedBox(height: 40),

          // Next button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  // Feet and inches picker
  Widget _buildFeetInchPicker() {
    int feet = _height.floor();
    int inches = ((_height % 1) * 12).round();
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Text(
                  'Feet',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                height: 1,
                color: Colors.grey[300],
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: ListWheelScrollView.useDelegate(
                  controller: _feetController,
                  physics: const FixedExtentScrollPhysics(),
                  itemExtent: 50.0,
                  diameterRatio: 2.0,
                  perspective: 0.003,
                  onSelectedItemChanged: (index) {
                    setState(() {
                      int newFeet = index + 4;
                      _height = newFeet + (inches / 12.0);
                    });
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (context, index) {
                      final feetValue = index + 4;
                      if (feetValue < 4 || feetValue > 7) return null;
                      bool isSelected = feet == feetValue;
                      double opacity = isSelected ? 1.0 : 0.3;
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.black
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$feetValue ft',
                            style: TextStyle(
                              fontSize: isSelected ? 36 : 28,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.black.withOpacity(opacity),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.grey[300]),
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Text(
                  'Inches',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                height: 1,
                color: Colors.grey[300],
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: ListWheelScrollView.useDelegate(
                  controller: _inchesController,
                  physics: const FixedExtentScrollPhysics(),
                  itemExtent: 50.0,
                  diameterRatio: 2.0,
                  perspective: 0.003,
                  onSelectedItemChanged: (index) {
                    setState(() {
                      _height = feet + (index / 12.0);
                    });
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (context, index) {
                      if (index < 0 || index >= 12) return null;
                      bool isSelected = inches == index;
                      double opacity = isSelected ? 1.0 : 0.3;
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.black
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$index in',
                            style: TextStyle(
                              fontSize: isSelected ? 24 : 20,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.black.withOpacity(opacity),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Centimeters picker
  Widget _buildCmPicker() {
    int heightInCm = (_height * 30.48).round();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: const Text(
            'Centimeters',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ),
        Container(
          height: 1,
          color: Colors.grey[300],
          margin: const EdgeInsets.symmetric(horizontal: 16),
        ),
        Expanded(
          child: ListWheelScrollView.useDelegate(
            itemExtent: 50,
            physics: const FixedExtentScrollPhysics(),
            diameterRatio: 2.0,
            perspective: 0.003,
            controller: FixedExtentScrollController(
              initialItem: heightInCm - 120, // Start from 120cm
            ),
            onSelectedItemChanged: (index) {
              setState(() {
                int newHeightInCm = index + 120; // 120 to 220 cm
                _height = newHeightInCm / 30.48; // Convert back to feet
              });
            },
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (context, index) {
                final cmValue = index + 120;
                if (cmValue < 120 || cmValue > 220) return null;

                bool isSelected = heightInCm == cmValue;

                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$cmValue cm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
              childCount: 101, // 120cm to 220cm
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeightStep() {
    // Always update whole and decimal based on _weight
    _wholeWeight = _weight.floor();
    _decimalWeight = (((_weight - _wholeWeight) * 10).round() % 10);

    // Ensure controllers are in sync with _weight
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateWeightControllers();
    });

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          // Added scrollability for better UX
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'What\'s your current weight?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 24),

                // --- Weight Display Section (like height page) ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Your Weight',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isWeightMetric
                            ? '${_weight.toStringAsFixed(1)} kg'
                            : '${_weight.toStringAsFixed(1)} lbs',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Unit toggle buttons
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_isWeightMetric) {
                            // Convert from kg to lbs
                            _weight = double.parse(
                              (_weight * 2.20462).toStringAsFixed(1),
                            );
                            _isWeightMetric = false;
                            _updateWeightControllers();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: !_isWeightMetric
                              ? Colors.black
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'lbs',
                          style: TextStyle(
                            color: !_isWeightMetric
                                ? Colors.white
                                : Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (!_isWeightMetric) {
                            // Convert from lbs to kg
                            _weight = double.parse(
                              (_weight / 2.20462).toStringAsFixed(1),
                            );
                            _isWeightMetric = true;
                            _updateWeightControllers();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _isWeightMetric
                              ? Colors.black
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'kg',
                          style: TextStyle(
                            color: _isWeightMetric
                                ? Colors.white
                                : Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Weight wheel picker with flexible height
                SizedBox(
                  height: 220,
                  child: Stack(
                    children: [
                      // Selection highlight background
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Whole number wheel
                          SizedBox(
                            width: 100,
                            child: ListWheelScrollView.useDelegate(
                              controller: _wholeController,
                              physics: const FixedExtentScrollPhysics(),
                              itemExtent: 50.0,
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  int value = _isWeightMetric
                                      ? 30 + index
                                      : 66 + index;
                                  bool isSelected = value == _weight.floor();
                                  return Center(
                                    child: Text(
                                      value.toString(),
                                      style: TextStyle(
                                        fontSize: isSelected ? 36 : 28,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.black
                                            : Colors.black.withOpacity(0.3),
                                      ),
                                    ),
                                  );
                                },
                                childCount: _isWeightMetric ? 171 : 375,
                              ),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  if (_isWeightMetric) {
                                    _wholeWeight = (30 + index).clamp(30, 200);
                                  } else {
                                    _wholeWeight = (66 + index).clamp(66, 440);
                                  }
                                  _weight =
                                      _wholeWeight + (_decimalWeight / 10.0);
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Text(
                              '.',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          // Decimal wheel
                          SizedBox(
                            width: 60,
                            child: ListWheelScrollView.useDelegate(
                              controller: _decimalController,
                              physics: const FixedExtentScrollPhysics(),
                              itemExtent: 50.0,
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  int value = index;
                                  bool isSelected = value == _decimalWeight;
                                  return Center(
                                    child: Text(
                                      value.toString(),
                                      style: TextStyle(
                                        fontSize: isSelected ? 36 : 28,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.black
                                            : Colors.black.withOpacity(0.3),
                                      ),
                                    ),
                                  );
                                },
                                childCount: 10,
                              ),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  _decimalWeight = (index % 10).clamp(0, 9);
                                  _weight =
                                      _wholeWeight + (_decimalWeight / 10.0);
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0),
                            child: Text(
                              _isWeightMetric ? 'kg' : 'lbs',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Instruction text
                Center(
                  child: Text(
                    'Scroll to select your weight',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Next button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Next', style: TextStyle(fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              'How often do you exercise?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'How many times per week do you do recreational sports, cardio, or resistance training?',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            _buildExerciseOption(0, '0\nNo exercise'),
            const SizedBox(height: 16),
            _buildExerciseOption(1, '1 to 3\nLightly active'),
            const SizedBox(height: 16),
            _buildExerciseOption(2, '4 to 5\nModerately active'),
            const SizedBox(height: 16),
            _buildExerciseOption(3, '6 to 7\nActive'),
            const SizedBox(height: 16),
            _buildExerciseOption(4, '7+\nExtremely active'),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _exerciseFrequency != -1 ? _nextStep : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Next', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseOption(int frequency, String description) {
    final isSelected = _exerciseFrequency == frequency;
    return GestureDetector(
      onTap: () {
        setState(() {
          _exerciseFrequency = frequency;
        });
      },
      child: SizedBox(
        width: double.infinity,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.black : Colors.black,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                description,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardioStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              'What\'s your cardio experience level?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tell us about your cardio activity.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            _buildCardioOption('None', 'Currently not doing cardio'),
            const SizedBox(height: 16),
            _buildCardioOption('Beginner', 'Cardio for 1 year or less'),
            const SizedBox(height: 16),
            _buildCardioOption('Intermediate', 'Cardio for 1-4 years'),
            const SizedBox(height: 16),
            _buildCardioOption('Advanced', 'Cardio for 4+ years'),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cardioLevel.isNotEmpty ? _nextStep : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Next', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardioOption(String level, String description) {
    final isSelected = _cardioLevel == level;
    return GestureDetector(
      onTap: () {
        setState(() {
          _cardioLevel = level;
        });
      },
      child: SizedBox(
        width: double.infinity,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.black : Colors.black,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                level,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected ? Colors.white70 : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaloriesStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'Your daily calories',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Based on your information, here\'s your recommended daily calorie intake.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${_calculateBMR().round()}',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const Text(
                        'calories per day',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This is calculated using your age, gender, height, weight, and activity level.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _dailyCalories = _calculateBMR().round();
                });
                _goToGoalSetup();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Continue', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailPasswordStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              'Create your account',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your email and create a password to secure your account.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'Enter your email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(
                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Create a password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                hintText: 'Confirm your password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _nextStep();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Next', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'Review your information',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please review your details before creating your account.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildInfoCard('Personal Info', [
                    'Name: $_userName',
                    'Gender: $_userGender',
                    'Date of Birth: ${_dateOfBirth != null ? _dateOfBirth!.toString().split(' ')[0] : 'Not set'}',
                    'Email: ${_emailController.text}',
                  ]),
                  const SizedBox(height: 16),
                  _buildInfoCard('Physical Stats', [
                    _isMetric
                        ? 'Height: ${_getHeightCm().round()} cm'
                        : 'Height: ${(_height.floor())}ft ${((_height % 1) * 12).round()}in',
                    _isWeightMetric
                        ? 'Weight: ${_weight.toStringAsFixed(1)} kg'
                        : 'Weight: ${_weight.toStringAsFixed(1)} lbs',
                  ]),
                  const SizedBox(height: 16),
                  _buildInfoCard('Activity Level', [
                    'Exercise Frequency: ${_getExerciseDescription()}',
                    'Cardio Level: $_cardioLevel',
                    'Daily Calories: $_dailyCalories',
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _completeSignup,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Create Account',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<String> items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          ...items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  String _getExerciseDescription() {
    switch (_exerciseFrequency) {
      case 0:
        return '0 - No exercise';
      case 1:
        return '1-3 - Lightly active';
      case 2:
        return '4-5 - Moderately active';
      case 3:
        return '6-7 - Active';
      case 4:
        return '7+ - Extremely active';
      default:
        return 'Not set';
    }
  }
}
