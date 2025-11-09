import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';

// ============================================================================
// BATCH 1: Core Data Models with Improvements
// ============================================================================

/// Represents a segmented food region with actual mask data and real bounding box
class SegmentedFood {
  String id;
  Rect boundingBox; // Real bounding box calculated from mask
  Uint8List mask; // CHANGED: Actual binary mask data (1D array, width*height)
  int maskWidth; // Width of the mask
  int maskHeight; // Height of the mask
  double confidence;
  String? foodName;
  String? segmentationSource;
  String? classificationSource;
  int? caloriesPer100g; // RENAMED: Clearer that this is per 100g
  Map<String, int>? macrosPer100g; // RENAMED: Clearer that this is per 100g
  Offset? center; // Center in segmentation coordinates
  int gramsAmount; // CHANGED: Actual grams (not multiplier)
  List<FoodPrediction> perRegionPredictions =
      []; // NEW: Per-region classification predictions

  SegmentedFood({
    required this.id,
    required this.boundingBox,
    required this.mask,
    required this.maskWidth,
    required this.maskHeight,
    required this.confidence,
    this.foodName,
    this.segmentationSource,
    this.classificationSource,
    this.caloriesPer100g,
    this.macrosPer100g,
    this.center,
    this.gramsAmount = 100, // Default 100g serving
  });

  /// Calculate actual calories based on grams
  int get actualCalories =>
      ((caloriesPer100g ?? 0) * gramsAmount / 100.0).round();

  /// Calculate actual macros based on grams
  Map<String, int> get actualMacros {
    if (macrosPer100g == null) return {'carbs': 0, 'protein': 0, 'fat': 0};
    return {
      'carbs': ((macrosPer100g!['carbs'] ?? 0) * gramsAmount / 100.0).round(),
      'protein': ((macrosPer100g!['protein'] ?? 0) * gramsAmount / 100.0)
          .round(),
      'fat': ((macrosPer100g!['fat'] ?? 0) * gramsAmount / 100.0).round(),
    };
  }

  /// Get cropped image from original image using the mask
  img.Image? getCroppedImage(img.Image originalImage) {
    if (mask.isEmpty) return null;

    // Scale bounding box from segmentation coordinates to original image coordinates
    final scaleX = originalImage.width / maskWidth;
    final scaleY = originalImage.height / maskHeight;

    final scaledBox = Rect.fromLTRB(
      (boundingBox.left * scaleX).clamp(0, originalImage.width.toDouble()),
      (boundingBox.top * scaleY).clamp(0, originalImage.height.toDouble()),
      (boundingBox.right * scaleX).clamp(0, originalImage.width.toDouble()),
      (boundingBox.bottom * scaleY).clamp(0, originalImage.height.toDouble()),
    );

    // Crop the original image to bounding box
    final cropped = img.copyCrop(
      originalImage,
      x: scaledBox.left.toInt(),
      y: scaledBox.top.toInt(),
      width: (scaledBox.width).toInt(),
      height: (scaledBox.height).toInt(),
    );

    return cropped;
  }

  /// Get highlighted/masked image showing only this food region
  img.Image? getHighlightedImage(img.Image originalImage) {
    if (mask.isEmpty) return getCroppedImage(originalImage);

    final scaleX = originalImage.width / maskWidth;
    final scaleY = originalImage.height / maskHeight;

    // Create a copy of the cropped region
    final cropped = getCroppedImage(originalImage);
    if (cropped == null) return null;

    // Apply mask transparency to show only the food region
    final result = img.Image(width: cropped.width, height: cropped.height);

    for (int y = 0; y < cropped.height; y++) {
      for (int x = 0; x < cropped.width; x++) {
        // Map back to mask coordinates
        final maskX = ((boundingBox.left + x / scaleX))
            .clamp(0, maskWidth - 1)
            .toInt();
        final maskY = ((boundingBox.top + y / scaleY))
            .clamp(0, maskHeight - 1)
            .toInt();
        final maskIdx = maskY * maskWidth + maskX;

        if (maskIdx < mask.length && mask[maskIdx] > 0) {
          // Food region - copy original pixel
          result.setPixel(x, y, cropped.getPixel(x, y));
        } else {
          // Non-food region - make it semi-transparent gray
          result.setPixel(x, y, img.ColorRgba8(200, 200, 200, 100));
        }
      }
    }

    return result;
  }
}

class FoodPrediction {
  String foodName;
  double confidence;
  int caloriesPer100g; // RENAMED: Clearer
  Map<String, int> macrosPer100g; // RENAMED: Clearer
  String source;

  FoodPrediction({
    required this.foodName,
    required this.confidence,
    required this.caloriesPer100g,
    required this.macrosPer100g,
    required this.source,
  });
}

/// Helper class for connected component analysis
class ConnectedComponent {
  List<Point<int>> pixels = [];
  int minX = 999999;
  int maxX = 0;
  int minY = 999999;
  int maxY = 0;

  void addPixel(int x, int y) {
    pixels.add(Point(x, y));
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }

  Rect get boundingBox => Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    (maxX + 1).toDouble(),
    (maxY + 1).toDouble(),
  );

  Offset get center => Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);

  int get area => pixels.length;

  /// Create binary mask for this component
  Uint8List createMask(int width, int height) {
    final mask = Uint8List(width * height);
    for (final p in pixels) {
      final idx = p.y * width + p.x;
      if (idx >= 0 && idx < mask.length) {
        mask[idx] = 255; // Mark as food region
      }
    }
    return mask;
  }
}

// ============================================================================
// Nutrition Data Model & API Service
// ============================================================================

/// Nutrition data model for API responses
class NutritionData {
  final int caloriesPer100g;
  final Map<String, int> macrosPer100g; // carbs, protein, fat
  final String? source; // API source name

  NutritionData({
    required this.caloriesPer100g,
    required this.macrosPer100g,
    this.source,
  });

  factory NutritionData.fromJson(Map<String, dynamic> json, {String? source}) {
    // Extract nutrition values (per 100g)
    final energy =
        json['energy-kcal_100g']?.toDouble() ??
        json['energy']?.toDouble() ??
        json['calories']?.toDouble() ??
        0.0;

    final carbs =
        json['carbohydrates_100g']?.toDouble() ??
        json['carbs']?.toDouble() ??
        0.0;
    final protein =
        json['proteins_100g']?.toDouble() ?? json['protein']?.toDouble() ?? 0.0;
    final fat = json['fat_100g']?.toDouble() ?? json['fat']?.toDouble() ?? 0.0;

    return NutritionData(
      caloriesPer100g: energy.round(),
      macrosPer100g: {
        'carbs': carbs.round(),
        'protein': protein.round(),
        'fat': fat.round(),
      },
      source: source ?? 'API',
    );
  }

  // Fallback constructor with default values
  factory NutritionData.defaultValues() {
    return NutritionData(
      caloriesPer100g: 150,
      macrosPer100g: {'carbs': 30, 'protein': 10, 'fat': 5},
      source: 'Default',
    );
  }
}

/// Nutrition API Service - Uses Open Food Facts (free, no API key required)
class NutritionService {
  static final NutritionService _instance = NutritionService._internal();
  factory NutritionService() => _instance;
  NutritionService._internal();

  // Cache to avoid repeated API calls
  final Map<String, NutritionData> _cache = {};

  /// Check if nutrition data is cached
  NutritionData? getCachedNutrition(String foodName) {
    return _cache[foodName.toLowerCase().trim()];
  }

  /// Fetch nutrition data from Open Food Facts API (free, no API key)
  Future<NutritionData> fetchNutrition(String foodName) async {
    // Check cache first
    final cacheKey = foodName.toLowerCase().trim();
    if (_cache.containsKey(cacheKey)) {
      print('Using cached nutrition data for: $foodName');
      return _cache[cacheKey]!;
    }

    try {
      print('Fetching nutrition data for: $foodName');

      // Clean food name for API search
      final searchQuery = _cleanFoodName(foodName);

      // Open Food Facts API - completely free, no API key needed
      // Search endpoint: https://world.openfoodfacts.org/cgi/search.pl
      final searchUrl = Uri.parse(
        'https://world.openfoodfacts.org/cgi/search.pl?'
        'action=process&'
        'tagtype_0=categories&'
        'tag_contains_0=contains&'
        'tag_0=$searchQuery&'
        'page_size=1&'
        'json=true&'
        'fields=product_name,energy-kcal_100g,carbohydrates_100g,proteins_100g,fat_100g',
      );

      final response = await http
          .get(searchUrl)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw Exception('API request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['products'] != null && (data['products'] as List).isNotEmpty) {
          final product = (data['products'] as List)[0];

          // Extract nutrition values
          final nutrition = NutritionData.fromJson(
            product as Map<String, dynamic>,
            source: 'Open Food Facts',
          );

          // Cache the result
          _cache[cacheKey] = nutrition;

          print(
            '✓ Found nutrition data: ${nutrition.caloriesPer100g} kcal/100g',
          );
          return nutrition;
        }
      }

      // If no results, try alternative search
      return await _tryAlternativeSearch(foodName, cacheKey);
    } catch (e) {
      print('Error fetching nutrition from API: $e');
      // Return default values on error
      final defaultData = NutritionData.defaultValues();
      _cache[cacheKey] = defaultData;
      return defaultData;
    }
  }

  /// Try alternative search methods
  Future<NutritionData> _tryAlternativeSearch(
    String foodName,
    String cacheKey,
  ) async {
    try {
      // Try searching with simplified name
      final simplifiedName = _simplifyFoodName(foodName);
      if (simplifiedName != foodName.toLowerCase()) {
        return await fetchNutrition(simplifiedName);
      }

      // Try USDA FoodData Central (free, no API key for basic search)
      // Note: This is a fallback, Open Food Facts is primary
      final usdaUrl = Uri.parse(
        'https://api.nal.usda.gov/fdc/v1/foods/search?'
        'query=${Uri.encodeComponent(foodName)}&'
        'pageSize=1',
      );

      final response = await http
          .get(usdaUrl)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['foods'] != null && (data['foods'] as List).isNotEmpty) {
          final food = (data['foods'] as List)[0];
          final nutrients = food['foodNutrients'] as List?;

          if (nutrients != null) {
            int calories = 0;
            double carbs = 0;
            double protein = 0;
            double fat = 0;

            for (var nutrient in nutrients) {
              final nutrientId = nutrient['nutrientId'];
              final value = nutrient['value']?.toDouble() ?? 0.0;

              // USDA nutrient IDs
              if (nutrientId == 1008) calories = value.round(); // Energy (kcal)
              if (nutrientId == 1005) carbs = value; // Carbohydrate
              if (nutrientId == 1003) protein = value; // Protein
              if (nutrientId == 1004) fat = value; // Fat
            }

            final nutrition = NutritionData(
              caloriesPer100g: calories,
              macrosPer100g: {
                'carbs': carbs.round(),
                'protein': protein.round(),
                'fat': fat.round(),
              },
              source: 'USDA FoodData',
            );

            _cache[cacheKey] = nutrition;
            print('✓ Found nutrition data from USDA: $calories kcal/100g');
            return nutrition;
          }
        }
      }
    } catch (e) {
      print('Alternative search failed: $e');
    }

    // Return default if all searches fail
    final defaultData = NutritionData.defaultValues();
    _cache[cacheKey] = defaultData;
    return defaultData;
  }

  /// Clean food name for API search
  String _cleanFoodName(String foodName) {
    return foodName
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special chars
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
        .trim();
  }

  /// Simplify food name (remove common prefixes/suffixes)
  String _simplifyFoodName(String foodName) {
    final lower = foodName.toLowerCase();

    // Remove common prefixes
    final prefixes = ['grilled ', 'fried ', 'baked ', 'roasted ', 'steamed '];
    String simplified = lower;
    for (final prefix in prefixes) {
      if (simplified.startsWith(prefix)) {
        simplified = simplified.substring(prefix.length);
        break;
      }
    }

    return simplified.trim();
  }

  /// Clear cache (useful for testing or memory management)
  void clearCache() {
    _cache.clear();
  }
}

// ============================================================================
// Food Recognition Page
// ============================================================================

class FoodRecognitionPage extends StatefulWidget {
  final String mealType;
  final XFile imageFile;

  const FoodRecognitionPage({
    Key? key,
    required this.mealType,
    required this.imageFile,
  }) : super(key: key);

  @override
  State<FoodRecognitionPage> createState() => _FoodRecognitionPageState();
}

