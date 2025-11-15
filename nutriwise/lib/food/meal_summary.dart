import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutriwise/home/home_screen.dart';
import 'package:barcode_scan2/barcode_scan2.dart';

// Model class for food items
class FoodItem {
  String barcode;
  String? foodName;
  double baseCalories;
  double baseCarbs;
  double baseProtein;
  double baseFat;
  String servingUnit;
  double baselineQuantity;
  int wholeQuantity;
  int selectedDivision;
  bool isCustomQuantity;
  double customQuantity;
  bool hasNutritionData;
  bool isOcrMode;

  FoodItem({
    required this.barcode,
    this.foodName,
    this.baseCalories = 0,
    this.baseCarbs = 0,
    this.baseProtein = 0,
    this.baseFat = 0,
    this.servingUnit = 'g',
    this.baselineQuantity = 100.0,
    this.wholeQuantity = 1,
    this.selectedDivision = 10,
    this.isCustomQuantity = false,
    this.customQuantity = 0.0,
    this.hasNutritionData = false,
    this.isOcrMode = false,
  });

  double getTotalQuantity() {
    if (isCustomQuantity) {
      return customQuantity;
    }
    return (wholeQuantity * baselineQuantity) +
        (selectedDivision < 10
            ? baselineQuantity * selectedDivision / 10.0
            : 0.0);
  }

  double getMultiplier() {
    return getTotalQuantity() / baselineQuantity;
  }

