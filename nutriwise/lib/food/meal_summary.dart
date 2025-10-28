import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutriwise/home/home_screen.dart';

class MealSummaryPage extends StatefulWidget {
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
  State<MealSummaryPage> createState() => _MealSummaryPageState();
}

class _MealSummaryPageState extends State<MealSummaryPage> {
  bool _isLoading = true;
  bool _hasNutritionData = false;
  bool _isOcrMode = false;
  bool _isProcessingOcr = false;
  bool _showOcrReview = false; // New: Track if showing OCR review screen
  String? _customFoodName;
  
  // Nutrition data per 100g/ml
  double _baseCalories = 0;
  double _baseCarbs = 0;
  double _baseProtein = 0;
  double _baseFat = 0;
  String _servingUnit = 'g';
  
  // Temporary storage for OCR extracted values (before confirmation)
  double _tempCalories = 0;
  double _tempCarbs = 0;
  double _tempProtein = 0;
  double _tempFat = 0;
  
  // Quantity controls
  int _wholeQuantity = 1;
  int _selectedDivision = 10;
  
  // Controllers for manual editing
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final TextEditingController _foodNameController = TextEditingController();
  
  // Controllers for OCR review editing
  final TextEditingController _ocrCaloriesController = TextEditingController();
  final TextEditingController _ocrCarbsController = TextEditingController();
  final TextEditingController _ocrProteinController = TextEditingController();
  final TextEditingController _ocrFatController = TextEditingController();
  
  String _selectedUnit = 'g';
  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();
  
