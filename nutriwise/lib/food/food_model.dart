import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class FoodPrediction {
  final String label;
  final double confidence;
  final String modelName;

  FoodPrediction({
    required this.label,
    required this.confidence,
    required this.modelName,
  });
}

class SegmentedFoodPortion {
  final String label;
  final double confidence;
  final Uint8List mask; // Segmentation mask as bytes
  final int classIndex;

  SegmentedFoodPortion({
    required this.label,
    required this.confidence,
    required this.mask,
    required this.classIndex,
  });
}

class FoodModelManager {
  Interpreter? uecUnetInterpreter;
  Interpreter? food101Interpreter;
  Interpreter? kenyanFoodInterpreter;

  List<String> food101Labels = [
    'apple_pie',
    'baby_back_ribs',
    'baklava',
    'beef_carpaccio',
    'beef_tartare',
    'beet_salad',
    'beignets',
    'bibimbap',
    'bread_pudding',
    'breakfast_burrito',
    'bruschetta',
    'caesar_salad',
    'cannoli',
    'caprese_salad',
    'carrot_cake',
    'ceviche',
    'cheesecake',
    'cheese_plate',
    'chicken_curry',
    'chicken_quesadilla',
    'chicken_wings',
    'chocolate_cake',
    'chocolate_mousse',
    'churros',
    'clam_chowder',
    'club_sandwich',
    'crab_cakes',
    'creme_brulee',
    'croque_madame',
    'cup_cakes',
    'deviled_eggs',
    'donuts',
    'dumplings',
    'edamame',
    'eggs_benedict',
    'escargots',
    'falafel',
    'filet_mignon',
    'fish_and_chips',
    'foie_gras',
    'french_fries',
    'french_onion_soup',
    'french_toast',
    'fried_calamari',
    'fried_rice',
    'frozen_yogurt',
    'garlic_bread',
    'gnocchi',
    'greek_salad',
    'grilled_cheese_sandwich',
    'grilled_salmon',
    'guacamole',
    'gyoza',
    'hamburger',
    'hot_and_sour_soup',
    'hot_dog',
    'huevos_rancheros',
    'hummus',
    'ice_cream',
    'lasagna',
    'lobster_bisque',
    'lobster_roll_sandwich',
    'macaroni_and_cheese',
    'macarons',
    'miso_soup',
    'mussels',
    'nachos',
    'omelette',
    'onion_rings',
    'oysters',
    'pad_thai',
    'paella',
    'pancakes',
    'panna_cotta',
    'peking_duck',
    'pho',
    'pizza',
    'pork_chop',
    'poutine',
    'prime_rib',
    'pulled_pork_sandwich',
    'ramen',
    'ravioli',
    'red_velvet_cake',
    'risotto',
    'samosa',
    'sashimi',
    'scallops',
    'seaweed_salad',
    'shrimp_and_grits',
    'spaghetti_bolognese',
    'spaghetti_carbonara',
    'spring_rolls',
    'steak',
    'strawberry_shortcake',
    'sushi',
    'tacos',
    'takoyaki',
    'tiramisu',
    'tuna_tartare',
    'waffles',
  ];

  List<String> kenyanFoodLabels = [
    'bhaji',
    'chapati',
    'githeri',
    'kachumbari',
    'kukuchoma',
    'mandazi',
    'masalachips',
    'matoke',
    'mukimo',
    'nyamachoma',
    'pilau',
    'sukumawikia',
    'ugali',
  ];

  List<String> uecUnetLabels = [
    'rice',
    'eels on rice',
    'pilaf',
    'chicken-\'n\'-egg on rice',
    'pork cutlet on rice',
    'beef curry',
    'sushi',
    'chicken rice',
    'fried rice',
    'tempura bowl',
    'bibimbap',
    'toast',
    'croissant',
    'roll bread',
    'raisin bread',
    'chip butty',
    'hamburger',
    'pizza',
    'sandwiches',
    'udon noodle',
    'tempura udon',
    'soba noodle',
    'ramen noodle',
    'beef noodle',
    'tensin noodle',
    'fried noodle',
    'spaghetti',
    'Japanese-style pancake',
    'takoyaki',
    'gratin',
    'sauteed vegetables',
    'croquette',
    'grilled eggplant',
    'sauteed spinach',
    'vegetable tempura',
    'miso soup',
    'potage',
    'sausage',
    'oden',
    'omelet',
    'ganmodoki',
    'jiaozi',
    'stew',
    'teriyaki grilled fish',
    'fried fish',
    'grilled salmon',
    'salmon meuniere',
    'sashimi',
    'grilled pacific saury',
    'sukiyaki',
    'sweet and sour pork',
    'lightly roasted fish',
    'steamed egg hotchpotch',
    'tempura',
    'fried chicken',
    'sirloin cutlet',
    'nanbanzuke',
    'boiled fish',
    'seasoned beef with potatoes',
    'hambarg steak',
    'beef steak',
    'dried fish',
    'ginger pork saute',
    'spicy chili-flavored tofu',
    'yakitori',
    'cabbage roll',
    'rolled omelet',
    'egg sunny-side up',
    'fermented soybeans',
    'cold tofu',
    'egg roll',
    'chilled noodle',
    'stir-fried beef and peppers',
    'simmered pork',
    'boiled chicken and vegetables',
    'sashimi bowl',
    'sushi bowl',
    'fish-shaped pancake with bean jam',
    'shrimp with chill source',
    'roast chicken',
    'steamed meat dumpling',
    'omelet with fried rice',
    'cutlet curry',
    'spaghetti meat sauce',
    'fried shrimp',
    'potato salad',
    'green salad',
    'macaroni salad',
    'Japanese tofu and vegetable chowder',
    'pork miso soup',
    'chinese soup',
    'beef bowl',
    'kinpira-style sauteed burdock',
    'rice ball',
    'pizza toast',
    'dipping noodles',
    'hot dog',
    'french fries',
    'mixed rice',
    'goya chanpuru',
    'others',
    'beverage',
  ];

