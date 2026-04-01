import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nutriwise/food/after_meal_summary.dart';
import 'package:nutriwise/food/food_search_service.dart';
import 'package:nutriwise/food/meal_summary.dart';
import 'package:nutriwise/home/home_screen.dart';
import 'package:nutriwise/services/food_collections.dart';
import 'package:shimmer/shimmer.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

class SelectedSearchFoodItem {
  final FoodSearchResult result;
  final double quantity;
  final String quantityUnit;
  final String? servingLabel;
  final String logSource;
  final DateTime selectedAt;

  SelectedSearchFoodItem({
    required this.result,
    required this.quantity,
    required this.quantityUnit,
    this.servingLabel,
    this.logSource = 'Manually Added',
    DateTime? selectedAt,
  }) : selectedAt = selectedAt ?? DateTime.now();

  double get grams => quantity;
  double get factor => grams / 100.0;
  double get calories => result.caloriesPer100g * factor;
  double get carbs => result.carbsPer100g * factor;
  double get protein => result.proteinPer100g * factor;
  double get fat => result.fatPer100g * factor;

  SelectedSearchFoodItem copyWith({
    double? quantity,
    String? quantityUnit,
    String? servingLabel,
    String? logSource,
  }) {
    return SelectedSearchFoodItem(
      result: result,
      quantity: quantity ?? this.quantity,
      quantityUnit: quantityUnit ?? this.quantityUnit,
      servingLabel: servingLabel ?? this.servingLabel,
      logSource: logSource ?? this.logSource,
      selectedAt: selectedAt,
    );
  }
}

// ============================================================================
// MAIN SEARCH PAGE - MFP-STYLE REDESIGN
// ============================================================================

class SearchFoodPage extends StatefulWidget {
  final String mealType;
  final DateTime? selectedDate;

  const SearchFoodPage({
    super.key,
    required this.mealType,
    this.selectedDate,
  });

  @override
  State<SearchFoodPage> createState() => _SearchFoodPageState();
}

