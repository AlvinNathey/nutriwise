import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'meal_summary.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'food_recognition.dart';

class LogFoodModal extends StatefulWidget {
  const LogFoodModal({Key? key}) : super(key: key);

  @override
  State<LogFoodModal> createState() => _LogFoodModalState();
}

class _LogFoodModalState extends State<LogFoodModal> {
  String? selectedMeal;
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Log Food',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: selectedMeal == null
                ? _buildMealOptions()
                : _buildInputOptionsSheet(selectedMeal!),
          ),
        ],
      ),
    );
  }

  Widget _buildMealOptions() {
    final meals = [
      {'name': 'Breakfast', 'icon': Icons.free_breakfast},
      {'name': 'Lunch', 'icon': Icons.lunch_dining},
      {'name': 'Dinner', 'icon': Icons.dinner_dining},
      {'name': 'Breakfast Snack', 'icon': Icons.bakery_dining},
      {'name': 'Afternoon Snack', 'icon': Icons.cookie},
      {'name': 'Midnight Snack', 'icon': Icons.nightlife},
    ];

    return ListView.builder(
      shrinkWrap: true,
      itemCount: meals.length,
      itemBuilder: (context, index) {
        final meal = meals[index];
        return ListTile(
          leading: Icon(
            meal['icon'] as IconData,
            color: Colors.grey[600],
            size: 28,
          ),
          title: Text(
            meal['name'] as String,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: const Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: Colors.grey,
          ),
          onTap: () {
            setState(() {
              selectedMeal = meal['name'] as String;
            });
          },
        );
      },
    );
  }

  Widget _buildInputOptionsSheet(String mealName) {
    return _InputOptionsSheet(
      mealName: mealName,
      onBack: () => setState(() => selectedMeal = null),
      onGallery: _handleGalleryTap,
      onCamera: _handleCameraTap,
      onBarcode: _handleBarcodeTap,
    );
  }

  Future<void> _handleGalleryTap() async {
    try {
      PermissionStatus permission;
      if (Platform.isIOS) {
        permission = await Permission.photos.status;
      } else {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          permission = await Permission.photos.status;
        } else {
          permission = await Permission.storage.status;
        }
      }
      if (permission.isDenied) {
        PermissionStatus requestResult;
        if (Platform.isIOS) {
          requestResult = await Permission.photos.request();
        } else {
          final androidInfo = await DeviceInfoPlugin().androidInfo;
          if (androidInfo.version.sdkInt >= 33) {
            requestResult = await Permission.photos.request();
          } else {
            requestResult = await Permission.storage.request();
          }
        }
        if (requestResult.isDenied) {
          _showPermissionDeniedDialog('Gallery');
          return;
        } else if (requestResult.isPermanentlyDenied) {
          _showPermissionPermanentlyDeniedDialog('Gallery');
          return;
        }
        permission = requestResult;
      }
      if (permission.isPermanentlyDenied) {
        _showPermissionPermanentlyDeniedDialog('Gallery');
        return;
      }
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        Navigator.of(context).pop(); // Close the input options sheet/modal
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FoodRecognitionPage(
              mealType: selectedMeal!,
              imageFile: image,
            ),
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to access gallery: ${e.toString()}');
    }
  }

  Future<void> _handleCameraTap() async {
    Navigator.of(context).pop(); // Close the input options sheet
    try {
      final PermissionStatus permission = await Permission.camera.status;
      if (permission.isDenied) {
        final PermissionStatus requestResult = await Permission.camera.request();
        if (requestResult.isDenied) {
          _showPermissionDeniedDialog('Camera');
          return;
        } else if (requestResult.isPermanentlyDenied) {
          _showPermissionPermanentlyDeniedDialog('Camera');
          return;
        }
      }
      if (permission.isPermanentlyDenied) {
        _showPermissionPermanentlyDeniedDialog('Camera');
        return;
      }
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        // Navigator.pop(context); // Close the modal
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FoodRecognitionPage(
              mealType: selectedMeal!,
              imageFile: image,
            ),
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to access camera: ${e.toString()}');
    }
  }

  Future<void> _handleBarcodeTap() async {
    try {
      var scanResult = await BarcodeScanner.scan();
      String barcode = scanResult.rawContent;
      if (barcode.isEmpty) {
        _showErrorSnackBar('No barcode scanned.');
        return;
      }

      // Show loading indicator while looking up
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Enhanced barcode lookup with multiple sources
      String productName = await _enhancedBarcodeLookup(barcode);

      if (Navigator.of(context).canPop()) Navigator.of(context).pop();

      if (!mounted) return;
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MealSummaryPage(
            mealType: selectedMeal ?? 'Unknown',
            foodName: productName,
            barcode: barcode,
          ),
        ),
      );
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      _showErrorSnackBar('Barcode scan failed: ${e.toString()}');
    }
  }

  Future<String> _enhancedBarcodeLookup(String barcode) async {
    final List<Future<String?>> lookups = [
      _lookupBarcodeList(barcode),
      _lookupOpenFoodFacts(barcode),
      _lookupKenyanRetailStores(barcode),
      _lookupUPCItemDB(barcode),
      _lookupGoogleSearch(barcode),
    ];

    // Try lookups in sequence, return first successful result
    for (var lookup in lookups) {
      try {
        final result = await lookup.timeout(const Duration(seconds: 10));
        if (result != null && result != 'Unknown Product' && result.isNotEmpty) {
          return result;
        }
      } catch (e) {
        // Continue to next lookup source
        continue;
      }
    }

    // Fallback if all lookups fail
    return 'Unknown Product (Barcode: $barcode)';
  }

  Future<String?> _lookupBarcodeList(String barcode) async {
    try {
      final url = Uri.parse('https://barcode-list.com/barcode/EN/Search.htm?barcode=$barcode');
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      });

      if (response.statusCode == 200) {
        final html = response.body;

        // Try to extract product name from the main result table
        final tableMatch = RegExp(r'<table[^>]*class="[^"]*search-results[^"]*"[^>]*>([\s\S]*?)</table>', caseSensitive: false).firstMatch(html);
        if (tableMatch != null) {
          final tableHtml = tableMatch.group(1) ?? ''; 
          // Look for a row with "Product Name"
          final rowMatch = RegExp(r'<tr>[\s\S]*?<td[^>]*>Product Name:?<\/td>[\s\S]*?<td[^>]*>([^<]+)<\/td>', caseSensitive: false).firstMatch(tableHtml);
          if (rowMatch != null) {
            final productName = _cleanProductName(rowMatch.group(1));
            if (productName != 'Unknown Product' && productName.isNotEmpty) {
              return productName;
            }
          }
        }

        // Fallback: Try <h1> tag
        final h1Match = RegExp(r'<h1[^>]*>([^<]+)</h1>', caseSensitive: false).firstMatch(html);
        if (h1Match != null) {
          final productName = _cleanProductName(h1Match.group(1));
          if (productName != 'Unknown Product' && productName.isNotEmpty) {
            return productName;
          }
        }
      }
    } catch (e) {
      // Silently fail and continue to next source
    }
    return null;
  }

  Future<String?> _lookupKenyanRetailStores(String barcode) async {
    // List of popular Kenyan retail store APIs/websites to check
    final kenyanStores = [
      {'name': 'Naivas', 'url': 'naivas.co.ke'},
      {'name': 'QuickMart', 'url': 'quickmart.co.ke'},
      {'name': 'Carrefour Kenya', 'url': 'carrefour.ke'},
      {'name': 'Chandarana', 'url': 'chandarana.com'},
      {'name': 'Shoprite Kenya', 'url': 'shoprite.co.ke'},
    ];

    // Try each store's potential API or web search
    for (var store in kenyanStores) {
      try {
        // First try a direct search on the store's website (simulated)
        final searchUrl = Uri.parse('https://www.google.com/search?q=site:${store['url']}+$barcode');
        final response = await http.get(searchUrl, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final productName = _extractProductNameFromSearch(response.body, barcode);
          if (productName != null && productName != 'Unknown Product') {
            return productName;
          }
        }
      } catch (e) {
        // Continue to next store
      }
    }

    return null;
  }

  Future<String?> _lookupOpenFoodFacts(String barcode) async {
    try {
      final url = Uri.parse('https://world.openfoodfacts.org/api/v0/product/$barcode.json');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          
          final productName = _cleanProductName(
            product['product_name'] ??
            product['product_name_en'] ??
            product['generic_name'] ??
            product['generic_name_en'] ??
            product['abbreviated_product_name'] ??
            'Unknown Product'
          );
          
          if (productName != 'Unknown Product') {
            return productName;
          }
        }
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  Future<String?> _lookupUPCItemDB(String barcode) async {
    try {
      final url = Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['items'] != null && data['items'] is List && (data['items'] as List).isNotEmpty) {
          final item = (data['items'] as List)[0];
          final candidate = item['title'] ?? item['description'];
          
          if (candidate != null && candidate.toString().trim().isNotEmpty) {
            final productName = _cleanProductName(candidate.toString());
            if (productName != 'Unknown Product') {
              return productName;
            }
          }
        }
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  Future<String?> _lookupGoogleSearch(String barcode) async {
    try {
      final googleUrl = Uri.parse('https://www.google.com/search?q=$barcode+product+kenya');
      final response = await http.get(googleUrl, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      });

      if (response.statusCode == 200) {
        final productName = _extractProductNameFromSearch(response.body, barcode);
        if (productName != null && productName != 'Unknown Product') {
          return productName;
        }
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  String? _extractProductNameFromSearch(String html, String barcode) {
    try {
      // Multiple extraction strategies
      final strategies = [
        _extractFromH3Tags,
        _extractFromTitle,
        _extractFromJsonLd,
        _extractFromMetaTags,
        _extractFromDivs,
      ];

      for (var strategy in strategies) {
        final name = strategy(html, barcode);
        if (name != null && _isValidProductName(name, barcode)) {
          return name;
        }
      }
    } catch (e) {
      // Continue to next strategy
    }
    return null;
  }

  String? _extractFromH3Tags(String html, String barcode) {
    final h3Matches = RegExp(r'<h3[^>]*>([^<]+)</h3>', caseSensitive: false).allMatches(html);
    for (final match in h3Matches) {
      final candidate = _cleanProductName(match.group(1));
      if (_isValidProductName(candidate, barcode)) {
        return candidate;
      }
    }
    return null;
  }

  String? _extractFromTitle(String html, String barcode) {
    final titleMatch = RegExp(r'<title>([^<]+)</title>', caseSensitive: false).firstMatch(html);
    if (titleMatch != null) {
      String title = _cleanProductName(titleMatch.group(1));
      title = title.replaceAll(' - Google Search', '').trim();
      if (_isValidProductName(title, barcode)) {
        return title;
      }
    }
    return null;
  }

  String? _extractFromJsonLd(String html, String barcode) {
    final jsonLdMatches = RegExp(r'<script type="application/ld\+json">([\s\S]*?)</script>', caseSensitive: false).allMatches(html);
    for (final m in jsonLdMatches) {
      try {
        final block = m.group(1);
        if (block == null) continue;
        final obj = json.decode(block);
        if (obj is Map && obj['name'] is String) {
          final name = _cleanProductName(obj['name'] as String);
          if (_isValidProductName(name, barcode)) {
            return name;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  String? _extractFromMetaTags(String html, String barcode) {
    final metaMatches = RegExp(r'''<meta[^>]*name=["']description["'][^>]*content=["']([^"']+)["']''', caseSensitive: false).allMatches(html);
    for (final match in metaMatches) {
      final candidate = _cleanProductName(match.group(1));
      if (_isValidProductName(candidate, barcode)) {
        return candidate;
      }
    }
    return null;
  }

  String? _extractFromDivs(String html, String barcode) {
    final divMatches = RegExp(r'<div[^>]*class="[^"]*product[^"]*"[^>]*>([^<]+)</div>', caseSensitive: false).allMatches(html);
    for (final match in divMatches) {
      final candidate = _cleanProductName(match.group(1));
      if (_isValidProductName(candidate, barcode)) {
        return candidate;
      }
    }
    return null;
  }

  String _cleanProductName(String? name) {
    if (name == null || name.isEmpty) return 'Unknown Product';
    
    String cleaned = name
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[–—-]\s*(Google|Bing|Search|Results?).*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^\W+|\W+$'), '')
        .trim();

    if (cleaned.isNotEmpty && cleaned.length > 2) {
      // Capitalize first letter of each word
      cleaned = cleaned.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    return cleaned.isEmpty ? 'Unknown Product' : cleaned;
  }

  bool _isValidProductName(String candidate, String barcode) {
    if (candidate.isEmpty || candidate == 'Unknown Product') return false;
    final lower = candidate.toLowerCase();
    
    final invalidPatterns = [
      'google search',
      'search results',
      'bing results',
      'yahoo search',
      'not found',
      '404',
      'error',
      barcode.toLowerCase(),
    ];

    for (var pattern in invalidPatterns) {
      if (lower.contains(pattern)) return false;
    }

    // Check if it's just numbers or special characters
    if (RegExp(r'^[\d\W_]+$').hasMatch(candidate)) return false;
    
    // Check minimum length
    if (candidate.trim().length <= 2) return false;
    
    return true;
  }

  void _showPermissionDeniedDialog(String feature) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('$feature Permission Required'),
          content: Text(
            'This app needs $feature permission to function properly. '
            'Please grant permission in the next dialog.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showPermissionPermanentlyDeniedDialog(String feature) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('$feature Permission Required'),
          content: Text(
            '$feature permission has been permanently denied. '
            'Please enable it in Settings > Privacy > $feature to use this feature.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}

// --- Input Options Sheet Widget ---
class _InputOptionsSheet extends StatelessWidget {
  final String mealName;
  final VoidCallback onBack;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback onBarcode;

  const _InputOptionsSheet({
    required this.mealName,
    required this.onBack,
    required this.onGallery,
    required this.onCamera,
    required this.onBarcode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Wrap(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
                tooltip: 'Back',
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Add to $mealName',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48), // To balance the back button visually
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.photo_library,
                color: Colors.blue[600],
                size: 24,
              ),
            ),
            title: const Text(
              'Gallery',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: const Text(
              'Choose from your photos',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            onTap: onGallery,
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.camera_alt,
                color: Colors.green[600],
                size: 24,
              ),
            ),
            title: const Text(
              'Camera',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: const Text(
              'Take a photo',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            onTap: onCamera,
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.qr_code_scanner,
                color: Colors.orange[600],
                size: 24,
              ),
            ),
            title: const Text(
              'Barcode',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: const Text(
              'Scan product barcode',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            onTap: onBarcode,
          ),
        ],
      ),
    );
  }
}