class _FoodRecognitionPageState extends State<FoodRecognitionPage>
    with TickerProviderStateMixin {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Models
  Interpreter? _segmentationModel;
  Interpreter? _kenyanFoodModel;
  Interpreter? _food101Model;

  // Recognition results
  List<SegmentedFood> _segmentedFoods = [];
  List<FoodPrediction> _topPredictions = [];
  bool _isProcessing = true;
  String? _errorMessage;

  // Image
  File? _imageFile;
  img.Image? _processedImage;
  img.Image? _originalImage;

  // User goals - loaded from Firestore
  int dailyGoal = 0;
  int carbsTarget = 0;
  int proteinTarget = 0;
  int fatTarget = 0;
  bool _userGoalsLoaded = false;

  // Today's consumed values (before this meal)
  int todayCaloriesConsumed = 0;
  int todayCarbsConsumed = 0;
  int todayProteinConsumed = 0;
  int todayFatConsumed = 0;

  double _processingProgress = 0.0;
  int _currentStage = 0;

  // Stream for real-time detection updates
  final StreamController<List<SegmentedFood>> _detectionStreamController =
      StreamController<List<SegmentedFood>>.broadcast();
  Stream<List<SegmentedFood>> get detectionStream =>
      _detectionStreamController.stream;

  // Animation controllers for progress rings
  late AnimationController _calorieAnimationController;
  late AnimationController _carbsAnimationController;
  late AnimationController _proteinAnimationController;
  late AnimationController _fatAnimationController;

  late Animation<double> _calorieAnimation;
  late Animation<double> _carbsAnimation;
  late Animation<double> _proteinAnimation;
  late Animation<double> _fatAnimation;

  @override
  void initState() {
    super.initState();
    _imageFile = File(widget.imageFile.path);

    // Initialize animation controllers
    _calorieAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _carbsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _proteinAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fatAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Create animations with curves
    _calorieAnimation = CurvedAnimation(
      parent: _calorieAnimationController,
      curve: Curves.easeOutCubic,
    );
    _carbsAnimation = CurvedAnimation(
      parent: _carbsAnimationController,
      curve: Curves.easeOutCubic,
    );
    _proteinAnimation = CurvedAnimation(
      parent: _proteinAnimationController,
      curve: Curves.easeOutCubic,
    );
    _fatAnimation = CurvedAnimation(
      parent: _fatAnimationController,
      curve: Curves.easeOutCubic,
    );

    _fetchUserGoalsAndTodayIntake().then((_) {
      _loadModelsAndProcess();
    });
  }

  @override
  void dispose() {
    _segmentationModel?.close();
    _kenyanFoodModel?.close();
    _food101Model?.close();

    // Dispose animation controllers
    _calorieAnimationController.dispose();
    _carbsAnimationController.dispose();
    _proteinAnimationController.dispose();
    _fatAnimationController.dispose();

    // Close stream controller
    _detectionStreamController.close();

    super.dispose();
  }

  Future<void> _loadModelsAndProcess() async {
    try {
      setState(() {
        _currentStage = 0;
        _processingProgress = 0.1;
      });
      await _loadModels();
      setState(() {
        _currentStage = 1;
        _processingProgress = 0.3;
      });
      await _processImage();
      setState(() {
        _currentStage = 2;
        _processingProgress = 0.7;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() {
        _currentStage = 3;
        _processingProgress = 1.0;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to process image: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _loadModels() async {
    try {
      print('Loading models...');

      _segmentationModel = await Interpreter.fromAsset(
        'assets/uec_unet_int8.tflite',
      );
      print('✓ Segmentation model loaded');
      print('  Input shape: ${_segmentationModel!.getInputTensor(0).shape}');
      print('  Output shape: ${_segmentationModel!.getOutputTensor(0).shape}');

      _kenyanFoodModel = await Interpreter.fromAsset(
        'assets/kenyanfood.tflite',
      );
      print('✓ Kenyan food model loaded');
      print('  Input shape: ${_kenyanFoodModel!.getInputTensor(0).shape}');
      print('  Output shape: ${_kenyanFoodModel!.getOutputTensor(0).shape}');

      _food101Model = await Interpreter.fromAsset('assets/food101.tflite');
      print('✓ Food101 model loaded');
      print('  Input shape: ${_food101Model!.getInputTensor(0).shape}');
      print('  Output shape: ${_food101Model!.getOutputTensor(0).shape}');

      print('All models loaded successfully');
    } catch (e) {
      print('Model loading error: $e');
      throw Exception('Model loading failed: $e');
    }
  }

  Future<void> _processImage() async {
    try {
      print('Processing image...');

      final imageBytes = await _imageFile!.readAsBytes();
      _originalImage = img.decodeImage(imageBytes);

      if (_originalImage == null) {
        throw Exception('Failed to decode image');
      }

      print(
        'Image decoded: ${_originalImage!.width}x${_originalImage!.height}',
      );

      _processedImage = img.copyResize(
        _originalImage!,
        width: math.min(_originalImage!.width, 512),
        height: math.min(_originalImage!.height, 512),
      );

      print('Running segmentation...');
      await _runSegmentation();

      print('Running classification...');
      await _runClassification();

      print('Image processing completed');
    } catch (e) {
      print('Image processing error: $e');
      throw Exception('Image processing failed: $e');
    }
  }

  // ============================================================================
  // BATCH 2: Improved Segmentation with Connected Components & Real Bounding Boxes
  // ============================================================================

  Future<void> _runSegmentation() async {
    if (_segmentationModel == null || _processedImage == null) {
      print('Segmentation model or image is null');
      return;
    }

    try {
      final inputShape = _segmentationModel!.getInputTensor(0).shape;
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];

      print('Segmentation input size: ${inputWidth}x${inputHeight}');

      final resizedImage = img.copyResize(
        _processedImage!,
        width: inputWidth,
        height: inputHeight,
      );

      final inputType = _segmentationModel!.getInputTensor(0).type;
      final input = _prepareImageInput(
        resizedImage,
        inputWidth,
        inputHeight,
        inputType,
      );

      final outputShape = _segmentationModel!.getOutputTensor(0).shape;
      final outputType = _segmentationModel!.getOutputTensor(0).type;

      print('Output shape: $outputShape, type: $outputType');

      dynamic output;
      if (outputType == TensorType.float32) {
        output = List.generate(
          outputShape[0],
          (_) => List.generate(
            outputShape[1],
            (_) => List.generate(
              outputShape[2],
              (_) => List<double>.filled(outputShape[3], 0.0),
            ),
          ),
        );
      } else if (outputType == TensorType.uint8) {
        final totalSize =
            outputShape[0] * outputShape[1] * outputShape[2] * outputShape[3];
        output = Uint8List(totalSize);
      } else {
        throw Exception('Unsupported output type: $outputType');
      }

      print('Running segmentation inference...');
      _segmentationModel!.run(input, output);
      print('Segmentation inference completed');

      _processSegmentationOutput(output, outputShape, outputType);
    } catch (e) {
      print('Segmentation error: $e');
      print('Stack trace: ${StackTrace.current}');
      print('Creating fallback segments...');
      _createFallbackSegment();
    }
  }

  dynamic _prepareImageInput(
    img.Image image,
    int width,
    int height,
    TensorType inputType,
  ) {
    if (inputType == TensorType.uint8) {
      final buffer = Uint8List(1 * height * width * 3);
      int index = 0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = image.getPixel(x, y);
          buffer[index++] = pixel.r.toInt();
          buffer[index++] = pixel.g.toInt();
          buffer[index++] = pixel.b.toInt();
        }
      }
      return buffer.reshape([1, height, width, 3]);
    } else {
      return List.generate(
        1,
        (_) => List.generate(
          height,
          (y) => List.generate(width, (x) {
            final pixel = image.getPixel(x, y);
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          }),
        ),
      );
    }
  }

  /// IMPROVED: Process segmentation with connected component analysis
  void _processSegmentationOutput(
    dynamic output,
    List<int> outputShape,
    TensorType outputType,
  ) {
    try {
      print('Processing segmentation output with connected components...');
      final height = outputShape[1];
      final width = outputShape[2];
      final numClasses = outputShape[3];

      // Step 1: Get class predictions for each pixel
      final classMap = Uint8List(
        width * height,
      ); // Store predicted class for each pixel
      final confidenceMap = List<double>.filled(width * height, 0.0);

      if (outputType == TensorType.uint8) {
        final flatOutput = output as Uint8List;
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            int maxClass = 0;
            double maxProb = 0.0;
            final baseIdx = (y * width + x) * numClasses;

            for (int c = 0; c < numClasses && c < uecUnetLabels.length; c++) {
              final quantizedValue = flatOutput[baseIdx + c];
              final prob = quantizedValue / 255.0;
              if (prob > maxProb) {
                maxProb = prob;
                maxClass = c;
              }
            }

            final pixelIdx = y * width + x;
            if (maxProb > 0.3 && maxClass > 0) {
              // Threshold: 30% confidence, not background
              classMap[pixelIdx] = maxClass;
              confidenceMap[pixelIdx] = maxProb;
            }
          }
        }
      } else {
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            int maxClass = 0;
            double maxProb = 0.0;

            for (int c = 0; c < numClasses && c < uecUnetLabels.length; c++) {
              final prob = output[0][y][x][c];
              if (prob > maxProb) {
                maxProb = prob;
                maxClass = c;
              }
            }

            final pixelIdx = y * width + x;
            if (maxProb > 0.3 && maxClass > 0) {
              classMap[pixelIdx] = maxClass;
              confidenceMap[pixelIdx] = maxProb;
            }
          }
        }
      }

      // Step 2: Connected component analysis for each food class
      final components =
          <int, List<ConnectedComponent>>{}; // classId -> list of components
      final visited = List<bool>.filled(width * height, false);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixelIdx = y * width + x;
          if (!visited[pixelIdx] && classMap[pixelIdx] > 0) {
            final classId = classMap[pixelIdx];
            final component = _floodFill(
              classMap,
              visited,
              x,
              y,
              width,
              height,
              classId,
            );

            if (component.area > (width * height * 0.01)) {
              // Min 1% of image
              components.putIfAbsent(classId, () => []).add(component);
            }
          }
        }
      }

      print(
        'Found ${components.length} food classes with ${components.values.fold(0, (sum, list) => sum + list.length)} total regions',
      );

      // Step 3: Convert components to SegmentedFood objects
      _segmentedFoods = [];
      int foodId = 0;

      components.forEach((classId, componentList) {
        for (final component in componentList) {
          // Calculate average confidence for this component
          double totalConfidence = 0.0;
          int count = 0;
          for (final pixel in component.pixels) {
            final idx = pixel.y * width + pixel.x;
            totalConfidence += confidenceMap[idx];
            count++;
          }
          final avgConfidence = count > 0 ? totalConfidence / count : 0.5;

          // Create mask for this component
          final mask = component.createMask(width, height);

          // Get food name from UEC labels
          final foodName = classId < uecUnetLabels.length
              ? uecUnetLabels[classId]
              : 'Unknown';

          print(
            'Region ${foodId + 1}: $foodName (${(avgConfidence * 100).toStringAsFixed(1)}%, ${component.area} pixels)',
          );

          _segmentedFoods.add(
            SegmentedFood(
              id: foodId.toString(),
              boundingBox: component.boundingBox,
              mask: mask,
              maskWidth: width,
              maskHeight: height,
              confidence: avgConfidence,
              foodName: foodName,
              segmentationSource: 'UEC UNET',
              center: component.center,
              gramsAmount: 100, // Default 100g
            ),
          );

          // Emit real-time update to stream
          if (!_detectionStreamController.isClosed) {
            _detectionStreamController.add(List.from(_segmentedFoods));
          }

          foodId++;
          if (foodId >= 5) break; // Limit to 5 food items
        }
        if (foodId >= 5) return;
      });

      if (_segmentedFoods.isEmpty) {
        print('No foods detected, creating fallback segment');
        _createFallbackSegment();
      } else {
        print('Created ${_segmentedFoods.length} segmented food regions');
        // Emit final update
        if (!_detectionStreamController.isClosed) {
          _detectionStreamController.add(List.from(_segmentedFoods));
        }
      }
    } catch (e) {
      print('Error processing segmentation output: $e');
      print('Stack trace: ${StackTrace.current}');
      _createFallbackSegment();
    }
  }

  /// Flood fill algorithm for connected component analysis
  ConnectedComponent _floodFill(
    Uint8List classMap,
    List<bool> visited,
    int startX,
    int startY,
    int width,
    int height,
    int targetClass,
  ) {
    final component = ConnectedComponent();
    final queue = <Point<int>>[];
    queue.add(Point(startX, startY));

    while (queue.isNotEmpty) {
      final point = queue.removeAt(0);
      final x = point.x;
      final y = point.y;

      if (x < 0 || x >= width || y < 0 || y >= height) continue;

      final idx = y * width + x;
      if (visited[idx]) continue;
      if (classMap[idx] != targetClass) continue;

      visited[idx] = true;
      component.addPixel(x, y);

      // Check 4-connected neighbors
      queue.add(Point(x + 1, y));
      queue.add(Point(x - 1, y));
      queue.add(Point(x, y + 1));
      queue.add(Point(x, y - 1));
    }

    return component;
  }

  void _createFallbackSegment() {
    // Create a single region when segmentation fails
    final width = 256;
    final height = 256;
    final mask = Uint8List(width * height);

    // Fill center region as food
    for (int y = height ~/ 4; y < height * 3 ~/ 4; y++) {
      for (int x = width ~/ 4; x < width * 3 ~/ 4; x++) {
        mask[y * width + x] = 255;
      }
    }

    _segmentedFoods = [
      SegmentedFood(
        id: '0',
        boundingBox: Rect.fromLTWH(
          width / 4,
          height / 4,
          width / 2,
          height / 2,
        ),
        mask: mask,
        maskWidth: width,
        maskHeight: height,
        confidence: 0.5,
        foodName: null, // Will be filled by classification
        segmentationSource: 'Fallback',
        center: Offset(width / 2, height / 2),
        gramsAmount: 100,
      ),
    ];
    print('Created fallback segment');
  }

  // Continue to batch 3...

  // ============================================================================
  // BATCH 3: Classification & FIXED Prediction Priority Logic
  // ============================================================================

  Future<void> _runClassification() async {
    if (_processedImage == null) {
      print('No image for classification');
      return;
    }

    try {
      print('Running multi-food classification on each segmented region...');

      List<FoodPrediction> allPredictions = [];

      // NEW: Run classification on EACH cropped food region for better accuracy
      for (int i = 0; i < _segmentedFoods.length; i++) {
        final food = _segmentedFoods[i];
        print(
          '\n--- Classifying region ${i + 1}/${_segmentedFoods.length} ---',
        );

        // Get cropped image for this food region
        final croppedImage = food.getCroppedImage(_processedImage!);

        if (croppedImage != null) {
          print(
            '  Cropped image size: ${croppedImage.width}x${croppedImage.height}',
          );

          // Run both classification models on the cropped region
          final kenyanPredictions = await _runKenyanFoodClassification(
            croppedImage,
          );
          final food101Predictions = await _runFood101Classification(
            croppedImage,
          );

          // Store per-region predictions (will be used in assignment)
          food.perRegionPredictions = [
            ...kenyanPredictions,
            ...food101Predictions,
          ];

          // Also add to global predictions list for fallback
          allPredictions.addAll(kenyanPredictions);
          allPredictions.addAll(food101Predictions);

          print(
            '  Found ${kenyanPredictions.length + food101Predictions.length} predictions for this region',
          );
        } else {
          print('  Warning: Could not crop image for region ${i + 1}');
        }
      }

      // Also run on full image as fallback
      print('\n--- Running classification on full image (fallback) ---');
      final fullKenyanPredictions = await _runKenyanFoodClassification(
        _processedImage!,
      );
      final fullFood101Predictions = await _runFood101Classification(
        _processedImage!,
      );

      allPredictions.addAll(fullKenyanPredictions);
      allPredictions.addAll(fullFood101Predictions);

      // Sort by confidence (highest first)
      allPredictions.sort((a, b) => b.confidence.compareTo(a.confidence));
      _topPredictions = allPredictions;

      print(
        '\nGot ${_topPredictions.length} total predictions (including fallback)',
      );

      // Print top 5 predictions
      for (int i = 0; i < math.min(5, _topPredictions.length); i++) {
        final pred = _topPredictions[i];
        print(
          '  ${i + 1}. ${pred.foodName} (${(pred.confidence * 100).toStringAsFixed(1)}%) - ${pred.source}',
        );
      }

      // Fetch nutrition data from API for all predictions (non-Kenyan foods)
      await _fetchNutritionForPredictions(_topPredictions);

      // Also fetch for per-region predictions
      for (var food in _segmentedFoods) {
        if (food.perRegionPredictions.isNotEmpty) {
          await _fetchNutritionForPredictions(food.perRegionPredictions);
        }
      }

      // FIXED: Assign predictions with proper priority (now uses per-region predictions)
      _assignPredictionsToSegments();

      // Estimate portion sizes AFTER food names are assigned (needed for density calculation)
      _estimatePortionSizes();

      // Update animations and UI with new nutrition data
      if (mounted) {
        _updateAnimations();
        setState(() {});
      }
    } catch (e) {
      print('Classification error: $e');
      _assignDummyPredictions();
    }
  }

  /// IMPROVED: Now uses per-region predictions for better accuracy
  void _assignPredictionsToSegments() {
    if (_segmentedFoods.isEmpty) {
      print('No segments to assign predictions to');
      return;
    }

    print('\n=== PREDICTION ASSIGNMENT (PER-REGION CLASSIFICATION) ===');

    for (int i = 0; i < _segmentedFoods.length; i++) {
      final segment = _segmentedFoods[i];

      // Build list of all possible predictions for this segment
      List<FoodPrediction> candidatePredictions = [];

      // 1. Add segmentation prediction with its confidence
      if (segment.foodName != null && segment.foodName!.isNotEmpty) {
        candidatePredictions.add(
          FoodPrediction(
            foodName: segment.foodName!,
            confidence: segment.confidence,
            caloriesPer100g: _getCaloriesForFood(segment.foodName!),
            macrosPer100g: _getMacrosForFood(segment.foodName!),
            source: segment.segmentationSource ?? 'UEC UNET',
          ),
        );
      }

      // 2. NEW: Prioritize per-region predictions (more accurate for this specific region)
      if (segment.perRegionPredictions.isNotEmpty) {
        candidatePredictions.addAll(segment.perRegionPredictions);
        print(
          'Segment ${i + 1}: Using ${segment.perRegionPredictions.length} per-region predictions',
        );
      }

    

      // 4. Sort by confidence (highest first)
      candidatePredictions.sort((a, b) => b.confidence.compareTo(a.confidence));

      // 5. Pick the highest confidence prediction
      if (candidatePredictions.isNotEmpty) {
        final bestPrediction = candidatePredictions[0];

        print('Segment ${i + 1}:');
        print(
          '  Segmentation: ${segment.foodName ?? "None"} (${(segment.confidence * 100).toStringAsFixed(1)}%)',
        );
        if (segment.perRegionPredictions.isNotEmpty) {
          print(
            '  Best per-region: ${segment.perRegionPredictions[0].foodName} (${(segment.perRegionPredictions[0].confidence * 100).toStringAsFixed(1)}%)',
          );
        }
        print(
          '  ✓ CHOSEN: ${bestPrediction.foodName} (${(bestPrediction.confidence * 100).toStringAsFixed(1)}%) - ${bestPrediction.source}',
        );

        // Apply the best prediction
        segment.foodName = bestPrediction.foodName;
        segment.caloriesPer100g = bestPrediction.caloriesPer100g;
        segment.macrosPer100g = bestPrediction.macrosPer100g;
        segment.classificationSource = bestPrediction.source;

        // Update confidence if classification was chosen
        if (bestPrediction.source != segment.segmentationSource) {
          segment.confidence = bestPrediction.confidence;
        }
      } else {
        // Fallback if no predictions at all
        print('Segment ${i + 1}: No predictions available, using defaults');
        segment.foodName = segment.foodName ?? 'Unknown Food';
        segment.caloriesPer100g = 150;
        segment.macrosPer100g = {'carbs': 30, 'protein': 10, 'fat': 5};
      }
    }

    print('=== ASSIGNMENT COMPLETE ===\n');
  }

  void _assignDummyPredictions() {
    for (var segment in _segmentedFoods) {
      if (segment.foodName == null || segment.foodName!.isEmpty) {
        segment.foodName = 'Unknown Food';
      }
      segment.caloriesPer100g = 150;
      segment.macrosPer100g = {'carbs': 30, 'protein': 10, 'fat': 5};
    }
  }

  FoodPrediction _createDummyPrediction() {
    return FoodPrediction(
      foodName: 'Unknown',
      confidence: 0.5,
      caloriesPer100g: 150,
      macrosPer100g: {'carbs': 30, 'protein': 10, 'fat': 5},
      source: 'Fallback',
    );
  }

  Future<List<FoodPrediction>> _runKenyanFoodClassification(
    img.Image image,
  ) async {
    if (_kenyanFoodModel == null) {
      print('Kenyan food model is null');
      return [];
    }

    try {
      print('Running Kenyan food classification...');

      final inputShape = _kenyanFoodModel!.getInputTensor(0).shape;
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      final inputType = _kenyanFoodModel!.getInputTensor(0).type;

      print(
        'Kenyan model input: ${inputWidth}x${inputHeight}, type: $inputType',
      );

      final resizedImage = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
      );

      final input = _prepareImageInput(
        resizedImage,
        inputWidth,
        inputHeight,
        inputType,
      );

      final outputShape = _kenyanFoodModel!.getOutputTensor(0).shape;
      final outputType = _kenyanFoodModel!.getOutputTensor(0).type;
      final numClasses = outputShape[1];

      print('Kenyan model output: $numClasses classes, type: $outputType');

      dynamic output;
      if (outputType == TensorType.float32) {
        output = [List<double>.filled(numClasses, 0.0)];
      } else if (outputType == TensorType.uint8) {
        output = [Uint8List(numClasses)];
      } else {
        throw Exception('Unsupported output type: $outputType');
      }

      _kenyanFoodModel!.run(input, output);
      print('Kenyan food inference completed');

      List<double> probabilities;
      if (output[0] is Uint8List) {
        probabilities = (output[0] as Uint8List).map((e) => e / 255.0).toList();
      } else if (output[0] is List<double>) {
        probabilities = output[0];
      } else {
        probabilities = List<double>.filled(numClasses, 0.0);
      }

      final predictions = _processClassificationOutput(
        probabilities,
        kenyanFoodLabels,
        'Kenyan Food Model',
      );

      print('Kenyan predictions: ${predictions.length}');
      return predictions;
    } catch (e) {
      print('Kenyan food classification error: $e');
      return [];
    }
  }

  Future<List<FoodPrediction>> _runFood101Classification(
    img.Image image,
  ) async {
    if (_food101Model == null) {
      print('Food101 model is null');
      return [];
    }

    try {
      print('Running Food101 classification...');

      final inputShape = _food101Model!.getInputTensor(0).shape;
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      final inputType = _food101Model!.getInputTensor(0).type;

      print(
        'Food101 model input: ${inputWidth}x${inputHeight}, type: $inputType',
      );

      final resizedImage = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
      );

      final input = _prepareImageInput(
        resizedImage,
        inputWidth,
        inputHeight,
        inputType,
      );

      final outputShape = _food101Model!.getOutputTensor(0).shape;
      final outputType = _food101Model!.getOutputTensor(0).type;
      final numClasses = outputShape[1];

      print('Food101 model output: $numClasses classes, type: $outputType');

      dynamic output;
      if (outputType == TensorType.float32) {
        output = [List<double>.filled(numClasses, 0.0)];
      } else if (outputType == TensorType.uint8) {
        output = [Uint8List(numClasses)];
      } else {
        throw Exception('Unsupported output type: $outputType');
      }

      _food101Model!.run(input, output);
      print('Food101 inference completed');

      List<double> probabilities;
      if (output[0] is Uint8List) {
        probabilities = (output[0] as Uint8List).map((e) => e / 255.0).toList();
      } else if (output[0] is List<double>) {
        probabilities = output[0];
      } else {
        probabilities = List<double>.filled(numClasses, 0.0);
      }

      final predictions = _processClassificationOutput(
        probabilities,
        food101Labels,
        'Food101 Model',
      );

      print('Food101 predictions: ${predictions.length}');
      return predictions;
    } catch (e) {
      print('Food101 classification error: $e');
      return [];
    }
  }

  List<FoodPrediction> _processClassificationOutput(
    List<double> output,
    List<String> labels,
    String source,
  ) {
    List<FoodPrediction> predictions = [];

    for (int i = 0; i < output.length && i < labels.length; i++) {
      if (output[i] > 0.05) {
        // 5% confidence threshold
        predictions.add(
          FoodPrediction(
            foodName: labels[i],
            confidence: output[i],
            caloriesPer100g: _getCaloriesForFood(labels[i]),
            macrosPer100g: _getMacrosForFood(labels[i]),
            source: source,
          ),
        );
      }
    }

    predictions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return predictions.take(10).toList();
  }

  // Continue to batch 4...

  // ============================================================================
  // BATCH 4: Nutrition Database, Firestore & Calculations
  // ============================================================================

  // Nutrition service instance
  final _nutritionService = NutritionService();

  // Kenyan foods list (keep static database for these)
  static const List<String> _kenyanFoods = [
    'Bhaji',
    'Chapati',
    'Githeri',
    'Kachumbari',
    'Kuku Choma',
    'Mandazi',
    'Masala Chips',
    'Matoke',
    'Mukimo',
    'Nyama Choma',
    'Pilau',
    'Sukuma Wiki',
    'Ugali',
  ];

  // Static calorie and macro data for Kenyan foods only (per 100g serving)
  int _getCaloriesForFood(String foodName) {
    // Check if it's a Kenyan food - use static database
    if (_kenyanFoods.contains(foodName)) {
      final calorieDb = {
        'Bhaji': 120,
        'Chapati': 140,
        'Githeri': 180,
        'Kachumbari': 45,
        'Kuku Choma': 165,
        'Mandazi': 160,
        'Masala Chips': 280,
        'Matoke': 150,
        'Mukimo': 170,
        'Nyama Choma': 250,
        'Pilau': 220,
        'Sukuma Wiki': 45,
        'Ugali': 180,
      };
      return calorieDb[foodName] ?? 150;
    }

    // For non-Kenyan foods, check API cache first, then use static fallback
    final cached = _nutritionService.getCachedNutrition(foodName);
    if (cached != null) {
      return cached.caloriesPer100g;
    }

    // Static fallback for non-Kenyan foods (will be replaced by API data)
    final fallbackDb = {
      'Rice': 206,
      'Chicken': 165,
      'Beef': 250,
      'Fish': 120,
      'Beans': 127,
      'Pizza': 266,
      'Hamburger': 295,
      'Salad': 50,
      'Soup': 80,
      'Bread': 265,
      'Noodles': 138,
      'Curry': 195,
      'Steak': 271,
      'Sushi': 143,
      'Pasta': 131,
      'Sandwich': 200,
      'Fries': 312,
      'Apple Pie': 237,
      'Cheesecake': 321,
      'Chocolate Cake': 352,
      'Ice Cream': 207,
      'Pancakes': 227,
      'Waffles': 291,
      'Donuts': 452,
      'French Toast': 202,
      'Fried Rice': 228,
      'Grilled Salmon': 206,
      'Chicken Curry': 195,
      'Miso Soup': 40,
      'Ramen': 436,
      'Spaghetti Bolognese': 195,
      'Caesar Salad': 184,
      'Greek Salad': 107,
      'Club Sandwich': 280,
      'Hot Dog': 290,
      'Tacos': 226,
      'Nachos': 346,
    };

    return fallbackDb[foodName] ?? 150;
  }

  Map<String, int> _getMacrosForFood(String foodName) {
    // Check if it's a Kenyan food - use static database
    if (_kenyanFoods.contains(foodName)) {
      final macroDb = {
        'Ugali': {'carbs': 40, 'protein': 3, 'fat': 1},
        'Sukuma Wiki': {'carbs': 7, 'protein': 3, 'fat': 1},
        'Chapati': {'carbs': 28, 'protein': 4, 'fat': 3},
        'Pilau': {'carbs': 38, 'protein': 8, 'fat': 6},
        'Nyama Choma': {'carbs': 0, 'protein': 26, 'fat': 15},
        'Githeri': {'carbs': 32, 'protein': 8, 'fat': 2},
        'Mukimo': {'carbs': 30, 'protein': 5, 'fat': 2},
        'Mandazi': {'carbs': 28, 'protein': 3, 'fat': 5},
      };
      return macroDb[foodName] ?? {'carbs': 30, 'protein': 10, 'fat': 5};
    }

    // For non-Kenyan foods, check API cache first, then use static fallback
    final cached = _nutritionService.getCachedNutrition(foodName);
    if (cached != null) {
      return cached.macrosPer100g;
    }

    // Static fallback for non-Kenyan foods (will be replaced by API data)
    final fallbackDb = {
      'Rice': {'carbs': 45, 'protein': 4, 'fat': 0},
      'Chicken': {'carbs': 0, 'protein': 31, 'fat': 3},
      'Beef': {'carbs': 0, 'protein': 26, 'fat': 17},
      'Fish': {'carbs': 0, 'protein': 22, 'fat': 1},
      'Beans': {'carbs': 22, 'protein': 8, 'fat': 0},
      'Pizza': {'carbs': 33, 'protein': 11, 'fat': 10},
      'Hamburger': {'carbs': 30, 'protein': 17, 'fat': 13},
      'Salad': {'carbs': 10, 'protein': 2, 'fat': 0},
      'Grilled Salmon': {'carbs': 0, 'protein': 25, 'fat': 12},
      'Chicken Curry': {'carbs': 18, 'protein': 20, 'fat': 8},
      'Fried Rice': {'carbs': 42, 'protein': 6, 'fat': 5},
      'Miso Soup': {'carbs': 6, 'protein': 2, 'fat': 1},
      'Caesar Salad': {'carbs': 8, 'protein': 12, 'fat': 12},
      'Spaghetti Bolognese': {'carbs': 28, 'protein': 12, 'fat': 5},
    };

    return fallbackDb[foodName] ?? {'carbs': 30, 'protein': 10, 'fat': 5};
  }

  /// Fetch nutrition data from API for all predictions (async)
  Future<void> _fetchNutritionForPredictions(
    List<FoodPrediction> predictions,
  ) async {
    print('\n=== FETCHING NUTRITION DATA FROM API ===');

    for (final prediction in predictions) {
      // Skip Kenyan foods - they use static database
      if (_kenyanFoods.contains(prediction.foodName)) {
        print('Skipping API fetch for Kenyan food: ${prediction.foodName}');
        continue;
      }

      try {
        final nutrition = await _nutritionService.fetchNutrition(
          prediction.foodName,
        );

        // Update prediction with API data
        prediction.caloriesPer100g = nutrition.caloriesPer100g;
        prediction.macrosPer100g = nutrition.macrosPer100g;

        print(
          '✓ Updated ${prediction.foodName}: ${nutrition.caloriesPer100g} kcal/100g (${nutrition.source})',
        );
      } catch (e) {
        print('Error fetching nutrition for ${prediction.foodName}: $e');
        // Keep existing static values on error
      }
    }

    print('=== NUTRITION FETCH COMPLETE ===\n');
  }

  Future<void> _fetchUserGoalsAndTodayIntake() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    // Fetch user goals
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data()!;
      setState(() {
        dailyGoal = _parseFirestoreNumber(data['calories']);
        carbsTarget = _parseFirestoreNumber(data['carbG']);
        proteinTarget = _parseFirestoreNumber(data['proteinG']);
        fatTarget = _parseFirestoreNumber(data['fatG']);
        _userGoalsLoaded = true;
      });

      print(
        'User goals loaded: $dailyGoal cal, $carbsTarget carbs, $proteinTarget protein, $fatTarget fat',
      );
    }

    // Fetch today's already consumed food from BOTH collections
    final today = DateTime.now();
    final dateStr =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    int totalCals = 0;
    int totalCarbs = 0;
    int totalProtein = 0;
    int totalFat = 0;

    // 1. Fetch from NEW 'meals' collection
    final mealsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .where('date', isEqualTo: dateStr)
        .get();

    for (var mealDoc in mealsSnapshot.docs) {
      final mealData = mealDoc.data();
      
      // Use aggregated totals from meal document
      totalCals += _parseFirestoreNumber(mealData['totalCalories']);
      totalCarbs += _parseFirestoreNumber(mealData['totalCarbs']);
      totalProtein += _parseFirestoreNumber(mealData['totalProtein']);
      totalFat += _parseFirestoreNumber(mealData['totalFat']);
    }

    // 2. Also fetch from OLD 'barcodes' collection for backward compatibility
    final barcodesSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where('date', isEqualTo: dateStr)
        .get();

    for (var doc in barcodesSnapshot.docs) {
      final mealData = doc.data();
      totalCals += _parseFirestoreNumber(mealData['calories']);
      totalCarbs += _parseFirestoreNumber(mealData['carbs']);
      totalProtein += _parseFirestoreNumber(mealData['protein']);
      totalFat += _parseFirestoreNumber(mealData['fat']);
    }

    setState(() {
      todayCaloriesConsumed = totalCals;
      todayCarbsConsumed = totalCarbs;
      todayProteinConsumed = totalProtein;
      todayFatConsumed = totalFat;
    });

    print(
      'Today consumed so far (from meals + barcodes): $totalCals cal, $totalCarbs carbs, $totalProtein protein, $totalFat fat',
    );
  } catch (e) {
    print('Error fetching user goals and today intake: $e');
  }
}
  // ============================================================================
  // Portion Size Estimation using Computer Vision
  // ============================================================================
  
  // Helper to safely parse Firestore numbers (handles int, double, String, null)
  int _parseFirestoreNumber(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value) ?? double.tryParse(value);
      if (parsed != null) return parsed.round();
    }
    return 0;
  }

  /// Estimate portion sizes for all segmented foods based on bounding box area and food density
  void _estimatePortionSizes() {
    if (_processedImage == null || _originalImage == null) {
      print('Cannot estimate portion sizes: image not available');
      return;
    }

    print('\n=== ESTIMATING PORTION SIZES ===');

    // Detect plate size as reference (if possible)
    final estimatedPlateSize = _detectPlateSize();

    for (int i = 0; i < _segmentedFoods.length; i++) {
      final food = _segmentedFoods[i];
      final estimatedGrams = estimatePortionSize(
        food,
        plateSizeCm: estimatedPlateSize,
      );

      // Only update if food name is known (for accurate density calculation)
      if (food.foodName != null && food.foodName!.isNotEmpty) {
        food.gramsAmount = estimatedGrams;
        print('Food ${i + 1} (${food.foodName}): Estimated ${estimatedGrams}g');
      } else {
        print(
          'Food ${i + 1} (Unknown): Using default 100g (name not yet identified)',
        );
      }
    }

    print('=== PORTION SIZE ESTIMATION COMPLETE ===\n');
  }

  /// Estimate grams based on bounding box area, food density, and plate reference
  int estimatePortionSize(SegmentedFood food, {double? plateSizeCm}) {
    // Calculate bounding box area in pixels
    final area = food.boundingBox.width * food.boundingBox.height;

    // Get food density (grams per square pixel, adjusted for typical serving)
    final density = _getFoodDensity(food.foodName ?? 'Unknown');

    // Scale factor: convert pixel area to real-world area
    // Assumes average phone camera: ~2000px width = ~20cm plate
    // This is a rough estimate and can be improved with plate detection
    final imageWidth = _processedImage?.width.toDouble() ?? 512.0;
    final imageHeight = _processedImage?.height.toDouble() ?? 512.0;
    final imageArea = imageWidth * imageHeight;

    // Estimate scale: if we detect a plate, use it; otherwise use image dimensions
    double scaleFactor;
    if (plateSizeCm != null) {
      // Plate detected: use it as reference
      // Assume plate takes up ~60% of image area on average
      final plateAreaPixels = imageArea * 0.6;
      final plateAreaCm2 = math.pi * math.pow(plateSizeCm / 2, 2);
      scaleFactor = plateAreaCm2 / plateAreaPixels;
    } else {
      // No plate detected: estimate based on image dimensions
      // Assume image represents ~25cm x 25cm area (typical plate size)
      final estimatedRealAreaCm2 = 25.0 * 25.0; // 625 cm²
      scaleFactor = estimatedRealAreaCm2 / imageArea;
    }

    // Calculate estimated grams: area (cm²) * density (g/cm²)
    final areaCm2 = area * scaleFactor;
    final estimatedGrams = (areaCm2 * density).round();

    // Clamp to reasonable range (50g to 1000g)
    return estimatedGrams.clamp(50, 1000);
  }

  /// Get food density in grams per square centimeter
  /// Different foods have different densities (e.g., rice is dense, salad is light)
  double _getFoodDensity(String foodName) {
    // Food density database (grams per cm² for typical serving)
    // These are approximate values based on typical food densities
    final densityDb = {
      // Dense foods (high density)
      'Rice': 0.8,
      'Pilau': 0.75,
      'Fried Rice': 0.7,
      'Ugali': 0.85,
      'Pasta': 0.6,
      'Noodles': 0.55,
      'Spaghetti': 0.6,
      'Bread': 0.5,
      'Chapati': 0.6,
      'Mandazi': 0.55,

      // Medium density foods
      'Chicken': 0.4,
      'Kuku Choma': 0.4,
      'Beef': 0.45,
      'Nyama Choma': 0.45,
      'Fish': 0.35,
      'Grilled Salmon': 0.35,
      'Pizza': 0.5,
      'Hamburger': 0.45,
      'Githeri': 0.6,
      'Mukimo': 0.65,
      'Beans': 0.55,
      'Curry': 0.5,
      'Chicken Curry': 0.5,
      'Steak': 0.45,

      // Light foods (low density)
      'Salad': 0.15,
      'Caesar Salad': 0.2,
      'Greek Salad': 0.18,
      'Sukuma Wiki': 0.2,
      'Kachumbari': 0.15,
      'Bhaji': 0.25,
      'Soup': 0.3,
      'Miso Soup': 0.25,
      'Vegetable Tempura': 0.3,

      // Very dense foods
      'Cheesecake': 0.7,
      'Chocolate Cake': 0.75,
      'Donuts': 0.6,
      'Ice Cream': 0.5,

      // Default for unknown foods
      'Unknown': 0.4,
    };

    // Try exact match first
    if (densityDb.containsKey(foodName)) {
      return densityDb[foodName]!;
    }

    // Try partial match (case-insensitive)
    final lowerName = foodName.toLowerCase();
    for (final entry in densityDb.entries) {
      if (lowerName.contains(entry.key.toLowerCase()) ||
          entry.key.toLowerCase().contains(lowerName)) {
        return entry.value;
      }
    }

    // Default density for unknown foods
    return 0.4;
  }

  /// Detect plate size as a reference object (future enhancement)
  /// Returns plate diameter in cm, or null if plate not detected
  double? _detectPlateSize() {
    // TODO: Implement plate detection using computer vision
    // For now, return null to use image-based estimation
    // Future: Use edge detection, circle detection, or ML model to detect plates

    // Simple heuristic: if image has circular/oval regions, might be a plate
    // This is a placeholder for future implementation
    if (_processedImage == null) return null;

    // For now, estimate based on image size
    // Typical phone camera: assume ~20cm plate if image is well-framed
    final imageWidth = _processedImage!.width;
    final imageHeight = _processedImage!.height;

    // If image is roughly square and well-framed, estimate plate size
    final aspectRatio = imageWidth / imageHeight;
    if (aspectRatio > 0.8 && aspectRatio < 1.2) {
      // Square-ish image: likely a plate
      return 20.0; // Estimate 20cm plate
    }

    // Otherwise, use image-based estimation
    return null;
  }

  /// Calculate total calories for THIS meal only using gramsAmount
  int _calculateTotalCalories() {
    int total = 0;
    for (var food in _segmentedFoods) {
      total += food.actualCalories;
    }
    return total;
  }

  /// Calculate total macros for THIS meal only using gramsAmount
  Map<String, int> _calculateTotalMacros() {
    Map<String, int> total = {'carbs': 0, 'protein': 0, 'fat': 0};
    for (var food in _segmentedFoods) {
      final macros = food.actualMacros;
      total['carbs'] = (total['carbs'] ?? 0) + macros['carbs']!;
      total['protein'] = (total['protein'] ?? 0) + macros['protein']!;
      total['fat'] = (total['fat'] ?? 0) + macros['fat']!;
    }
    return total;
  }

  /// Get the appropriate animation for a macro label
  Animation<double> _getMacroAnimation(String label) {
    switch (label.toLowerCase()) {
      case 'carbs':
        return _carbsAnimation;
      case 'protein':
        return _proteinAnimation;
      case 'fat':
        return _fatAnimation;
      default:
        return _carbsAnimation;
    }
  }

  /// Update animations when nutrition values change
