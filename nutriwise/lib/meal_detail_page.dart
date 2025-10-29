import 'package:flutter/material.dart';

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
                  if (meals.isEmpty)
                    Text(
                      'No $type records for this week.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    )
                  else
                    Column(
                      children: meals.map((meal) {
                        final carbs = meal['carbohydrate'] ?? 0;
                        final protein = meal['protein'] ?? 0;
                        final fat = meal['fat'] ?? 0;
                        final fiber = meal['fiber'] ?? 0;
                        final sugar = meal['sugar'] ?? 0;
                        final name = meal['name'] ?? 'Meal';
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 6),
                              Text('Carbs: $carbs g'),
                              Text('Protein: $protein g'),
                              Text('Fat: $fat g'),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
