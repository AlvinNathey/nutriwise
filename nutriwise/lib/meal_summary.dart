import 'package:flutter/material.dart';

class MealSummaryPage extends StatelessWidget {
  
  final String mealType;
  final String? foodName;
  final String barcode;
  

  const MealSummaryPage({
    Key? key,
    required this.mealType,
    required this.foodName,
    required this.barcode,
  }) : super(key: key);
  

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final weekdayStr = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ][now.weekday - 1];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Meal Summary'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date/Meal/Time box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$weekdayStr, $dateStr', style: const TextStyle(fontWeight: FontWeight.w500, color: Color.fromARGB(255, 0, 0, 0))),
                  Text(mealType, style: const TextStyle(fontWeight: FontWeight.w500, color: Color.fromARGB(255, 0, 0, 0))),
                  Text(timeStr, style: const TextStyle(fontWeight: FontWeight.w500, color: Color.fromARGB(255, 0, 0, 0))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Scanned Food Item:',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color.fromARGB(255, 0, 0, 0)),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Text(
                foodName ?? 'Food item not identified for barcode: $barcode',
                style: const TextStyle(fontSize: 18, color: Color.fromARGB(255, 0, 0, 0)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
