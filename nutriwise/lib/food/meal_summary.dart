import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutriwise/food/after_meal_summary.dart';
import 'package:nutriwise/home/home_screen.dart';
import 'package:nutriwise/services/food_collections.dart';
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

enum NutritionBasisKind { per100, perServing, perPackage, unknown }

class NutritionExtractionResult {
  final double? calories;
  final double? carbs;
  final double? protein;
  final double? fat;
  final double? baselineQuantity;
  final String? baselineUnit;
  final NutritionBasisKind basisKind;
  final double confidence;

  const NutritionExtractionResult({
    required this.basisKind,
    required this.confidence,
    this.calories,
    this.carbs,
    this.protein,
    this.fat,
    this.baselineQuantity,
    this.baselineUnit,
  });
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
  final TextEditingController _ocrServingQuantityController =
      TextEditingController();
  final TextEditingController _customQuantityController =
      TextEditingController();

  String _ocrUnit = 'g';
  NutritionBasisKind _reviewBasisKind = NutritionBasisKind.unknown;
  double _reviewConfidence = 0.0;
  String _reviewBasisLabel = 'per 100g/ml';

  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _dailyGoal = 2000;
  int _carbsTarget = 250;
  int _proteinTarget = 150;
  int _fatTarget = 70;
  int _todayCaloriesConsumed = 0;
  int _todayCarbsConsumed = 0;
  int _todayProteinConsumed = 0;
  int _todayFatConsumed = 0;

