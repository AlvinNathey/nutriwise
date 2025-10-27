import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nutriwise/more_screen.dart';
import 'package:nutriwise/bottom_nav.dart';
import 'package:nutriwise/log_food.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'dart:ui';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  List<DateTime> weekDates = [];
  DateTime selectedDate = DateTime.now();
  DateTime weekStart = DateTime.now().subtract(
    Duration(days: DateTime.now().weekday - 1),
  );
  bool _isLogModalOpen = false;

  @override
  void initState() {
    super.initState();
    _generateWeekDates();
  }

  void _goToPreviousWeek() {
    setState(() {
      weekStart = weekStart.subtract(const Duration(days: 7));
      _generateWeekDates();
    });
  }

  void _goToNextWeek() {
    DateTime nextWeekStart = weekStart.add(const Duration(days: 7));
    DateTime today = DateTime.now();
    if (nextWeekStart.isAfter(
      today.subtract(Duration(days: today.weekday - 1)),
    ))
      return;
    setState(() {
      weekStart = nextWeekStart;
      _generateWeekDates();
    });
  }

  void _generateWeekDates() {
    weekDates.clear();
    for (int i = 0; i < 7; i++) {
      weekDates.add(weekStart.add(Duration(days: i)));
    }
    // If selectedDate is not in the new week, reset to first day
    if (!weekDates.any(
      (d) =>
          d.day == selectedDate.day &&
          d.month == selectedDate.month &&
          d.year == selectedDate.year,
    )) {
      selectedDate = weekDates[0];
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();
  }

  void _showWeightDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
            Center(
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser?.uid)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return SizedBox(
                          height: 120,
                          child: Center(child: Text('No weight data found.')),
                        );
                      }
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      double weight = data['weight']?.toDouble() ?? 0.0;
                      bool metric = data['isWeightMetric'] == true;
                      String weightStr = metric
                          ? '${weight.toStringAsFixed(1)} kg'
                          : '${weight.toStringAsFixed(1)} lbs';
                      final TextEditingController _weightController =
                          TextEditingController(
                            text: weight > 0 ? weight.toStringAsFixed(1) : '',
                          );
                      final _formKey = GlobalKey<FormState>();

                      // --- Macro/BMR utility functions (copied from profile.dart) ---
                      int calculateAge(DateTime dob) {
                        final now = DateTime.now();
                        int age = now.year - dob.year;
                        if (now.month < dob.month ||
                            (now.month == dob.month && now.day < dob.day)) {
                          age--;
                        }
                        return age;
                      }

                      double calculateBMR({
                        required String gender,
                        required double weight,
                        required double height,
                        required int age,
                        required bool isMetric,
                      }) {
                        double w = isMetric ? weight : weight * 0.453592;
                        double h;
                        if (isMetric) {
                          h = height;
                        } else {
                          h = height * 30.48;
                        }
                        if (gender == 'Male') {
                          return 88.362 +
                              (13.397 * w) +
                              (4.799 * h) -
                              (5.677 * age);
                        } else {
                          return 447.593 +
                              (9.247 * w) +
                              (3.098 * h) -
                              (4.330 * age);
                        }
                      }

                      double getActivityFactor(String trainingType) {
                        switch (trainingType) {
                          case 'Lifting':
                            return 1.55;
                          case 'Cardio':
                            return 1.375;
                          case 'Cardio and Lifting':
                            return 1.725;
                          case 'None or Related Activity':
                          default:
                            return 1.2;
                        }
                      }

                      double getGoalAdjustment(
                        String mainGoal,
                        String pace,
                        bool isMetric,
                      ) {
                        double perWeek = 0;
                        if (pace == 'Relaxed')
                          perWeek = isMetric ? 0.125 : 0.25;
                        if (pace == 'Steady') perWeek = isMetric ? 0.25 : 0.5;
                        if (pace == 'Accelerated')
                          perWeek = isMetric ? 0.5 : 1.0;
                        if (pace == 'Intense') perWeek = isMetric ? 1.0 : 2.0;
                        double kcalPerUnit = isMetric ? 7700 : 3500;
                        double kcalPerDay = perWeek * kcalPerUnit / 7.0;
                        if (mainGoal == 'Lose weight') return -kcalPerDay;
                        if (mainGoal == 'Gain weight') return kcalPerDay;
                        return 0;
                      }

                      Map<String, double> getMacroPercents(
                        String dietType,
                        String proteinIntake,
                      ) {
                        double carb = 0.5, protein = 0.25, fat = 0.25;
                        if (dietType == 'Low-fat') {
                          carb = 0.55;
                          protein = 0.25;
                          fat = 0.20;
                        } else if (dietType == 'Low-carb') {
                          carb = 0.25;
                          protein = 0.35;
                          fat = 0.40;
                        } else if (dietType == 'Keto') {
                          carb = 0.05;
                          protein = 0.20;
                          fat = 0.75;
                        }
                        if (proteinIntake == 'High Intake') protein += 0.05;
                        if (proteinIntake == 'Very High Intake')
                          protein += 0.10;
                        double sum = carb + protein + fat;
                        if (sum > 1.0) {
                          carb /= sum;
                          protein /= sum;
                          fat /= sum;
                        }
                        return {'carb': carb, 'protein': protein, 'fat': fat};
                      }
                      // --- End macro/BMR utility functions ---

                      return Stack(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
                              Icon(
                                Icons.monitor_weight,
                                color: Colors.green,
                                size: 40,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "Current Weight",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                weightStr,
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                metric ? 'Unit: kg' : 'Unit: lbs',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Form(
                                key: _formKey,
                                child: TextFormField(
                                  controller: _weightController,
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: metric
                                        ? 'Update Weight (kg)'
                                        : 'Update Weight (lbs)',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  validator: (v) {
                                    double? val = double.tryParse(v ?? '');
                                    if (val == null || val < 20 || val > 500)
                                      return 'Enter realistic weight';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: () async {
                                    if (_formKey.currentState?.validate() ??
                                        false) {
                                      double? newWeight = double.tryParse(
                                        _weightController.text,
                                      );
                                      if (newWeight != null) {
                                        // --- Recalculate macros/calories ---
                                        final gender = data['gender'] ?? 'Male';
                                        final dobStr = data['dateOfBirth'];
                                        final dob = dobStr != null
                                            ? DateTime.tryParse(dobStr)
                                            : null;
                                        final age = dob != null
                                            ? calculateAge(dob)
                                            : 30;
                                        final height = data['height'] != null
                                            ? double.tryParse(
                                                    data['height'].toString(),
                                                  ) ??
                                                  170
                                            : 170;
                                        // Use height unit setting for BMR conversion
                                        final isMetric =
                                            data['isMetric'] == true;
                                        final trainingType =
                                            data['trainingType'] ??
                                            'None or Related Activity';
                                        final dietType =
                                            data['dietType'] ?? 'Balanced';
                                        final proteinIntake =
                                            data['proteinIntake'] ??
                                            'Moderate Intake';
                                        final mainGoal =
                                            data['mainGoal'] ??
                                            'Maintain weight';
                                        final pace = data['pace'] ?? 'Steady';

                                        double bmr = calculateBMR(
                                          gender: gender,
                                          weight: newWeight,
                                          height: height.toDouble(),
                                          age: age,
                                          isMetric: isMetric,
                                        );
                                        double activity = getActivityFactor(
                                          trainingType,
                                        );
                                        double tdee = bmr * activity;
                                        double goalAdj = getGoalAdjustment(
                                          mainGoal,
                                          pace,
                                          isMetric,
                                        );
                                        double calories = tdee + goalAdj;

                                        final macroPercents = getMacroPercents(
                                          dietType,
                                          proteinIntake,
                                        );
                                        int carbG =
                                            (calories *
                                                    macroPercents['carb']! /
                                                    4)
                                                .round();
                                        int proteinG =
                                            (calories *
                                                    macroPercents['protein']! /
                                                    4)
                                                .round();
                                        int fatG =
                                            (calories *
                                                    macroPercents['fat']! /
                                                    9)
                                                .round();

                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(
                                              FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.uid,
                                            )
                                            .update({
                                              'weight': double.parse(
                                                newWeight.toStringAsFixed(2),
                                              ),
                                              'calories': calories.round(),
                                              'carbG': carbG,
                                              'proteinG': proteinG,
                                              'fatG': fatG,
                                            });
                                        Navigator.of(ctx).pop();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Weight and macros updated!',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: const Text(
                                    'Save',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 28,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                              tooltip: 'Close',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _getDayAbbreviation(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  bool _isSelectedDate(DateTime date) {
    return date.day == selectedDate.day &&
        date.month == selectedDate.month &&
        date.year == selectedDate.year;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData ||
            !snapshot.data!.exists ||
            snapshot.data!.data() == null) {
          return const Scaffold(
            body: Center(child: Text('No user data found.')),
          );
        }
        final userDoc = snapshot.data!.data()!;
        // Use local variables instead of setState
        String userName = userDoc['name'] ?? 'User';
        int dailyGoal = userDoc['calories']?.round() ?? 0;
        int carbsTarget = userDoc['carbG']?.round() ?? 0;
        int proteinTarget = userDoc['proteinG']?.round() ?? 0;
        int fatTarget = userDoc['fatG']?.round() ?? 0;
        // double userWeight = userDoc['weight']?.toDouble() ?? 0.0;
        // bool isWeightMetric = userDoc['isWeightMetric'] == true;
        // Static dummy data for now
        int caloriesConsumed = 300;
        int carbsConsumed = 50;
        int proteinConsumed = 45;
        int fatConsumed = 30;

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: Text('Hello $userName'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _showWeightDialog,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.monitor_weight, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            "Today's weight?",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: const BoxDecoration(color: Colors.green),
                    child: Column(
                      children: [
                        // Week navigation row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_left,
                                color: Colors.white,
                              ),
                              onPressed: _goToPreviousWeek,
                            ),
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: weekDates.map((date) {
                                  bool isSelected = _isSelectedDate(date);
                                  const months = [
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
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          selectedDate = date;
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _getDayAbbreviation(date),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.white70,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.transparent,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color:
                                                      date.day ==
                                                              DateTime.now()
                                                                  .day &&
                                                          date.month ==
                                                              DateTime.now()
                                                                  .month &&
                                                          date.year ==
                                                              DateTime.now()
                                                                  .year
                                                      ? Colors.yellow.shade700
                                                      : Colors.transparent,
                                                  width: 2,
                                                ),
                                              ),
                                              child: SizedBox(
                                                width: 36,
                                                height: 36,
                                                child: Center(
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      if (isSelected)
                                                        Text(
                                                          months[date.month - 1],
                                                          style: const TextStyle(
                                                            fontSize: 8, // reduced from 9
                                                            color: Colors.green,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      if (isSelected)
                                                        const SizedBox(height: 1),
                                                      Text(
                                                        '${date.day}',
                                                        style: TextStyle(
                                                          fontSize: 13, // reduced from 14
                                                          fontWeight: FontWeight.bold,
                                                          color: isSelected
                                                              ? Colors.green
                                                              : Colors.white,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_right,
                                color: Colors.white,
                              ),
                              onPressed: _goToNextWeek,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Food Diary",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.08),
                                  spreadRadius: 1,
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Daily Goal',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '$dailyGoal cal',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  height: 120,
                                  width: 120,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CustomPaint(
                                        size: const Size(120, 120),
                                        painter: SemiCircleProgressPainter(
                                          progress: dailyGoal > 0
                                              ? caloriesConsumed / dailyGoal
                                              : 0,
                                          backgroundColor: Colors.grey[200]!,
                                          progressColor: const Color.fromARGB(
                                            255,
                                            47,
                                            222,
                                            38,
                                          ),
                                          strokeWidth: 8,
                                        ),
                                      ),
                                      Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              dailyGoal > 0
                                                  ? '${dailyGoal - caloriesConsumed}'
                                                  : '-',
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            Text(
                                              'kcal left',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildMacroCircle(
                                      'Carbs',
                                      carbsConsumed,
                                      carbsTarget,
                                      Colors.orange,
                                    ),
                                    _buildMacroCircle(
                                      'Protein',
                                      proteinConsumed,
                                      proteinTarget,
                                      Colors.red,
                                    ),
                                    _buildMacroCircle(
                                      'Fat',
                                      fatConsumed,
                                      fatTarget,
                                      Colors.blue,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            "Recent Meals",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.08),
                                  spreadRadius: 1,
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Text(
                                      'Rice and Chicken',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Spacer(),
                                    Text(
                                      '300 kcal',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.restaurant,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Lunch',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _buildMacroChip(
                                        'Carbs',
                                        '50g',
                                        Colors.orange,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildMacroChip(
                                        'Protein',
                                        '45g',
                                        Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      _buildMacroChip(
                                        'Fat',
                                        '30g',
                                        Colors.blue,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.green,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: Image.asset(
                                        'assets/rice-chicken.jpg',
                                        width: 250,
                                        height: 160,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  width: 220,
                                                  height: 160,
                                                  color: Colors.grey[200],
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                    size: 48,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                      ),
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
                ],
              ),
              Container(),
              const MoreScreen(),
            ],
          ),
          bottomNavigationBar: _isLogModalOpen
              ? null
              : BottomNav(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    if (index == 1) return;
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  onLogPressed: _openLogFoodModal,
                ),
        );
      },
    );
  }

  Future<void> _openLogFoodModal() async {
    setState(() {
      _isLogModalOpen = true;
    });
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height,
            ),
            child: const LogFoodModal(),
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() {
      _isLogModalOpen = false;
    });
  }

  Widget _buildMacroCircle(String name, int current, int target, Color color) {
    double progress = target > 0 ? current / target : 0;
    int left = target - current;
    return Column(
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 50,
          height: 50,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(50, 50),
                painter: SemiCircleProgressPainter(
                  progress: progress,
                  backgroundColor: Colors.grey[200]!,
                  progressColor: color,
                  strokeWidth: 4,
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$current',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '/${target}g',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${left}g left',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildMacroChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }
}

class SemiCircleProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  SemiCircleProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;

    // Start from top (-π/2) and go almost full circle (2π - small gap)
    final startAngle = -math.pi / 2; // Start from top
    final sweepAngle =
        2 * math.pi -
        (math.pi / 12); // Almost full circle with small gap at bottom

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw background arc (almost full circle)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Draw progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