  Future<void> loadModels() async {
    uecUnetInterpreter ??= await Interpreter.fromAsset(
      'assets/uec_unet.tflite',
    );
    food101Interpreter ??= await Interpreter.fromAsset('assets/food101.tflite');
    kenyanFoodInterpreter ??= await Interpreter.fromAsset(
      'assets/kenyanfood.tflite',
    );
  }

  // --- Image Preprocessing ---
  Float32List preprocessImage(File imageFile, int inputSize) {
    final rawBytes = imageFile.readAsBytesSync();
    final image = img.decodeImage(rawBytes)!;
    final resized = img.copyResize(image, width: inputSize, height: inputSize);

    final input = Float32List(inputSize * inputSize * 3);
    int i = 0;

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);

        // ✅ In image 4.5.4, pixel is a Color object
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        // Normalize RGB values to [0, 1]
        input[i++] = r / 255.0;
        input[i++] = g / 255.0;
        input[i++] = b / 255.0;
      }
    }

    return input;
  }

  // --- Segmentation using uec_unet ---
  Future<List<SegmentedFoodPortion>> runSegmentation(File imageFile) async {
    if (uecUnetInterpreter == null)
      throw Exception('Segmentation model not loaded');
    final inputSize = 224;
    final input = preprocessImage(imageFile, inputSize);

    // Prepare input/output
    var modelInput = input.reshape([1, inputSize, inputSize, 3]);
    var output = List.generate(
      1,
      (_) => List.filled(inputSize * inputSize, 0, growable: false),
    );
    uecUnetInterpreter!.run(modelInput, output);

    final maskBytes = Uint8List.fromList(
      output[0].map((e) => e as int).toList(),
    );

    Map<int, int> classCounts = {};
    for (var idx in maskBytes) {
      classCounts[idx] = (classCounts[idx] ?? 0) + 1;
    }
    final totalPixels = maskBytes.length;
    List<SegmentedFoodPortion> portions = [];
    classCounts.forEach((classIdx, count) {
      if (classIdx == 0) return;
      final confidence = count / totalPixels;
      final label = classIdx < uecUnetLabels.length
          ? uecUnetLabels[classIdx]
          : 'Unknown';
      portions.add(
        SegmentedFoodPortion(
          label: label,
          confidence: confidence,
          mask: maskBytes,
          classIndex: classIdx,
        ),
      );
    });
    portions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return portions.take(3).toList();
  }

  // --- Classification ---
  Future<List<FoodPrediction>> runClassification(
    Interpreter interpreter,
    File imageFile,
    List<String> labels,
    String modelName, {
    int inputSize = 224,
  }) async {
    final input = preprocessImage(imageFile, inputSize);

    // Prepare input/output
    var modelInput = input.reshape([1, inputSize, inputSize, 3]);
    var output = List.filled(labels.length, 0.0);
    interpreter.run(modelInput, output);

    final indexed = List.generate(labels.length, (i) => i);
    indexed.sort(
      (a, b) => (output[b] as double).compareTo(output[a] as double),
    );
    return indexed
        .take(3)
        .map(
          (i) => FoodPrediction(
            label: labels[i],
            confidence: output[i] as double,
            modelName: modelName,
          ),
        )
        .toList();
  }

  // --- Convenience method to run all models ---
  Future<List<FoodPrediction>> predictAll(File imageFile) async {
    await loadModels();
    final preds = <FoodPrediction>[];
    if (food101Interpreter != null && food101Labels.isNotEmpty) {
      preds.addAll(
        await runClassification(
          food101Interpreter!,
          imageFile,
          food101Labels,
          'food101',
        ),
      );
    }
    if (kenyanFoodInterpreter != null) {
      preds.addAll(
        await runClassification(
          kenyanFoodInterpreter!,
          imageFile,
          kenyanFoodLabels,
          'kenyanfood',
        ),
      );
    }
    return preds;
  }
}

// Helper extension for reshaping Float32List
extension Float32ListReshape on Float32List {
  List<List<List<List<double>>>> reshape(List<int> shape) {
    final batch = shape[0];
    final height = shape[1];
    final width = shape[2];
    final channels = shape[3];
    int idx = 0;
    return List.generate(
      batch,
      (_) => List.generate(
        height,
        (_) => List.generate(
          width,
          (_) => List.generate(channels, (_) => this[idx++].toDouble()),
        ),
      ),
    );
  }
}
