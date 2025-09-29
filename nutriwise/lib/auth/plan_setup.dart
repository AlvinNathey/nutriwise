import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home/home_screen.dart';

class PlanSetupScreen extends StatefulWidget {
  final double weight;
  final int previousCalories;
  final Map<String, dynamic> signupData;
  final Map<String, dynamic> goalData;
  const PlanSetupScreen({
    Key? key,
    required this.weight,
    required this.previousCalories,
    required this.signupData,
    required this.goalData,
  }) : assert(weight != null),
       assert(previousCalories != null),
       super(key: key);

  @override
  State<PlanSetupScreen> createState() => _PlanSetupScreenState();
}

class _PlanSetupScreenState extends State<PlanSetupScreen> {
  int _currentStep = 0;
  final Map<String, dynamic> _formData = {};

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final int _totalSteps = 5;

  // Macro calculation logic
  Map<String, dynamic> _macroSummary = {};

  // Add state for password visibility and error message
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _passwordError;
  String? _emailError;
  final _formKey = GlobalKey<FormState>();

  void _nextStep() {
    setState(() {
      if (_currentStep < 4) {
        _currentStep++;
      } else {
        _submit();
      }
    });
  }

  void _prevStep() {
    setState(() {
      if (_currentStep > 0) _currentStep--;
    });
  }

  void _calculateMacros() {
    // Determine unit and convert weight to kg accurately
    final bool isMetric = widget.signupData['isWeightMetric'] ?? false;
    double weightInput = widget.weight;
    if (weightInput.isNaN || weightInput == 0) weightInput = 70.0;
    final double weightKg = isMetric ? weightInput : weightInput / 2.20462;

    // Protein per kg by preference
    final String proteinPref = _formData['proteinIntake'] ?? 'Moderate Intake';
    double proteinPerKg = 1.2;
    if (proteinPref == 'Low Intake') proteinPerKg = 0.8;
    if (proteinPref == 'Moderate Intake') proteinPerKg = 1.2;
    if (proteinPref == 'High Intake') proteinPerKg = 1.6;
    if (proteinPref == 'Very High Intake') proteinPerKg = 2.0;
    final int proteinG = (weightKg * proteinPerKg).round();
    final int proteinCals = proteinG * 4;

    // Maintenance from previous step (already tailored to user)
    int maintenanceCals = widget.previousCalories;
    if (maintenanceCals == 0 || maintenanceCals.isNaN) maintenanceCals = 2000;

    // Goal pacing (kg/week or lb/week based on unit selection)
    final String mainGoal = widget.goalData['mainGoal'] ?? 'Maintain weight';
    final String pace = widget.goalData['pace'] ?? 'Steady';
    double paceValue = 0.0;
    if (mainGoal == 'Lose weight' || mainGoal == 'Gain weight') {
      if (isMetric) {
        if (pace == 'Relaxed')
          paceValue = 0.125;
        else if (pace == 'Steady')
          paceValue = 0.25;
        else if (pace == 'Accelerated')
          paceValue = 0.5;
        else if (pace == 'Intense')
          paceValue = 1.0;
      } else {
        if (pace == 'Relaxed')
          paceValue = 0.25;
        else if (pace == 'Steady')
          paceValue = 0.5;
        else if (pace == 'Accelerated')
          paceValue = 1.0;
        else if (pace == 'Intense')
          paceValue = 2.0;
      }
    }

    int dailyCalorieDelta = 0;
    if (mainGoal == 'Lose weight') {
      dailyCalorieDelta = isMetric
          ? -((paceValue * 7700) / 7)
                .round() // kg/week → kcal/day
          : -(paceValue * 500).round(); // lb/week → kcal/day (3500/7)
    } else if (mainGoal == 'Gain weight') {
      dailyCalorieDelta = isMetric
          ? ((paceValue * 7700) / 7).round()
          : (paceValue * 500).round();
    } else {
      dailyCalorieDelta = 0;
    }

    int targetCalories = maintenanceCals + dailyCalorieDelta;
    if (targetCalories < 1200) targetCalories = 1200;

    // Diet splits applied to remaining calories after protein
    final String diet = _formData['dietType'] ?? 'Balanced';
    double fatRatio; // of remaining calories
    double carbRatio; // of remaining calories
    if (diet == 'Keto') {
      fatRatio = 0.85; // remaining mostly fat
      carbRatio = 0.15;
    } else if (diet == 'Low-carb') {
      fatRatio = 0.6;
      carbRatio = 0.4;
    } else if (diet == 'Low-fat') {
      fatRatio = 0.3;
      carbRatio = 0.7;
    } else {
      // Balanced
      fatRatio = 0.5;
      carbRatio = 0.5;
    }

    int remainingCalories = targetCalories - proteinCals;
    if (remainingCalories < 0) remainingCalories = 0;

    final int fatCals = (remainingCalories * fatRatio).round();
    final int carbCals = remainingCalories - fatCals; // ensure totals line up
    int fatG = (fatCals / 9).round();
    int carbG = (carbCals / 4).round();

    final int newTotalCals = (proteinG * 4) + (carbG * 4) + (fatG * 9);
    _macroSummary = {
      'previousCalories': maintenanceCals,
      'newCalories': newTotalCals,
      'proteinG': proteinG,
      'carbG': carbG,
      'fatG': fatG,
      'change': newTotalCals > maintenanceCals
          ? 'increase'
          : newTotalCals < maintenanceCals
          ? 'decrease'
          : 'same',
    };
  }