  double getCalories() => baseCalories * getMultiplier();
  double getCarbs() => baseCarbs * getMultiplier();
  double getProtein() => baseProtein * getMultiplier();
  double getFat() => baseFat * getMultiplier();
}

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
  List<FoodItem> _foodItems = [];
  int _currentFoodIndex = 0;
  bool _isLoading = true;
  bool _isProcessingOcr = false;
  bool _showOcrReview = false;
  bool _isScanningNewFood = false;

  // Temporary storage for OCR extracted values (before confirmation)
  double _tempCalories = 0;
  double _tempCarbs = 0;
  double _tempProtein = 0;
  double _tempFat = 0;

  final TextEditingController _foodNameController = TextEditingController();
  final TextEditingController _ocrCaloriesController = TextEditingController();
  final TextEditingController _ocrCarbsController = TextEditingController();
  final TextEditingController _ocrProteinController = TextEditingController();
  final TextEditingController _ocrFatController = TextEditingController();
  final TextEditingController _customQuantityController =
      TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initializeFirstFood();
  }

  void _initializeFirstFood() {
    final firstFood = FoodItem(
      barcode: widget.barcode,
      foodName: widget.foodName,
    );
    _foodItems.add(firstFood);
    _fetchNutritionData(_currentFoodIndex);
  }

  @override
  void dispose() {
    _foodNameController.dispose();
    _ocrCaloriesController.dispose();
    _ocrCarbsController.dispose();
    _ocrProteinController.dispose();
    _ocrFatController.dispose();
    _customQuantityController.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  FoodItem get _currentFood => _foodItems[_currentFoodIndex];

  Future<void> _fetchNutritionData(int index) async {
    setState(() => _isLoading = true);

    try {
      final food = _foodItems[index];
      final user = FirebaseAuth.instance.currentUser;
      DocumentSnapshot<Map<String, dynamic>>? barcodeDoc;

      if (user != null) {
        barcodeDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('barcodes')
            .doc(food.barcode)
            .get();
      }

      if (barcodeDoc != null && barcodeDoc.exists) {
        final data = barcodeDoc.data();
        setState(() {
          food.baseCalories = (data?['calories'] ?? 0).toDouble();
          food.baseCarbs = (data?['carbs'] ?? 0).toDouble();
          food.baseProtein = (data?['protein'] ?? 0).toDouble();
          food.baseFat = (data?['fat'] ?? 0).toDouble();
          food.servingUnit = 'g';
          food.baselineQuantity = 100.0;
          food.foodName = data?['foodName'];
          food.hasNutritionData = true;
          _isLoading = false;
        });
        return;
      }

      final globalDoc = await _firestore
          .collection('barcodes')
          .doc(food.barcode)
          .get();
      if (globalDoc.exists) {
        final data = globalDoc.data();
        setState(() {
          food.baseCalories = (data?['calories'] ?? 0).toDouble();
          food.baseCarbs = (data?['carbs'] ?? 0).toDouble();
          food.baseProtein = (data?['protein'] ?? 0).toDouble();
          food.baseFat = (data?['fat'] ?? 0).toDouble();
          food.servingUnit = 'g';
          food.baselineQuantity = 100.0;
          food.foodName = data?['foodName'];
          food.hasNutritionData = true;
          _isLoading = false;
        });
        return;
      }

      final nutritionData = await _fetchFromOpenFoodFacts(food.barcode);

      if (nutritionData != null) {
        setState(() {
          food.baseCalories = nutritionData['calories'] ?? 0;
          food.baseCarbs = nutritionData['carbs'] ?? 0;
          food.baseProtein = nutritionData['protein'] ?? 0;
          food.baseFat = nutritionData['fat'] ?? 0;
          food.servingUnit = nutritionData['unit'] ?? 'g';
          food.baselineQuantity = nutritionData['baselineQuantity'] ?? 100.0;
          food.hasNutritionData = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          food.hasNutritionData = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _foodItems[index].hasNutritionData = false;
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchFromOpenFoodFacts(String barcode) async {
    try {
      final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v0/product/$barcode.json',
      );
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

            if (product.containsKey('serving_size')) {
              final servingStr = product['serving_size']
                  .toString()
                  .toLowerCase();
              final match = RegExp(
                r'(\d+\.?\d*)\s*(g|ml)',
              ).firstMatch(servingStr);
              if (match != null) {
                baselineQuantity = double.tryParse(match.group(1)!) ?? 100.0;
                unit = match.group(2) ?? unit;
                hasServing = true;
              }
            }

            if (!hasServing && product.containsKey('quantity')) {
              final quantityStr = product['quantity'].toString().toLowerCase();
              final match = RegExp(
                r'(\d+\.?\d*)\s*(g|ml)',
              ).firstMatch(quantityStr);
              if (match != null) {
                baselineQuantity =
                    double.tryParse(match.group(1)!) ?? baselineQuantity;
                unit = match.group(2) ?? unit;
              }
            }

            final categories = product['categories_tags'] ?? [];
            if (categories.toString().toLowerCase().contains('beverage') ||
                categories.toString().toLowerCase().contains('drink') ||
                categories.toString().toLowerCase().contains('juice')) {
              unit = 'ml';
            }

            double? calories, carbs, protein, fat;
            if (hasServing) {
              calories =
                  _parseDouble(nutriments['energy-kcal_serving']) ??
                  _parseDouble(nutriments['energy_serving']);
              carbs = _parseDouble(nutriments['carbohydrates_serving']);
              protein = _parseDouble(nutriments['proteins_serving']);
              fat = _parseDouble(nutriments['fat_serving']);
            }

            calories ??=
                _parseDouble(nutriments['energy-kcal_100g']) ??
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

  Future<void> _scanAnotherFood() async {
    setState(() => _isScanningNewFood = true);

    try {
      var scanResult = await BarcodeScanner.scan();
      String barcode = scanResult.rawContent;

      if (barcode.isEmpty) {
        setState(() => _isScanningNewFood = false);
        _showErrorDialog('No barcode scanned.');
        return;
      }

      // Check if barcode already exists
      bool alreadyScanned = _foodItems.any((food) => food.barcode == barcode);
      if (alreadyScanned) {
        setState(() => _isScanningNewFood = false);
        _showErrorDialog('This product has already been scanned!');
        return;
      }

      // Lookup product name
      String productName = await _enhancedBarcodeLookup(barcode);

      // Add new food item
      final newFood = FoodItem(barcode: barcode, foodName: productName);

      setState(() {
        _foodItems.add(newFood);
        _currentFoodIndex = _foodItems.length - 1;
        _isScanningNewFood = false;
      });

      // Fetch nutrition data for new food
      await _fetchNutritionData(_currentFoodIndex);
    } catch (e) {
      setState(() => _isScanningNewFood = false);
      _showErrorDialog('Barcode scan failed: ${e.toString()}');
    }
  }

  Future<String> _enhancedBarcodeLookup(String barcode) async {
    try {
      final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v0/product/$barcode.json',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          final productName =
              product['product_name'] ??
              product['product_name_en'] ??
              product['generic_name'];

          if (productName != null && productName.toString().trim().isNotEmpty) {
            return productName.toString();
          }
        }
      }
    } catch (e) {
      // Continue to fallback
    }
    return 'Unknown Product (Barcode: $barcode)';
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
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      final extractedData = _extractNutritionalData(recognizedText.text);

      if (extractedData['calories'] != null ||
          extractedData['carbs'] != null ||
          extractedData['protein'] != null ||
          extractedData['fat'] != null) {
        setState(() {
          _tempCalories = extractedData['calories'] ?? 0;
          _tempCarbs = extractedData['carbs'] ?? 0;
          _tempProtein = extractedData['protein'] ?? 0;
          _tempFat = extractedData['fat'] ?? 0;

          _ocrCaloriesController.text = _tempCalories.toStringAsFixed(1);
          _ocrCarbsController.text = _tempCarbs.toStringAsFixed(1);
          _ocrProteinController.text = _tempProtein.toStringAsFixed(1);
          _ocrFatController.text = _tempFat.toStringAsFixed(1);

          _isProcessingOcr = false;
          _showOcrReview = true;
        });
      } else {
        setState(() => _isProcessingOcr = false);
        _showErrorDialog(
          'Could not extract nutritional information from the image. Please try again or enter values manually.',
        );
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

    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase();
      final match = RegExp(r'(\d+\.?\d*)\s*kcal').firstMatch(l);
      if (match != null) {
        calories = double.tryParse(match.group(1)!);
        int macroIdx = i + 1;
        int found = 0;
        while (macroIdx < lines.length && found < 3) {
          final macroLine = lines[macroIdx].toLowerCase();
          if (macroLine.contains('of which')) {
            macroIdx++;
            continue;
          }
          final macroMatch = RegExp(r'(\d+\.?\d*)\s*g').firstMatch(macroLine);
          if (macroMatch != null) {
            final val = double.tryParse(macroMatch.group(1)!);
            if (val != null) {
              if (found == 0)
                protein = val;
              else if (found == 1)
                carbs = val;
              else if (found == 2)
                fat = val;
              found++;
            }
          }
          macroIdx++;
        }
        break;
      }
    }

    return {
      'calories': calories,
      'carbs': carbs,
      'protein': protein,
      'fat': fat,
    };
  }

  void _confirmOcrValues() {
    final calories = double.tryParse(_ocrCaloriesController.text) ?? 0;
    final carbs = double.tryParse(_ocrCarbsController.text) ?? 0;
    final protein = double.tryParse(_ocrProteinController.text) ?? 0;
    final fat = double.tryParse(_ocrFatController.text) ?? 0;

    if (calories == 0 && carbs == 0 && protein == 0 && fat == 0) {
      _showErrorDialog('Please enter at least one nutritional value.');
      return;
    }

    setState(() {
      _currentFood.baseCalories = calories;
      _currentFood.baseCarbs = carbs;
      _currentFood.baseProtein = protein;
      _currentFood.baseFat = fat;
    });

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
                  _currentFood.hasNutritionData = false;
                });
              },
            ),
            TextButton(
              child: const Text('Continue'),
              onPressed: () async {
                if (_foodNameController.text.trim().isNotEmpty) {
                  final foodName = _foodNameController.text.trim();
                  setState(() {
                    _currentFood.foodName = foodName;
                    _currentFood.hasNutritionData = true;
                    _currentFood.isOcrMode = true;
                    _showOcrReview = false;
                  });
                  Navigator.of(context).pop();

                  await _firestore
                      .collection('barcodes')
                      .doc(_currentFood.barcode)
                      .set({
                        'calories': _currentFood.baseCalories,
                        'carbs': _currentFood.baseCarbs,
                        'protein': _currentFood.baseProtein,
                        'fat': _currentFood.baseFat,
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

  void _saveAllFoodDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not logged in!')));
      return;
    }

    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final weekdayStr = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][now.weekday - 1];

    // Save all food items
    for (var food in _foodItems) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('barcodes')
          .add({
            'foodName': food.foodName ?? 'Unknown Product (${food.barcode})',
            'calories': food.getCalories(),
            'carbs': food.getCarbs(),
            'protein': food.getProtein(),
            'fat': food.getFat(),
            'quantity': food.getTotalQuantity(),
            'unit': food.servingUnit,
            'mealType': widget.mealType,
            'date': dateStr,
            'time': timeStr,
            'weekday': weekdayStr,
            'createdAt': FieldValue.serverTimestamp(),
          });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              '${_foodItems.length} item${_foodItems.length > 1 ? "s" : ""} saved successfully!',
              style: const TextStyle(
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

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _showCustomQuantityDialog() {
    _customQuantityController.text = _currentFood
        .getTotalQuantity()
        .toStringAsFixed(1);
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
            suffixText: _currentFood.servingUnit,
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
              final val = double.tryParse(_customQuantityController.text);
              if (val != null && val > 0) {
                setState(() {
                  _currentFood.customQuantity = val;
                  _currentFood.isCustomQuantity = true;
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
      _currentFood.isCustomQuantity = false;
      _currentFood.customQuantity = 0.0;
    });
  }

  void _removeFoodItem(int index) {
    if (_foodItems.length <= 1) {
      _showErrorDialog(
        'Cannot remove the last item. Please add another item first.',
      );
      return;
    }

    setState(() {
      _foodItems.removeAt(index);

      // Adjust current index if needed
      if (_currentFoodIndex >= _foodItems.length) {
        _currentFoodIndex = _foodItems.length - 1;
      } else if (_currentFoodIndex > index) {
        // If we removed an item before the current one, adjust index
        _currentFoodIndex--;
      }
    });
  }

  String _getQuantityDisplay() {
    if (_currentFood.wholeQuantity == 0) {
      double fraction = _currentFood.selectedDivision / 10.0;
      if (fraction == 0.5) return '½';
      if (fraction == 0.25) return '¼';
      if (fraction == 0.75) return '¾';
      return fraction.toString();
    } else if (_currentFood.selectedDivision == 10 ||
        _currentFood.selectedDivision == 0) {
      return _currentFood.wholeQuantity.toString();
    } else {
      double fraction = _currentFood.selectedDivision / 10.0;
      String fractionStr = '';
      if (fraction == 0.5)
        fractionStr = '½';
      else if (fraction == 0.25)
        fractionStr = '¼';
      else if (fraction == 0.75)
        fractionStr = '¾';
      else
        fractionStr = '($fraction)';
      return '${_currentFood.wholeQuantity} $fractionStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final weekdayStr = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][now.weekday - 1];

    if (_showOcrReview) {
      return _buildOcrReviewScreen();
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          '${widget.mealType} - ${_foodItems.length} item${_foodItems.length > 1 ? "s" : ""}',
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading || _isProcessingOcr || _isScanningNewFood
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _isProcessingOcr
                        ? 'Processing image...'
                        : _isScanningNewFood
                        ? 'Scanning barcode...'
                        : 'Loading...',
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

                  // Show summary of all scanned foods
                  if (_foodItems.length > 1) ...[
                    _buildAllFoodsSummary(),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Currently Editing:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Food tabs for navigation
                  if (_foodItems.length > 1) _buildFoodTabs(),
                  if (_foodItems.length > 1) const SizedBox(height: 16),

                  // Current Food Item Name
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
                      _currentFood.foodName ??
                          'Unknown Product (${_currentFood.barcode})',
                      style: const TextStyle(fontSize: 18, color: Colors.black),
                    ),
                  ),

                  if (_currentFood.hasNutritionData) ...[
                    const SizedBox(height: 24),
                    _buildQuantityControl(),
                    const SizedBox(height: 24),
                    _buildNutritionInfo(),
                    const SizedBox(height: 24),

                    // Scan Another Food Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _scanAnotherFood,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text(
                          'Scan Another Food',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Save All Foods Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saveAllFoodDetails,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Text(
                          _foodItems.length > 1
                              ? 'Save All ${_foodItems.length} Items'
                              : 'Save & Continue',
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
                              Icon(
                                Icons.info_outline,
                                color: Colors.orange[700],
                              ),
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
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'How to scan nutritional information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 200,
                                width: 280,
                                child: Image.asset(
                                  'assets/nutritional_info.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Make sure to capture the full nutritional label, similar to the example above. The clearer the image, the better the results!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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

  Widget _buildAllFoodsSummary() {
    double totalCalories = 0;
    double totalCarbs = 0;
    double totalProtein = 0;
    double totalFat = 0;

    for (var food in _foodItems) {
      if (food.hasNutritionData) {
        totalCalories += food.getCalories();
        totalCarbs += food.getCarbs();
        totalProtein += food.getProtein();
        totalFat += food.getFat();
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              const Text(
                'Total Nutritional Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(_foodItems.length, (index) {
            final food = _foodItems[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${index + 1}. ${food.foodName ?? "Unknown"}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        fontWeight: index == _currentFoodIndex
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (food.hasNutritionData)
                    Text(
                      '${food.getCalories().toStringAsFixed(0)} kcal',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            );
          }),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryItem('Cal', totalCalories, 'kcal', Colors.orange),
              _buildSummaryItem('Carbs', totalCarbs, 'g', Colors.blue),
              _buildSummaryItem('Protein', totalProtein, 'g', Colors.red),
              _buildSummaryItem('Fat', totalFat, 'g', Colors.yellow[700]!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    double value,
    String unit,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(unit, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildFoodTabs() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _foodItems.length,
        itemBuilder: (context, index) {
          final isSelected = index == _currentFoodIndex;
          final food = _foodItems[index];
          final foodName = food.foodName ?? 'Unknown Product (${food.barcode})';
          final displayName = foodName.length > 20
              ? '${foodName.substring(0, 20)}...'
              : foodName;

          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.green : Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: isSelected ? Colors.green : Colors.grey[300]!,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentFoodIndex = index;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!food.hasNutritionData)
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: isSelected ? Colors.white : Colors.orange,
                        ),
                      if (!food.hasNutritionData) const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _removeFoodItem(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.3)
                          : Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
                onTap: _showCustomQuantityDialog,
                child: Row(
                  children: [
                    Text(
                      '${_currentFood.getTotalQuantity().toStringAsFixed(1)}${_currentFood.servingUnit}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    if (_currentFood.isCustomQuantity)
                      IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 18,
                          color: Colors.red,
                        ),
                        onPressed: _clearCustomQuantity,
                        tooltip: 'Clear custom quantity',
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_currentFood.isCustomQuantity) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: _currentFood.servingUnit,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'g', child: Text('g')),
                      DropdownMenuItem(value: 'ml', child: Text('ml')),
                      DropdownMenuItem(value: 'oz', child: Text('oz')),
                    ],
                    onChanged: (value) {
                      setState(() => _currentFood.servingUnit = value!);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (_currentFood.wholeQuantity > 0) {
                        _currentFood.wholeQuantity--;
                        if (_currentFood.wholeQuantity == 0 &&
                            _currentFood.selectedDivision == 10) {
                          _currentFood.selectedDivision = 0;
                        }
                      }
                    });
                  },
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
                  onPressed: () {
                    setState(() {
                      _currentFood.wholeQuantity++;
                    });
                  },
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
                    onTap: () {
                      setState(() {
                        _currentFood.selectedDivision = index + 1;
                        if (_currentFood.wholeQuantity == 0 &&
                            _currentFood.selectedDivision == 10) {
                          _currentFood.wholeQuantity = 1;
                        }
                      });
                    },
                    child: Container(
                      height: 32,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: (index + 1) <= _currentFood.selectedDivision
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
                '${_currentFood.selectedDivision}/10 portions',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
          ],
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
            'Per ${_currentFood.getTotalQuantity().toStringAsFixed(0)}${_currentFood.servingUnit}',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          _buildNutritionRow(
            'Calories',
            _currentFood.getCalories().toStringAsFixed(1),
            'kcal',
            Colors.orange,
          ),
          const Divider(height: 24),
          _buildNutritionRow(
            'Carbohydrates',
            _currentFood.getCarbs().toStringAsFixed(1),
            'g',
            Colors.blue,
          ),
          const Divider(height: 24),
          _buildNutritionRow(
            'Protein',
            _currentFood.getProtein().toStringAsFixed(1),
            'g',
            Colors.red,
          ),
          const Divider(height: 24),
          _buildNutritionRow(
            'Fat',
            _currentFood.getFat().toStringAsFixed(1),
            'g',
            Colors.yellow[700]!,
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionRow(
    String label,
    String value,
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
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Text(
                value.isEmpty ? '0.0' : value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
}
