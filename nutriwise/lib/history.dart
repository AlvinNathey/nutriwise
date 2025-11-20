import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutriwise/food/edit_food_log.dart'; // Import the new edit page

class FoodLog {
  final String id;
  final String mealType;
  final String time;
  final String foodName;
  final int calories;
  final DateTime createdAt;
  final String? imageUrl; // NEW: For meal image
  final bool isMeal; // NEW: Distinguish meal vs barcode
  final List<Map<String, dynamic>>? foodItems; // NEW: For meal foods

  FoodLog({
    required this.id,
    required this.mealType,
    required this.time,
    required this.foodName,
    required this.calories,
    required this.createdAt,
    this.imageUrl,
    this.isMeal = false,
    this.foodItems,
  });
}

// Fetch barcode logs (old)
Future<List<FoodLog>> fetchLoggedFoods() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('barcodes')
      .orderBy('createdAt', descending: true)
      .get();

  return snapshot.docs.map((doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    DateTime date = DateTime.now();
    String timeStr = '';
    if (createdAt is Timestamp) {
      date = createdAt.toDate();
      final hour = date.hour > 12 ? date.hour - 12 : date.hour;
      final ampm = date.hour >= 12 ? 'pm' : 'am';
      timeStr = '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $ampm';
    }
    return FoodLog(
      id: doc.id,
      mealType: (data['mealType'] ?? 'Meal').toString(),
      time: timeStr,
      foodName: (data['foodName'] ?? data['name'] ?? 'Unknown').toString(),
      calories: (data['calories'] ?? 0).round(),
      createdAt: date,
      isMeal: false,
    );
  }).toList();
}

// NEW: Fetch meals from 'meals' subcollection
Future<List<FoodLog>> fetchMealLogs() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('meals')
      .orderBy('createdAt', descending: true)
      .get();

  return snapshot.docs.map((doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    DateTime date = DateTime.now();
    String timeStr = '';
    if (createdAt is Timestamp) {
      date = createdAt.toDate();
      timeStr = (data['time'] ?? '').toString();
    }
    // Show first food name or "Meal"
    String foodName = "Meal";
    if (data['foodItems'] is List && (data['foodItems'] as List).isNotEmpty) {
      foodName = (data['foodItems'][0]['foodName'] ?? "Meal").toString();
    }
    return FoodLog(
      id: doc.id,
      mealType: (data['mealType'] ?? 'Meal').toString(),
      time: timeStr,
      foodName: foodName,
      calories: (data['totalCalories'] ?? 0).round(),
      createdAt: date,
      imageUrl: data['originalImageUrl'] as String?,
      isMeal: true,
      foodItems: (data['foodItems'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }).toList();
}

// Helper to group logs by timeline section (barcode + meal logs)
Map<String, List<FoodLog>> groupLogsByTimeline(List<FoodLog> logs) {
  final now = DateTime.now();
  Map<String, List<FoodLog>> grouped = {};

  for (var log in logs) {
    final logDate = DateTime(log.createdAt.year, log.createdAt.month, log.createdAt.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(logDate).inDays;

    String section;
    if (diff == 0) {
      section = 'Today';
    } else if (diff == 1) {
      section = 'Yesterday';
    } else if (diff == 2) {
      section = '2 days ago';
    } else if (diff == 3) {
      section = '3 days ago';
    } else if (diff < 7) {
      section = '${diff} days ago';
    } else {
      section = 'Last week';
    }

    grouped.putIfAbsent(section, () => []);
    grouped[section]!.add(log);
  }

  // Sort sections: Today, Yesterday, 2 days ago, 3 days ago, ..., Last week
  final orderedSections = ['Today', 'Yesterday', '2 days ago', '3 days ago', 'Last week'];
  Map<String, List<FoodLog>> ordered = {};
  for (var sec in orderedSections) {
    if (grouped.containsKey(sec)) ordered[sec] = grouped[sec]!;
  }
  // Add any other sections (e.g., "4 days ago") not in orderedSections
  for (var sec in grouped.keys) {
    if (!orderedSections.contains(sec)) ordered[sec] = grouped[sec]!;
  }
  return ordered;
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<FoodLog>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = _fetchAllLogs();
  }

  void _refreshLogs() {
    setState(() {
      _logsFuture = _fetchAllLogs();
    });
  }

  // NEW: Fetch both barcode logs and meal logs, combine and sort
  Future<List<FoodLog>> _fetchAllLogs() async {
    final barcodeLogs = await fetchLoggedFoods();
    final mealLogs = await fetchMealLogs();
    final allLogs = [...barcodeLogs, ...mealLogs];
    allLogs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return allLogs;
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
          'Timeline',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<FoodLog>>(
        future: _logsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No foods logged yet.'));
          }
          final logs = snapshot.data!;
          final grouped = groupLogsByTimeline(logs);
          final sectionKeys = grouped.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sectionKeys.length,
            itemBuilder: (context, idx) {
              final key = sectionKeys[idx];
              final meals = grouped[key]!;
              final isFirst = idx == 0;
              final isLast = idx == sectionKeys.length - 1;
              return _buildDaySection(key, meals, isFirst: isFirst, isLast: isLast, context: context);
            },
          );
        },
      ),
    );
  }

  Widget _buildDaySection(String day, List<FoodLog> meals, {bool isFirst = false, bool isLast = false, required BuildContext context}) {
    return Stack(
      children: [
        // Draw line above the dot unless it's the first section
        if (!isFirst)
          Positioned(
            left: 3.5,
            top: 0,
            child: Container(
              width: 1,
              height: 24,
              color: Colors.green.withOpacity(0.3),
            ),
          ),
        // Draw line below the dot unless it's the last section
        if (!isLast)
          Positioned(
            left: 3.5,
            top: 32,
            bottom: 0,
            child: Container(
              width: 1,
              color: Colors.green.withOpacity(0.3),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isFirst) const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  day,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                children: meals.map((meal) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: meal.isMeal
                      ? _buildMealLogCard(context, meal)
                      : _buildFoodLogCard(context, meal),
                )).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }

  // NEW: Card for meal logs (with image on left)
  Widget _buildMealLogCard(BuildContext context, FoodLog log) {
    return GestureDetector(
      onTap: () async {
        // TODO: Implement meal edit page if needed
        // await Navigator.of(context).push(...);
        // _refreshLogs();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.green.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Image on left
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: log.imageUrl != null
                  ? Image.network(
                      log.imageUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey[200],
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            log.mealType,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        Text(
                          log.time,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Show all food names, comma separated
                    if (log.foodItems != null && log.foodItems!.isNotEmpty)
                      Text(
                        log.foodItems!
                            .map((f) => (f['foodName'] as String?) ?? '')
                            .where((n) => n != null && n!.isNotEmpty)
                            .map((n) => n!)
                            .join(', '),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else
                      Text(
                        log.foodName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '${log.calories} kcal',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodLogCard(BuildContext context, FoodLog log) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditFoodLogPage(foodLogId: log.id),
          ),
        );
        _refreshLogs(); // Refresh after returning from edit
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 60,
                    height: 36,
                    decoration: BoxDecoration(
                     
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.qr_code_2, size: 36, color: Colors.green),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Scanned',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            log.mealType,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        Text(
                          log.time,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      log.foodName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${log.calories} kcal',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}