class _SearchFoodPageState extends State<SearchFoodPage> 
    with TickerProviderStateMixin {
  
  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  // State
  final List<SelectedSearchFoodItem> _selectedFoods = [];
  Timer? _debounce;
  Timer? _searchRetryTimer;
  
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isSearching = false;
  
  String? _errorMessage;
  List<FoodSearchResult> _searchResults = [];
  List<FoodSearchResult> _recentFoods = [];
  List<FoodSearchResult> _myFoods = [];
  Set<String> _favoriteFoodKeys = <String>{};
  String _browseTab = 'recent';
  bool _isAfterMealExpanded = true;
  bool _isSavedFoodsLoading = true;
  
  // User context
  int _dailyGoal = 2000;
  int _carbsTarget = 250;
  int _proteinTarget = 150;
  int _fatTarget = 70;
  int _todayCalories = 0;
  int _todayCarbs = 0;
  int _todayProtein = 0;
  int _todayFat = 0;
  int _searchRequestId = 0;

  // Animation controllers
  late AnimationController _fabAnimationController;
  
  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fetchContext();
    _loadRecentAndFrequentFoods();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchRetryTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // DATA FETCHING
  // ==========================================================================

  Future<void> _fetchContext() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Please sign in to log foods');
      return;
    }

    try {
      final dateStr = _formatDate(widget.selectedDate ?? DateTime.now());
      
      // Parallel fetching for better performance
      final results = await Future.wait([
        _fetchUserGoals(user.uid),
        _fetchTodayTotals(user.uid, dateStr),
      ]);

      if (!mounted) return;

      setState(() {
        final goals = results[0];
        final totals = results[1];
        
        _dailyGoal = goals['calories'] ?? 2000;
        _carbsTarget = goals['carbs'] ?? 250;
        _proteinTarget = goals['protein'] ?? 150;
        _fatTarget = goals['fat'] ?? 70;
        
        _todayCalories = totals['calories'] ?? 0;
        _todayCarbs = totals['carbs'] ?? 0;
        _todayProtein = totals['protein'] ?? 0;
        _todayFat = totals['fat'] ?? 0;
      });
    } on FirebaseException catch (e) {
      _handleFirebaseError(e, 'Failed to load daily context');
    } catch (e) {
      _showError('Unable to load your daily goals. Please try again.');
    }
  }

  Future<Map<String, int>> _fetchUserGoals(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      final data = doc.data() ?? {};
      return {
        'calories': ((data['calories'] ?? 2000) as num).round(),
        'carbs': ((data['carbG'] ?? 250) as num).round(),
        'protein': ((data['proteinG'] ?? 150) as num).round(),
        'fat': ((data['fatG'] ?? 70) as num).round(),
      };
    } catch (e) {
      throw Exception('Failed to fetch user goals: $e');
    }
  }

  Future<Map<String, int>> _fetchTodayTotals(String userId, String dateStr) async {
    int calories = 0, carbs = 0, protein = 0, fat = 0;
    
    try {
      // Fetch meals
      final mealsQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('meals')
          .where('date', isEqualTo: dateStr)
          .get();

      for (final doc in mealsQuery.docs) {
        final data = doc.data();
        calories += ((data['totalCalories'] ?? 0) as num).round();
        carbs += ((data['totalCarbs'] ?? 0) as num).round();
        protein += ((data['totalProtein'] ?? 0) as num).round();
        fat += ((data['totalFat'] ?? 0) as num).round();
      }

      // Fetch barcode scans
      final barcodesQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('barcodes')
          .where('date', isEqualTo: dateStr)
          .get();

      final manualFoodsQuery = await userManualFoodsCollection(userId)
          .where('date', isEqualTo: dateStr)
          .get();

      for (final doc in barcodesQuery.docs) {
        final data = doc.data();
        calories += ((data['calories'] ?? 0) as num).round();
        carbs += ((data['carbs'] ?? 0) as num).round();
        protein += ((data['protein'] ?? 0) as num).round();
        fat += ((data['fat'] ?? 0) as num).round();
      }

      for (final doc in manualFoodsQuery.docs) {
        final data = doc.data();
        calories += ((data['calories'] ?? 0) as num).round();
        carbs += ((data['carbs'] ?? 0) as num).round();
        protein += ((data['protein'] ?? 0) as num).round();
        fat += ((data['fat'] ?? 0) as num).round();
      }

      return {'calories': calories, 'carbs': carbs, 'protein': protein, 'fat': fat};
    } catch (e) {
      throw Exception('Failed to fetch today totals: $e');
    }
  }

  Future<void> _loadRecentAndFrequentFoods() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isSavedFoodsLoading = false;
      });
      return;
    }

    final recentIds = <String>{};
    final recent = <FoodSearchResult>[];
    final myFoods = <FoodSearchResult>[];
    final favoriteKeys = <String>{};

    try {
      final recentSnapshot = await userManualFoodsCollection(user.uid)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();

      for (final doc in recentSnapshot.docs) {
        _addRecentFoodFromMap(recent, recentIds, doc.data());
      }
    } catch (e) {
      debugPrint('Failed to load recent manual foods: $e');
    }

    try {
      final legacyRecentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('barcodes')
          .where('source', isEqualTo: 'Manually Added')
          .get();

      final legacyDocs = legacyRecentSnapshot.docs.toList()
        ..sort((a, b) {
          final aCreatedAt = _asDateTime(a.data()['createdAt']);
          final bCreatedAt = _asDateTime(b.data()['createdAt']);
          return bCreatedAt.compareTo(aCreatedAt);
        });

      for (final doc in legacyDocs) {
        _addRecentFoodFromMap(recent, recentIds, doc.data());
      }
    } catch (e) {
      debugPrint('Failed to load legacy recent manual foods: $e');
    }

    try {
      final favoritesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('manual_food_favorites')
          .orderBy('updatedAt', descending: true)
          .get();

      for (final doc in favoritesSnapshot.docs) {
        final data = doc.data();
        final item = _foodResultFromMap(data, fallbackSource: 'My Food');
        myFoods.add(item);
        favoriteKeys.add(_foodKey(item.name));
      }
    } catch (e) {
      debugPrint('Failed to load My Foods favorites: $e');
    }

    if (!mounted) return;

    setState(() {
      _recentFoods = recent.take(8).toList();
      _myFoods = myFoods;
      _favoriteFoodKeys = favoriteKeys;
      _isSavedFoodsLoading = false;
    });
  }

  DateTime _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _addRecentFoodFromMap(
    List<FoodSearchResult> recent,
    Set<String> recentIds,
    Map<String, dynamic> data,
  ) {
    final name = data['foodName'] as String?;
    if (name == null) return;

    final key = _foodKey(name);
    if (recentIds.contains(key)) return;

    recentIds.add(key);
    final unit = (data['unit'] ?? 'g').toString();
    recent.add(
      FoodSearchResult(
        id: 'recent_${name.toLowerCase().replaceAll(RegExp(r'\\s+'), '_')}',
        name: name,
        subtitle: 'Recently logged',
        caloriesPer100g: ((data['caloriesPer100g'] ?? 0) as num).toDouble(),
        proteinPer100g: ((data['proteinPer100g'] ?? 0) as num).toDouble(),
        carbsPer100g: ((data['carbsPer100g'] ?? 0) as num).toDouble(),
        fatPer100g: ((data['fatPer100g'] ?? 0) as num).toDouble(),
        defaultQuantity: ((data['quantity'] ?? 100) as num).toDouble(),
        quantityUnit: unit,
        source: (data['sourceDb'] ?? 'Recent').toString(),
        groupKey: 'recent',
        servingOptions: [
          FoodServingOption(
            label: 'Last used',
            quantity: ((data['quantity'] ?? 100) as num).toDouble(),
            unit: unit,
          ),
          FoodServingOption(label: '100 g', quantity: 100, unit: 'g'),
        ],
        matchScore: 100,
      ),
    );
  }

  FoodSearchResult _foodResultFromMap(
    Map<String, dynamic> data, {
    String fallbackSource = 'Recent',
  }) {
    final name = (data['foodName'] ?? data['name'] ?? '').toString().trim();
    final unit = (data['unit'] ?? data['quantityUnit'] ?? 'g').toString();
    final quantity = ((data['quantity'] ?? data['defaultQuantity'] ?? 100) as num)
        .toDouble();
    return FoodSearchResult(
      id: (data['id'] ?? 'saved_${name.toLowerCase().replaceAll(RegExp(r'\\s+'), '_')}')
          .toString(),
      name: name,
      subtitle: (data['subtitle'] ?? 'Saved food').toString(),
      caloriesPer100g: ((data['caloriesPer100g'] ?? 0) as num).toDouble(),
      proteinPer100g: ((data['proteinPer100g'] ?? 0) as num).toDouble(),
      carbsPer100g: ((data['carbsPer100g'] ?? 0) as num).toDouble(),
      fatPer100g: ((data['fatPer100g'] ?? 0) as num).toDouble(),
      defaultQuantity: quantity,
      quantityUnit: unit,
      source: (data['sourceDb'] ?? data['source'] ?? fallbackSource).toString(),
      groupKey: 'saved',
      servingOptions: [
        FoodServingOption(label: 'Last used', quantity: quantity, unit: unit),
        FoodServingOption(label: '100 g', quantity: 100, unit: 'g'),
      ],
      matchScore: 110,
    );
  }

  String _foodKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _toggleFavorite(FoodSearchResult result) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final key = _foodKey(result.name);
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('manual_food_favorites')
        .doc(key.replaceAll(' ', '_'));
    final isFav = _favoriteFoodKeys.contains(key);

    if (isFav) {
      await ref.delete();
      if (!mounted) return;
      setState(() {
        _favoriteFoodKeys.remove(key);
        _myFoods.removeWhere((f) => _foodKey(f.name) == key);
      });
    } else {
      await ref.set({
        'id': result.id,
        'foodName': result.name,
        'subtitle': result.subtitle,
        'caloriesPer100g': result.caloriesPer100g,
        'carbsPer100g': result.carbsPer100g,
        'proteinPer100g': result.proteinPer100g,
        'fatPer100g': result.fatPer100g,
        'defaultQuantity': result.defaultQuantity,
        'quantityUnit': result.quantityUnit,
        'quantity': result.defaultQuantity,
        'unit': result.quantityUnit,
        'source': 'My Food',
        'sourceDb': result.source,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _favoriteFoodKeys.add(key);
        if (_myFoods.every((f) => _foodKey(f.name) != key)) {
          _myFoods.insert(0, result);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.name} added to My Foods'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ==========================================================================
  // SEARCH LOGIC
  // ==========================================================================

  void _onSearchChanged(String value) {
    setState(() {
      _isSearching = value.isNotEmpty;
      _errorMessage = null;
      if (value.isNotEmpty) {
        _isAfterMealExpanded = false;
      }
    });
    
    _debounce?.cancel();
    _searchRetryTimer?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _performSearch(value),
    );
  }

  bool _shouldAutoRetrySearch(String query) {
    return mounted &&
        _searchFocusNode.hasFocus &&
        _searchController.text.trim() == query;
  }

  void _scheduleSearchRetry(String query) {
    _searchRetryTimer?.cancel();
    _searchRetryTimer = Timer(
      const Duration(milliseconds: 700),
      () => _performSearch(query, allowAutoRetry: true),
    );
  }

  Future<void> _performSearch(
    String query, {
    bool allowAutoRetry = true,
  }) async {
    final trimmed = query.trim();
    final requestId = ++_searchRequestId;
    
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _errorMessage = null;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await FoodSearchService.searchFoods(trimmed);
      
      if (!mounted ||
          requestId != _searchRequestId ||
          _searchController.text.trim() != trimmed) {
        return;
      }
      
      setState(() {
        _searchResults = results;
        _isLoading = false;
        if (results.isEmpty) {
          _errorMessage = 'No foods found for "$trimmed"';
        }
      });
    } on TimeoutException {
      if (!mounted ||
          requestId != _searchRequestId ||
          _searchController.text.trim() != trimmed) {
        return;
      }
      if (allowAutoRetry && _shouldAutoRetrySearch(trimmed)) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
        _scheduleSearchRetry(trimmed);
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Search timed out. Please check your connection and try again.';
      });
    } catch (_) {
      if (!mounted ||
          requestId != _searchRequestId ||
          _searchController.text.trim() != trimmed) {
        return;
      }
      if (allowAutoRetry && _shouldAutoRetrySearch(trimmed)) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
        _scheduleSearchRetry(trimmed);
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to refresh results right now. Keep typing and we\'ll retry automatically.';
      });
    }
  }

  // ==========================================================================
  // FOOD SELECTION
  // ==========================================================================

  Future<void> _showFoodDetail(FoodSearchResult result, {bool isQuickAdd = false}) async {
    try {
      final selected = await Navigator.of(context).push<SelectedSearchFoodItem>(
        MaterialPageRoute(
          builder: (_) => FoodDetailPage(
            mealType: widget.mealType,
            result: result,
            isQuickAdd: isQuickAdd,
          ),
        ),
      );

      if (selected != null && mounted) {
        _addFoodToSelection(selected);
      }
    } catch (e) {
      _showError('Unable to open food details. Please try again.');
    }
  }

  void _addFoodToSelection(SelectedSearchFoodItem item) {
    FocusScope.of(context).unfocus();
    _searchFocusNode.unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    setState(() {
      _searchController.clear();
      _searchResults = [];
      _isSearching = false;
      _errorMessage = null;
      _selectedFoods.add(item);
      _fabAnimationController.forward();
    });
  }

  Future<void> _scanBarcodeAndAddToSelection() async {
    try {
      final scanResult = await BarcodeScanner.scan();
      final barcode = scanResult.rawContent.trim();
      if (barcode.isEmpty || !mounted) return;

      final barcodeItems =
          await Navigator.of(context).push<List<BarcodeSelectionItem>>(
        MaterialPageRoute(
          builder: (_) => MealSummaryPage(
            mealType: widget.mealType,
            foodName: null,
            barcode: barcode,
            returnSelectionOnly: true,
          ),
        ),
      );

      if (!mounted || barcodeItems == null || barcodeItems.isEmpty) return;

      for (final barcodeItem in barcodeItems) {
        _addFoodToSelection(_barcodeItemToSelection(barcodeItem));
      }
    } catch (e) {
      _showError('Barcode scan failed. Please try again.');
    }
  }

  SelectedSearchFoodItem _barcodeItemToSelection(BarcodeSelectionItem item) {
    final baselineQuantity = item.baselineQuantity <= 0
        ? 100.0
        : item.baselineQuantity;
    final scaleTo100 = 100 / baselineQuantity;
    final servingLabel = '${baselineQuantity.toStringAsFixed(0)} ${item.unit}';

    return SelectedSearchFoodItem(
      result: FoodSearchResult(
        id: 'barcode_${item.barcode}',
        name: item.foodName,
        subtitle: 'Scanned in manual add',
        caloriesPer100g: item.baseCalories * scaleTo100,
        proteinPer100g: item.baseProtein * scaleTo100,
        carbsPer100g: item.baseCarbs * scaleTo100,
        fatPer100g: item.baseFat * scaleTo100,
        defaultQuantity: item.selectedQuantity,
        quantityUnit: item.unit,
        source: 'Manual Scan',
        groupKey: 'barcode',
        servingOptions: [
          FoodServingOption(
            label: servingLabel,
            quantity: baselineQuantity,
            unit: item.unit,
          ),
          FoodServingOption(
            label: 'Selected amount',
            quantity: item.selectedQuantity,
            unit: item.unit,
          ),
        ],
        matchScore: 120,
      ),
      quantity: item.selectedQuantity,
      quantityUnit: item.unit,
      servingLabel: servingLabel,
      logSource: 'Barcode Scanned',
    );
  }

  void _removeFood(int index) {
    setState(() {
      _selectedFoods.removeAt(index);
      if (_selectedFoods.isEmpty) {
        _fabAnimationController.reverse();
      }
    });
  }

  void _updateFoodQuantity(int index, double newQuantity) {
    setState(() {
      final oldItem = _selectedFoods[index];
      _selectedFoods[index] = oldItem.copyWith(quantity: newQuantity);
    });
  }

  // ==========================================================================
  // SAVE OPERATIONS
  // ==========================================================================

  Future<void> _saveSelectedFoods() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Please sign in to save foods');
      return;
    }

    if (_selectedFoods.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final now = widget.selectedDate ?? DateTime.now();
      final dateStr = _formatDate(now);
      final timeStr = _formatTime(now);
      final weekdayStr = _getWeekday(now.weekday);
      final mealGroupId = _selectedFoods.length > 1
          ? FirebaseFirestore.instance.collection('tmp').doc().id
          : null;
      final mealSource = _resolveMealSource();
      final combinedFoodName = _joinFoodNames(
        _selectedFoods.map((item) => item.result.name).toList(),
      );

      final batch = FirebaseFirestore.instance.batch();
      final collection = userManualFoodsCollection(user.uid);

      for (final item in _selectedFoods) {
        final docRef = collection.doc();
        batch.set(docRef, {
          'foodName': item.result.name,
          'calories': item.calories,
          'carbs': item.carbs,
          'protein': item.protein,
          'fat': item.fat,
          'quantity': item.quantity,
          'unit': item.quantityUnit,
          'mealType': widget.mealType,
          'date': dateStr,
          'time': timeStr,
          'weekday': weekdayStr,
          'source': mealSource,
          'itemSource': item.logSource,
          'sourceDb': item.result.source,
          'servingLabel': item.servingLabel,
          'caloriesPer100g': item.result.caloriesPer100g,
          'carbsPer100g': item.result.carbsPer100g,
          'proteinPer100g': item.result.proteinPer100g,
          'fatPer100g': item.result.fatPer100g,
          'mealGroupId': mealGroupId,
          'combinedFoodName': mealGroupId != null ? combinedFoodName : null,
          'foodCount': _selectedFoods.length,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (!mounted) return;

      final savedRecentFoods = _selectedFoods
          .map((item) => FoodSearchResult(
                id:
                    'recent_${item.result.name.toLowerCase().replaceAll(RegExp(r'\\s+'), '_')}',
                name: item.result.name,
                subtitle: 'Recently logged',
                caloriesPer100g: item.result.caloriesPer100g,
                proteinPer100g: item.result.proteinPer100g,
                carbsPer100g: item.result.carbsPer100g,
                fatPer100g: item.result.fatPer100g,
                defaultQuantity: item.quantity,
                quantityUnit: item.quantityUnit,
                source: item.result.source,
                groupKey: 'recent',
                servingOptions: [
                  FoodServingOption(
                    label: item.servingLabel ?? 'Last used',
                    quantity: item.quantity,
                    unit: item.quantityUnit,
                  ),
                  FoodServingOption(label: '100 g', quantity: 100, unit: 'g'),
                ],
                matchScore: 100,
              ))
          .toList();

      setState(() {
        _searchController.clear();
        _searchResults = [];
        _isSearching = false;
        _isAfterMealExpanded = true;
        for (final recentFood in savedRecentFoods.reversed) {
          _recentFoods.removeWhere(
            (food) => _foodKey(food.name) == _foodKey(recentFood.name),
          );
          _recentFoods.insert(0, recentFood);
        }
        if (_recentFoods.length > 8) {
          _recentFoods = _recentFoods.take(8).toList();
        }
      });

      _searchController.clear();
      _searchFocusNode.unfocus();
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _selectedFoods.clear();
        _isAfterMealExpanded = true;
      });

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on FirebaseException catch (e) {
      _handleFirebaseError(e, 'Failed to save foods');
    } catch (e) {
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _resolveMealSource() {
    final hasManual = _selectedFoods.any(
      (item) => item.logSource == 'Manually Added',
    );
    final hasBarcode = _selectedFoods.any(
      (item) => item.logSource == 'Barcode Scanned',
    );

    if (hasManual && hasBarcode) return 'Mixed Entry';
    if (hasBarcode) return 'Barcode Scanned';
    return 'Manually Added';
  }

  // ==========================================================================
  // ERROR HANDLING
  // ==========================================================================

  void _handleFirebaseError(FirebaseException e, String fallbackMessage) {
    String message = fallbackMessage;
    
    switch (e.code) {
      case 'permission-denied':
        message = 'You don\'t have permission to perform this action.';
        break;
      case 'unavailable':
        message = 'Service temporarily unavailable. Please try again later.';
        break;
      case 'deadline-exceeded':
        message = 'Request timed out. Please check your connection.';
        break;
      case 'not-found':
        message = 'The requested data was not found.';
        break;
      case 'already-exists':
        message = 'This item already exists.';
        break;
      case 'resource-exhausted':
        message = 'Too many requests. Please wait a moment and try again.';
        break;
      default:
        message = '$fallbackMessage: ${e.message}';
    }
    
    _showError(message);
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // ==========================================================================
  // UTILITIES
  // ==========================================================================

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getWeekday(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  // ==========================================================================
  // BUILD METHODS
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF5F7F2),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Food',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            Text(
              widget.mealType,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _scanBarcodeAndAddToSelection,
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            tooltip: 'Scan barcode',
          ),
          if (_selectedFoods.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_selectedFoods.length} selected',
                  style: TextStyle(
                color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar Section
          _buildSearchSection(),
          
          // Main Content
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
      bottomNavigationBar:
          _selectedFoods.isNotEmpty ? _buildBottomSummary() : null,
    );
  }

  Widget _buildSearchSection() {
    return Container(
      color: const Color(0xFFF5F7F2),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search for a food...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                        _searchFocusNode.requestFocus();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          // Quick Filters (when not searching)
          if (!_isSearching) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickFilter('Recent', Icons.history, 'recent'),
                  _buildQuickFilter('My Foods', Icons.favorite_border, 'myFoods'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickFilter(String label, IconData icon, String tabValue) {
    final selected = _browseTab == tabValue;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() => _browseTab = tabValue);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.green : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.green : Colors.grey[300]!,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : Colors.grey[700],
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey[800],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_searchController.text.isEmpty) {
      return _buildDefaultState();
    }

    if (_searchResults.isEmpty) {
      return _buildEmptyState();
    }

    return _buildSearchResults();
  }

  Widget _buildLoadingState() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Update the search text and the page will refresh automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching for something else or check your spelling',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                _searchFocusNode.requestFocus();
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear Search'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultState() {
    if (_isSavedFoodsLoading) {
      return _buildSavedFoodsLoadingState();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_browseTab == 'recent') ...[
          _buildSectionHeader('Recent Manual Foods'),
          const SizedBox(height: 8),
          if (_recentFoods.isEmpty)
            _buildInlineEmpty('No manual foods yet. Add foods manually to see them here.')
          else
            ..._recentFoods.map((food) => _buildFoodListTile(food, isRecent: true)),
        ] else ...[
          _buildSectionHeader('My Foods (Favorites)'),
          const SizedBox(height: 8),
          if (_myFoods.isEmpty)
            _buildInlineEmpty('Tap the heart on a food to save it to My Foods.')
          else
            ..._myFoods.map((food) => _buildFoodListTile(food)),
        ],
      ],
    );
  }

  Widget _buildSavedFoodsLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(
          _browseTab == 'recent' ? 'Recent Manual Foods' : 'My Foods (Favorites)',
        ),
        const SizedBox(height: 8),
        Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Column(
            children: List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 14,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 12,
                              width: 140,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: List.generate(
                                3,
                                (_) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Container(
                                    height: 20,
                                    width: 52,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineEmpty(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[700], fontSize: 13),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.black54,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return _buildFoodListTile(item);
      },
    );
  }

  Widget _buildFoodListTile(FoodSearchResult result, {bool isRecent = false}) {
    final isSelected = _selectedFoods.any((item) => item.result.name == result.name);
    
    return InkWell(
      onTap: () => _showFoodDetail(result),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.withOpacity(0.05) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            // Food Icon/Thumbnail
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.restaurant, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            
            // Food Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildMacroPill(
                        '${result.caloriesPer100g.toStringAsFixed(0)} cal',
                        Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      _buildMacroPill(
                        'P: ${result.proteinPer100g.toStringAsFixed(1)}g',
                        Colors.red,
                      ),
                      const SizedBox(width: 6),
                      _buildMacroPill(
                        'C: ${result.carbsPer100g.toStringAsFixed(1)}g',
                        Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    _favoriteFoodKeys.contains(_foodKey(result.name))
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: Colors.green,
                  ),
                  onPressed: () => _toggleFavorite(result),
                  tooltip: 'Save to My Foods',
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 16),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBottomSummary() {
    final mealCalories = _selectedFoods.fold<double>(0, (sum, item) => sum + item.calories);
    final mealCarbs = _selectedFoods.fold<double>(0, (sum, item) => sum + item.carbs);
    final mealProtein = _selectedFoods.fold<double>(0, (sum, item) => sum + item.protein);
    final mealFat = _selectedFoods.fold<double>(0, (sum, item) => sum + item.fat);
    final maxExpandedSummaryHeight = MediaQuery.of(context).size.height * 0.42;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                if (_isAfterMealExpanded)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () {
                        setState(() {
                          _isAfterMealExpanded = false;
                        });
                      },
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.green[700],
                      ),
                      tooltip: 'Collapse summary',
                    ),
                  )
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() {
                        _isAfterMealExpanded = true;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F8F1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.withOpacity(0.18)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insights_outlined, color: Colors.green),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'After This Meal',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${mealCalories.round()} cal',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.green[700],
                          ),
                        ],
                      ),
                    ),
                  ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: _isAfterMealExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxExpandedSummaryHeight),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          AfterMealSummary(
                            dailyGoal: _dailyGoal,
                            carbsTarget: _carbsTarget,
                            proteinTarget: _proteinTarget,
                            fatTarget: _fatTarget,
                            todayCaloriesConsumed: _todayCalories,
                            todayCarbsConsumed: _todayCarbs,
                            todayProteinConsumed: _todayProtein,
                            todayFatConsumed: _todayFat,
                            mealCalories: mealCalories.round(),
                            mealCarbs: mealCarbs.round(),
                            mealProtein: mealProtein.round(),
                            mealFat: mealFat.round(),
                            margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FBF7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.12),
                              ),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _selectedFoods.length,
                              itemBuilder: (context, index) {
                                final item = _selectedFoods[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 2,
                                  ),
                                  title: Text(
                                    item.result.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${item.quantity.toStringAsFixed(0)} ${item.quantityUnit} • ${item.calories.round()} cal',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        onPressed: () => _showEditDialog(index),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () => _removeFood(index),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveSelectedFoods,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _isSaving
                          ? 'Saving...'
                          : 'Log ${_selectedFoods.length} Item${_selectedFoods.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemiCircleSummary({
    required double mealCalories,
    required double mealCarbs,
    required double mealProtein,
    required double mealFat,
    required bool compact,
  }) {
    final remaining = _dailyGoal - _todayCalories - mealCalories.round();
    final carbsLeft = _carbsTarget - (_todayCarbs + mealCarbs.round());
    final proteinLeft = _proteinTarget - (_todayProtein + mealProtein.round());
    final fatLeft = _fatTarget - (_todayFat + mealFat.round());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                color: remaining >= 0 ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.05),
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meal Summary',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${mealCalories.round()}',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'calories added',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: remaining >= 0 ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          remaining >= 0 ? '$remaining left' : '${remaining.abs()} over',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
             
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 14,
                children: [
                  _miniSemiCircle(
                    label: 'Carbs',
                    current: _todayCarbs + mealCarbs.round(),
                    target: _carbsTarget,
                    left: carbsLeft,
                    color: Colors.orange,
                    unit: 'g',
                    size: compact ? 78 : 96,
                  ),
                  _miniSemiCircle(
                    label: 'Protein',
                    current: _todayProtein + mealProtein.round(),
                    target: _proteinTarget,
                    left: proteinLeft,
                    color: Colors.red,
                    unit: 'g',
                    size: compact ? 78 : 96,
                  ),
                  _miniSemiCircle(
                    label: 'Fat',
                    current: _todayFat + mealFat.round(),
                    target: _fatTarget,
                    left: fatLeft,
                    color: Colors.blue,
                    unit: 'g',
                    size: compact ? 78 : 96,
                  ),
                ],
              ),
            ),

            Container(
              constraints: BoxConstraints(maxHeight: compact ? 120 : 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _selectedFoods.length,
                itemBuilder: (context, index) {
                  final item = _selectedFoods[index];
                  return ListTile(
                    dense: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    title: Text(
                      item.result.name,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.quantity.toStringAsFixed(0)} ${item.quantityUnit} • ${item.calories.round()} cal',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showEditDialog(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _removeFood(index),
                        ),
                      ],
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

  String _joinFoodNames(List<String> names) {
    final filtered = names.map((name) => name.trim()).where((name) => name.isNotEmpty).toList();
    if (filtered.isEmpty) return 'Manual meal';
    if (filtered.length == 1) return filtered.first;
    if (filtered.length == 2) return '${filtered[0]} and ${filtered[1]}';
    return '${filtered.sublist(0, filtered.length - 1).join(', ')} and ${filtered.last}';
  }

  Widget _miniSemiCircle({
    required String label,
    required int current,
    required int target,
    required int left,
    required Color color,
    required String unit,
    required double size,
  }) {
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final strokeWidth = size * 0.09;
    return SizedBox(
      width: size + 8,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size,
            height: size * 0.65,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size(size, size * 0.65),
                  painter: _SemiCircleProgressPainter(
                    progress: progress,
                    backgroundColor: Colors.grey[200]!,
                    progressColor: left >= 0 ? color : Colors.red,
                    strokeWidth: strokeWidth,
                  ),
                ),
                Positioned(
                  top: size * 0.2,
                  child: Column(
                    children: [
                      Text(
                        left >= 0 ? '$left' : '${left.abs()}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: left >= 0 ? Colors.black87 : Colors.red,
                        ),
                      ),
                      Text(
                        left >= 0 ? '$unit left' : '$unit over',
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(int index) async {
    final item = _selectedFoods[index];
    final controller = TextEditingController(
      text: item.quantity.toStringAsFixed(0),
    );
    double draftQuantity = item.quantity;

    final newQuantity = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void syncQuantity(double value) {
              setModalState(() {
                draftQuantity = value < 1 ? 1 : value;
                controller.text = draftQuantity.toStringAsFixed(
                  draftQuantity % 1 == 0 ? 0 : 1,
                );
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      item.result.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Adjust quantity before saving this meal',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F9F3),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          _quantityStepperButton(
                            icon: Icons.remove,
                            onTap: () => syncQuantity(draftQuantity - 10),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              autofocus: true,
                              textAlign: TextAlign.center,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                suffixText: item.quantityUnit,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (value) {
                                final parsed = double.tryParse(value);
                                if (parsed != null && parsed > 0) {
                                  setModalState(() {
                                    draftQuantity = parsed;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          _quantityStepperButton(
                            icon: Icons.add,
                            onTap: () => syncQuantity(draftQuantity + 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _quickQuantityChip(
                            label: 'Half',
                            onTap: () => syncQuantity((item.quantity / 2).clamp(1, double.infinity)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _quickQuantityChip(
                            label: 'Original',
                            onTap: () => syncQuantity(item.quantity),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _quickQuantityChip(
                            label: 'Double',
                            onTap: () => syncQuantity(item.quantity * 2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final value = double.tryParse(controller.text);
                              Navigator.pop(
                                context,
                                value != null && value > 0 ? value : draftQuantity,
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Update'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (newQuantity != null && newQuantity > 0) {
      _updateFoodQuantity(index, newQuantity);
    }
  }

  Widget _quantityStepperButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.green.withOpacity(0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 46,
          height: 54,
          child: Icon(icon, color: Colors.green[700]),
        ),
      ),
    );
  }

  Widget _quickQuantityChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8F1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.12)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.green[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SemiCircleProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _SemiCircleProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - strokeWidth / 2;
    const startAngle = math.pi;
    const totalSweep = math.pi;

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

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      backgroundPaint,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        totalSweep * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SemiCircleProgressPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        backgroundColor != oldDelegate.backgroundColor ||
        progressColor != oldDelegate.progressColor ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}

// ============================================================================
// FOOD DETAIL PAGE - ENHANCED VERSION
// ============================================================================

class FoodDetailPage extends StatefulWidget {
  final String mealType;
  final FoodSearchResult result;
  final bool isQuickAdd;

  const FoodDetailPage({
    super.key,
    required this.mealType,
    required this.result,
    this.isQuickAdd = false,
  });

  @override
  State<FoodDetailPage> createState() => _FoodDetailPageState();
}

class _FoodDetailPageState extends State<FoodDetailPage> {
  late double _quantity;
  late String _quantityUnit;
  FoodServingOption? _selectedServing;
  int _numberOfServings = 1;
  
  final TextEditingController _quantityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeQuantity();
  }

  void _initializeQuantity() {
    if (widget.result.servingOptions.isNotEmpty) {
      _selectedServing = widget.result.servingOptions.first;
      _quantity = _selectedServing!.quantity;
      _quantityUnit = _selectedServing!.unit;
    } else {
      _quantity = widget.result.defaultQuantity > 0 ? widget.result.defaultQuantity : 100;
      _quantityUnit = widget.result.quantityUnit;
    }
  }

  double get _factor => _quantity / 100.0;
  double get _calories => widget.result.caloriesPer100g * _factor * _numberOfServings;
  double get _carbs => widget.result.carbsPer100g * _factor * _numberOfServings;
  double get _protein => widget.result.proteinPer100g * _factor * _numberOfServings;
  double get _fat => widget.result.fatPer100g * _factor * _numberOfServings;

  void _addFood() {
    final item = SelectedSearchFoodItem(
      result: widget.result,
      quantity: _quantity * _numberOfServings,
      quantityUnit: _quantityUnit,
      servingLabel: _selectedServing?.label,
    );
    
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F2),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('Food Details'),
        actions: [
          TextButton(
            onPressed: _addFood,
            child: const Text(
              'ADD',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Food Header Card
            _buildFoodHeader(),
            
            // Serving Size Selector
            _buildServingSection(),
            
            // Number of Servings
            _buildServingsCountSection(),
            
            // Nutrition Facts
            _buildNutritionSection(),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildFoodHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.restaurant, size: 40, color: Colors.green),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.result.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.result.subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.result.source,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServingSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Serving Size',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          
          if (widget.result.servingOptions.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.result.servingOptions.map((option) {
                final isSelected = _selectedServing?.label == option.label;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedServing = option;
                        _quantity = option.quantity;
                        _quantityUnit = option.unit;
                      });
                    }
                  },
                  selectedColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: isSelected ? Theme.of(context).primaryColor : Colors.black87,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          
          // Custom Quantity Input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityController..text = _quantity.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: _quantityUnit,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    final newValue = double.tryParse(value);
                    if (newValue != null && newValue > 0) {
                      setState(() {
                        _quantity = newValue;
                        _selectedServing = null;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  setState(() {
                    _quantity = math.max(1, _quantity - 10);
                    _selectedServing = null;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  setState(() {
                    _quantity += 10;
                    _selectedServing = null;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServingsCountSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Number of Servings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle),
                onPressed: _numberOfServings > 1
                    ? () => setState(() => _numberOfServings--)
                    : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_numberOfServings',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: () => setState(() => _numberOfServings++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nutrition Facts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Per $_quantity $_quantityUnit',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildNutritionRow('Calories', _calories, 'kcal', Colors.orange, isBold: true),
          const Divider(height: 32),
          _buildNutritionRow('Total Carbs', _carbs, 'g', Colors.blue),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8),
            child: Text('Includes sugars and fiber', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const Divider(height: 32),
          _buildNutritionRow('Protein', _protein, 'g', Colors.red),
          const Divider(height: 32),
          _buildNutritionRow('Total Fat', _fat, 'g', Colors.amber),
        ],
      ),
    );
  }

  Widget _buildNutritionRow(String label, double value, String unit, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          '${value.toStringAsFixed(1)} $unit',
          style: TextStyle(
            fontSize: 16,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _addFood,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add),
                const SizedBox(width: 8),
                Text(
                  'Add ${_calories.round()} cal',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
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
// CUSTOM PAINTERS & HELPERS
// ============================================================================

class MacroProgressBar extends StatelessWidget {
  final String label;
  final int current;
  final int target;
  final Color color;

  const MacroProgressBar({
    super.key,
    required this.label,
    required this.current,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final percentage = (progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$current / $target g',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$percentage% of daily goal',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}