  Future<void> _submit() async {
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final confirmPassword = _confirmPasswordController.text;
      if (password != confirmPassword) {
        setState(() {
          _passwordError = 'Passwords do not match';
        });
        return;
      }
      final UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      final uid = userCredential.user!.uid;
      final userData = {
        ...widget.signupData,
        ...widget.goalData,
        ..._formData,
        'email': email,
        'calories': _macroSummary['newCalories'],
        'proteinG': _macroSummary['proteinG'],
        'carbG': _macroSummary['carbG'],
        'fatG': _macroSummary['fatG'],
      };
      // Round weight and targetWeight to 1 decimal place if present
      if (userData['weight'] != null) {
        userData['weight'] = double.parse(
          userData['weight'].toStringAsFixed(1),
        );
      }
      if (userData['targetWeight'] != null) {
        userData['targetWeight'] = double.parse(
          userData['targetWeight'].toStringAsFixed(1),
        );
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData);
      final name = userData['name'] ?? '';
      final calories = userData['calories'] ?? 0;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => HomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        setState(() {
          _emailError = 'Email already exists';
        });
      } else {
        setState(() {
          _emailError = e.message;
        });
      }
    } catch (e) {
      setState(() {
        _emailError = 'Error: ${e.toString()}';
      });
    }
  }

  Widget _buildProgressBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(_totalSteps, (index) {
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

  Widget _buildDietStep() {
    final options = [
      {
        'label': 'Balanced',
        'desc': 'A mix of all macronutrients for overall health.',
      },
      {
        'label': 'Low-fat',
        'desc': 'Reduced fat intake, higher carbs and protein.',
      },
      {'label': 'Low-carb', 'desc': 'Reduced carbs, higher protein and fat.'},
      {'label': 'Keto', 'desc': 'Very low carb, high fat, moderate protein.'},
    ];
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              'Which type of diet do you prefer to follow?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 40),
            ...options.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildOptionCard(
                  o['label']!,
                  o['desc']!,
                  _formData['dietType'] == o['label'],
                  () => setState(() => _formData['dietType'] = o['label']),
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _formData['dietType'] != null ? _nextStep : null,
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

  Widget _buildTrainingStep() {
    final options = [
      {
        'label': 'None or Related Activity',
        'desc': 'No structured training or only light activity.',
      },
      {
        'label': 'Lifting',
        'desc': 'Strength or resistance training as main focus.',
      },
      {'label': 'Cardio', 'desc': 'Aerobic/cardio training as main focus.'},
      {
        'label': 'Cardio and Lifting',
        'desc': 'A mix of both cardio and lifting.',
      },
    ];
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              'What type of training will you follow during this program?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 40),
            ...options.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildOptionCard(
                  o['label']!,
                  o['desc']!,
                  _formData['trainingType'] == o['label'],
                  () => setState(() => _formData['trainingType'] = o['label']),
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _formData['trainingType'] != null ? _nextStep : null,
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

  Widget _buildProteinStep() {
    final options = [
      {
        'label': 'Low Intake',
        'desc': 'At the lower end of the recommended range.',
      },
      {
        'label': 'Moderate Intake',
        'desc': 'In the middle of the recommended range.',
      },
      {
        'label': 'High Intake',
        'desc': 'At the high end of the recommended range.',
      },
      {
        'label': 'Very High Intake',
        'desc': 'Above the typical recommended range.',
      },
    ];
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              'What is your preferred daily protein intake level?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 40),
            ...options.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildOptionCard(
                  o['label']!,
                  o['desc']!,
                  _formData['proteinIntake'] == o['label'],
                  () => setState(() => _formData['proteinIntake'] = o['label']),
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _formData['proteinIntake'] != null
                    ? _nextStep
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
      ),
    );
  }

  Widget _buildOptionCard(
    String label,
    String desc,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          border: Border.all(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: TextStyle(
                fontSize: 14,
                color: selected ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to estimate goal date
  String _estimateGoalDate() {
    final mainGoal = widget.goalData['mainGoal'] ?? '';
    final pace = widget.goalData['pace'] ?? '';
    final isMetric = widget.signupData['isWeightMetric'] ?? false;
    final double? weight = widget.signupData['weight'] is double
        ? widget.signupData['weight']
        : double.tryParse(widget.signupData['weight']?.toString() ?? '');
    final double? targetWeight = widget.goalData['targetWeight'] is double
        ? widget.goalData['targetWeight']
        : double.tryParse(widget.goalData['targetWeight']?.toString() ?? '');

    if (mainGoal == 'Maintain weight' ||
        weight == null ||
        targetWeight == null) {
      return '';
    }

    double paceValue = 0.0;
    if (isMetric) {
      if (pace == 'Relaxed')
        paceValue = 0.125;
      else if (pace == 'Steady')
        paceValue = 0.25;
      else if (pace == 'Accelerated')
        paceValue = 0.5;
      else if (pace == 'Intense')
        paceValue = 1.0;
    } else {
      if (pace == 'Relaxed')
        paceValue = 0.25;
      else if (pace == 'Steady')
        paceValue = 0.5;
      else if (pace == 'Accelerated')
        paceValue = 1.0;
      else if (pace == 'Intense')
        paceValue = 2.0;
    }

    double kgPerWeek = paceValue;
    if (!isMetric) {
      // Convert lbs/week to kg/week
      kgPerWeek = paceValue * 0.453592;
    }

    double weeks = 0;
    if (mainGoal == 'Lose weight') {
      weeks = (weight - targetWeight) / kgPerWeek;
    } else if (mainGoal == 'Gain weight') {
      weeks = (targetWeight - weight) / kgPerWeek;
    }
    if (weeks.isNaN || weeks.isInfinite || weeks < 0) weeks = 0;

    final now = DateTime.now();
    final goalDate = now.add(Duration(days: (weeks * 7).ceil()));
    final formatted =
        "${goalDate.day} ${_monthName(goalDate.month)} ${goalDate.year}";
    return formatted;
  }

  String _monthName(int month) {
    const months = [
      '',
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
    return months[month];
  }

  Widget _buildMacroSummaryStep() {
    _calculateMacros();

    String changeLabel = _macroSummary['change'] == 'increase'
        ? "Increase"
        : _macroSummary['change'] == 'decrease'
        ? "Decrease"
        : "Same";

    Color changeColor = _macroSummary['change'] == 'increase'
        ? Colors.green
        : _macroSummary['change'] == 'decrease'
        ? Colors.red
        : Colors.grey;

    String goalDate = _estimateGoalDate();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Title
          const Text(
            "Your Personalized Plan is Ready",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Here's how your plan was created based on your current data.",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Step 1
          _buildStepCard(
            stepNumber: 1,
            title: "Estimated Energy Expenditure",
            value: "${_macroSummary['previousCalories']} kcal",
            description:
                "Based on your current data, your estimated daily energy expenditure is approximately ${_macroSummary['previousCalories']} calories per day.",
          ),
          const SizedBox(height: 12),

          // Step 2
          _buildStepCard(
            stepNumber: 2,
            title: "Average Calorie Target",
            value: "${_macroSummary['newCalories']} kcal",
            description:
                "To achieve your weekly goal, your daily calorie target is set at ${_macroSummary['newCalories']} calories.",
          ),
          const SizedBox(height: 12),

          // Step 3
          _buildStepCard(
            stepNumber: 3,
            title: "Daily Macronutrient Breakdown",
            value: "",
            description:
                "Your daily targets are: "
                "${_macroSummary['carbG']}g carbohydrates, "
                "${_macroSummary['proteinG']}g protein, and "
                "${_macroSummary['fatG']}g fat.",
          ),
          const SizedBox(height: 12),
          // Bold values row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  children: [
                    const TextSpan(text: "Carbs: "),
                    TextSpan(
                      text: "${_macroSummary['carbG']}g",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  children: [
                    const TextSpan(text: "Protein: "),
                    TextSpan(
                      text: "${_macroSummary['proteinG']}g",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  children: [
                    const TextSpan(text: "Fat: "),
                    TextSpan(
                      text: "${_macroSummary['fatG']}g",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Estimated goal date section
          if (goalDate.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.yellow[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.yellow[700]!),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        children: [
                          const TextSpan(
                            text: "We'll help you reach your goal by ",
                          ),
                          TextSpan(
                            text: goalDate,
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(
                            text: ", If you stay consistent with your plan.",
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 30),

          // Commit Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "I’m Ready to Commit",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required int stepNumber,
    required String title,
    required String value,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.black,
                child: Text(
                  "$stepNumber",
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (value.isNotEmpty)
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
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
              const SizedBox(height: 40),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: const OutlineInputBorder(),
                  errorText: _emailError,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
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
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
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
                  border: const OutlineInputBorder(),
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
              if (_passwordError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _passwordError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _passwordError = null;
                      _emailError = null;
                    });
                    if (_formKey.currentState!.validate()) {
                      await _submit();
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
                  child: const Text('Finish', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      _buildDietStep(),
      _buildTrainingStep(),
      _buildProteinStep(),
      _buildMacroSummaryStep(),
      _buildAccountStep(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set My Plan'),
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _prevStep,
              )
            : null,
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildProgressBar(),
          Expanded(child: steps[_currentStep]),
        ],
      ),
    );
  }
}