  bool _isCustomQuantity = false;
  final TextEditingController _customQuantityController = TextEditingController();
  double _customQuantity = 0.0;
  double _baselineQuantity = 100.0; // Default to 100g/ml
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchNutritionData();
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _foodNameController.dispose();
    _ocrCaloriesController.dispose();
    _ocrCarbsController.dispose();
    _ocrProteinController.dispose();
    _ocrFatController.dispose();
    _textRecognizer.close();
    _customQuantityController.dispose();
    super.dispose();
  }

  Future<void> _fetchNutritionData() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      DocumentSnapshot<Map<String, dynamic>>? barcodeDoc;

      if (user != null) {
        // Try user-specific barcode first
        barcodeDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('barcodes')
          .doc(widget.barcode)
          .get();
      }

      if (barcodeDoc != null && barcodeDoc.exists) {
        final data = barcodeDoc.data();
        setState(() {
          _baseCalories = (data?['calories'] ?? 0).toDouble();
          _baseCarbs = (data?['carbs'] ?? 0).toDouble();
          _baseProtein = (data?['protein'] ?? 0).toDouble();
          _baseFat = (data?['fat'] ?? 0).toDouble();
          _servingUnit = 'g';
          _selectedUnit = _servingUnit;
          _baselineQuantity = 100.0;
          _customFoodName = data?['foodName'];
          _hasNutritionData = true;
          _isLoading = false;
          _updateDisplayedValues();
        });
        return;
      }

      // Fallback: fetch from global barcodes collection
      final globalDoc = await _firestore.collection('barcodes').doc(widget.barcode).get();
      if (globalDoc.exists) {
        final data = globalDoc.data();
        setState(() {
          _baseCalories = (data?['calories'] ?? 0).toDouble();
          _baseCarbs = (data?['carbs'] ?? 0).toDouble();
          _baseProtein = (data?['protein'] ?? 0).toDouble();
          _baseFat = (data?['fat'] ?? 0).toDouble();
          _servingUnit = 'g';
          _selectedUnit = _servingUnit;
          _baselineQuantity = 100.0;
          _customFoodName = data?['foodName'];
          _hasNutritionData = true;
          _isLoading = false;
          _updateDisplayedValues();
        });
        return;
      }

      // Fallback: fetch from OpenFoodFacts
      final nutritionData = await _fetchFromOpenFoodFacts(widget.barcode);

      if (nutritionData != null) {
        setState(() {
          _baseCalories = nutritionData['calories'] ?? 0;
          _baseCarbs = nutritionData['carbs'] ?? 0;
          _baseProtein = nutritionData['protein'] ?? 0;
          _baseFat = nutritionData['fat'] ?? 0;
          _servingUnit = nutritionData['unit'] ?? 'g';
          _selectedUnit = _servingUnit;
          _baselineQuantity = nutritionData['baselineQuantity'] ?? 100.0;
          _hasNutritionData = true;
          _isLoading = false;
          _updateDisplayedValues();
        });
      } else {
        setState(() {
          _hasNutritionData = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _hasNutritionData = false;
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchFromOpenFoodFacts(String barcode) async {
    try {
      final url = Uri.parse('https://world.openfoodfacts.org/api/v0/product/$barcode.json');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          final nutriments = product['nutriments'];

          if (nutriments != null) {
            String unit = 'g';
            double baselineQuantity = 100.0;
            bool hasServing = false;

            // Try to get serving size from product info
            if (product.containsKey('serving_size')) {
              final servingStr = product['serving_size'].toString().toLowerCase();
              final match = RegExp(r'(\d+\.?\d*)\s*(g|ml)').firstMatch(servingStr);
              if (match != null) {
                baselineQuantity = double.tryParse(match.group(1)!) ?? 100.0;
                unit = match.group(2) ?? unit;
                hasServing = true;
              }
            }
            // Fallback: check for known fields
            if (!hasServing && product.containsKey('quantity')) {
              final quantityStr = product['quantity'].toString().toLowerCase();
              final match = RegExp(r'(\d+\.?\d*)\s*(g|ml)').firstMatch(quantityStr);
              if (match != null) {
                baselineQuantity = double.tryParse(match.group(1)!) ?? baselineQuantity;
                unit = match.group(2) ?? unit;
              }
            }

            final categories = product['categories_tags'] ?? [];
            if (categories.toString().toLowerCase().contains('beverage') ||
                categories.toString().toLowerCase().contains('drink') ||
                categories.toString().toLowerCase().contains('juice')) {
              unit = 'ml';
            }

            // Prefer per serving values if available
            double? calories, carbs, protein, fat;
            if (hasServing) {
              calories = _parseDouble(nutriments['energy-kcal_serving']) ??
                         _parseDouble(nutriments['energy_serving']);
              carbs = _parseDouble(nutriments['carbohydrates_serving']);
              protein = _parseDouble(nutriments['proteins_serving']);
              fat = _parseDouble(nutriments['fat_serving']);
            }

            // Fallback to per 100g/ml if per serving not available
            calories ??= _parseDouble(nutriments['energy-kcal_100g']) ??
                         _parseDouble(nutriments['energy_100g']);
            carbs ??= _parseDouble(nutriments['carbohydrates_100g']);
            protein ??= _parseDouble(nutriments['proteins_100g']);
            fat ??= _parseDouble(nutriments['fat_100g']);

            return {
              'calories': calories ?? 0,
              'carbs': carbs ?? 0,
              'protein': protein ?? 0,
              'fat': fat ?? 0,
              'unit': unit,
              'baselineQuantity': baselineQuantity,
            };
          }
        }
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _captureNutritionalInfo() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      
      if (image == null) return;
      
      setState(() => _isProcessingOcr = true);
      
      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      print('Recognized text: ${recognizedText.text}');
      
      final extractedData = _extractNutritionalData(recognizedText.text);
      
      if (extractedData['calories'] != null || 
          extractedData['carbs'] != null || 
          extractedData['protein'] != null || 
          extractedData['fat'] != null) {
        
        // Store extracted values in temporary variables
        setState(() {
          _tempCalories = extractedData['calories'] ?? 0;
          _tempCarbs = extractedData['carbs'] ?? 0;
          _tempProtein = extractedData['protein'] ?? 0;
          _tempFat = extractedData['fat'] ?? 0;
          
          // Set controllers for OCR review
          _ocrCaloriesController.text = _tempCalories.toStringAsFixed(1);
          _ocrCarbsController.text = _tempCarbs.toStringAsFixed(1);
          _ocrProteinController.text = _tempProtein.toStringAsFixed(1);
          _ocrFatController.text = _tempFat.toStringAsFixed(1);
          
          _isProcessingOcr = false;
          _showOcrReview = true; // Show the review screen
        });
      } else {
        setState(() => _isProcessingOcr = false);
        _showErrorDialog('Could not extract nutritional information from the image. Please try again or enter values manually.');
      }
      
    } catch (e) {
      setState(() => _isProcessingOcr = false);
      _showErrorDialog('Error processing image: ${e.toString()}');
    }
  }

  Map<String, double?> _extractNutritionalData(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();

    double? calories;
    double? protein;
    double? carbs;
    double? fat;

    // Find first kcal value
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase();
      final match = RegExp(r'(\d+\.?\d*)\s*kcal').firstMatch(l);
      if (match != null) {
        calories = double.tryParse(match.group(1)!);
        // Start scanning for macros after this line
        int macroIdx = i + 1;
        int found = 0;
        while (macroIdx < lines.length && found < 3) {
          final macroLine = lines[macroIdx].toLowerCase();
          // Skip subtypes
          if (macroLine.contains('of which')) {
            macroIdx++;
            continue;
          }
          final macroMatch = RegExp(r'(\d+\.?\d*)\s*g').firstMatch(macroLine);
          if (macroMatch != null) {
            final val = double.tryParse(macroMatch.group(1)!);
            if (val != null) {
              if (found == 0) protein = val;
              else if (found == 1) carbs = val;
              else if (found == 2) fat = val;
              found++;
            }
          }
          macroIdx++;
        }
        break; // Stop after first kcal found
      }
    }

    return {
      'calories': calories,
      'carbs': carbs,
      'protein': protein,
      'fat': fat,
    };
  }

  // Confirm OCR extracted values and proceed to food name entry
  void _confirmOcrValues() {
    // Validate that at least some values are entered
    final calories = double.tryParse(_ocrCaloriesController.text) ?? 0;
    final carbs = double.tryParse(_ocrCarbsController.text) ?? 0;
    final protein = double.tryParse(_ocrProteinController.text) ?? 0;
    final fat = double.tryParse(_ocrFatController.text) ?? 0;

    if (calories == 0 && carbs == 0 && protein == 0 && fat == 0) {
      _showErrorDialog('Please enter at least one nutritional value.');
      return;
    }

    // Update base values
    setState(() {
      _baseCalories = calories;
      _baseCarbs = carbs;
      _baseProtein = protein;
      _baseFat = fat;
    });

    // Show food name dialog, and save to Firestore after user enters name
    _showFoodNameDialogAndSave();
  }

  Future<void> _showFoodNameDialogAndSave() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Name This Food Item'),
          content: TextField(
            controller: _foodNameController,
            decoration: const InputDecoration(
              labelText: 'Food Name',
              hintText: 'Enter the name of the food',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                _foodNameController.clear();
                Navigator.of(context).pop();
                setState(() {
                  _showOcrReview = false;
                  _hasNutritionData = false;
                });
              },
            ),
            TextButton(
              child: const Text('Continue'),
              onPressed: () async {
                if (_foodNameController.text.trim().isNotEmpty) {
                  final foodName = _foodNameController.text.trim();
                  setState(() {
                    _customFoodName = foodName;
                    _hasNutritionData = true;
                    _isOcrMode = true;
                    _showOcrReview = false;
                    _updateDisplayedValues();
                  });
                  Navigator.of(context).pop();

                  // Save nutritional info to Firestore barcodes collection
                  await _firestore.collection('barcodes').doc(widget.barcode).set({
                    'calories': _baseCalories,
                    'carbs': _baseCarbs,
                    'protein': _baseProtein,
                    'fat': _baseFat,
                    'foodName': foodName,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _saveFoodDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in!')),
      );
      return;
    }

    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final weekdayStr = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ][now.weekday - 1];

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('barcodes') 
        .add({
      'foodName': _customFoodName ?? widget.foodName ?? 'Unknown Product (${widget.barcode})',
      'calories': double.tryParse(_caloriesController.text) ?? 0,
      'carbs': double.tryParse(_carbsController.text) ?? 0,
      'protein': double.tryParse(_proteinController.text) ?? 0,
      'fat': double.tryParse(_fatController.text) ?? 0,
      'quantity': _getTotalQuantity(),
      'unit': _selectedUnit,
      'mealType': widget.mealType,
      'date': dateStr,
      'time': timeStr,
      'weekday': weekdayStr,
      'createdAt': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text(
              'Meal stored successfully!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );

    // Navigate to HomeScreen after saving
    await Future.delayed(const Duration(milliseconds: 500)); // Let snackbar show briefly
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  double _getTotalQuantity() {
    if (_isCustomQuantity) {
      return _customQuantity;
    }
    // Use baseline quantity instead of 100
    return (_wholeQuantity * _baselineQuantity) +
        (_selectedDivision < 10 ? _baselineQuantity * _selectedDivision / 10.0 : 0.0);
  }

  double _getMultiplier() {
    // Always divide by baseline quantity
    return _getTotalQuantity() / _baselineQuantity;
  }

  void _updateDisplayedValues() {
    final multiplier = _getMultiplier();
    
    _caloriesController.text = (_baseCalories * multiplier).toStringAsFixed(1);
    _carbsController.text = (_baseCarbs * multiplier).toStringAsFixed(1);
    _proteinController.text = (_baseProtein * multiplier).toStringAsFixed(1);
    _fatController.text = (_baseFat * multiplier).toStringAsFixed(1);
  }

  void _showCustomQuantityDialog() {
    _customQuantityController.text = _getTotalQuantity().toStringAsFixed(1);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Custom Quantity'),
        content: TextField(
          controller: _customQuantityController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          decoration: InputDecoration(
            labelText: 'Quantity',
            suffixText: _selectedUnit,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(_customQuantityController.text);
              if (val != null && val > 0) {
                setState(() {
                  _customQuantity = val;
                  _isCustomQuantity = true;
                  _updateDisplayedValues();
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _clearCustomQuantity() {
    setState(() {
      _isCustomQuantity = false;
      _customQuantity = 0.0;
      _updateDisplayedValues();
    });
  }

  Widget _buildQuantityControl() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Quantity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              GestureDetector(
                onTap: () {
                  _showCustomQuantityDialog();
                },
                child: Row(
                  children: [
                    Text(
                      '${_getTotalQuantity().toStringAsFixed(1)}$_selectedUnit',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    if (_isCustomQuantity)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                        onPressed: _clearCustomQuantity,
                        tooltip: 'Clear custom quantity',
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_isCustomQuantity) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedUnit,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'g', child: Text('g')),
                      DropdownMenuItem(value: 'ml', child: Text('ml')),
                      DropdownMenuItem(value: 'oz', child: Text('oz')),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedUnit = value!);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _decrementWholeQuantity,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Colors.red[400],
                  iconSize: 32,
                ),
                Container(
                  width: 80,
                  alignment: Alignment.center,
                  child: Text(
                    _getQuantityDisplay(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _incrementWholeQuantity,
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.green[400],
                  iconSize: 32,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Fine adjustment (0-10/10):',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(
                10,
                (index) => Expanded(
                  child: GestureDetector(
                    onTap: () => _onDivisionTap(index + 1),
                    child: Container(
                      height: 32,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: (index + 1) <= _selectedDivision
                            ? Colors.red[400]
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '$_selectedDivision/10 portions',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onDivisionTap(int division) {
    setState(() {
      _selectedDivision = division;
      if (_wholeQuantity == 0 && division == 10) {
        _wholeQuantity = 1;
      }
      _updateDisplayedValues();
    });
  }

  void _decrementWholeQuantity() {
    setState(() {
      if (_wholeQuantity > 0) {
        _wholeQuantity--;
        if (_wholeQuantity == 0 && _selectedDivision == 10) {
          _selectedDivision = 0;
        }
        _updateDisplayedValues();
      }
    });
  }

  void _incrementWholeQuantity() {
    setState(() {
      _wholeQuantity++;
      _updateDisplayedValues();
    });
  }

  void _showEditDialog(String field, TextEditingController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $field'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          decoration: InputDecoration(
            labelText: field,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getQuantityDisplay() {
    if (_wholeQuantity == 0) {
      double fraction = _selectedDivision / 10.0;
      if (fraction == 0.5) return '½';
      if (fraction == 0.25) return '¼';
      if (fraction == 0.75) return '¾';
      return fraction.toString();
    } else if (_selectedDivision == 10 || _selectedDivision == 0) {
      return _wholeQuantity.toString();
    } else {
      double fraction = _selectedDivision / 10.0;
      String fractionStr = '';
      if (fraction == 0.5) fractionStr = '½';
      else if (fraction == 0.25) fractionStr = '¼';
      else if (fraction == 0.75) fractionStr = '¾';
      else fractionStr = '($fraction)';
      return '$_wholeQuantity $fractionStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final weekdayStr = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ][now.weekday - 1];

    // Show OCR Review Screen
    if (_showOcrReview) {
      return _buildOcrReviewScreen();
    }

    // Main Meal Summary Screen
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
      body: _isLoading || _isProcessingOcr
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _isProcessingOcr ? 'Processing image...' : 'Loading...',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
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
                          '$weekdayStr, $dateStr',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          widget.mealType,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Food Item Name
                  const Text(
                    'Food Item:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
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
                      _customFoodName ?? widget.foodName ?? 'Unknown Product (${widget.barcode})',
                      style: const TextStyle(fontSize: 18, color: Colors.black),
                    ),
                  ),
                  
                  if (_hasNutritionData) ...[
                    const SizedBox(height: 24),
                    
                    _buildQuantityControl(),
                    
                    const SizedBox(height: 24),
                    
                    _buildNutritionInfo(),
                    
                    const SizedBox(height: 32),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saveFoodDetails,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Text(
                          _isOcrMode ? 'Save Food Details' : 'Save & Continue',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                    
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[300]!),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.orange[700]),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Nutritional information not available for this product.',
                                  style: TextStyle(color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Take a photo of the nutritional information on the package to extract the details.',
                            style: TextStyle(color: Colors.black87, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _captureNutritionalInfo,
                        icon: const Icon(Icons.camera_alt, color: Colors.white),
                        label: const Text(
                          'Scan Nutrition Label',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  // New: OCR Review Screen
  Widget _buildOcrReviewScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Review Extracted Values'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _showOcrReview = false;
            });
          },
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Review and edit the extracted nutritional values per 100g/ml',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            const Text(
              'Nutritional Information (per 100g/ml)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Editable nutrition fields
            _buildOcrEditField(
              'Calories',
              _ocrCaloriesController,
              'kcal',
              Icons.local_fire_department,
              Colors.orange,
            ),
            
            const SizedBox(height: 16),
            
            _buildOcrEditField(
              'Carbohydrates',
              _ocrCarbsController,
              'g',
              Icons.grain,
              Colors.blue,
            ),
            
            const SizedBox(height: 16),
            
            _buildOcrEditField(
              'Protein',
              _ocrProteinController,
              'g',
              Icons.egg,
              Colors.red,
            ),
            
            const SizedBox(height: 16),
            
            _buildOcrEditField(
              'Fat',
              _ocrFatController,
              'g',
              Icons.water_drop,
              Colors.yellow[700]!,
            ),
            
            const SizedBox(height: 32),
            
            // Confirm button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _confirmOcrValues,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: const Text(
                  'Confirm & Continue',
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

  Widget _buildOcrEditField(
    String label,
    TextEditingController controller,
    String unit,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                    hintText: '0.0',
                    suffixText: unit,
                    suffixStyle: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionInfo() {
    return Container(
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
            'Per ${_getTotalQuantity().toStringAsFixed(0)}$_selectedUnit',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          
          _buildNutritionRow(
            'Calories',
            _caloriesController,
            'kcal',
            Colors.orange,
          ),
          const Divider(height: 24),
          _buildNutritionRow(
            'Carbohydrates',
            _carbsController,
            'g',
            Colors.blue,
          ),
          const Divider(height: 24),
          _buildNutritionRow(
            'Protein',
            _proteinController,
            'g',
            Colors.red,
          ),
          const Divider(height: 24),
          _buildNutritionRow(
            'Fat',
            _fatController,
            'g',
            Colors.yellow[700]!,
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionRow(
    String label,
    TextEditingController controller,
    String unit,
    Color color,
  ) {
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
        GestureDetector(
          onTap: () => _showEditDialog(label, controller),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Text(
                  controller.text.isEmpty ? '0.0' : controller.text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.edit,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}