void _updateAnimations() {
  if (!_userGoalsLoaded || dailyGoal == 0) return;

  // Calculate current values
  final thisMealCalories = _calculateTotalCalories();
  final thisMealMacros = _calculateTotalMacros();

  final caloriesAfterMeal = todayCaloriesConsumed + thisMealCalories;
  final carbsAfterMeal = todayCarbsConsumed + (thisMealMacros['carbs'] ?? 0);
  final proteinAfterMeal =
      todayProteinConsumed + (thisMealMacros['protein'] ?? 0);
  final fatAfterMeal = todayFatConsumed + (thisMealMacros['fat'] ?? 0);

  // Calculate ACTUAL progress percentages (0.0 to 1.0, or higher if exceeded)
  final calorieProgress = dailyGoal > 0
      ? (caloriesAfterMeal / dailyGoal).clamp(0.0, 1.5)
      : 0.0;
  final carbsProgress = carbsTarget > 0
      ? (carbsAfterMeal / carbsTarget).clamp(0.0, 1.5)
      : 0.0;
  final proteinProgress = proteinTarget > 0
      ? (proteinAfterMeal / proteinTarget).clamp(0.0, 1.5)
      : 0.0;
  final fatProgress = fatTarget > 0
      ? (fatAfterMeal / fatTarget).clamp(0.0, 1.5)
      : 0.0;

  // ✅ FIX: Animate to ACTUAL progress (not normalized)
  // For display, we'll handle the clamping in the painter
  _calorieAnimationController.animateTo(calorieProgress.clamp(0.0, 1.0));
  _carbsAnimationController.animateTo(carbsProgress.clamp(0.0, 1.0));
  _proteinAnimationController.animateTo(proteinProgress.clamp(0.0, 1.0));
  _fatAnimationController.animateTo(fatProgress.clamp(0.0, 1.0));
}

  // Continue to batch 5...

  // ============================================================================
  // BATCH 5: Main UI Build Methods & Processing States
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Meal Summary',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isProcessing
          ? _buildProcessingState()
          : _errorMessage != null
          ? _buildErrorState()
          : _buildResultsState(),
    );
  }

  Widget _buildProcessingState() {
    return _buildProcessingPreview();
  }

  /// IMPROVED: Show what AI is detecting in real-time
  Widget _buildProcessingPreview() {
    return Stack(
      children: [
        // Blurred background image
        if (_imageFile != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Image.file(
              _imageFile!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        // Real-time detection preview
        StreamBuilder<List<SegmentedFood>>(
          stream: detectionStream,
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return _buildDetectionOverlay(snapshot.data!);
            }
            return Container();
          },
        ),
        // Processing overlay with progress
        Container(
          color: Colors.black.withOpacity(0.4),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildProcessingStage(),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(value: _processingProgress),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<SegmentedFood>>(
                  stream: detectionStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                      return Text(
                        'Found ${snapshot.data!.length} food${snapshot.data!.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Draw bounding boxes for detected regions
  Widget _buildDetectionOverlay(List<SegmentedFood> foods) {
    if (_originalImage == null || _imageFile == null) {
      return Container();
    }

    final displayHeight = MediaQuery.of(context).size.height;
    final displayWidth = MediaQuery.of(context).size.width;
    final originalWidth = _originalImage!.width.toDouble();
    final originalHeight = _originalImage!.height.toDouble();

    // Calculate display aspect ratio vs original aspect ratio
    final displayAspect = displayWidth / displayHeight;
    final originalAspect = originalWidth / originalHeight;

    // Calculate actual rendered image dimensions (considering BoxFit.cover)
    double renderedWidth, renderedHeight;
    double offsetX = 0, offsetY = 0;

    if (originalAspect > displayAspect) {
      renderedHeight = displayHeight;
      renderedWidth = displayHeight * originalAspect;
      offsetX = -(renderedWidth - displayWidth) / 2;
    } else {
      renderedWidth = displayWidth;
      renderedHeight = displayWidth / originalAspect;
      offsetY = -(renderedHeight - displayHeight) / 2;
    }

    return CustomPaint(
      painter: DetectionOverlayPainter(
        foods: foods,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        renderedWidth: renderedWidth,
        renderedHeight: renderedHeight,
        offsetX: offsetX,
        offsetY: offsetY,
      ),
      size: Size(displayWidth, displayHeight),
    );
  }

  Widget _buildProcessingStage() {
    final stages = [
      'Loading models',
      'Analyzing image',
      'Detecting foods',
      'Calculating nutrition',
    ];
    return Text(
      stages[_currentStage.clamp(0, stages.length - 1)],
      style: const TextStyle(color: Colors.white, fontSize: 16),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.green[300]),
            const SizedBox(height: 16),
            const Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsState() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMealHeader(),
          _buildFoodImage(),
          _buildTotalIntake(),
          _buildModifyFoodSection(),
          const SizedBox(height: 24),
// Save button
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton(
      onPressed: _isProcessing ? null : _saveMealToFirestore,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        disabledBackgroundColor: Colors.grey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
        elevation: 2,
        shadowColor: Colors.green.withOpacity(0.3),
      ),
      child: _isProcessing
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Save Meal (${_segmentedFoods.length} item${_segmentedFoods.length > 1 ? "s" : ""})',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
    ),
  ),
),
const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildMealHeader() {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final dayName = _getDayName(now.weekday);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$dateStr ($dayName) • ${now.hour >= 12 ? "pm" : "am"} $timeStr • ${widget.mealType}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(Icons.edit, size: 20, color: Colors.green[600]),
        ],
      ),
    );
  }

  String _getDayName(int weekday) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[weekday - 1];
  }

  Widget _buildFoodImage() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Image.file(
              _imageFile!,
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),
            ..._buildFoodLabels(),
          ],
        ),
      ),
    );
  }

  /// IMPROVED: Better coordinate scaling from segmentation to display
  List<Widget> _buildFoodLabels() {
    List<Widget> labels = [];

    // Get actual display dimensions
    final displayHeight = 300.0;
    final displayWidth = MediaQuery.of(context).size.width - 32;

    // Get original image dimensions for proper scaling
    final originalWidth = _originalImage?.width.toDouble() ?? displayWidth;
    final originalHeight = _originalImage?.height.toDouble() ?? displayHeight;

    // Calculate display aspect ratio vs original aspect ratio
    final displayAspect = displayWidth / displayHeight;
    final originalAspect = originalWidth / originalHeight;

    // Calculate actual rendered image dimensions (considering BoxFit.cover)
    double renderedWidth, renderedHeight;
    double offsetX = 0, offsetY = 0;

    if (originalAspect > displayAspect) {
      // Image is wider - height fills, width is cropped
      renderedHeight = displayHeight;
      renderedWidth = displayHeight * originalAspect;
      offsetX = -(renderedWidth - displayWidth) / 2;
    } else {
      // Image is taller - width fills, height is cropped
      renderedWidth = displayWidth;
      renderedHeight = displayWidth / originalAspect;
      offsetY = -(renderedHeight - displayHeight) / 2;
    }

    for (int i = 0; i < _segmentedFoods.length && i < 5; i++) {
      final food = _segmentedFoods[i];
      if (food.foodName != null &&
          food.foodName!.isNotEmpty &&
          food.center != null) {
        // Scale from segmentation coordinates to original image coordinates
        final segWidth = food.maskWidth.toDouble();
        final segHeight = food.maskHeight.toDouble();

        final originalX = (food.center!.dx / segWidth) * originalWidth;
        final originalY = (food.center!.dy / segHeight) * originalHeight;

        // Scale from original to rendered coordinates
        final renderedX = (originalX / originalWidth) * renderedWidth + offsetX;
        final renderedY =
            (originalY / originalHeight) * renderedHeight + offsetY;

        // Only show if within visible bounds
        if (renderedX >= 0 &&
            renderedX <= displayWidth &&
            renderedY >= 0 &&
            renderedY <= displayHeight) {
          labels.add(
            Positioned(
              left: renderedX.clamp(0, displayWidth - 120),
              top: renderedY.clamp(0, displayHeight - 40),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      food.foodName!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(food.confidence * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }
    }
    return labels;
  }

  // Continue to batch 6...

  // ============================================================================
  // BATCH 6: Total Intake Display with Overflow Handling
  // ============================================================================

  /// IMPROVED: Fixed overflow handling - shows "exceeded by" when over budget
  Widget _buildTotalIntake() {
    // Calculate this meal's totals
    final thisMealCalories = _calculateTotalCalories();
    final thisMealMacros = _calculateTotalMacros();

    // Calculate what would be total AFTER this meal
    final caloriesAfterMeal = todayCaloriesConsumed + thisMealCalories;
    final carbsAfterMeal = todayCarbsConsumed + (thisMealMacros['carbs'] ?? 0);
    final proteinAfterMeal =
        todayProteinConsumed + (thisMealMacros['protein'] ?? 0);
    final fatAfterMeal = todayFatConsumed + (thisMealMacros['fat'] ?? 0);

    // Calculate remaining (can be negative if over budget)
    final caloriesLeft = dailyGoal - caloriesAfterMeal;
    final carbsLeft = carbsTarget - carbsAfterMeal;
    final proteinLeft = proteinTarget - proteinAfterMeal;
    final fatLeft = fatTarget - fatAfterMeal;

    // Calculate percentage for progress ring (cap at 1.5 for visual purposes)
    final percentage = dailyGoal > 0
        ? (caloriesAfterMeal / dailyGoal).clamp(0.0, 1.5)
        : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'After This Meal',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.left,
                ),
                Text(
                  'Goal: $dailyGoal kcal',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color.fromARGB(127, 218, 21, 21),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Breakdown box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Already consumed today:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    Text(
                      '$todayCaloriesConsumed kcal',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'This meal:',
                      style: TextStyle(fontSize: 13, color: Colors.green[700]),
                    ),
                    Text(
                      '+$thisMealCalories kcal',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total after meal:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      '$caloriesAfterMeal kcal',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Animated progress ring with overflow handling
          SizedBox(
            height: 120,
            width: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _calorieAnimation,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(150, 180),
                      painter: AnimatedSemiCircleProgressPainter(
                        progress: percentage,
                        backgroundColor: Colors.grey[200]!,
                        progressColor: caloriesLeft >= 0
                            ? Colors.green
                            : Colors.red,
                        strokeWidth: 8,
                        animation: _calorieAnimation,
                      ),
                    );
                  },
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        caloriesLeft >= 0
                            ? caloriesLeft.toString()
                            : caloriesLeft.abs().toString(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: caloriesLeft >= 0
                              ? Colors.black87
                              : Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        caloriesLeft >= 0 ? 'kcal left' : 'kcal over',
                        style: TextStyle(
                          fontSize: 12,
                          color: caloriesLeft >= 0
                              ? Colors.grey[600]
                              : Colors.red[400],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Macro circles with overflow handling
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMacroCircle(
                'Carbs',
                carbsAfterMeal,
                carbsTarget,
                Colors.orange,
                carbsLeft,
                size: 70,
              ),
              _buildMacroCircle(
                'Protein',
                proteinAfterMeal,
                proteinTarget,
                Colors.red,
                proteinLeft,
                size: 70,
              ),
              _buildMacroCircle(
                'Fat',
                fatAfterMeal,
                fatTarget,
                Colors.blue,
                fatLeft,
                size: 70,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// IMPROVED: Fixed overflow - shows "exceeded by X" instead of overflowing UI
Widget _buildMacroCircle(
  String label,
  int current,
  int target,
  Color color,
  int left, {
  double size = 50,
}) {
  // ✅ FIX: Calculate ACTUAL progress (not clamped yet)
  double progress = target > 0 ? (current / target) : 0.0;

  return Column(
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _getMacroAnimation(label),
              builder: (context, child) {
                return CustomPaint(
                  size: Size(size, size),
                  painter: AnimatedSemiCircleProgressPainter(
                    progress: progress, // ✅ Pass actual progress
                    backgroundColor: Colors.grey[200]!,
                    progressColor: left >= 0 ? color : Colors.red,
                    strokeWidth: 4,
                    animation: _getMacroAnimation(label),
                  ),
                );
              },
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
                    '/$target g',
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        width: size + 10,
        child: Text(
          left >= 0 ? '${left}g left' : '${left.abs()}g over',
          style: TextStyle(
            fontSize: 11,
            color: left >= 0 ? Colors.grey[600] : Colors.red[400],
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ],
  );
}

  // Continue to batch 7...

  // ============================================================================
  // BATCH 7: Modify Food Section with Cropped/Highlighted Images
  // ============================================================================

  Widget _buildModifyFoodSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text(
                    'Modify food information',
                    style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Swipe up on a food to delete',
                    style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w400,
                    ),
                  ),
                  ],
                ),
              // Merge and Split action buttons
              Row(
                children: [
                  if (_segmentedFoods.length >= 2)
                    IconButton(
                      icon: const Icon(Icons.merge_type, color: Colors.blue),
                      tooltip: 'Merge Foods',
                      onPressed: _showMergeDialog,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 1 + _segmentedFoods.length, // Add button + foods
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildAddFoodButton();
                } else {
                  final foodIndex = index - 1;
                  return _buildFoodCard(_segmentedFoods[foodIndex], foodIndex);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddFoodButton() {
    return GestureDetector(
      onTap: () {
        _showAddFoodDialog();
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add Food',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// IMPROVED: Now shows CROPPED and HIGHLIGHTED image of individual food region
  Widget _buildFoodCard(SegmentedFood food, int index) {
    // Calculate actual calories based on grams
    final displayCalories = food.actualCalories;

    // Get cropped/highlighted image for this food
    Widget foodImage;
    if (_originalImage != null) {
      final croppedImage = food.getHighlightedImage(_originalImage!);
      if (croppedImage != null) {
        // Convert img.Image to Uint8List for display
        final bytes = img.encodePng(croppedImage);
        foodImage = Image.memory(
          Uint8List.fromList(bytes),
          width: 140,
          height: 120,
          fit: BoxFit.cover,
        );
      } else {
        // Fallback to full image
        foodImage = Image.file(
          _imageFile!,
          width: 140,
          height: 120,
          fit: BoxFit.cover,
        );
      }
    } else {
      foodImage = Image.file(
        _imageFile!,
        width: 140,
        height: 120,
        fit: BoxFit.cover,
      );
    }

    return Dismissible(
      key: Key(food.id),
      direction: DismissDirection.up,
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 32),
            SizedBox(height: 8),
            Text(
              'Swipe up to delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        // Show confirmation dialog
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Remove Food'),
                content: Text(
                  'Are you sure you want to remove "${food.foodName ?? 'this food'}"?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (direction) {
        setState(() {
          _segmentedFoods.removeAt(index);
        });
        _updateAnimations();
      },
      child: GestureDetector(
        onTap: () {
          _showEditFoodDialog(food, index);
        },
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                    child: foodImage,
                  ),
                  // Action buttons (Remove and Split)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Split button
                        GestureDetector(
                          onTap: () {
                            _showSplitDialog(index);
                          },
                          
                        ),
                        // Remove button
                        GestureDetector(
                          onTap: () {
                            _removeFood(index);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Confidence badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(food.confidence * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.foodName ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${food.gramsAmount}g',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      '$displayCalories kcal',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
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

  void _showEditFoodDialog(SegmentedFood food, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditFoodPage(
          food: food,
          originalImage: _originalImage!,
          allPredictions: _topPredictions,
          onUpdate: (updatedFood) {
            setState(() {
              _segmentedFoods[index] = updatedFood;
            });
            _updateAnimations();
          },
        ),
      ),
    );
  }

  void _showAddFoodDialog() {
    final TextEditingController _foodNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Food'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You can manually add food items that were not detected automatically.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _foodNameController,
              decoration: const InputDecoration(
                labelText: 'Food Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final customName = _foodNameController.text.trim().isEmpty
                  ? 'Custom Food'
                  : _foodNameController.text.trim();

              // Create a new food item with fallback mask
              final width = 256;
              final height = 256;
              final mask = Uint8List(width * height);

              // Fill center region
              for (int y = height ~/ 4; y < height * 3 ~/ 4; y++) {
                for (int x = width ~/ 4; x < width * 3 ~/ 4; x++) {
                  mask[y * width + x] = 255;
                }
              }

              setState(() {
                _segmentedFoods.add(
                  SegmentedFood(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    boundingBox: Rect.fromLTWH(
                      width / 4,
                      height / 4,
                      width / 2,
                      height / 2,
                    ),
                    mask: mask,
                    maskWidth: width,
                    maskHeight: height,
                    confidence: 0.5,
                    foodName: customName,
                    caloriesPer100g: 150,
                    macrosPer100g: {'carbs': 30, 'protein': 10, 'fat': 5},
                    gramsAmount: 100,
                  ),
                );
              });
              _updateAnimations();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeFood(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Food'),
        content: Text(
          'Are you sure you want to remove "${_segmentedFoods[index].foodName ?? 'this food'}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _segmentedFoods.removeAt(index);
              });
              _updateAnimations();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  /// Merge two detected regions (e.g., rice + sauce)
  void mergeFoods(int index1, int index2) {
    if (index1 >= _segmentedFoods.length ||
        index2 >= _segmentedFoods.length ||
        index1 == index2) {
      return;
    }

    final food1 = _segmentedFoods[index1];
    final food2 = _segmentedFoods[index2];

    // Combine bounding boxes
    final mergedBox = Rect.fromLTRB(
      math.min(food1.boundingBox.left, food2.boundingBox.left),
      math.min(food1.boundingBox.top, food2.boundingBox.top),
      math.max(food1.boundingBox.right, food2.boundingBox.right),
      math.max(food1.boundingBox.bottom, food2.boundingBox.bottom),
    );

    // Combine masks (union)
    final maxWidth = math.max(food1.maskWidth, food2.maskWidth);
    final maxHeight = math.max(food1.maskHeight, food2.maskHeight);
    final mergedMask = Uint8List(maxWidth * maxHeight);

    // Copy food1 mask
    for (int y = 0; y < food1.maskHeight; y++) {
      for (int x = 0; x < food1.maskWidth; x++) {
        final idx = y * food1.maskWidth + x;
        if (idx < food1.mask.length && food1.mask[idx] > 0) {
          final newIdx = y * maxWidth + x;
          if (newIdx < mergedMask.length) {
            mergedMask[newIdx] = 255;
          }
        }
      }
    }

    // Add food2 mask
    for (int y = 0; y < food2.maskHeight; y++) {
      for (int x = 0; x < food2.maskWidth; x++) {
        final idx = y * food2.maskWidth + x;
        if (idx < food2.mask.length && food2.mask[idx] > 0) {
          final newIdx = y * maxWidth + x;
          if (newIdx < mergedMask.length) {
            mergedMask[newIdx] = 255;
          }
        }
      }
    }
      //Smart naming logic
  String mergedName;
  final name1 = food1.foodName ?? 'Food';
  final name2 = food2.foodName ?? 'Food';
  
  // Check if both foods are the same
  if (name1.toLowerCase().trim() == name2.toLowerCase().trim()) {
    // Same food - just use the name once
    mergedName = name1;
  } else {
    // Different foods - combine names
    mergedName = '$name1 with $name2';
  }

    // Calculate combined nutrition (weighted average by grams)
    final totalGrams = food1.gramsAmount + food2.gramsAmount;
    final food1Weight = food1.gramsAmount / totalGrams;
    final food2Weight = food2.gramsAmount / totalGrams;

    final mergedCaloriesPer100g =
        ((food1.caloriesPer100g ?? 150) * food1Weight +
                (food2.caloriesPer100g ?? 150) * food2Weight)
            .round();

    final mergedMacrosPer100g = {
      'carbs':
          ((food1.macrosPer100g?['carbs'] ?? 0) * food1Weight +
                  (food2.macrosPer100g?['carbs'] ?? 0) * food2Weight)
              .round(),
      'protein':
          ((food1.macrosPer100g?['protein'] ?? 0) * food1Weight +
                  (food2.macrosPer100g?['protein'] ?? 0) * food2Weight)
              .round(),
      'fat':
          ((food1.macrosPer100g?['fat'] ?? 0) * food1Weight +
                  (food2.macrosPer100g?['fat'] ?? 0) * food2Weight)
              .round(),
    };

    // Create merged food
    final mergedFood = SegmentedFood(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    boundingBox: mergedBox,
    mask: mergedMask,
    maskWidth: maxWidth,
    maskHeight: maxHeight,
    confidence: (food1.confidence + food2.confidence) / 2,
    foodName: mergedName,  // ✅ Use smart merged name
    segmentationSource: 'Merged',
    caloriesPer100g: mergedCaloriesPer100g,
    macrosPer100g: mergedMacrosPer100g,
    center: Offset(
      (mergedBox.left + mergedBox.right) / 2,
      (mergedBox.top + mergedBox.bottom) / 2,
    ),
    gramsAmount: totalGrams,
  );

  setState(() {
    // Remove both foods and add merged one
    _segmentedFoods.removeAt(math.max(index1, index2));
    _segmentedFoods.removeAt(math.min(index1, index2));
    _segmentedFoods.add(mergedFood);
  });

  _updateAnimations();
}

  /// Split one region into multiple (e.g., mixed plate)
  void splitFood(int index, Map<String, double> components) {
    // components: {'Rice': 0.5, 'Chicken': 0.3, 'Vegetables': 0.2}
    if (index >= _segmentedFoods.length || components.isEmpty) {
      return;
    }

    final originalFood = _segmentedFoods[index];
    final totalPercentage = components.values.fold(
      0.0,
      (sum, val) => sum + val,
    );

    if (totalPercentage.abs() - 1.0 > 0.01) {
      // Normalize if percentages don't sum to 1.0
      final scale = 1.0 / totalPercentage;
      components = components.map((key, value) => MapEntry(key, value * scale));
    }

    final newFoods = <SegmentedFood>[];

    components.forEach((foodName, percentage) {
      final splitGrams = (originalFood.gramsAmount * percentage).round();
      final splitCaloriesPer100g = originalFood.caloriesPer100g ?? 150;
      final splitMacrosPer100g =
          originalFood.macrosPer100g ?? {'carbs': 30, 'protein': 10, 'fat': 5};

      // Create split food with same bounding box and mask
      final splitFood = SegmentedFood(
        id: '${originalFood.id}_${foodName}_${DateTime.now().millisecondsSinceEpoch}',
        boundingBox: originalFood.boundingBox,
        mask: originalFood.mask,
        maskWidth: originalFood.maskWidth,
        maskHeight: originalFood.maskHeight,
        confidence: originalFood.confidence * percentage.toDouble(),
        foodName: foodName,
        segmentationSource: 'Split',
        caloriesPer100g: splitCaloriesPer100g,
        macrosPer100g: splitMacrosPer100g,
        center: originalFood.center,
        gramsAmount: splitGrams,
      );

      newFoods.add(splitFood);
    });

    setState(() {
      _segmentedFoods.removeAt(index);
      _segmentedFoods.addAll(newFoods);
    });

    _updateAnimations();
  }

  /// Show merge dialog
  void _showMergeDialog() {
    if (_segmentedFoods.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need at least 2 foods to merge')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge Foods'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _segmentedFoods.length,
            itemBuilder: (context, index) {
              final food = _segmentedFoods[index];
              return ListTile(
                title: Text(food.foodName ?? 'Food ${index + 1}'),
                subtitle: Text('${food.gramsAmount}g'),
                onTap: () {
                  Navigator.pop(context);
                  _showMergeSelectionDialog(index);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

 void _showMergeSelectionDialog(int firstIndex) {
  final firstName = _segmentedFoods[firstIndex].foodName ?? 'Food';
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Merge with $firstName'),  // ✅ Show first food name
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _segmentedFoods.length,
          itemBuilder: (context, index) {
            if (index == firstIndex) return const SizedBox.shrink();
            final food = _segmentedFoods[index];
            final secondName = food.foodName ?? 'Food ${index + 1}';
            
            // ✅ Show preview of merged name
            final previewName = firstName.toLowerCase().trim() == 
                                secondName.toLowerCase().trim()
                ? firstName  // Same food
                : '$firstName with $secondName';  // Different foods
            
            return ListTile(
              title: Text(food.foodName ?? 'Food ${index + 1}'),
              subtitle: Text('Will become: $previewName'), 
              onTap: () {
                Navigator.pop(context);
                mergeFoods(firstIndex, index);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

  /// Show split dialog
  void _showSplitDialog(int index) {
    final food = _segmentedFoods[index];
    final componentsController = <String, TextEditingController>{};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Split Food'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Split "${food.foodName ?? 'Food'}" into components.\nEnter percentages (must sum to 100%):',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ...componentsController.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: entry.value,
                                decoration: InputDecoration(
                                  labelText: entry.key,
                                  hintText: '0-100%',
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setDialogState(() {
                                  componentsController.remove(entry.key);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    ElevatedButton.icon(
                      onPressed: () {
                        final controller = TextEditingController();
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Add Component'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'Food Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  if (controller.text.isNotEmpty) {
                                    setDialogState(() {
                                      componentsController[controller.text] =
                                          TextEditingController();
                                    });
                                    Navigator.pop(context);
                                  }
                                },
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Component'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final components = <String, double>{};

                    for (final entry in componentsController.entries) {
                      final value = double.tryParse(entry.value.text) ?? 0.0;
                      if (value > 0) {
                        components[entry.key] =
                            value / 100.0; // Convert to decimal
                      }
                    }

                    if (components.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please add at least one component'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(context);
                    splitFood(index, components);
                  },
                  child: const Text('Split'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Save the meal to Firestore
  /// Save the entire meal as ONE document with all foods in an array
Future<void> _saveMealToFirestore() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User not logged in!')),
    );
    return;
  }

  // Show loading indicator
  setState(() => _isProcessing = true);

  try {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final weekdayStr = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ][now.weekday - 1];

    // Generate unique meal ID (timestamp-based)
    final mealId = DateTime.now().millisecondsSinceEpoch.toString();

    // Step 1: Upload original image to Firebase Storage
    String? originalImageDownloadUrl;

    if (_imageFile != null) {
      print('Uploading meal image to Storage...');
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/${user.uid}/meal_images/${mealId}_original.jpg');
      
      final uploadTask = await storageRef.putFile(_imageFile!);
      originalImageDownloadUrl = await uploadTask.ref.getDownloadURL();
      print('✓ Image uploaded: $originalImageDownloadUrl');
    }

    // Step 2: Prepare ALL food items data (from the single meal)
    final List<Map<String, dynamic>> foodItemsData = [];
    
    for (final food in _segmentedFoods) {
      foodItemsData.add({
        'id': food.id,
        'foodName': food.foodName ?? 'Unknown',
        'gramsAmount': food.gramsAmount,
        'calories': food.actualCalories,
        'carbs': food.actualMacros['carbs'],
        'protein': food.actualMacros['protein'],
        'fat': food.actualMacros['fat'],
        'caloriesPer100g': food.caloriesPer100g,
        'macrosPer100g': food.macrosPer100g,
        'confidence': food.confidence,
        'segmentationSource': food.segmentationSource,
        'classificationSource': food.classificationSource,
        'boundingBox': {
          'left': food.boundingBox.left,
          'top': food.boundingBox.top,
          'width': food.boundingBox.width,
          'height': food.boundingBox.height,
        },
      });
    }

    // Step 3: Calculate totals for this meal
    final totalCalories = _calculateTotalCalories();
    final totalMacros = _calculateTotalMacros();


    // Step 4: Save ONE document to "meals" subcollection
    print('Saving meal document with ${_segmentedFoods.length} food items...');
    
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(mealId)  // Single document for the entire meal
        .set({
      // Meal metadata
      'mealType': widget.mealType,
      'date': dateStr,
      'time': timeStr,
      'weekday': weekdayStr,
      'createdAt': FieldValue.serverTimestamp(),
      
      // Image reference
      'originalImageUrl': originalImageDownloadUrl,
      
      // Totals for this meal
      'totalCalories': totalCalories,
      'totalCarbs': totalMacros['carbs'],
      'totalProtein': totalMacros['protein'],
      'totalFat': totalMacros['fat'],
      
      // ALL food items in one array
      'foodItems': foodItemsData,
      
      // Metadata
      'numFoodsDetected': _segmentedFoods.length,
      'detectionMetadata': {
        'modelVersion': '1.0',
        'processingTime': 0, // You can track this if needed
      },
    });

    print('✓ Meal saved successfully!');

    // Show success message
    if (mounted) {
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
          'Meal saved: ${_segmentedFoods.length} food${_segmentedFoods.length > 1 ? "s" : ""}!',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          ),
        ],
        ),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      );

      // Navigate back and trigger refresh
      await Future.delayed(const Duration(seconds: 2));
      
      // Pop back to home with success flag
      Navigator.of(context).popUntil((route) => route.isFirst);
      // Alternative: Navigator.of(context).pop(true); if you have direct navigation
    }

  } catch (e) {
    print('Error saving meal: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save meal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }
}

  // Continue to batch 8...
}

// ============================================================================
// BATCH 8: Enhanced Edit Food Page with Cropped Images
// ============================================================================

class EditFoodPage extends StatefulWidget {
  final SegmentedFood food;
  final img.Image originalImage; // CHANGED: Now receives original image
  final List<FoodPrediction> allPredictions;
  final Function(SegmentedFood) onUpdate;

  const EditFoodPage({
    Key? key,
    required this.food,
    required this.originalImage,
    required this.allPredictions,
    required this.onUpdate,
  }) : super(key: key);

  @override
  State<EditFoodPage> createState() => _EditFoodPageState();
}

class _EditFoodPageState extends State<EditFoodPage> {
  late String selectedFoodName;
  late String selectedSize;
  late int gramsAmount; // CHANGED: Direct grams, not multiplier
  late int caloriesPer100g;
  late Map<String, int> macrosPer100g;
  bool showDetailedNutrition = false;

  // Plate size to grams mapping
  final Map<String, int> plateSizeGrams = {
    'Small dish ~8cm': 80,
    'Small plate 8~13cm': 120,
    'Medium plate 13~17cm': 180,
    'Large plate 17~21cm': 250,
    'Buffet plate 21cm~': 350,
  };

  final List<String> sizes = [
    'Small dish ~8cm',
    'Small plate 8~13cm',
    'Medium plate 13~17cm',
    'Large plate 17~21cm',
    'Buffet plate 21cm~',
  ];

  // Generate suggestions from predictions with >70% confidence
  List<String> get foodSuggestions {
    final Set<String> suggestions = {};

    if (widget.food.confidence > 0.3 &&
        widget.food.foodName != null &&
        widget.food.foodName!.isNotEmpty) {
      suggestions.add(widget.food.foodName!);
    }

    for (final pred in widget.allPredictions) {
      if (pred.confidence > 0.3) {
        suggestions.add(pred.foodName);
      }
    }

    if (suggestions.isEmpty) {
      for (int i = 0; i < widget.allPredictions.length && i < 5; i++) {
        suggestions.add(widget.allPredictions[i].foodName);
      }
    }

    if (suggestions.isEmpty) {
      if (widget.food.foodName != null && widget.food.foodName!.isNotEmpty) {
        suggestions.add(widget.food.foodName!);
      } else {
        suggestions.add('Unknown');
      }
    }

    return suggestions.toList();
  }

  @override
  void initState() {
    super.initState();
    selectedFoodName = widget.food.foodName ?? 'Unknown';
    selectedSize = 'Medium plate 13~17cm';

    // Initialize from food data
    caloriesPer100g = widget.food.caloriesPer100g ?? 150;
    macrosPer100g =
        widget.food.macrosPer100g ?? {'carbs': 30, 'protein': 10, 'fat': 5};
    gramsAmount = widget.food.gramsAmount;

    // Get macros from prediction if available
    final prediction = widget.allPredictions.firstWhere(
      (p) => p.foodName == selectedFoodName,
      orElse: () => FoodPrediction(
        foodName: selectedFoodName,
        confidence: widget.food.confidence,
        caloriesPer100g: caloriesPer100g,
        macrosPer100g: macrosPer100g,
        source: '',
      ),
    );

    if (prediction.macrosPer100g.isNotEmpty) {
      macrosPer100g = prediction.macrosPer100g;
      caloriesPer100g = prediction.caloriesPer100g;
    }
  }

  // Calculate current calories based on grams
  int get currentCalories => ((caloriesPer100g / 100.0) * gramsAmount).round();

  // Calculate current macros based on grams
  Map<String, int> get currentMacros {
    return {
      'carbs': ((macrosPer100g['carbs']! / 100.0) * gramsAmount).round(),
      'protein': ((macrosPer100g['protein']! / 100.0) * gramsAmount).round(),
      'fat': ((macrosPer100g['fat']! / 100.0) * gramsAmount).round(),
    };
  }

  void _updateGramsFromSlider(double newGrams) {
    setState(() {
      gramsAmount = newGrams.round();
    });
  }

  void _setPortionPreset(String preset) {
    setState(() {
      int baseGrams = plateSizeGrams[selectedSize]!;
      switch (preset) {
        case 'Half':
          gramsAmount = (baseGrams * 0.5).round();
          break;
        case 'Full':
          gramsAmount = baseGrams;
          break;
        case 'Double':
          gramsAmount = (baseGrams * 2.0).round();
          break;
      }
    });
  }

  void _updatePlateSize(String newSize) {
    setState(() {
      selectedSize = newSize;
      gramsAmount = plateSizeGrams[newSize]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Food',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFoodImageSection(),
                const SizedBox(height: 24),
                _buildCalorieHeader(),
                const SizedBox(height: 24),
                _buildFoodNameSection(),
                const SizedBox(height: 24),
                _buildPlateSizeSection(),
                const SizedBox(height: 24),
                _buildPortionPresetsSection(),
                const SizedBox(height: 24),
                _buildQuantitySliderSection(),
                const SizedBox(height: 24),
                _buildDetailedNutritionSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
          _buildStickyBottomButton(),
        ],
      ),
    );
  }

  /// IMPROVED: Shows highlighted food region, not full image
  Widget _buildFoodImageSection() {
    Widget foodImage;

    // Get highlighted image for this food
    final highlightedImage = widget.food.getHighlightedImage(
      widget.originalImage,
    );
    if (highlightedImage != null) {
      final bytes = img.encodePng(highlightedImage);
      foodImage = Image.memory(
        Uint8List.fromList(bytes),
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
      );
    } else {
      // Fallback: try cropped image
      final croppedImage = widget.food.getCroppedImage(widget.originalImage);
      if (croppedImage != null) {
        final bytes = img.encodePng(croppedImage);
        foodImage = Image.memory(
          Uint8List.fromList(bytes),
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
        );
      } else {
        // Final fallback: show full image
        final bytes = img.encodePng(widget.originalImage);
        foodImage = Image.memory(
          Uint8List.fromList(bytes),
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: foodImage,
      ),
    );
  }

  Widget _buildCalorieHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedFoodName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${gramsAmount}g serving',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '$currentCalories',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const Text(
                  'kcal',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodNameSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Food Name (AI Suggestions)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Top predictions with >70% confidence',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: foodSuggestions.map((food) {
              final isSelected = food == selectedFoodName;

              final pred = widget.allPredictions.firstWhere(
                (p) => p.foodName == food,
                orElse: () => FoodPrediction(
                  foodName: food,
                  confidence: widget.food.confidence,
                  caloriesPer100g: caloriesPer100g,
                  macrosPer100g: macrosPer100g,
                  source: '',
                ),
              );

              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedFoodName = food;
                    // Update nutrition values when food changes
                    if (pred.macrosPer100g.isNotEmpty) {
                      macrosPer100g = pred.macrosPer100g;
                      caloriesPer100g = pred.caloriesPer100g;
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.green : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.green : Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        food,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(pred.confidence * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlateSizeSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Plate Size',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          ...sizes.map((size) {
            final isSelected = size == selectedSize;
            final grams = plateSizeGrams[size]!;
            return GestureDetector(
              onTap: () => _updatePlateSize(size),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.grey[400]!,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        size,
                        style: TextStyle(
                          fontSize: 14,
                          color: isSelected ? Colors.black : Colors.grey[700],
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      '~${grams}g',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildPortionPresetsSection() {
    final baseGrams = plateSizeGrams[selectedSize]!;
    final presets = [
      {'name': 'Half', 'multiplier': 0.5},
      {'name': 'Full', 'multiplier': 1.0},
      {'name': 'Double', 'multiplier': 2.0},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Portions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: presets.map((preset) {
              final name = preset['name'] as String;
              final multiplier = preset['multiplier'] as double;
              final presetGrams = (baseGrams * multiplier).round();
              final isSelected = (gramsAmount - presetGrams).abs() < 10;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => _setPortionPreset(name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${presetGrams}g',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? Colors.white70
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantitySliderSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fine-tune Amount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${gramsAmount}g',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.green,
              inactiveTrackColor: Colors.grey[300],
              thumbColor: Colors.green,
              overlayColor: Colors.green.withOpacity(0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: gramsAmount.toDouble(),
              min: 50,
              max: 500,
              divisions: 45, // 10g increments
              onChanged: _updateGramsFromSlider,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '50g',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  '500g',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Continue to batch 10...

  // ============================================================================
  // BATCH 10 (FINAL): Detailed Nutrition, Save Button & Custom Painter
  // ============================================================================

  Widget _buildDetailedNutritionSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  showDetailedNutrition = !showDetailedNutrition;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Detailed Nutrition',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    Icon(
                      showDetailedNutrition
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ),
            if (showDetailedNutrition) ...[
              Divider(height: 1, color: Colors.grey[300]),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildMacroRow(
                      'Carbohydrates',
                      currentMacros['carbs']!.toDouble(),
                      Colors.orange,
                      Icons.bakery_dining,
                    ),
                    const SizedBox(height: 12),
                    _buildMacroRow(
                      'Protein',
                      currentMacros['protein']!.toDouble(),
                      Colors.blue,
                      Icons.fitness_center,
                    ),
                    const SizedBox(height: 12),
                    _buildMacroRow(
                      'Fat',
                      currentMacros['fat']!.toDouble(),
                      Colors.purple,
                      Icons.water_drop,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMacroRow(String name, double value, Color color, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
        Text(
          '${value.toStringAsFixed(1)}g',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStickyBottomButton() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () {
              // Update food with new values
              widget.food.foodName = selectedFoodName;
              widget.food.gramsAmount = gramsAmount;
              widget.food.caloriesPer100g = caloriesPer100g;
              widget.food.macrosPer100g = macrosPer100g;

              widget.onUpdate(widget.food);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              elevation: 2,
              shadowColor: Colors.green.withOpacity(0.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.check_circle, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Save Changes',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Food Labels (UEC UNET, Kenyan Food, Food101)
// ============================================================================

// Kenyan Foods
final List<String> kenyanFoodLabels = [
  'Bhaji',
  'Chapati',
  'Githeri',
  'Kachumbari',
  'Kuku Choma',
  'Mandazi',
  'Masala Chips',
  'Matoke',
  'Mukimo',
  'Nyama Choma',
  'Pilau',
  'Sukuma Wiki',
  'Ugali',
];

// Food-101 Foods
final List<String> food101Labels = [
  'Apple Pie',
  'Baby Back Ribs',
  'Baklava',
  'Beef Carpaccio',
  'Beef Tartare',
  'Beet Salad',
  'Beignets',
  'Bibimbap',
  'Bread Pudding',
  'Breakfast Burrito',
  'Bruschetta',
  'Caesar Salad',
  'Cannoli',
  'Caprese Salad',
  'Carrot Cake',
  'Ceviche',
  'Cheesecake',
  'Cheese Plate',
  'Chicken Curry',
  'Chicken Quesadilla',
  'Chicken Wings',
  'Chocolate Cake',
  'Chocolate Mousse',
  'Churros',
  'Clam Chowder',
  'Club Sandwich',
  'Crab Cakes',
  'Creme Brulee',
  'Croque Madame',
  'Cup Cakes',
  'Deviled Eggs',
  'Donuts',
  'Dumplings',
  'Edamame',
  'Eggs Benedict',
  'Escargots',
  'Falafel',
  'Filet Mignon',
  'Fish and Chips',
  'Foie Gras',
  'French Fries',
  'French Onion Soup',
  'French Toast',
  'Fried Calamari',
  'Fried Rice',
  'Frozen Yogurt',
  'Garlic Bread',
  'Gnocchi',
  'Greek Salad',
  'Grilled Cheese Sandwich',
  'Grilled Salmon',
  'Guacamole',
  'Gyoza',
  'Hamburger',
  'Hot and Sour Soup',
  'Hot Dog',
  'Huevos Rancheros',
  'Hummus',
  'Ice Cream',
  'Lasagna',
  'Lobster Bisque',
  'Lobster Roll Sandwich',
  'Macaroni and Cheese',
  'Macarons',
  'Miso Soup',
  'Mussels',
  'Nachos',
  'Omelette',
  'Onion Rings',
  'Oysters',
  'Pad Thai',
  'Paella',
  'Pancakes',
  'Panna Cotta',
  'Peking Duck',
  'Pho',
  'Pizza',
  'Pork Chop',
  'Poutine',
  'Prime Rib',
  'Pulled Pork Sandwich',
  'Ramen',
  'Ravioli',
  'Red Velvet Cake',
  'Risotto',
  'Samosa',
  'Sashimi',
  'Scallops',
  'Seaweed Salad',
  'Shrimp and Grits',
  'Spaghetti Bolognese',
  'Spaghetti Carbonara',
  'Spring Rolls',
  'Steak',
  'Strawberry Shortcake',
  'Sushi',
  'Tacos',
  'Takoyaki',
  'Tiramisu',
  'Tuna Tartare',
  'Waffles',
];

// UEC UNet Foods (all 103 classes)
final List<String> uecUnetLabels = [
  'Background',
  'Rice',
  'Eels on Rice',
  'Pilaf',
  'Chicken-n-Egg on Rice',
  'Pork Cutlet on Rice',
  'Beef Curry',
  'Sushi',
  'Chicken Rice',
  'Fried Rice',
  'Tempura Bowl',
  'Bibimbap',
  'Toast',
  'Croissant',
  'Roll Bread',
  'Raisin Bread',
  'Chip Butty',
  'Hamburger',
  'Pizza',
  'Sandwiches',
  'Udon Noodle',
  'Tempura Udon',
  'Soba Noodle',
  'Ramen Noodle',
  'Beef Noodle',
  'Tensin Noodle',
  'Fried Noodle',
  'Spaghetti',
  'Japanese-Style Pancake',
  'Takoyaki',
  'Gratin',
  'Sauteed Vegetables',
  'Croquette',
  'Grilled Eggplant',
  'Sauteed Spinach',
  'Vegetable Tempura',
  'Miso Soup',
  'Potage',
  'Sausage',
  'Oden',
  'Omelet',
  'Ganmodoki',
  'Jiaozi',
  'Stew',
  'Teriyaki Grilled Fish',
  'Fried Fish',
  'Grilled Salmon',
  'Salmon Meuniere',
  'Sashimi',
  'Grilled Pacific Saury',
  'Sukiyaki',
  'Sweet and Sour Pork',
  'Lightly Roasted Fish',
  'Steamed Egg Hotchpotch',
  'Tempura',
  'Fried Chicken',
  'Sirloin Cutlet',
  'Nanbanzuke',
  'Boiled Fish',
  'Seasoned Beef with Potatoes',
  'Hambarg Steak',
  'Beef Steak',
  'Dried Fish',
  'Ginger Pork Saute',
  'Spicy Chili-Flavored Tofu',
  'Yakitori',
  'Cabbage Roll',
  'Rolled Omelet',
  'Egg Sunny-Side Up',
  'Fermented Soybeans',
  'Cold Tofu',
  'Egg Roll',
  'Chilled Noodle',
  'Stir-Fried Beef and Peppers',
  'Simmered Pork',
  'Boiled Chicken and Vegetables',
  'Sashimi Bowl',
  'Sushi Bowl',
  'Fish-Shaped Pancake with Bean Jam',
  'Shrimp with Chili Source',
  'Roast Chicken',
  'Steamed Meat Dumpling',
  'Omelet with Fried Rice',
  'Cutlet Curry',
  'Spaghetti Meat Sauce',
  'Fried Shrimp',
  'Potato Salad',
  'Green Salad',
  'Macaroni Salad',
  'Japanese Tofu and Vegetable Chowder',
  'Pork Miso Soup',
  'Chinese Soup',
  'Beef Bowl',
  'Kinpira-Style Sauteed Burdock',
  'Rice Ball',
  'Pizza Toast',
  'Dipping Noodles',
  'Hot Dog',
  'French Fries',
  'Mixed Rice',
  'Goya Chanpuru',
  'Others',
  'Beverage',
];

// ============================================================================
// Custom Painter for Semi-Circle Progress
// ============================================================================

class SemiCircleProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.5
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
    final radius = (size.width / 2) - strokeWidth / 2;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw background arc (semi-circle)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi, // Start at 180 degrees
      math.pi, // Sweep 180 degrees
      false,
      backgroundPaint,
    );

    // Draw progress arc (capped at 1.0 for display, even if progress > 1.0)
    final displayProgress = progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi * displayProgress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

// ============================================================================
// Animated Progress Painter
// ============================================================================

class AnimatedSemiCircleProgressPainter extends CustomPainter {
  final double progress; // Target progress (0.0 to 1.5)
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;
  final Animation<double> animation;

  AnimatedSemiCircleProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw background arc (semi-circle)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      backgroundPaint,
    );

    // ✅ FIX: Use animation.value directly (which represents the actual progress)
    // The animation controller is already set to the correct progress value
    final displayProgress = animation.value.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi * displayProgress, // ✅ This now correctly represents the actual progress
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is AnimatedSemiCircleProgressPainter) {
      return oldDelegate.progress != progress ||
          oldDelegate.progressColor != progressColor;
    }
    return true;
  }
}

// ============================================================================
// Detection Overlay Painter (for real-time preview)
// ============================================================================

class DetectionOverlayPainter extends CustomPainter {
  final List<SegmentedFood> foods;
  final double originalWidth;
  final double originalHeight;
  final double renderedWidth;
  final double renderedHeight;
  final double offsetX;
  final double offsetY;

  DetectionOverlayPainter({
    required this.foods,
    required this.originalWidth,
    required this.originalHeight,
    required this.renderedWidth,
    required this.renderedHeight,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.red,
    ];

    for (int i = 0; i < foods.length && i < 5; i++) {
      final food = foods[i];

      // Scale from segmentation coordinates to original image coordinates
      final segWidth = food.maskWidth.toDouble();
      final segHeight = food.maskHeight.toDouble();

      final originalX = (food.boundingBox.left / segWidth) * originalWidth;
      final originalY = (food.boundingBox.top / segHeight) * originalHeight;
      final originalWidthScaled =
          (food.boundingBox.width / segWidth) * originalWidth;
      final originalHeightScaled =
          (food.boundingBox.height / segHeight) * originalHeight;

      // Scale from original to rendered coordinates
      final renderedX = (originalX / originalWidth) * renderedWidth + offsetX;
      final renderedY = (originalY / originalHeight) * renderedHeight + offsetY;
      final renderedWidthScaled =
          (originalWidthScaled / originalWidth) * renderedWidth;
      final renderedHeightScaled =
          (originalHeightScaled / originalHeight) * renderedHeight;

      // Draw bounding box
      final paint = Paint()
        ..color = colors[i % colors.length].withAlpha((0.6 * 255).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRect(
        Rect.fromLTWH(
          renderedX,
          renderedY,
          renderedWidthScaled,
          renderedHeightScaled,
        ),
        paint,
      );

      // Draw label
      final textPainter = TextPainter(
        text: TextSpan(
          text: food.foodName ?? 'Food ${i + 1}',
          style: TextStyle(
            color: colors[i % colors.length],
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.black.withAlpha((0.8 * 255).toInt()), blurRadius: 4),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(renderedX + 8, renderedY + 8));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is DetectionOverlayPainter) {
      return oldDelegate.foods.length != foods.length;
    }
    return true;
  }
}
