import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  final String name;
  const HomePage({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    // Dummy data
    final int calories = 1850;
    final int protein = 120;
    final int carbs = 200;
    final int fat = 60;
    final List<Map<String, dynamic>> meals = [
      {'name': 'Breakfast', 'calories': 350, 'protein': 20, 'carbs': 40, 'fat': 10},
      {'name': 'Lunch', 'calories': 600, 'protein': 35, 'carbs': 70, 'fat': 20},
      {'name': 'Dinner', 'calories': 700, 'protein': 45, 'carbs': 80, 'fat': 25},
      {'name': 'Snack', 'calories': 200, 'protein': 20, 'carbs': 10, 'fat': 5},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('NutriWise Home'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello $name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            const Text(
              'Today\'s Summary',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MacroCard(label: 'Calories', value: calories),
                _MacroCard(label: 'Protein', value: protein, unit: 'g'),
                _MacroCard(label: 'Carbs', value: carbs, unit: 'g'),
                _MacroCard(label: 'Fat', value: fat, unit: 'g'),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Meals',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: meals.length,
                itemBuilder: (context, index) {
                  final meal = meals[index];
                  return Card(
                    child: ListTile(
                      title: Text(meal['name']),
                      subtitle: Text(
                        'Calories: ${meal['calories']}, Protein: ${meal['protein']}g, Carbs: ${meal['carbs']}g, Fat: ${meal['fat']}g',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroCard extends StatelessWidget {
  final String label;
  final int value;
  final String unit;

  const _MacroCard({
    required this.label,
    required this.value,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text('$value $unit', style: const TextStyle(fontSize: 18)),
      ],
    );
  }
}