  @override
  void initState() {
    super.initState();
    _initializeFirstFood();
    _fetchUserGoalsAndTodayIntake();
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
    _ocrServingQuantityController.dispose();
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
          food.servingUnit = (data?['unit'] ?? 'g').toString();
          final baselineRaw = data?['baselineQuantity'];
          food.baselineQuantity = baselineRaw is num
              ? baselineRaw.toDouble()
              : double.tryParse(baselineRaw?.toString() ?? '') ?? 100.0;
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
          food.servingUnit = (data?['unit'] ?? 'g').toString();
          final baselineRaw = data?['baselineQuantity'];
          food.baselineQuantity = baselineRaw is num
              ? baselineRaw.toDouble()
              : double.tryParse(baselineRaw?.toString() ?? '') ?? 100.0;
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

      // Lookup product name (may be null if unrecognized)
      final String? productName = await _enhancedBarcodeLookup(barcode);

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

  Future<String?> _enhancedBarcodeLookup(String barcode) async {
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

          if (productName != null &&
              productName.toString().trim().isNotEmpty &&
              productName.toString().trim().toLowerCase() != 'unknown product') {
            return productName.toString();
          }
        }
      }
    } catch (e) {
      // Continue to fallback
    }
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
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      final parsed = _parseNutritionFromOcrText(recognizedText.text);

      final bool missingAnyMacro = parsed.calories == null ||
          parsed.carbs == null ||
          parsed.protein == null ||
          parsed.fat == null;
      final bool productNeedsName = _currentFood.foodName == null ||
          _currentFood.foodName!.trim().isEmpty ||
          _currentFood.foodName!.toLowerCase().contains('unknown product');

      final bool missingBasis = (parsed.basisKind == NutritionBasisKind.perServing ||
              parsed.basisKind == NutritionBasisKind.perPackage) &&
          (parsed.baselineQuantity == null ||
              parsed.baselineUnit == null ||
              parsed.baselineQuantity! <= 0);

      final bool needsReview =
          missingAnyMacro || parsed.confidence < 0.65 || productNeedsName || missingBasis;

      if (!needsReview) {
        final resolvedName = _currentFood.foodName?.trim() ?? '';
        if (resolvedName.trim().isEmpty) {
          // Still require a name if we can't confidently resolve one.
          setState(() => _isProcessingOcr = false);
          _openManualNutritionReview();
          return;
        }

        setState(() {
          _currentFood
            ..foodName = resolvedName.trim()
            ..baseCalories = parsed.calories ?? 0
            ..baseCarbs = parsed.carbs ?? 0
            ..baseProtein = parsed.protein ?? 0
            ..baseFat = parsed.fat ?? 0
            ..baselineQuantity = parsed.baselineQuantity ?? 100.0
            ..servingUnit = parsed.baselineUnit ?? 'g'
            ..hasNutritionData = true
            ..isOcrMode = true;
        });

        await _firestore.collection('barcodes').doc(_currentFood.barcode).set({
          'calories': _currentFood.baseCalories,
          'carbs': _currentFood.baseCarbs,
          'protein': _currentFood.baseProtein,
          'fat': _currentFood.baseFat,
          'foodName': _currentFood.foodName,
          'unit': _currentFood.servingUnit,
          'baselineQuantity': _currentFood.baselineQuantity,
          'createdAt': FieldValue.serverTimestamp(),
        });

        setState(() => _isProcessingOcr = false);
        _showOcrReview = false;
        return;
      }

      // Review/edit screen (prefilled with OCR)
      setState(() {
        _reviewBasisKind = parsed.basisKind;
        _reviewConfidence = parsed.confidence;
        _ocrUnit = parsed.baselineUnit ?? _currentFood.servingUnit;

        _foodNameController.clear();
        _ocrCaloriesController.text =
            parsed.calories?.toStringAsFixed(1) ?? '';
        _ocrCarbsController.text = parsed.carbs?.toStringAsFixed(1) ?? '';
        _ocrProteinController.text =
            parsed.protein?.toStringAsFixed(1) ?? '';
        _ocrFatController.text = parsed.fat?.toStringAsFixed(1) ?? '';

        _ocrServingQuantityController.text =
            parsed.baselineQuantity?.toStringAsFixed(1) ?? '100';
        _reviewBasisLabel = _buildReviewBasisLabel();

        _isProcessingOcr = false;
        _showOcrReview = true;
      });
    } catch (e) {
      setState(() => _isProcessingOcr = false);
      _showErrorDialog('Error processing image: ${e.toString()}');
    }
  }

  NutritionExtractionResult _parseNutritionFromOcrText(String rawText) {
    final normalizedText = _normalizeOcrTextForParsing(rawText);
    final lines = normalizedText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Basis indicators
    final per100Regex = RegExp(r'(?:(?:per\s*)?100)\s*(g|ml)\b',
        caseSensitive: false);
    final perServingRegex = RegExp(
      r'(per\s*(?:\d+[\dOo\., ]*)?\s*(serving|portion|serve)\b|serving\s*size\b|portion\s*size\b)',
      caseSensitive: false,
    );
    final perPackageRegex = RegExp(
      r'per\s*(?:\d+[\dOo\., ]*)?\s*(pack|package|container|bottle|can)\b|net\s*(weight|content)\b|contents\b',
      caseSensitive: false,
    );

    final per100Indices = _findLineIndices(lines, per100Regex);
    final perServingIndices = _findLineIndices(lines, perServingRegex);
    final perPackageIndices = _findLineIndices(lines, perPackageRegex);

    NutritionExtractionResult? bestPer100;
    for (final idx in per100Indices) {
      final candidate = _extractBasisNutrition(
        lines: lines,
        basisKind: NutritionBasisKind.per100,
        basisIndex: idx,
      );
      if (bestPer100 == null || candidate.confidence > bestPer100.confidence) {
        bestPer100 = candidate;
      }
    }

    NutritionExtractionResult? bestPerServing;
    for (final idx in perServingIndices) {
      final candidate = _extractBasisNutrition(
        lines: lines,
        basisKind: NutritionBasisKind.perServing,
        basisIndex: idx,
      );
      if (bestPerServing == null ||
          candidate.confidence > bestPerServing.confidence) {
        bestPerServing = candidate;
      }
    }

    NutritionExtractionResult? bestPerPackage;
    for (final idx in perPackageIndices) {
      final candidate = _extractBasisNutrition(
        lines: lines,
        basisKind: NutritionBasisKind.perPackage,
        basisIndex: idx,
      );
      if (bestPerPackage == null ||
          candidate.confidence > bestPerPackage.confidence) {
        bestPerPackage = candidate;
      }
    }

    // Prefer per-serving only when serving size is clearly detected.
    final bool perServingHasBasis =
        bestPerServing != null &&
            bestPerServing.baselineQuantity != null &&
            bestPerServing.baselineQuantity! > 0.0;

    final bool per100HasBasis =
        bestPer100 != null && bestPer100.baselineQuantity != null;

    if (perServingHasBasis) {
      return bestPerServing!;
    }

    if (per100HasBasis) {
      return bestPer100!;
    }

    if (bestPerPackage != null) {
      return bestPerPackage!;
    }

    // Last resort: try to extract macros without strict basis assumptions.
    final macros = _extractMacrosFromLines(lines);
    final anyMacroFound = macros.calories != null ||
        macros.carbs != null ||
        macros.protein != null ||
        macros.fat != null;
    return NutritionExtractionResult(
      basisKind: NutritionBasisKind.unknown,
      confidence: anyMacroFound ? 0.3 : 0.0,
      calories: macros.calories,
      carbs: macros.carbs,
      protein: macros.protein,
      fat: macros.fat,
      baselineQuantity: 100.0,
      baselineUnit: 'g',
    );
  }

  List<int> _findLineIndices(List<String> lines, RegExp regex) {
    final indices = <int>[];
    for (int i = 0; i < lines.length; i++) {
      if (regex.hasMatch(lines[i])) indices.add(i);
    }
    return indices;
  }

  NutritionExtractionResult _extractBasisNutrition({
    required List<String> lines,
    required NutritionBasisKind basisKind,
    required int basisIndex,
  }) {
    final start = (basisIndex - 2).clamp(0, lines.length);
    final end = (basisIndex + 14).clamp(0, lines.length);
    final window = lines.sublist(start, end);

    double? baselineQuantity;
    String? baselineUnit;

    if (basisKind == NutritionBasisKind.per100) {
      final line = lines[basisIndex];
      final m = RegExp(r'100\s*(g|ml)\b', caseSensitive: false).firstMatch(line);
      baselineUnit = m?.group(1) ?? 'g';
      baselineQuantity = 100.0;
    } else if (basisKind == NutritionBasisKind.perServing) {
      final qty = _extractServingQuantityFromWindow(lines: window);
      baselineQuantity = qty?.quantity;
      baselineUnit = qty?.unit;
    } else if (basisKind == NutritionBasisKind.perPackage) {
      final qty = _extractPackageQuantityFromWindow(lines: window);
      baselineQuantity = qty?.quantity;
      baselineUnit = qty?.unit;
    }

    final macros = _extractMacrosFromLines(window);

    final macroFoundCount = [
      macros.calories != null,
      macros.carbs != null,
      macros.protein != null,
      macros.fat != null,
    ].where((x) => x).length;

    final hasAnyMacro = macroFoundCount > 0;
    final hasBasis = baselineQuantity != null && baselineQuantity! > 0.0 && baselineUnit != null;

    double confidence =
        (macroFoundCount / 4.0) * 0.7 + (hasBasis ? 0.3 : 0.0);
    if (!hasAnyMacro) confidence = 0.0;

    return NutritionExtractionResult(
      basisKind: basisKind,
      confidence: confidence,
      calories: macros.calories,
      carbs: macros.carbs,
      protein: macros.protein,
      fat: macros.fat,
      baselineQuantity: baselineQuantity,
      baselineUnit: baselineUnit,
    );
  }

  ({double? calories, double? carbs, double? protein, double? fat})
      _extractMacrosFromLines(List<String> lines) {
    double? calories;
    double? carbs;
    double? protein;
    double? fat;

    final normalizedLines =
        lines.map(_normalizeNutritionLineForMatching).toList(growable: false);

    for (int i = 0; i < normalizedLines.length; i++) {
      final line = normalizedLines[i];
      final nextLine =
          i + 1 < normalizedLines.length ? normalizedLines[i + 1] : null;
      final combinedLine = nextLine == null ? line : '$line $nextLine';

      calories ??= _extractMacroValueForLabel(
        line: line,
        combinedLine: combinedLine,
        labelPattern: r'(energy|calories|kcal|kilocalories)',
        unitPattern: r'(?:kcal|cal)',
      );

      carbs ??= _extractMacroValueForLabel(
        line: line,
        combinedLine: combinedLine,
        labelPattern: r'(carbohydrates|carbohydrate|carbs?)',
        unitPattern: r'g',
      );

      protein ??= _extractMacroValueForLabel(
        line: line,
        combinedLine: combinedLine,
        labelPattern: r'proteins?',
        unitPattern: r'g',
      );

      fat ??= _extractMacroValueForLabel(
        line: line,
        combinedLine: combinedLine,
        labelPattern: r'(?:total\s+fat|fat\b)',
        unitPattern: r'g',
        invalidContextPattern: RegExp(r'saturated|trans', caseSensitive: false),
      );
    }

    return (calories: calories, carbs: carbs, protein: protein, fat: fat);
  }

  String _normalizeOcrTextForParsing(String input) {
    var text = input.toLowerCase();

    // Common label OCR mistakes.
    text = text.replaceAll(RegExp(r'kca\s*i'), 'kcal');
    text = text.replaceAll(RegExp(r'kca[i1l]', caseSensitive: false), 'kcal');
    text = text.replaceAll(
      RegExp(r'carbohydrat[e3]s?', caseSensitive: false),
      'carbohydrates',
    );
    text = text.replaceAll(
      RegExp(r'prot[e3][i1l]n', caseSensitive: false),
      'protein',
    );
    text = text.replaceAll(
      RegExp(r'tota[1l]\s*fat', caseSensitive: false),
      'total fat',
    );
    text = text.replaceAll(RegExp(r'ener9y', caseSensitive: false), 'energy');

    return text;
  }

  String _normalizeNutritionLineForMatching(String input) {
    return input
        .replaceAll('|', ' ')
        .replaceAll(':', ' ')
        .replaceAll(';', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double? _parseOcrNumber(String raw) {
    var token = raw.trim().toLowerCase();

    // Heuristic fixes for numeric OCR noise.
    token = token
        .replaceAll('o', '0')
        .replaceAll('O', '0')
        .replaceAll('l', '1')
        .replaceAll('i', '1');

    // Fix common broken decimals like "12 3" => "12.3"
    final brokenDecimal = RegExp(r'^(\d+)\s+(\d{1,2})$').firstMatch(token);
    if (brokenDecimal != null) {
      final composed = '${brokenDecimal.group(1)}.${brokenDecimal.group(2)}';
      return double.tryParse(composed);
    }

    token = token.replaceAll(',', '.');
    token = token.replaceAll(RegExp(r'\s+'), '');

    // Keep only the first decimal point if OCR produced multiple.
    final firstDot = token.indexOf('.');
    if (firstDot != -1) {
      final before = token.substring(0, firstDot);
      final after = token.substring(firstDot + 1).replaceAll('.', '');
      token = '$before.$after';
    }

    final cleaned = token.replaceAll(RegExp(r'[^0-9\.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double? _extractMacroValueForLabel({
    required String line,
    required String combinedLine,
    required String labelPattern,
    required String unitPattern,
    RegExp? invalidContextPattern,
  }) {
    if (invalidContextPattern != null &&
        invalidContextPattern.hasMatch(line) &&
        !RegExp(labelPattern, caseSensitive: false).hasMatch(line)) {
      return null;
    }

    final directPatterns = <RegExp>[
      RegExp(
        '$labelPattern[^0-9]{0,14}([0-9OoIl\\., ]+)(?:\\s*$unitPattern\\b)?',
        caseSensitive: false,
      ),
      RegExp(
        '([0-9OoIl\\., ]+)(?:\\s*$unitPattern\\b)?[^a-z]{0,8}$labelPattern',
        caseSensitive: false,
      ),
    ];

    for (final pattern in directPatterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        final parsed = _parseOcrNumber(match.group(1) ?? '');
        if (parsed != null) return parsed;
      }
    }

    final crossLineMatch = RegExp(
      '$labelPattern[^0-9]{0,18}([0-9OoIl\\., ]+)(?:\\s*$unitPattern\\b)?',
      caseSensitive: false,
    ).firstMatch(combinedLine);
    if (crossLineMatch != null) {
      final parsed = _parseOcrNumber(crossLineMatch.group(1) ?? '');
      if (parsed != null) return parsed;
    }

    return null;
  }

  // Temporary struct-like record for serving/package quantity.
  ({double? quantity, String? unit})? _extractServingQuantityFromWindow({
    required List<String> lines,
  }) {
    final keywordRegex = RegExp(
      r'(serving|portion|serve|servings?\s+per\s+container)',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = _normalizeNutritionLineForMatching(lines[i]);
      if (!keywordRegex.hasMatch(line)) continue;

      final sameLine = _extractQuantityWithUnit(line);
      if (sameLine != null) return sameLine;

      if (i + 1 < lines.length) {
        final nextLine = _normalizeNutritionLineForMatching(lines[i + 1]);
        final nextLineQty = _extractQuantityWithUnit(nextLine);
        if (nextLineQty != null) return nextLineQty;
      }

      final parenthetical = RegExp(
        r'\(([0-9OoIl\., ]+)\s*(g|ml|oz)\b\)',
        caseSensitive: false,
      ).firstMatch(line);
      if (parenthetical != null) {
        final q = _parseOcrNumber(parenthetical.group(1) ?? '');
        final unit = parenthetical.group(2);
        if (q != null && q > 0 && unit != null) {
          return (quantity: q, unit: unit);
        }
      }
    }
    return null;
  }

  ({double? quantity, String? unit})? _extractPackageQuantityFromWindow({
    required List<String> lines,
  }) {
    final keywordRegex = RegExp(
      r'(per\s*(pack|package|container|bottle|can)|net\s*(weight|content)|contents)',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = _normalizeNutritionLineForMatching(lines[i]);
      if (!keywordRegex.hasMatch(line)) continue;

      final sameLine = _extractQuantityWithUnit(line);
      if (sameLine != null) return sameLine;

      if (i + 1 < lines.length) {
        final nextLine = _normalizeNutritionLineForMatching(lines[i + 1]);
        final nextLineQty = _extractQuantityWithUnit(nextLine);
        if (nextLineQty != null) return nextLineQty;
      }
    }
    return null;
  }

  ({double? quantity, String? unit})? _extractQuantityWithUnit(String line) {
    final match = RegExp(
      r'([0-9OoIl\., ]+)\s*(g|ml|oz)\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return null;

    final quantity = _parseOcrNumber(match.group(1) ?? '');
    final unit = match.group(2);
    if (quantity == null || quantity <= 0 || unit == null) return null;

    return (quantity: quantity, unit: unit);
  }

  Future<void> _confirmOcrValues() async {
    final foodName = _foodNameController.text.trim();
    if (foodName.isEmpty) {
      _showErrorDialog('Please enter a food name.');
      return;
    }

    final calories = double.tryParse(_ocrCaloriesController.text) ?? 0;
    final carbs = double.tryParse(_ocrCarbsController.text) ?? 0;
    final protein = double.tryParse(_ocrProteinController.text) ?? 0;
    final fat = double.tryParse(_ocrFatController.text) ?? 0;

    if (calories == 0 && carbs == 0 && protein == 0 && fat == 0) {
      _showErrorDialog('Please enter at least one nutritional value.');
      return;
    }

    final servingQty = double.tryParse(_ocrServingQuantityController.text);
    if (servingQty == null || servingQty <= 0) {
      _showErrorDialog('Please enter a valid serving quantity.');
      return;
    }

    setState(() {
      _currentFood
        ..foodName = foodName
        ..baseCalories = calories
        ..baseCarbs = carbs
        ..baseProtein = protein
        ..baseFat = fat
        ..baselineQuantity = servingQty
        ..servingUnit = _ocrUnit
        ..hasNutritionData = true
        ..isOcrMode = true;
    });

    await _firestore.collection('barcodes').doc(_currentFood.barcode).set({
      'calories': _currentFood.baseCalories,
      'carbs': _currentFood.baseCarbs,
      'protein': _currentFood.baseProtein,
      'fat': _currentFood.baseFat,
      'foodName': _currentFood.foodName,
      'unit': _currentFood.servingUnit,
      'baselineQuantity': _currentFood.baselineQuantity,
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() {
      _showOcrReview = false;
    });
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

  Widget _buildProductNotIdentifiedFallbackCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange[700]),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Product not identified',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Add image to show what to scan
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 160,
                width: 220,
                child: Image.asset(
                  'assets/nutritional_info.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Example of a nutritional label to scan',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _captureNutritionalInfo,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text(
                'Scan Nutritional Facts',
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _openManualNutritionReview,
              icon: const Icon(Icons.edit, color: Colors.green),
              label: const Text(
                'Enter Manually',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.green, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openManualNutritionReview() {
    final bool hasExisting = _currentFood.hasNutritionData;

    setState(() {
      _foodNameController.clear();

      _ocrCaloriesController.text = hasExisting
          ? _currentFood.baseCalories.toStringAsFixed(1)
          : '';
      _ocrCarbsController.text =
          hasExisting ? _currentFood.baseCarbs.toStringAsFixed(1) : '';
      _ocrProteinController.text =
          hasExisting ? _currentFood.baseProtein.toStringAsFixed(1) : '';
      _ocrFatController.text =
          hasExisting ? _currentFood.baseFat.toStringAsFixed(1) : '';

      _ocrUnit = hasExisting ? _currentFood.servingUnit : 'g';
      _ocrServingQuantityController.text =
          hasExisting ? _currentFood.baselineQuantity.toStringAsFixed(1) : '100';

      _reviewConfidence = hasExisting ? 0.9 : 0.0;
      _reviewBasisKind = NutritionBasisKind.unknown;
      if (hasExisting) {
        if (_currentFood.baselineQuantity == 100.0) {
          _reviewBasisKind = NutritionBasisKind.per100;
        } else {
          _reviewBasisKind = NutritionBasisKind.perServing;
        }
      }
      _reviewBasisLabel = _buildReviewBasisLabel();

      _showOcrReview = true;
    });
  }

  String _buildReviewBasisLabel() {
    final qty = double.tryParse(_ocrServingQuantityController.text);
    final unit = _ocrUnit;

    String? qtyStr;
    if (qty != null && qty > 0) {
      qtyStr = qty.toStringAsFixed(1);
      qtyStr = qtyStr!.replaceAll(RegExp(r'\.0$'), '');
    }

    switch (_reviewBasisKind) {
      case NutritionBasisKind.per100:
        return 'per 100$unit';
      case NutritionBasisKind.perServing:
        return (qtyStr != null && qtyStr.isNotEmpty)
            ? 'per serving ($qtyStr$unit)'
            : 'per serving';
      case NutritionBasisKind.perPackage:
        return (qtyStr != null && qtyStr.isNotEmpty)
            ? 'per package ($qtyStr$unit)'
            : 'per package';
      case NutritionBasisKind.unknown:
      default:
        return (qtyStr != null && qtyStr.isNotEmpty)
            ? 'per $qtyStr$unit'
            : 'per 100$unit';
    }
  }

  void _saveAllFoodDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not logged in!')));
      return;
    }

    // Prevent saving items that are still using a placeholder name.
    for (final food in _foodItems) {
      final name = food.foodName?.trim();
      if (name == null ||
          name.isEmpty ||
          name.toLowerCase().contains('unknown product')) {
        _showErrorDialog(
          'Product not identified yet. Please use "Enter Manually" or "Scan Nutritional Facts" before saving.',
        );
        return;
      }
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
            'foodName': food.foodName!,
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

  Future<void> _fetchUserGoalsAndTodayIntake() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      int calories = 0;
      int carbs = 0;
      int protein = 0;
      int fat = 0;

      final mealsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .where('date', isEqualTo: dateStr)
          .get();
      for (final doc in mealsSnapshot.docs) {
        final data = doc.data();
        calories += ((data['totalCalories'] ?? 0) as num).round();
        carbs += ((data['totalCarbs'] ?? 0) as num).round();
        protein += ((data['totalProtein'] ?? 0) as num).round();
        fat += ((data['totalFat'] ?? 0) as num).round();
      }

      final barcodesSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('barcodes')
          .where('date', isEqualTo: dateStr)
          .get();
      for (final doc in barcodesSnapshot.docs) {
        final data = doc.data();
        calories += ((data['calories'] ?? 0) as num).round();
        carbs += ((data['carbs'] ?? 0) as num).round();
        protein += ((data['protein'] ?? 0) as num).round();
        fat += ((data['fat'] ?? 0) as num).round();
      }

      final manualSnapshot = await userManualFoodsCollection(user.uid)
          .where('date', isEqualTo: dateStr)
          .get();
      for (final doc in manualSnapshot.docs) {
        final data = doc.data();
        calories += ((data['calories'] ?? 0) as num).round();
        carbs += ((data['carbs'] ?? 0) as num).round();
        protein += ((data['protein'] ?? 0) as num).round();
        fat += ((data['fat'] ?? 0) as num).round();
      }

      if (!mounted) return;
      setState(() {
        _dailyGoal = ((userData['calories'] ?? 2000) as num).round();
        _carbsTarget = ((userData['carbG'] ?? 250) as num).round();
        _proteinTarget = ((userData['proteinG'] ?? 150) as num).round();
        _fatTarget = ((userData['fatG'] ?? 70) as num).round();
        _todayCaloriesConsumed = calories;
        _todayCarbsConsumed = carbs;
        _todayProteinConsumed = protein;
        _todayFatConsumed = fat;
      });
    } catch (_) {}
  }

  int _calculateMealCalories() => _foodItems.fold(
        0,
        (sum, food) => sum + (food.hasNutritionData ? food.getCalories().round() : 0),
      );

  int _calculateMealCarbs() => _foodItems.fold(
        0,
        (sum, food) => sum + (food.hasNutritionData ? food.getCarbs().round() : 0),
      );

  int _calculateMealProtein() => _foodItems.fold(
        0,
        (sum, food) => sum + (food.hasNutritionData ? food.getProtein().round() : 0),
      );

  int _calculateMealFat() => _foodItems.fold(
        0,
        (sum, food) => sum + (food.hasNutritionData ? food.getFat().round() : 0),
      );

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
                  Builder(
                    builder: (context) {
                      final productNotIdentified = _currentFood.foodName == null ||
                          _currentFood.foodName!.trim().isEmpty ||
                          _currentFood.foodName!
                              .toLowerCase()
                              .contains('unknown product');
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[300]!),
                        ),
                        child: Text(
                          productNotIdentified
                              ? 'Product not identified'
                              : (_currentFood.foodName ?? 'Product not identified'),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black,
                          ),
                        ),
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final productNotIdentified = _currentFood.foodName == null ||
                          _currentFood.foodName!.trim().isEmpty ||
                          _currentFood.foodName!
                              .toLowerCase()
                              .contains('unknown product');

                      if (productNotIdentified) {
                        return Column(
                          children: [
                            const SizedBox(height: 24),
                            _buildProductNotIdentifiedFallbackCard(),
                            if (_currentFood.hasNutritionData) ...[
                              const SizedBox(height: 24),
                              _buildQuantityControl(),
                              const SizedBox(height: 24),
                              _buildNutritionInfo(),
                              const SizedBox(height: 24),
                              AfterMealSummary(
                                dailyGoal: _dailyGoal,
                                carbsTarget: _carbsTarget,
                                proteinTarget: _proteinTarget,
                                fatTarget: _fatTarget,
                                todayCaloriesConsumed: _todayCaloriesConsumed,
                                todayCarbsConsumed: _todayCarbsConsumed,
                                todayProteinConsumed: _todayProteinConsumed,
                                todayFatConsumed: _todayFatConsumed,
                                mealCalories: _calculateMealCalories(),
                                mealCarbs: _calculateMealCarbs(),
                                mealProtein: _calculateMealProtein(),
                                mealFat: _calculateMealFat(),
                                margin: const EdgeInsets.only(bottom: 24),
                              ),
                            ],
                            if (_currentFood.hasNutritionData) ...[
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
                                    side: const BorderSide(
                                      color: Colors.green,
                                      width: 2,
                                    ),
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
                            ],
                          ],
                        );
                      }

                      if (_currentFood.hasNutritionData) {
                        return Column(
                          children: [
                            const SizedBox(height: 24),
                            _buildQuantityControl(),
                            const SizedBox(height: 24),
                            _buildNutritionInfo(),
                            const SizedBox(height: 24),
                            AfterMealSummary(
                              dailyGoal: _dailyGoal,
                              carbsTarget: _carbsTarget,
                              proteinTarget: _proteinTarget,
                              fatTarget: _fatTarget,
                              todayCaloriesConsumed: _todayCaloriesConsumed,
                              todayCarbsConsumed: _todayCarbsConsumed,
                              todayProteinConsumed: _todayProteinConsumed,
                              todayFatConsumed: _todayFatConsumed,
                              mealCalories: _calculateMealCalories(),
                              mealCarbs: _calculateMealCarbs(),
                              mealProtein: _calculateMealProtein(),
                              mealFat: _calculateMealFat(),
                              margin: const EdgeInsets.only(bottom: 24),
                            ),

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
                                  side: const BorderSide(
                                    color: Colors.green,
                                    width: 2,
                                  ),
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
                          ],
                        );
                      }

                      return Column(
                        children: [
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
                              icon:
                                  const Icon(Icons.camera_alt, color: Colors.white),
                              label: const Text(
                                'Scan Nutritional Facts',
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
                      );
                    },
                  ),
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
          final foodName = food.foodName ?? 'Product not identified';
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
        title: const Text('Review Nutritional Facts'),
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
                  Expanded(
                    child: Text(
                      'Review and edit the extracted nutritional values (${_reviewBasisLabel})',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_reviewConfidence < 0.65)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 0),
                child: Text(
                  'Tip: Please verify the values below (OCR confidence is low).',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 24),

            const Text(
              'Food Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 16),

            // Food name (required for saving)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _foodNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Food name',
                  hintText: 'e.g., Oat Milk',
                  border: OutlineInputBorder(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Quantity basis: baseline quantity + unit for scaling
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
                    'Quantity basis',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ocrServingQuantityController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '100',
                            suffixText: _ocrUnit,
                            suffixStyle: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: _ocrUnit,
                        items: const [
                          DropdownMenuItem(value: 'g', child: Text('g')),
                          DropdownMenuItem(value: 'ml', child: Text('ml')),
                          DropdownMenuItem(value: 'oz', child: Text('oz')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _ocrUnit = v;
                            _reviewBasisLabel = _buildReviewBasisLabel();
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Nutritional Information',
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
                onPressed: () async {
                  await _confirmOcrValues();
                },
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
