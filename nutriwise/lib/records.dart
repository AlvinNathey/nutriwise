import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:nutriwise/services/auth_services.dart';

// Main Records Page
class RecordsPage extends StatefulWidget {
  const RecordsPage({Key? key}) : super(key: key);

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  int _selectedTab = 0;

  // Track user's account creation date
  DateTime? _accountCreated;
  // Map: day -> calories
  Map<int, int> _calorieData = {};
  // Map: mealType -> count for the month
  Map<String, int> _mealTypeCounts = {
    'Breakfast': 0,
    'Lunch': 0,
    'Dinner': 0,
    'Snack': 0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTab = _tabController.index;
      });
    });
    _fetchAccountCreatedAndMeals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAccountCreatedAndMeals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch account creation date
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final createdAt = userDoc.data()?['createdAt'];
    if (createdAt != null && createdAt is Timestamp) {
      setState(() {
        _accountCreated = createdAt.toDate();
      });
    } else {
      setState(() {
        _accountCreated = DateTime.now();
      });
    }

    await _fetchMealsForMonth();
  }

  Future<void> _fetchMealsForMonth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    // Reset data
    Map<int, int> calorieData = {};
    Map<String, int> mealTypeCounts = {
      'Breakfast': 0,
      'Lunch': 0,
      'Dinner': 0,
      'Snack': 0,
    };

    // Query meals for the month
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThan: Timestamp.fromDate(endDate))
        .get();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final calories = (data['calories'] ?? 0).round();
      final mealType = (data['mealType'] ?? 'Meal').toString();

      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        final day = date.day;
        calorieData[day] = ((calorieData[day] ?? 0) + calories).toInt();
        if (mealTypeCounts.containsKey(mealType)) {
          mealTypeCounts[mealType] = mealTypeCounts[mealType]! + 1;
        }
      }
    }

    setState(() {
      _calorieData = calorieData;
      _mealTypeCounts = mealTypeCounts;
    });
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _fetchMealsForMonth();
  }

  void _nextMonth() {
    final now = DateTime.now();
    final nextMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (nextMonth.isBefore(DateTime(now.year, now.month + 1))) {
      setState(() {
        _selectedMonth = nextMonth;
      });
      _fetchMealsForMonth();
    }
  }

  bool _isFutureMonth() {
    final now = DateTime.now();
    return _selectedMonth.year > now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month > now.month);
  }

  bool _isBeforeAccountCreated() {
    if (_accountCreated == null) return false;
    return _selectedMonth.year < _accountCreated!.year ||
        (_selectedMonth.year == _accountCreated!.year && _selectedMonth.month < _accountCreated!.month);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Report',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.green, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.green,
              indicatorWeight: 3,
              labelColor: Colors.green,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              tabs: const [
                Tab(text: 'RECORD'),
                Tab(text: 'NUTRIENT'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRecordView(),
                const NutrientsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordView() {
    final hasData = _calorieData.isNotEmpty || _mealTypeCounts.values.any((v) => v > 0);

    return Column(
      children: [
        const SizedBox(height: 30),
        // Month Selector
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _isBeforeAccountCreated() ? null : _previousMonth,
              color: _isBeforeAccountCreated() ? Colors.grey : Colors.black,
            ),
            const SizedBox(width: 20),
            Text(
              '${_selectedMonth.year}.${_selectedMonth.month.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: Icon(
                Icons.chevron_right,
                color: _isFutureMonth() ? Colors.grey : Colors.black,
              ),
              onPressed: _isFutureMonth() ? null : _nextMonth,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Show counters only if there is data
        if (hasData)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMealCounter('Breakfast', _mealTypeCounts['Breakfast'] ?? 0, Colors.orange),
              _buildMealCounter('Lunch', _mealTypeCounts['Lunch'] ?? 0, Colors.teal),
              _buildMealCounter('Dinner', _mealTypeCounts['Dinner'] ?? 0, Colors.purple),
              _buildMealCounter('Snack', _mealTypeCounts['Snack'] ?? 0, Colors.blue),
            ],
          ),
        if (hasData) const SizedBox(height: 30),
        // Show note if no data for this month
        if (!hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              "No records for this month",
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ),
        // Calendar (always show, even if no data)
        Expanded(
          child: _buildCalendarWithCalories(hasData ? _calorieData : {}),
        ),
      ],
    );
  }

  Widget _buildMealCounter(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarWithCalories(Map<int, int> calorieData) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday

    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Weekday headers
          Row(
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((day) {
              final isSunday = day == 'Sun';
              final isSaturday = day == 'Sat';
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      color: isSunday ? Colors.red : (isSaturday ? Colors.green : Colors.green[800]),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Calendar Grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.8,
              ),
              itemCount: 42, // 6 weeks max
              itemBuilder: (context, index) {
                final dayNumber = index - firstWeekday + 1;
                final isCurrentMonth = dayNumber > 0 && dayNumber <= daysInMonth;
                final date = DateTime(_selectedMonth.year, _selectedMonth.month, dayNumber);
                final isFuture = date.isAfter(now);
                final isToday = date.year == now.year &&
                               date.month == now.month &&
                               date.day == now.day;
                final isSunday = index % 7 == 0;
                final isSaturday = index % 7 == 6;

                if (!isCurrentMonth) {
                  return Container();
                }

                return Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: isToday ? Border.all(color: Colors.blue, width: 2) : null,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Text(
                          dayNumber.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: isFuture
                                ? Colors.grey[300]
                                : (isSunday ? Colors.red : (isSaturday ? Colors.green : Colors.black)),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Only show calorie dot if there is data for the day
                      if (calorieData.containsKey(dayNumber) && !isFuture)
                        Positioned(
                          bottom: 4,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                calorieData[dayNumber].toString(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isFuture)
                        Positioned.fill(
                          child: Container(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Nutrients Page with 4 sections
class NutrientsPage extends StatefulWidget {
  const NutrientsPage({Key? key}) : super(key: key);

  @override
  State<NutrientsPage> createState() => _NutrientsPageState();
}

class _NutrientsPageState extends State<NutrientsPage> {
  List<Map<String, dynamic>> _weightEntries = [];
  bool _loading = true;
  final AuthService _authService = AuthService();

  // Intake trend state
  int _selectedWeekOffset = 0; // 0 = current week, -1 = previous, etc.
  Map<int, int> _weekCalorieIntake = {}; // dayOfWeek (1=Mon) -> calories
  int? _targetCalories;

  // Meal trend state
  int _selectedMealWeekOffset = 0;
  Map<String, int> _weekMealCounts = {
    'Breakfast': 0,
    'Lunch': 0,
    'Dinner': 0,
    'Snack': 0,
  };
  Map<String, List<Map<String, dynamic>>> _weekMealMacros = {
    'Breakfast': [],
    'Lunch': [],
    'Dinner': [],
    'Snack': [],
  };

  // Add state for nutrition trend week navigation and macro data
  int _selectedNutritionWeekOffset = 0;
  Map<String, double> _nutritionMacros = {
    'Carbs': 0,
    'Protein': 0,
    'Fat': 0,
  };

  @override
  void initState() {
    super.initState();
    _fetchWeightEntries();
    _fetchTargetCalories();
    _fetchIntakeForWeek();
    _fetchMealTrendForWeek();
    _fetchNutritionMacrosForWeek();
  }

  Future<void> _fetchTargetCalories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    setState(() {
      _targetCalories = userDoc.data()?['calories']?.round();
    });
  }

  Future<void> _fetchIntakeForWeek() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _weekCalorieIntake = {};
      });
      return;
    }
    // Calculate week range
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: 7 * _selectedWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    final startDate = DateTime(monday.year, monday.month, monday.day);
    final endDate = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);

    // Query meals for the week
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    Map<int, int> weekIntake = {};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final calories = (data['calories'] ?? 0).round();
      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        final weekday = date.weekday; // 1=Mon, 7=Sun
        weekIntake[weekday] = ((weekIntake[weekday] ?? 0) + calories).toInt();
      }
    }
    setState(() {
      _weekCalorieIntake = weekIntake;
    });
  }

  Future<void> _fetchMealTrendForWeek() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _weekMealCounts = {
          'Breakfast': 0,
          'Lunch': 0,
          'Dinner': 0,
          'Snack': 0,
        };
        _weekMealMacros = {
          'Breakfast': [],
          'Lunch': [],
          'Dinner': [],
          'Snack': [],
        };
      });
      return;
    }
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: 7 * _selectedMealWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    final startDate = DateTime(monday.year, monday.month, monday.day);
    final endDate = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    Map<String, int> mealCounts = {
      'Breakfast': 0,
      'Lunch': 0,
      'Dinner': 0,
      'Snack': 0,
    };
    Map<String, List<Map<String, dynamic>>> mealMacros = {
      'Breakfast': [],
      'Lunch': [],
      'Dinner': [],
      'Snack': [],
    };

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final mealType = (data['mealType'] ?? 'Meal').toString();
      if (mealCounts.containsKey(mealType)) {
        mealCounts[mealType] = mealCounts[mealType]! + 1;
        mealMacros[mealType]!.add(data);
      }
    }

    setState(() {
      _weekMealCounts = mealCounts;
      _weekMealMacros = mealMacros;
    });
  }

  Future<void> _fetchNutritionMacrosForWeek() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _nutritionMacros = {'Carbs': 0, 'Protein': 0, 'Fat': 0};
      });
      return;
    }
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: 7 * _selectedNutritionWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    final startDate = DateTime(monday.year, monday.month, monday.day);
    final endDate = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    double totalCarbs = 0;
    double totalProtein = 0;
    double totalFat = 0;
    for (var doc in snapshot.docs) {
      final data = doc.data();
      totalCarbs += (data['carbohydrate'] ?? data['carbs'] ?? 0).toDouble();
      totalProtein += (data['protein'] ?? 0).toDouble();
      totalFat += (data['fat'] ?? 0).toDouble();
    }
    setState(() {
      _nutritionMacros = {
        'Carbs': totalCarbs,
        'Protein': totalProtein,
        'Fat': totalFat,
      };
    });
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekOffset -= 1;
    });
    _fetchIntakeForWeek();
  }

  void _nextWeek() {
    if (_selectedWeekOffset < 0) {
      setState(() {
        _selectedWeekOffset += 1;
      });
      _fetchIntakeForWeek();
    }
  }

  void _previousMealWeek() {
    setState(() {
      _selectedMealWeekOffset -= 1;
    });
    _fetchMealTrendForWeek();
  }

  void _nextMealWeek() {
    if (_selectedMealWeekOffset < 0) {
      setState(() {
        _selectedMealWeekOffset += 1;
      });
      _fetchMealTrendForWeek();
    }
  }

  void _previousNutritionWeek() {
    setState(() {
      _selectedNutritionWeekOffset -= 1;
    });
    _fetchNutritionMacrosForWeek();
  }

  void _nextNutritionWeek() {
    if (_selectedNutritionWeekOffset < 0) {
      setState(() {
        _selectedNutritionWeekOffset += 1;
      });
      _fetchNutritionMacrosForWeek();
    }
  }

  Future<void> _fetchWeightEntries() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _weightEntries = [];
        _loading = false;
      });
      return;
    }
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('weight_entries')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfMonth))
        .orderBy('timestamp', descending: false)
        .get();

    setState(() {
      _weightEntries = snapshot.docs.map((doc) => doc.data()).toList();
      _loading = false;
    });
  }

  Future<void> _showUpdateWeightDialog(BuildContext context) async {
    if (_weightEntries.isEmpty) return;
    final latest = _weightEntries.last;
    double weight = (latest['weight'] ?? 0.0).toDouble();
    bool metric = latest['isMetric'] == true;
    final TextEditingController _weightController =
        TextEditingController(text: weight > 0 ? weight.toStringAsFixed(1) : '');
    final _formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.monitor_weight, color: Colors.green, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    "Update Weight",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    metric
                        ? '${weight.toStringAsFixed(1)} kg'
                        : '${weight.toStringAsFixed(1)} lbs',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    metric ? 'Unit: kg' : 'Unit: lbs',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _weightController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: metric ? 'Update Weight (kg)' : 'Update Weight (lbs)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (v) {
                      double? val = double.tryParse(v ?? '');
                      if (val == null || val < 20 || val > 500)
                        return 'Enter realistic weight';
                      return null;
                    },
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        if (_formKey.currentState?.validate() ?? false) {
                          double? newWeight = double.tryParse(_weightController.text);
                          if (newWeight != null) {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user != null) {
                              // Update user profile weight
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .update({
                                'weight': double.parse(newWeight.toStringAsFixed(2)),
                              });
                              // Save weight entry for trend
                              await _authService.saveWeightEntry(
                                user.uid,
                                double.parse(newWeight.toStringAsFixed(2)),
                                isMetric: metric,
                              );
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Weight updated!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              // Refresh weight entries
                              await _fetchWeightEntries();
                            }
                          }
                        }
                      },
                      child: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildWeightTrend(context),
        const SizedBox(height: 24),
        _buildIntakeTrend(),
        const SizedBox(height: 24),
        _buildMealTrend(),
        const SizedBox(height: 24),
        _buildNutritionTrend(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWeightTrend(BuildContext context) {
    if (_loading) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_weightEntries.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No weight data for this month.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    // Prepare chart data: group entries by month, use the first entry for each month
    Map<String, double> monthWeightMap = {};
    for (var entry in _weightEntries) {
      final ts = entry['timestamp'];
      if (ts is Timestamp) {
        final date = ts.toDate();
        final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        if (!monthWeightMap.containsKey(monthKey)) {
          monthWeightMap[monthKey] = (entry['weight'] ?? 0).toDouble();
        }
      }
    }
    // Sort months chronologically
    final sortedMonths = monthWeightMap.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    // Prepare FlSpot list: x = index, y = weight
    List<FlSpot> spots = [];
    for (int i = 0; i < sortedMonths.length; i++) {
      spots.add(FlSpot(i.toDouble(), monthWeightMap[sortedMonths[i]]!));
    }

    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 1;
    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 1;
    double latestWeight = spots.isNotEmpty ? spots.last.y : 0;
    String unit = (_weightEntries.last['isMetric'] == true) ? 'kg' : 'lbs';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Weight Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Text(
                  '${latestWeight.toStringAsFixed(1)} $unit',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[400],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey[300]!,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int idx = value.toInt();
                          if (idx >= 0 && idx < sortedMonths.length) {
                            final parts = sortedMonths[idx].split('-');
                            final year = parts[0];
                            final month = parts[1];
                            return Text(
                              '$month/$year',
                              style: const TextStyle(fontSize: 10),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: sortedMonths.length > 0 ? (sortedMonths.length - 1).toDouble() : 0,
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _showUpdateWeightDialog(context);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Update Weight'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntakeTrend() {
    // Days of week
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // Prepare bar chart data for the selected week
    List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < 7; i++) {
      int weekday = i + 1; // 1=Mon, 7=Sun
      double actual = (_weekCalorieIntake[weekday] ?? 0).toDouble();
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: actual,
              color: Colors.green,
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    // Get target calories
    double target = (_targetCalories ?? 0).toDouble();

    // Week range label
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: 7 * _selectedWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    String weekLabel = "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";

    bool hasData = _weekCalorieIntake.values.any((v) => v > 0);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Intake Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousWeek,
                    ),
                    Text(
                      weekLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        color: _selectedWeekOffset < 0 ? Colors.black : Colors.grey,
                      ),
                      onPressed: _selectedWeekOffset < 0 ? _nextWeek : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: hasData
                  ? BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: (target > 0)
                            ? [target, ...barGroups.map((g) => g.barRods.first.toY)].reduce((a, b) => a > b ? a : b) + 500
                            : 3000,
                        barGroups: barGroups,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                int idx = value.toInt();
                                if (idx >= 0 && idx < days.length) {
                                  return Text(
                                    days[idx],
                                    style: const TextStyle(fontSize: 10),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: target > 0
                            ? ExtraLinesData(horizontalLines: [
                                HorizontalLine(
                                  y: target,
                                  color: Colors.red,
                                  strokeWidth: 2,
                                  dashArray: [8, 4],
                                  label: HorizontalLineLabel(
                                    show: true,
                                    alignment: Alignment.topRight,
                                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                                    labelResolver: (_) => 'Target: ${target.toInt()}',
                                  ),
                                ),
                              ])
                            : ExtraLinesData(),
                      ),
                    )
                  : Center(
                      child: Text(
                        'No intake data for this week.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(Colors.green, 'Actual'),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.red, 'Target'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  BarChartGroupData _makeBarGroup(int x, double actualValue, double targetValue) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: actualValue,
          color: Colors.green,
          width: 16,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMealTrend() {
    // Prepare pie chart data for the selected week
    final totalMeals = _weekMealCounts.values.fold(0, (a, b) => a + b);
    final List<PieChartSectionData> sections = [
      PieChartSectionData(
        color: Colors.orange,
        value: totalMeals > 0 ? (_weekMealCounts['Breakfast']! * 100 / totalMeals) : 0,
        title: totalMeals > 0 ? '${(_weekMealCounts['Breakfast']! * 100 / totalMeals).toStringAsFixed(0)}%' : '',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      PieChartSectionData(
        color: Colors.teal,
        value: totalMeals > 0 ? (_weekMealCounts['Lunch']! * 100 / totalMeals) : 0,
        title: totalMeals > 0 ? '${(_weekMealCounts['Lunch']! * 100 / totalMeals).toStringAsFixed(0)}%' : '',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      PieChartSectionData(
        color: Colors.green,
        value: totalMeals > 0 ? (_weekMealCounts['Dinner']! * 100 / totalMeals) : 0,
        title: totalMeals > 0 ? '${(_weekMealCounts['Dinner']! * 100 / totalMeals).toStringAsFixed(0)}%' : '',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      PieChartSectionData(
        color: Colors.blue,
        value: totalMeals > 0 ? (_weekMealCounts['Snack']! * 100 / totalMeals) : 0,
        title: totalMeals > 0 ? '${(_weekMealCounts['Snack']! * 100 / totalMeals).toStringAsFixed(0)}%' : '',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    ];

    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: 7 * _selectedMealWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    String weekLabel = "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Meal Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousMealWeek,
                    ),
                    Text(
                      weekLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        color: _selectedMealWeekOffset < 0 ? Colors.black : Colors.grey,
                      ),
                      onPressed: _selectedMealWeekOffset < 0 ? _nextMealWeek : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: totalMeals > 0
                  ? PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 50,
                        sectionsSpace: 2,
                      ),
                    )
                  : Center(
                      child: Text(
                        'No meal data for this week.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMealLegend(Colors.orange, 'Breakfast'),
                _buildMealLegend(Colors.teal, 'Lunch'),
                _buildMealLegend(Colors.green, 'Dinner'),
                _buildMealLegend(Colors.blue, 'Snack'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: totalMeals > 0
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MealDetailPage(
                              weekLabel: weekLabel,
                              mealMacros: _weekMealMacros,
                            ),
                          ),
                        );
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Show Detail'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealLegend(Color color, String label) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildNutritionTrend() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: 7 * _selectedNutritionWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    String weekLabel = "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";

    final totalMacros = _nutritionMacros.values.reduce((a, b) => a + b);
    final List<PieChartSectionData> sections = [
      PieChartSectionData(
        color: Colors.green,
        value: totalMacros > 0 ? _nutritionMacros['Carbs']! : 0,
        title: totalMacros > 0 ? 'Carbs' : '',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      PieChartSectionData(
        color: Colors.blue,
        value: totalMacros > 0 ? _nutritionMacros['Protein']! : 0,
        title: totalMacros > 0 ? 'Protein' : '',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      PieChartSectionData(
        color: Colors.orange,
        value: totalMacros > 0 ? _nutritionMacros['Fat']! : 0,
        title: totalMacros > 0 ? 'Fat' : '',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    ];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nutrition Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousNutritionWeek,
                    ),
                    Text(
                      weekLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        color: _selectedNutritionWeekOffset < 0 ? Colors.black : Colors.grey,
                      ),
                      onPressed: _selectedNutritionWeekOffset < 0 ? _nextNutritionWeek : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: totalMacros > 0
                  ? PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 50,
                        sectionsSpace: 2,
                      ),
                    )
                  : Center(
                      child: Text(
                        'No nutrition data for this week.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMealLegend(Colors.green, 'Carbs'),
                _buildMealLegend(Colors.blue, 'Protein'),
                _buildMealLegend(Colors.orange, 'Fat'),
              ],
            ),
            // Removed Show Detail button
          ],
        ),
      ),
    );
  }
}

// New MealDetailPage to show macro distribution per meal type
class MealDetailPage extends StatelessWidget {
  final String weekLabel;
  final Map<String, List<Map<String, dynamic>>> mealMacros;

  const MealDetailPage({
    Key? key,
    required this.weekLabel,
    required this.mealMacros,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Meal Details ($weekLabel)',
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: mealTypes.length,
        itemBuilder: (context, idx) {
          final type = mealTypes[idx];
          final meals = mealMacros[type] ?? [];
          if (meals.isEmpty) {
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No $type records for this week.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
            );
          }
          double totalCalories = 0;
          double totalProtein = 0;
          double totalCarbs = 0;
          double totalFat = 0;
          for (var macro in meals) {
            totalCalories += (macro['calories'] ?? 0).toDouble();
            totalProtein += (macro['protein'] ?? 0).toDouble();
            totalCarbs += (macro['carbohydrate'] ?? macro['carbs'] ?? 0).toDouble();
            totalFat += (macro['fat'] ?? 0).toDouble();
          }
          final totalMacros = totalProtein + totalCarbs + totalFat;
          final List<PieChartSectionData> macroSections = [
            PieChartSectionData(
              color: Colors.green,
              value: totalMacros > 0 ? totalCarbs : 0,
              title: totalMacros > 0 ? 'Carbs' : '',
              radius: 40,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            PieChartSectionData(
              color: Colors.blue,
              value: totalMacros > 0 ? totalProtein : 0,
              title: totalMacros > 0 ? 'Protein' : '',
              radius: 40,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            PieChartSectionData(
              color: Colors.orange,
              value: totalMacros > 0 ? totalFat : 0,
              title: totalMacros > 0 ? 'Fat' : '',
              radius: 40,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 120,
                    child: totalMacros > 0
                        ? PieChart(
                            PieChartData(
                              sections: macroSections,
                              centerSpaceRadius: 30,
                              sectionsSpace: 2,
                            ),
                          )
                        : Center(
                            child: Text(
                              'No macro data for $type.',
                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _buildMacroColumn('Calories', totalCalories, Colors.red)),
                      Expanded(child: _buildMacroColumn('Protein', totalProtein, Colors.blue)),
                      Expanded(child: _buildMacroColumn('Carbs', totalCarbs, Colors.green)),
                      Expanded(child: _buildMacroColumn('Fat', totalFat, Colors.orange)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMacroColumn(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              value.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}