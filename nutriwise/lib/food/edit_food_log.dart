import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditFoodLogPage extends StatefulWidget {
  final String foodLogId;
  const EditFoodLogPage({Key? key, required this.foodLogId}) : super(key: key);

  @override
  State<EditFoodLogPage> createState() => _EditFoodLogPageState();
}

class _EditFoodLogPageState extends State<EditFoodLogPage> {
  bool _loading = true;
  bool _saving = false;
  String _foodName = '';
  String _mealType = '';
  String _unit = 'g';
  double _calories = 0;
  double _carbs = 0;
  double _protein = 0;
  double _fat = 0;
  double _quantity = 100;
  String _date = '';
  String _time = '';
  String _weekday = '';

  double _baseCalories = 0;
  double _baseCarbs = 0;
  double _baseProtein = 0;
  double _baseFat = 0;
  double _baseQuantity = 100;

  final _foodNameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _carbsController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _quantityController = TextEditingController();

  final List<String> _mealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Afternoon Snack',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _fetchFoodLog();
  }

  Future<void> _fetchFoodLog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .doc(widget.foodLogId)
        .get();
    final data = doc.data();
    if (data != null) {
      setState(() {
        _foodName = (data['foodName'] ?? '').toString();
        _mealType = (data['mealType'] ?? 'Meal').toString().trim(); // Trim spaces
        _unit = (data['unit'] ?? 'g').toString();
        _calories = (data['calories'] ?? 0).toDouble();
        _carbs = (data['carbs'] ?? 0).toDouble();
        _protein = (data['protein'] ?? 0).toDouble();
        _fat = (data['fat'] ?? 0).toDouble();
        _quantity = (data['quantity'] ?? 100).toDouble();
        _date = (data['date'] ?? '').toString();
        _time = (data['time'] ?? '').toString();
        _weekday = (data['weekday'] ?? '').toString();

        _foodNameController.text = _foodName;
        _caloriesController.text = _calories.toStringAsFixed(1);
        _carbsController.text = _carbs.toStringAsFixed(1);
        _proteinController.text = _protein.toStringAsFixed(1);
        _fatController.text = _fat.toStringAsFixed(1);
        _quantityController.text = _quantity.toStringAsFixed(1);

        // Store base values for dynamic calculation
        _baseCalories = _calories;
        _baseCarbs = _carbs;
        _baseProtein = _protein;
        _baseFat = _fat;
        _baseQuantity = _quantity;

        _loading = false;
      });
    }
  }

  void _updateMacrosFromQuantity() {
    final newQuantity = double.tryParse(_quantityController.text) ?? _baseQuantity;
    if (_baseQuantity > 0) {
      setState(() {
        _caloriesController.text = (_baseCalories * newQuantity / _baseQuantity).toStringAsFixed(1);
        _carbsController.text = (_baseCarbs * newQuantity / _baseQuantity).toStringAsFixed(1);
        _proteinController.text = (_baseProtein * newQuantity / _baseQuantity).toStringAsFixed(1);
        _fatController.text = (_baseFat * newQuantity / _baseQuantity).toStringAsFixed(1);
      });
    }
  }

  void _updateBaseFromMacros() {
    final newQuantity = double.tryParse(_quantityController.text) ?? _baseQuantity;
    setState(() {
      _baseCalories = double.tryParse(_caloriesController.text) ?? 0;
      _baseCarbs = double.tryParse(_carbsController.text) ?? 0;
      _baseProtein = double.tryParse(_proteinController.text) ?? 0;
      _baseFat = double.tryParse(_fatController.text) ?? 0;
      _baseQuantity = newQuantity;
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .doc(widget.foodLogId)
        .update({
      'foodName': _foodNameController.text.trim(),
      'mealType': _mealType,
      'calories': double.tryParse(_caloriesController.text) ?? 0,
      'carbs': double.tryParse(_carbsController.text) ?? 0,
      'protein': double.tryParse(_proteinController.text) ?? 0,
      'fat': double.tryParse(_fatController.text) ?? 0,
      'quantity': double.tryParse(_quantityController.text) ?? 100,
      'unit': _unit,
      // Keep date, time, weekday unchanged
    });
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Food record updated!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.green,
          title: const Text('Edit Food Record'),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text('Edit Food Record'),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
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
                  Text(
                    '$_weekday, $_date',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      fontSize: 12,
                    ),
                  ),
                  // Editable meal type dropdown
                  DropdownButton<String>(
                    value: _mealTypes.contains(_mealType) ? _mealType : _mealTypes[0],
                    items: _mealTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type, style: const TextStyle(fontWeight: FontWeight.w500)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _mealType = val ?? _mealTypes[0];
                      });
                    },
                    underline: const SizedBox(),
                  ),
                  Text(
                    _time,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Food Item:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _foodNameController,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'Food Name',
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nutritional Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Per ${_quantityController.text}${_unit}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNutritionRow('Calories', _caloriesController, 'kcal', Colors.orange, onChanged: _updateBaseFromMacros),
                  const Divider(height: 24),
                  _buildNutritionRow('Carbohydrates', _carbsController, 'g', Colors.blue, onChanged: _updateBaseFromMacros),
                  const Divider(height: 24),
                  _buildNutritionRow('Protein', _proteinController, 'g', Colors.red, onChanged: _updateBaseFromMacros),
                  const Divider(height: 24),
                  _buildNutritionRow('Fat', _fatController, 'g', Colors.yellow, onChanged: _updateBaseFromMacros),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Text(
                        'Quantity:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _quantityController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            suffixText: _unit,
                          ),
                          onChanged: (val) {
                            _updateMacrosFromQuantity();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionRow(
    String label,
    TextEditingController controller,
    String unit,
    Color color, {
    required VoidCallback onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        SizedBox(
          width: 120,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixText: unit,
            ),
            onChanged: (val) => onChanged(),
          ),
        ),
      ],
    );
  }
}
