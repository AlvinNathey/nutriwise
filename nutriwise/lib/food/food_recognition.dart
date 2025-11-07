import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Food Recognition Page
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

class _FoodRecognitionPageState extends State<FoodRecognitionPage> {
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

  @override
  void initState() {
    super.initState();
    _imageFile = File(widget.imageFile.path);
    _fetchUserGoalsAndTodayIntake().then((_) {
      _loadModelsAndProcess();
    });
  }

  @override
  void dispose() {
    _segmentationModel?.close();
    _kenyanFoodModel?.close();
    _food101Model?.close();
    super.dispose();
  }

  Future<void> _loadModelsAndProcess() async {
    try {
      print('Starting model loading and processing...');
      
      // Load all three models
      await _loadModels();
      
      // Process the image
      await _processImage();
      
      setState(() {
        _isProcessing = false;
      });
      
      print('Processing completed successfully');
    } catch (e) {
      print('Error in loadModelsAndProcess: $e');
      setState(() {
        _errorMessage = 'Failed to process image: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _loadModels() async {
    try {
      print('Loading models...');
      
      // Load segmentation model (UEC UNET)
      _segmentationModel = await Interpreter.fromAsset('assets/uec_unet_int8.tflite');
      print('✓ Segmentation model loaded');
      print('  Input shape: ${_segmentationModel!.getInputTensor(0).shape}');
      print('  Output shape: ${_segmentationModel!.getOutputTensor(0).shape}');
      
      // Load Kenyan food classification model
      _kenyanFoodModel = await Interpreter.fromAsset('assets/kenyanfood.tflite');
      print('✓ Kenyan food model loaded');
      print('  Input shape: ${_kenyanFoodModel!.getInputTensor(0).shape}');
      print('  Output shape: ${_kenyanFoodModel!.getOutputTensor(0).shape}');
      
      // Load Food101 classification model
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
      
      // Read and decode the image
      final imageBytes = await _imageFile!.readAsBytes();
      _originalImage = img.decodeImage(imageBytes);
      
      if (_originalImage == null) {
        throw Exception('Failed to decode image');
      }
      
      print('Image decoded: ${_originalImage!.width}x${_originalImage!.height}');
      
      // Make a copy for processing
      _processedImage = img.copyResize(
        _originalImage!,
        width: math.min(_originalImage!.width, 512),
        height: math.min(_originalImage!.height, 512),
      );

      // Step 1: Run segmentation
      print('Running segmentation...');
      await _runSegmentation();
      
      // Step 2: Run classification on detected regions
      print('Running classification...');
      await _runClassification();
      
      print('Image processing completed');
    } catch (e) {
      print('Image processing error: $e');
      throw Exception('Image processing failed: $e');
    }
  }

  Future<void> _runSegmentation() async {
    if (_segmentationModel == null || _processedImage == null) {
      print('Segmentation model or image is null');
      return;
    }

    try {
      // Get input shape from model
      final inputShape = _segmentationModel!.getInputTensor(0).shape;
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      
      print('Segmentation input size: ${inputWidth}x${inputHeight}');

      // Resize image to model input size
      final resizedImage = img.copyResize(
        _processedImage!,
        width: inputWidth,
        height: inputHeight,
      );

      // Prepare input tensor
      final inputType = _segmentationModel!.getInputTensor(0).type;
      final input = _prepareImageInput(resizedImage, inputWidth, inputHeight, inputType);

      // Prepare output tensor
      final outputShape = _segmentationModel!.getOutputTensor(0).shape;
      final outputType = _segmentationModel!.getOutputTensor(0).type;
      
      print('Output shape: $outputShape, type: $outputType');
      
      // FIXED: Create output buffer with proper structure for uint8
      dynamic output;
      if (outputType == TensorType.float32) {
        // For float32 output: [1, height, width, classes]
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
        // FIXED: For quantized output - create proper structure
        // Instead of List<List<List<int>>>, we need the exact bytes buffer
        final totalSize = outputShape[0] * outputShape[1] * outputShape[2] * outputShape[3];
        output = Uint8List(totalSize);
      } else {
        throw Exception('Unsupported output type: $outputType');
      }

      // Run inference
      print('Running segmentation inference...');
      _segmentationModel!.run(input, output);
      print('Segmentation inference completed');

      // Process segmentation output
      _processSegmentationOutput(output, outputShape, outputType);
      
    } catch (e) {
      print('Segmentation error: $e');
      print('Stack trace: ${StackTrace.current}');
      print('Creating fallback segments...');
      // Create a single region covering the whole image as fallback
      _createFallbackSegment();
    }
  }

  /// Prepare image input for model - Returns proper 4D tensor
  dynamic _prepareImageInput(img.Image image, int width, int height, TensorType inputType) {
    if (inputType == TensorType.uint8) {
      // Quantized model expects uint8 [0-255] in 4D shape [1, height, width, 3]
      // FIXED: Return as flattened Uint8List for better compatibility
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
      // Float32 model expects normalized [0-1] in 4D shape [1, height, width, 3]
      return List.generate(
        1,
        (_) => List.generate(
          height,
          (y) => List.generate(
            width,
            (x) {
              final pixel = image.getPixel(x, y);
              return [
                pixel.r / 255.0,
                pixel.g / 255.0,
                pixel.b / 255.0,
              ];
            },
          ),
        ),
      );
    }
  }

  void _processSegmentationOutput(dynamic output, List<int> outputShape, TensorType outputType) {
    try {
      print('Processing segmentation output...');
      final height = outputShape[1];
      final width = outputShape[2];
      final numClasses = outputShape[3];

      Map<int, int> classCounts = {};
      Map<int, double> classConfidences = {};
      Map<int, List<Offset>> classPixels = {}; // Store pixel positions

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
            if (maxProb > 0.3 && maxClass > 0) {
              classCounts[maxClass] = (classCounts[maxClass] ?? 0) + 1;
              classConfidences[maxClass] = math.max(classConfidences[maxClass] ?? 0.0, maxProb);
              classPixels.putIfAbsent(maxClass, () => []).add(Offset(x.toDouble(), y.toDouble()));
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
            if (maxProb > 0.3 && maxClass > 0) {
              classCounts[maxClass] = (classCounts[maxClass] ?? 0) + 1;
              classConfidences[maxClass] = math.max(classConfidences[maxClass] ?? 0.0, maxProb);
              classPixels.putIfAbsent(maxClass, () => []).add(Offset(x.toDouble(), y.toDouble()));
            }
          }
        }
      }

      print('Detected ${classCounts.length} food classes');
      var sortedClasses = classCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _segmentedFoods = [];
      final maxFoods = math.min(5, sortedClasses.length);

      for (int i = 0; i < maxFoods; i++) {
        final classIdx = sortedClasses[i].key;
        final pixelCount = sortedClasses[i].value;
        final confidence = classConfidences[classIdx] ?? 0.0;
        final minRegionSize = (width * height * 0.01).toInt();
        if (pixelCount < minRegionSize) {
          print('Skipping class $classIdx (too small: $pixelCount pixels)');
          continue;
        }
        if (classIdx < uecUnetLabels.length) {
          final foodName = uecUnetLabels[classIdx];
          print('Found: $foodName (confidence: ${(confidence * 100).toStringAsFixed(1)}%, pixels: $pixelCount)');

          // Calculate center from pixel positions
          Offset? center;
          final pixels = classPixels[classIdx] ?? [];
          if (pixels.isNotEmpty) {
            double sumX = 0, sumY = 0;
            for (final p in pixels) {
              sumX += p.dx;
              sumY += p.dy;
            }
            center = Offset(sumX / pixels.length, sumY / pixels.length);
          }

          // Create bounding box (simplified)
          final boxSize = 150.0;
          final spacing = 30.0;
          final xPos = 50.0 + (i * (boxSize + spacing));
          final yPos = 50.0;

          _segmentedFoods.add(
            SegmentedFood(
              id: i.toString(),
              boundingBox: Rect.fromLTWH(xPos, yPos, boxSize, boxSize),
              mask: [],
              confidence: confidence,
              foodName: foodName,
              segmentationSource: 'UEC UNET',
              calories: null,
              macros: null,
              center: center,
              quantity: 1, // Initialize with 1 serving
            ),
          );
        }
      }
      if (_segmentedFoods.isEmpty) {
        print('No foods detected, creating fallback segment');
        _createFallbackSegment();
      }
      print('Created ${_segmentedFoods.length} segmented food regions');
    } catch (e) {
      print('Error processing segmentation output: $e');
      print('Stack trace: ${StackTrace.current}');
      _createFallbackSegment();
    }
  }

  void _createFallbackSegment() {
    // Create a single region when segmentation fails or finds nothing
    _segmentedFoods = [
      SegmentedFood(
        id: '0',
        boundingBox: const Rect.fromLTWH(50, 50, 200, 200),
        mask: [],
        confidence: 0.5,
        foodName: null, // Will be filled by classification
        segmentationSource: 'Fallback',
        center: null,
        quantity: 1, // Initialize with 1 serving
      ),
    ];
    print('Created fallback segment');
  }

  Future<void> _runClassification() async {
    if (_processedImage == null) {
      print('No image for classification');
      return;
    }

    try {
      print('Running classification models...');
      
      List<FoodPrediction> allPredictions = [];

      // Run both classification models on the full image
      final kenyanPredictions = await _runKenyanFoodClassification(_processedImage!);
      final food101Predictions = await _runFood101Classification(_processedImage!);

      allPredictions.addAll(kenyanPredictions);
      allPredictions.addAll(food101Predictions);

      // Sort by confidence
      allPredictions.sort((a, b) => b.confidence.compareTo(a.confidence));
      _topPredictions = allPredictions;
      
      print('Got ${_topPredictions.length} total predictions');
      
      // Print top 5 predictions
      for (int i = 0; i < math.min(5, _topPredictions.length); i++) {
        final pred = _topPredictions[i];
        print('  ${i + 1}. ${pred.foodName} (${(pred.confidence * 100).toStringAsFixed(1)}%) - ${pred.source}');
      }

      // Assign predictions to segmented foods
      _assignPredictionsToSegments();
      
    } catch (e) {
      print('Classification error: $e');
      // Use dummy predictions if classification fails
      _assignDummyPredictions();
    }
  }
  void _assignPredictionsToSegments() {
    if (_segmentedFoods.isEmpty) {
      print('No segments to assign predictions to');
      return;
    }
    
    // Strategy: Assign best predictions to segments
    // Priority: UEC segmentation name > Classification predictions
    
    for (int i = 0; i < _segmentedFoods.length; i++) {
      final segment = _segmentedFoods[i];
      
      // If segmentation already found a food name, keep it but get better details from classification
      if (segment.foodName != null && segment.foodName!.isNotEmpty) {
        // Try to find matching prediction
        final matchingPred = _topPredictions.firstWhere(
          (pred) => pred.foodName.toLowerCase().contains(segment.foodName!.toLowerCase()) ||
                    segment.foodName!.toLowerCase().contains(pred.foodName.toLowerCase()),
          orElse: () => _topPredictions.isNotEmpty ? _topPredictions[0] : _createDummyPrediction(),
        );
        
        segment.calories = matchingPred.calories;
        segment.macros = matchingPred.macros;
        segment.classificationSource = matchingPred.source;
      } else {
        // No segmentation name, use top predictions
        if (i < _topPredictions.length) {
          final pred = _topPredictions[i];
          segment.foodName = pred.foodName;
          segment.calories = pred.calories;
          segment.macros = pred.macros;
          segment.classificationSource = pred.source;
        } else {
          // Fallback
          segment.foodName = 'Unknown Food';
          segment.calories = 150;
          segment.macros = {'carbs': 30, 'protein': 10, 'fat': 5, 'fiber': 3};
        }
      }
    }
    
    print('Assigned predictions to ${_segmentedFoods.length} segments');
  }

  void _assignDummyPredictions() {
    for (var segment in _segmentedFoods) {
      if (segment.foodName == null || segment.foodName!.isEmpty) {
        segment.foodName = 'Unknown Food';
      }
      segment.calories = 150;
      segment.macros = {'carbs': 30, 'protein': 10, 'fat': 5, 'fiber': 3};
    }
  }

  FoodPrediction _createDummyPrediction() {
    return FoodPrediction(
      foodName: 'Unknown',
      confidence: 0.5,
      calories: 150,
      macros: {'carbs': 30, 'protein': 10, 'fat': 5, 'fiber': 3},
      source: 'Fallback',
    );
  }

  Future<List<FoodPrediction>> _runKenyanFoodClassification(img.Image image) async {
    if (_kenyanFoodModel == null) {
      print('Kenyan food model is null');
      return [];
    }

    try {
      print('Running Kenyan food classification...');
      
      // Get input shape
      final inputShape = _kenyanFoodModel!.getInputTensor(0).shape;
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      final inputType = _kenyanFoodModel!.getInputTensor(0).type;

      print('Kenyan model input: ${inputWidth}x${inputHeight}, type: $inputType');

      // Resize image to model input size
      final resizedImage = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
      );

      // Prepare input
      final input = _prepareImageInput(resizedImage, inputWidth, inputHeight, inputType);

      // Get output shape
      final outputShape = _kenyanFoodModel!.getOutputTensor(0).shape;
      final outputType = _kenyanFoodModel!.getOutputTensor(0).type;
      final numClasses = outputShape[1];

      print('Kenyan model output: $numClasses classes, type: $outputType');

      // Prepare output buffer with correct shape [1, numClasses]
      dynamic output;
      if (outputType == TensorType.float32) {
        output = [List<double>.filled(numClasses, 0.0)];
      } else if (outputType == TensorType.uint8) {
        output = [Uint8List(numClasses)];
      } else {
        throw Exception('Unsupported output type: $outputType');
      }

      // Run inference
      _kenyanFoodModel!.run(input, output);
      print('Kenyan food inference completed');

      // Convert output to List<double>
      List<double> probabilities;
      if (output[0] is Uint8List) {
        probabilities = (output[0] as Uint8List).map((e) => e / 255.0).toList();
      } else if (output[0] is List<double>) {
        probabilities = output[0];
      } else {
        probabilities = List<double>.filled(numClasses, 0.0);
      }

      // Process predictions
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

  Future<List<FoodPrediction>> _runFood101Classification(img.Image image) async {
    if (_food101Model == null) {
      print('Food101 model is null');
      return [];
    }

    try {
      print('Running Food101 classification...');
      
      // Get input shape
      final inputShape = _food101Model!.getInputTensor(0).shape;
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      final inputType = _food101Model!.getInputTensor(0).type;

      print('Food101 model input: ${inputWidth}x${inputHeight}, type: $inputType');

      // Resize image to model input size
      final resizedImage = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
      );

      // Prepare input
      final input = _prepareImageInput(resizedImage, inputWidth, inputHeight, inputType);

      // Get output shape
      final outputShape = _food101Model!.getOutputTensor(0).shape;
      final outputType = _food101Model!.getOutputTensor(0).type;
      final numClasses = outputShape[1];

      print('Food101 model output: $numClasses classes, type: $outputType');

      // Prepare output buffer with correct shape [1, numClasses]
      dynamic output;
      if (outputType == TensorType.float32) {
        output = [List<double>.filled(numClasses, 0.0)];
      } else if (outputType == TensorType.uint8) {
        output = [Uint8List(numClasses)];
      } else {
        throw Exception('Unsupported output type: $outputType');
      }

      // Run inference
      _food101Model!.run(input, output);
      print('Food101 inference completed');

      // Convert output to List<double>
      List<double> probabilities;
      if (output[0] is Uint8List) {
        probabilities = (output[0] as Uint8List).map((e) => e / 255.0).toList();
      } else if (output[0] is List<double>) {
        probabilities = output[0];
      } else {
        probabilities = List<double>.filled(numClasses, 0.0);
      }

      // Process predictions
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

    // Get top predictions
    for (int i = 0; i < output.length && i < labels.length; i++) {
      if (output[i] > 0.05) { // 5% confidence threshold
        predictions.add(FoodPrediction(
          foodName: labels[i],
          confidence: output[i],
          calories: _getCaloriesForFood(labels[i]),
          macros: _getMacrosForFood(labels[i]),
          source: source,
        ));
      }
    }

    // Sort by confidence and take top 10
    predictions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return predictions.take(10).toList();
  }

  // Static calorie and macro data (per 100g serving)
  int _getCaloriesForFood(String foodName) {
    final calorieDb = {
      // Kenyan Foods (per 100g)
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
      
      // Common Foods
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
      
      // Food101 samples
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
    
    return calorieDb[foodName] ?? 150; // Default 150 calories per 100g
  }

  Map<String, int> _getMacrosForFood(String foodName) {
    final macroDb = {
      // Kenyan Foods (per 100g)
      'Ugali': {'carbs': 40, 'protein': 3, 'fat': 1, 'fiber': 2},
      'Sukuma Wiki': {'carbs': 7, 'protein': 3, 'fat': 1, 'fiber': 3},
      'Chapati': {'carbs': 28, 'protein': 4, 'fat': 3, 'fiber': 2},
      'Pilau': {'carbs': 38, 'protein': 8, 'fat': 6, 'fiber': 2},
      'Nyama Choma': {'carbs': 0, 'protein': 26, 'fat': 15, 'fiber': 0},
      'Githeri': {'carbs': 32, 'protein': 8, 'fat': 2, 'fiber': 6},
      'Mukimo': {'carbs': 30, 'protein': 5, 'fat': 2, 'fiber': 4},
      'Mandazi': {'carbs': 28, 'protein': 3, 'fat': 5, 'fiber': 1},
      
      // Common Foods (per 100g)
      'Rice': {'carbs': 45, 'protein': 4, 'fat': 0, 'fiber': 1},
      'Chicken': {'carbs': 0, 'protein': 31, 'fat': 3, 'fiber': 0},
      'Beef': {'carbs': 0, 'protein': 26, 'fat': 17, 'fiber': 0},
      'Fish': {'carbs': 0, 'protein': 22, 'fat': 1, 'fiber': 0},
      'Beans': {'carbs': 22, 'protein': 8, 'fat': 0, 'fiber': 6},
      'Pizza': {'carbs': 33, 'protein': 11, 'fat': 10, 'fiber': 2},
      'Hamburger': {'carbs': 30, 'protein': 17, 'fat': 13, 'fiber': 2},
      'Salad': {'carbs': 10, 'protein': 2, 'fat': 0, 'fiber': 3},
      
      // Food101 samples (per 100g)
      'Grilled Salmon': {'carbs': 0, 'protein': 25, 'fat': 12, 'fiber': 0},
      'Chicken Curry': {'carbs': 18, 'protein': 20, 'fat': 8, 'fiber': 3},
      'Fried Rice': {'carbs': 42, 'protein': 6, 'fat': 5, 'fiber': 2},
      'Miso Soup': {'carbs': 6, 'protein': 2, 'fat': 1, 'fiber': 1},
      'Caesar Salad': {'carbs': 8, 'protein': 12, 'fat': 12, 'fiber': 2},
      'Spaghetti Bolognese': {'carbs': 28, 'protein': 12, 'fat': 5, 'fiber': 3},
    };
    
    return macroDb[foodName] ?? {'carbs': 30, 'protein': 10, 'fat': 5, 'fiber': 3};
  }

  // FIXED: Fetch user goals AND today's consumed values from Firestore
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
        
        print('User goals loaded: $dailyGoal cal, $carbsTarget carbs, $proteinTarget protein, $fatTarget fat');
      }
      
      // FIXED: Fetch today's already consumed food
      final today = DateTime.now();
      final dateStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      
      final mealsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('barcodes')
          .where('date', isEqualTo: dateStr)
          .get();
      
      int totalCals = 0;
      int totalCarbs = 0;
      int totalProtein = 0;
      int totalFat = 0;
      
      for (var doc in mealsSnapshot.docs) {
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
      
      print('Today consumed so far: $totalCals cal, $totalCarbs carbs, $totalProtein protein, $totalFat fat');
      
    } catch (e) {
      print('Error fetching user goals and today intake: $e');
    }
  }

  int _parseFirestoreNumber(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // FIXED: Calculate total calories for THIS meal only (with quantity multipliers)
  int _calculateTotalCalories() {
    int total = 0;
    for (var food in _segmentedFoods) {
      // Calories per 100g * quantity (where quantity=1 means 100g)
      total += ((food.calories ?? 0) * food.quantity).round();
    }
    return total;
  }

  // FIXED: Calculate total macros for THIS meal only (with quantity multipliers)
  Map<String, int> _calculateTotalMacros() {
    Map<String, int> total = {'carbs': 0, 'protein': 0, 'fat': 0, 'fiber': 0};
    for (var food in _segmentedFoods) {
      if (food.macros != null) {
        // Macros per 100g * quantity
        total['carbs'] = (total['carbs'] ?? 0) + ((food.macros!['carbs'] ?? 0) * food.quantity).round();
        total['protein'] = (total['protein'] ?? 0) + ((food.macros!['protein'] ?? 0) * food.quantity).round();
        total['fat'] = (total['fat'] ?? 0) + ((food.macros!['fat'] ?? 0) * food.quantity).round();
        total['fiber'] = (total['fiber'] ?? 0) + ((food.macros!['fiber'] ?? 0) * food.quantity).round();
      }
    }
    return total;
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
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _buildResultsState(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          const SizedBox(height: 24),
          const Text(
            'Analyzing your food...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Using AI models to identify foods',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.green[300],
            ),
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
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
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
          const SizedBox(height: 80),
        ],
      ),
    );
  }
  Widget _buildMealHeader() {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
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
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
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
            // Overlay labels for detected foods
            ..._buildFoodLabels(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFoodLabels() {
    List<Widget> labels = [];
    // Get display image size (fixed height: 300, width: double.infinity)
    final displayHeight = 300.0;
    final displayWidth = MediaQuery.of(context).size.width - 32; // margin: 16 left/right

    // Segmentation size (model output)
    final segWidth = _segmentedFoods.isNotEmpty && _segmentedFoods[0].center != null
        ? 256.0 // You may want to use outputShape[2] if available
        : displayWidth;
    final segHeight = _segmentedFoods.isNotEmpty && _segmentedFoods[0].center != null
        ? 256.0
        : displayHeight;

    for (int i = 0; i < _segmentedFoods.length && i < 5; i++) {
      final food = _segmentedFoods[i];
      if (food.foodName != null && food.foodName!.isNotEmpty && food.center != null) {
        // Scale center from segmentation to display size
        final scaleX = displayWidth / segWidth;
        final scaleY = displayHeight / segHeight;
        final xPos = food.center!.dx * scaleX;
        final yPos = food.center!.dy * scaleY;

        labels.add(
          Positioned(
            left: xPos.clamp(0, displayWidth - 120), // prevent overflow
            top: yPos.clamp(0, displayHeight - 40),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
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
      // Fallback: If no center, use old stacking method
      else if (food.foodName != null && food.foodName!.isNotEmpty) {
        final xPos = 16.0 + (i * 10.0);
        final yPos = 16.0 + (i * 35.0);
        labels.add(
          Positioned(
            left: xPos,
            top: yPos,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
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
    return labels;
  }

  // FIXED: Total Intake section with correct calculations
  Widget _buildTotalIntake() {
    // Calculate this meal's totals
    final thisMealCalories = _calculateTotalCalories();
    final thisMealMacros = _calculateTotalMacros();

    // Calculate what would be left AFTER this meal
    final caloriesAfterMeal = todayCaloriesConsumed + thisMealCalories;
    final carbsAfterMeal = todayCarbsConsumed + (thisMealMacros['carbs'] ?? 0);
    final proteinAfterMeal = todayProteinConsumed + (thisMealMacros['protein'] ?? 0);
    final fatAfterMeal = todayFatConsumed + (thisMealMacros['fat'] ?? 0);

    // Calculate remaining (can be negative if over budget)
    final caloriesLeft = dailyGoal - caloriesAfterMeal;
    final carbsLeft = carbsTarget - carbsAfterMeal;
    final proteinLeft = proteinTarget - proteinAfterMeal;
    final fatLeft = fatTarget - fatAfterMeal;

    // Calculate percentage for progress ring
    final percentage = dailyGoal > 0
        ? (caloriesAfterMeal / dailyGoal).clamp(0, 1)
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
          // Show breakdown
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
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
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
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green[700],
                      ),
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
          SizedBox(
            height: 120,
            width: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(150, 180),
                  painter: SemiCircleProgressPainter(
                    progress: percentage.toDouble(),
                    backgroundColor: Colors.grey[200]!,
                    progressColor: caloriesLeft >= 0 ? Colors.green : Colors.red,
                    strokeWidth: 8,
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        caloriesLeft >= 0 ? caloriesLeft.toString() : '0',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: caloriesLeft >= 0 ? Colors.black87 : Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        caloriesLeft >= 0 ? 'kcal left' : 'over budget',
                        style: TextStyle(
                          fontSize: 12,
                          color: caloriesLeft >= 0 ? Colors.grey[600] : Colors.red[400],
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

  Widget _buildMacroCircle(
    String label, 
    int current, 
    int target, 
    Color color, 
    int left, 
    {double size = 50}
  ) {
    double progress = target > 0 ? (current / target).clamp(0, 1.5) : 0;
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
              CustomPaint(
                size: Size(size, size),
                painter: SemiCircleProgressPainter(
                  progress: progress,
                  backgroundColor: Colors.grey[200]!,
                  progressColor: left >= 0 ? color : Colors.red,
                  strokeWidth: 4,
                ),
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
        Text(
          left >= 0 ? '${left}g left' : '${left.abs()}g over',
          style: TextStyle(
            fontSize: 11, 
            color: left >= 0 ? Colors.grey[600] : Colors.red[400],
          ),
        ),
      ],
    );
  }

  Widget _buildModifyFoodSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
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
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 1 + _segmentedFoods.length, // Add button + foods
              itemBuilder: (context, index) {
                if (index == 0) {
                  // Add button
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
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add Food',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  // Food items
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

  Widget _buildFoodCard(SegmentedFood food, int index) {
    // Calculate actual calories based on quantity
    final displayCalories = ((food.calories ?? 0) * food.quantity).round();
    
    return GestureDetector(
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
                  child: Image.file(
                    _imageFile!,
                    width: 140,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
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
                ),
                // Confidence badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    '${(food.quantity * 100).round()}g',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
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
    );
  }

  void _showEditFoodDialog(SegmentedFood food, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditFoodPage(
          food: food,
          imageFile: _imageFile!,
          allPredictions: _topPredictions,
          onUpdate: (updatedFood) {
            setState(() {
              _segmentedFoods[index] = updatedFood;
            });
          },
        ),
      ),
    );
  }

  void _showAddFoodDialog() {
    // Simple dialog to manually add food
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Food'),
        content: const Text(
          'You can manually add food items that were not detected automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Add a new food item
              setState(() {
                _segmentedFoods.add(
                  SegmentedFood(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    boundingBox: const Rect.fromLTWH(0, 0, 100, 100),
                    mask: [],
                    confidence: 0.5,
                    foodName: 'Custom Food',
                    calories: 150,
                    macros: {'carbs': 30, 'protein': 10, 'fat': 5, 'fiber': 3},
                    quantity: 1,
                  ),
                );
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
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
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Data Models
// ============================================================================

class SegmentedFood {
  String id;
  Rect boundingBox;
  List<int> mask;
  double confidence;
  String? foodName;
  String? segmentationSource;
  String? classificationSource;
  int? calories; // Per 100g
  Map<String, int>? macros; // Per 100g
  Offset? center;
  double quantity; // Multiplier (1.0 = 100g, 2.0 = 200g, etc.)

  SegmentedFood({
    required this.id,
    required this.boundingBox,
    required this.mask,
    required this.confidence,
    this.foodName,
    this.segmentationSource,
    this.classificationSource,
    this.calories,
    this.macros,
    this.center,
    this.quantity = 1.0,
  });
}

class FoodPrediction {
  String foodName;
  double confidence;
  int calories;
  Map<String, int> macros;
  String source;

  FoodPrediction({
    required this.foodName,
    required this.confidence,
    required this.calories,
    required this.macros,
    required this.source,
  });
}

// ============================================================================
// Edit Food Page
// ============================================================================

class EditFoodPage extends StatefulWidget {
  final SegmentedFood food;
  final File imageFile;
  final List<FoodPrediction> allPredictions;
  final Function(SegmentedFood) onUpdate;

  const EditFoodPage({
    Key? key,
    required this.food,
    required this.imageFile,
    required this.allPredictions,
    required this.onUpdate,
  }) : super(key: key);

  @override
  State<EditFoodPage> createState() => _EditFoodPageState();
}

class _EditFoodPageState extends State<EditFoodPage> {
  late String selectedFoodName;
  late int quantity;
  String selectedSize = 'Medium plate 13~17cm';

  // Generate suggestions from predictions with >70% confidence
  List<String> get foodSuggestions {
    final Set<String> suggestions = {};
    
    // Add current food name if confidence is high
    if (widget.food.confidence > 0.7 && 
        widget.food.foodName != null && 
        widget.food.foodName!.isNotEmpty) {
      suggestions.add(widget.food.foodName!);
    }
    
    // Add predictions with >70% confidence
    for (final pred in widget.allPredictions) {
      if (pred.confidence > 0.7) {
        suggestions.add(pred.foodName);
      }
    }
    
    // If no high-confidence suggestions, add top 5 predictions
    if (suggestions.isEmpty) {
      for (int i = 0; i < widget.allPredictions.length && i < 5; i++) {
        suggestions.add(widget.allPredictions[i].foodName);
      }
    }
    
    // If still empty, add current food name or default
    if (suggestions.isEmpty) {
      if (widget.food.foodName != null && widget.food.foodName!.isNotEmpty) {
        suggestions.add(widget.food.foodName!);
      } else {
        suggestions.add('Unknown');
      }
    }
    
    return suggestions.toList();
  }

  final List<String> sizes = [
    'Small dish ~8cm',
    'Small plate 8~13cm',
    'Medium plate 13~17cm',
    'Large plate 17~21cm',
    'Buffet plate 21cm~',
  ];

  final ScrollController _scrollController = ScrollController();
  bool _showSaveButton = false;

  @override
  void initState() {
    super.initState();
    selectedFoodName = widget.food.foodName ?? 'Unknown';
    quantity = 1;
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.atEdge) {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        if (!_showSaveButton) {
          setState(() {
            _showSaveButton = true;
          });
        }
      } else {
        if (_showSaveButton) {
          setState(() {
            _showSaveButton = false;
          });
        }
      }
    } else {
      if (_showSaveButton) {
        setState(() {
          _showSaveButton = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFoodImageSection(),
                  const SizedBox(height: 24),
                  _buildCalorieHeader(),
                  const SizedBox(height: 24),
                  _buildFoodNameSection(),
                  const SizedBox(height: 24),
                  _buildQuantitySection(),
                  const SizedBox(height: 32),
                  if (_showSaveButton) _buildBottomButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodImageSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          widget.imageFile,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
        ),
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
            child: Text(
              selectedFoodName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.food.calories ?? 150} kcal',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green,
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
            'Food Name (Suggestions from AI)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Top predictions with >70% confidence',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: foodSuggestions.map((food) {
              final isSelected = food == selectedFoodName;
              
              // Find confidence for this food
              final pred = widget.allPredictions.firstWhere(
                (p) => p.foodName == food,
                orElse: () => FoodPrediction(
                  foodName: food,
                  confidence: widget.food.confidence,
                  calories: 0,
                  macros: {},
                  source: '',
                ),
              );
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedFoodName = food;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

  Widget _buildQuantitySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
              Text(
                '${quantity * 100}g',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedSize,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    if (quantity > 1) {
                      setState(() {
                        quantity--;
                      });
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.remove, color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 60,
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      quantity.toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      quantity++;
                    });
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...sizes.map((size) {
            final isSelected = size == selectedSize;
            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedSize = size;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                    Text(
                      size,
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected ? Colors.black : Colors.grey[700],
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      width: double.infinity,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () {
            widget.food.foodName = selectedFoodName;
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
            padding: const EdgeInsets.symmetric(vertical: 0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.save, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              const Text(
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
    );
  }
}

// ============================================================================
// Food Labels (Keep your original labels)
// ============================================================================

// 🥗 Kenyan Foods
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

// 🍽️ Food-101 Foods
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

// 🍱 UEC UNet Foods (all 103 classes)
final List<String> uecUnetLabels = [
  'Background', // Class 0
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
  final double progress; // 0.0 to 1.0
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
    final rect = Offset.zero & size;
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

    // Draw progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}