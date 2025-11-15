import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:nutriwise/services/auth_services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

// Color mapping for meal types
const Map<String, Color> mealTypeColors = {
  'Breakfast': Colors.orange,
  'Lunch': Colors.teal,
  'Dinner': Colors.purple,
  'Snack': Colors.blue,
};

// Main Records Page
class RecordsPage extends StatefulWidget {
  const RecordsPage({Key? key}) : super(key: key);

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  int _selectedTab = 0;

  // Track user's account creation date
  DateTime? _accountCreated;
  // Map: day -> calories
  Map<int, int> _calorieData = {};
  // Map: mealType -> count for the month
  Map<String, int> _mealTypeCounts = {
    'Breakfast': 0,
    'Lunch': 0,
    'Dinner': 0,
    'Snack': 0,
  };
  // New: Map day -> Set of meal types
  Map<int, Set<String>> _dayMealTypes = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTab = _tabController.index;
      });
    });
    _fetchAccountCreatedAndMeals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAccountCreatedAndMeals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch account creation date
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final createdAt = userDoc.data()?['createdAt'];
    if (createdAt != null && createdAt is Timestamp) {
      setState(() {
        _accountCreated = createdAt.toDate();
      });
    } else {
      setState(() {
        _accountCreated = DateTime.now();
      });
    }

    await _fetchMealsForMonth();
  }

  Future<void> _fetchMealsForMonth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    // Reset data
    Map<int, int> calorieData = {};
    Map<String, int> mealTypeCounts = {
      'Breakfast': 0,
      'Lunch': 0,
      'Dinner': 0,
      'Snack': 0,
    };
    Map<int, Set<String>> dayMealTypes = {};

    // --- Fetch from barcodes ---
    final barcodeSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThan: Timestamp.fromDate(endDate))
        .get();

    for (var doc in barcodeSnapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final calories = (data['calories'] ?? 0).round();
      String mealType = (data['mealType'] ?? 'Meal').toString().trim();

      if (mealType == 'Breakfast Snack' ||
          mealType == 'Afternoon Snack' ||
          mealType == 'Midnight Snack') {
        mealType = 'Snack';
      }

      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        final day = date.day;
        calorieData[day] = ((calorieData[day] ?? 0) + calories).toInt();
        if (mealTypeCounts.containsKey(mealType)) {
          mealTypeCounts[mealType] = mealTypeCounts[mealType]! + 1;
        }
        dayMealTypes.putIfAbsent(day, () => <String>{});
        dayMealTypes[day]!.add(mealType);
      }
    }

    // --- Fetch from meals ---
    final mealsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThan: Timestamp.fromDate(endDate))
        .get();

    for (var doc in mealsSnapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final calories = (data['totalCalories'] ?? 0).round();
      String mealType = (data['mealType'] ?? 'Meal').toString().trim();

      if (mealType == 'Breakfast Snack' ||
          mealType == 'Afternoon Snack' ||
          mealType == 'Midnight Snack') {
        mealType = 'Snack';
      }

      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        final day = date.day;
        calorieData[day] = ((calorieData[day] ?? 0) + calories).toInt();
        if (mealTypeCounts.containsKey(mealType)) {
          mealTypeCounts[mealType] = mealTypeCounts[mealType]! + 1;
        }
        dayMealTypes.putIfAbsent(day, () => <String>{});
        dayMealTypes[day]!.add(mealType);
      }
    }

    setState(() {
      _calorieData = calorieData;
      _mealTypeCounts = mealTypeCounts;
      _dayMealTypes = dayMealTypes;
    });
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _fetchMealsForMonth();
  }

  void _nextMonth() {
    final now = DateTime.now();
    final nextMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (nextMonth.isBefore(DateTime(now.year, now.month + 1))) {
      setState(() {
        _selectedMonth = nextMonth;
      });
      _fetchMealsForMonth();
    }
  }

  bool _isFutureMonth() {
    final now = DateTime.now();
    return _selectedMonth.year > now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month > now.month);
  }

  bool _isBeforeAccountCreated() {
    if (_accountCreated == null) return false;
    return _selectedMonth.year < _accountCreated!.year ||
        (_selectedMonth.year == _accountCreated!.year &&
            _selectedMonth.month < _accountCreated!.month);
  }

  // New method to show download dialog
  void _showDownloadDialog() {
    showDialog(context: context, builder: (ctx) => DownloadReportDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Report',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: _showDownloadDialog,
            tooltip: 'Download Report',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.green, width: 1)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.green,
              indicatorWeight: 3,
              labelColor: Colors.green,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              tabs: const [
                Tab(text: 'RECORD'),
                Tab(text: 'NUTRIENT'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildRecordView(), const NutrientsPage()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordView() {
    final hasData =
        _calorieData.isNotEmpty || _mealTypeCounts.values.any((v) => v > 0);

    return Column(
      children: [
        const SizedBox(height: 30),
        // Month Selector
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _isBeforeAccountCreated() ? null : _previousMonth,
              color: _isBeforeAccountCreated() ? Colors.grey : Colors.black,
            ),
            const SizedBox(width: 20),
            Text(
              '${_selectedMonth.year}.${_selectedMonth.month.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: Icon(
                Icons.chevron_right,
                color: _isFutureMonth() ? Colors.grey : Colors.black,
              ),
              onPressed: _isFutureMonth() ? null : _nextMonth,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Show counters only if there is data
        if (hasData)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMealCounter(
                'Breakfast',
                _mealTypeCounts['Breakfast'] ?? 0,
                Colors.orange,
              ),
              _buildMealCounter(
                'Lunch',
                _mealTypeCounts['Lunch'] ?? 0,
                Colors.teal,
              ),
              _buildMealCounter(
                'Dinner',
                _mealTypeCounts['Dinner'] ?? 0,
                Colors.purple,
              ),
              _buildMealCounter(
                'Snack',
                _mealTypeCounts['Snack'] ?? 0,
                Colors.blue,
              ),
            ],
          ),
        if (hasData) const SizedBox(height: 30),
        // Show note if no data for this month
        if (!hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              "No records for this month",
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ),
        // Calendar (always show, even if no data)
        Expanded(
          child: _buildCalendarWithCalories(hasData ? _calorieData : {}),
        ),
      ],
    );
  }

  Widget _buildMealCounter(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildCalendarWithCalories(Map<int, int> calorieData) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    );
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday

    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Weekday headers
          Row(
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((
              day,
            ) {
              final isSunday = day == 'Sun';
              final isSaturday = day == 'Sat';
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      color: isSunday
                          ? Colors.red
                          : (isSaturday ? Colors.green : Colors.green[800]),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Calendar Grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.8,
              ),
              itemCount: 42, // 6 weeks max
              itemBuilder: (context, index) {
                final dayNumber = index - firstWeekday + 1;
                final isCurrentMonth =
                    dayNumber > 0 && dayNumber <= daysInMonth;
                final date = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month,
                  dayNumber,
                );
                final isFuture = date.isAfter(now);
                final isToday =
                    date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
                final isSunday = index % 7 == 0;
                final isSaturday = index % 7 == 6;

                if (!isCurrentMonth) {
                  return Container();
                }

                // Get meal types for this day
                final mealTypes = _dayMealTypes[dayNumber]?.toList() ?? [];

                return Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: isToday
                        ? Border.all(color: Colors.blue, width: 2)
                        : null,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Text(
                          dayNumber.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: isFuture
                                ? Colors.grey[300]
                                : (isSunday
                                      ? Colors.red
                                      : (isSaturday
                                            ? Colors.green
                                            : Colors.black)),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Show colored dots for each meal type (max 4 per day)
                      if (mealTypes.isNotEmpty && !isFuture)
                        Positioned(
                          bottom: 4,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              mealTypes.length > 4 ? 4 : mealTypes.length,
                              (i) => Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      mealTypeColors[mealTypes[i]] ??
                                      Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (isFuture)
                        Positioned.fill(
                          child: Container(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Download Report Dialog
class DownloadReportDialog extends StatefulWidget {
  const DownloadReportDialog({Key? key}) : super(key: key);

  @override
  State<DownloadReportDialog> createState() => _DownloadReportDialogState();
}

class _DownloadReportDialogState extends State<DownloadReportDialog> {
  String _selectedPeriodType = 'Month'; // Month, Week, Custom
  int _selectedMonths = 1;
  int _selectedWeeks = 1;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Download Report',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Select Period Type:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // Period Type Selection
            Row(
              children: [
                Expanded(child: _buildPeriodTypeChip('Month')),
                const SizedBox(width: 8),
                Expanded(child: _buildPeriodTypeChip('Week')),
                const SizedBox(width: 8),
                Expanded(child: _buildPeriodTypeChip('Custom')),
              ],
            ),
            const SizedBox(height: 24),
            // Period Configuration based on type
            if (_selectedPeriodType == 'Month') _buildMonthSelector(),
            if (_selectedPeriodType == 'Week') _buildWeekSelector(),
            if (_selectedPeriodType == 'Custom') _buildCustomDatePicker(),
            const SizedBox(height: 32),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _previewReport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Preview'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodTypeChip(String type) {
    final isSelected = _selectedPeriodType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPeriodType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            type,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Number of Months:',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _selectedMonths.toDouble(),
                min: 1,
                max: 12,
                divisions: 11,
                activeColor: Colors.green,
                label:
                    '$_selectedMonths month${_selectedMonths > 1 ? 's' : ''}',
                onChanged: (value) {
                  setState(() {
                    _selectedMonths = value.toInt();
                  });
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_selectedMonths',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'From ${_getMonthRangeLabel()}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildWeekSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Number of Weeks:',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _selectedWeeks.toDouble(),
                min: 1,
                max: 12,
                divisions: 11,
                activeColor: Colors.green,
                label: '$_selectedWeeks week${_selectedWeeks > 1 ? 's' : ''}',
                onChanged: (value) {
                  setState(() {
                    _selectedWeeks = value.toInt();
                  });
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_selectedWeeks',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'From ${_getWeekRangeLabel()}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildCustomDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Custom Date Range:',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDateButton(
                label: 'Start Date',
                date: _customStartDate,
                onTap: () => _pickCustomDate(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateButton(
                label: 'End Date',
                date: _customEndDate,
                onTap: () => _pickCustomDate(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              date != null ? DateFormat('MMM dd, yyyy').format(date) : 'Select',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: date != null ? Colors.black87 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthRangeLabel() {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month - _selectedMonths + 1, 1);
    final endDate = DateTime(now.year, now.month, now.day);
    return '${DateFormat('MMM yyyy').format(startDate)} to ${DateFormat('MMM yyyy').format(endDate)}';
  }

  String _getWeekRangeLabel() {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: (_selectedWeeks * 7) - 1));
    return '${DateFormat('MMM dd, yyyy').format(startDate)} to ${DateFormat('MMM dd, yyyy').format(now)}';
  }

  Future<void> _pickCustomDate(bool isStartDate) async {
    final now = DateTime.now();
    final initialDate = isStartDate
        ? (_customStartDate ?? now.subtract(const Duration(days: 30)))
        : (_customEndDate ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _customStartDate = picked;
          // If end date is before start date, reset it
          if (_customEndDate != null && _customEndDate!.isBefore(picked)) {
            _customEndDate = null;
          }
        } else {
          // Only set end date if start date is selected
          if (_customStartDate != null) {
            _customEndDate = picked;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select start date first'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      });
    }
  }

  void _previewReport() {
    // Validate custom date range
    if (_selectedPeriodType == 'Custom') {
      if (_customStartDate == null || _customEndDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select both start and end dates'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // Calculate date range based on selected period
    DateTime startDate;
    DateTime endDate = DateTime.now();

    if (_selectedPeriodType == 'Month') {
      startDate = DateTime(
        endDate.year,
        endDate.month - _selectedMonths + 1,
        1,
      );
    } else if (_selectedPeriodType == 'Week') {
      startDate = endDate.subtract(Duration(days: (_selectedWeeks * 7) - 1));
    } else {
      startDate = _customStartDate!;
      endDate = _customEndDate!;
    }

    Navigator.of(context).pop();

    // Navigate to preview page
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportPreviewPage(
          startDate: startDate,
          endDate: endDate,
          periodType: _selectedPeriodType,
        ),
      ),
    );
  }
}

// Report Preview Page
class ReportPreviewPage extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final String periodType;

  const ReportPreviewPage({
    Key? key,
    required this.startDate,
    required this.endDate,
    required this.periodType,
  }) : super(key: key);

  @override
  State<ReportPreviewPage> createState() => _ReportPreviewPageState();
}

class _ReportPreviewPageState extends State<ReportPreviewPage> {
  bool _loading = true;
  Map<String, dynamic> _reportData = {};

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    try {
      // Fetch user profile
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};

      // --- Fetch meals from barcodes ---
      final barcodeSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('barcodes')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(widget.startDate),
          )
          .where(
            'createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(widget.endDate),
          )
          .get();

      // --- Fetch meals from meals ---
      final mealsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(widget.startDate),
          )
          .where(
            'createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(widget.endDate),
          )
          .get();

      // --- Fetch weight entries (unchanged) ---
      final weightSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('weight_entries')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(widget.startDate),
          )
          .where(
            'timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(widget.endDate),
          )
          .orderBy('timestamp', descending: false)
          .get();

      // --- Merge barcode and meals data ---
      List<Map<String, dynamic>> allMeals = [];
      for (var doc in barcodeSnapshot.docs) {
        final data = doc.data();
        allMeals.add({
          'name': data['foodName'] ?? 'Unknown',
          'mealType': (data['mealType'] ?? 'Meal').toString().trim(),
          'calories': (data['calories'] ?? 0).toDouble(),
          'protein': (data['protein'] ?? 0).toDouble(),
          'carbs': (data['carbohydrate'] ?? data['carbs'] ?? 0).toDouble(),
          'fat': (data['fat'] ?? 0).toDouble(),
          'date': data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          'imageUrl': null, // No image for barcode logs
        });
      }
      for (var doc in mealsSnapshot.docs) {
        final data = doc.data();
        // Show all food names comma separated
        String foodNames = '';
        if (data['foodItems'] is List &&
            (data['foodItems'] as List).isNotEmpty) {
          foodNames = (data['foodItems'] as List)
              .map((f) => (f['foodName'] ?? '') as String)
              .where((n) => n.isNotEmpty)
              .join(', ');
        } else {
          foodNames = (data['mealType'] ?? 'Meal').toString();
        }
        allMeals.add({
          'name': foodNames,
          'mealType': (data['mealType'] ?? 'Meal').toString().trim(),
          'calories': (data['totalCalories'] ?? 0).toDouble(),
          'protein': (data['totalProtein'] ?? 0).toDouble(),
          'carbs': (data['totalCarbs'] ?? 0).toDouble(),
          'fat': (data['totalFat'] ?? 0).toDouble(),
          'date': data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          'imageUrl': data['originalImageUrl'] as String?,
        });
      }

      // --- Process merged meals ---
      Map<String, dynamic> reportData = {
        'userName': userData['name'] ?? 'User',
        'userEmail': user.email ?? '',
        'targetCalories': userData['calories']?.round() ?? 0,
        'totalMeals': allMeals.length,
        'totalCalories': 0.0,
        'totalProtein': 0.0,
        'totalCarbs': 0.0,
        'totalFat': 0.0,
        'mealTypeCounts': {'Breakfast': 0, 'Lunch': 0, 'Dinner': 0, 'Snack': 0},
        'dailyCalories': <String, double>{},
        'weightEntries': <Map<String, dynamic>>[],
        'mealsDetails': <Map<String, dynamic>>[],
      };

      for (var meal in allMeals) {
        reportData['totalCalories'] += (meal['calories'] ?? 0).toDouble();
        reportData['totalProtein'] += (meal['protein'] ?? 0).toDouble();
        reportData['totalCarbs'] += (meal['carbs'] ?? 0).toDouble();
        reportData['totalFat'] += (meal['fat'] ?? 0).toDouble();

        String mealType = (meal['mealType'] ?? 'Meal').toString().trim();
        if (mealType == 'Breakfast Snack' ||
            mealType == 'Afternoon Snack' ||
            mealType == 'Midnight Snack') {
          mealType = 'Snack';
        }

        if (reportData['mealTypeCounts'].containsKey(mealType)) {
          reportData['mealTypeCounts'][mealType]++;
        }

        // Track daily calories
        if (meal['date'] is DateTime) {
          final dateKey = DateFormat(
            'yyyy-MM-dd',
          ).format(meal['date'] as DateTime);
          reportData['dailyCalories'][dateKey] =
              (reportData['dailyCalories'][dateKey] ?? 0.0) +
              (meal['calories'] ?? 0).toDouble();
        }

        // Store meal details
        reportData['mealsDetails'].add(meal);
      }

      // --- Process weight entries (unchanged) ---
      for (var doc in weightSnapshot.docs) {
        final data = doc.data();
        reportData['weightEntries'].add({
          'weight': (data['weight'] ?? 0).toDouble(),
          'isMetric': data['isMetric'] == true,
          'timestamp': data['timestamp'] is Timestamp
              ? (data['timestamp'] as Timestamp).toDate()
              : DateTime.now(),
        });
      }

      // Calculate averages
      final daysDiff = widget.endDate.difference(widget.startDate).inDays + 1;
      reportData['avgDailyCalories'] = reportData['totalCalories'] / daysDiff;
      reportData['avgDailyProtein'] = reportData['totalProtein'] / daysDiff;
      reportData['avgDailyCarbs'] = reportData['totalCarbs'] / daysDiff;
      reportData['avgDailyFat'] = reportData['totalFat'] / daysDiff;

      setState(() {
        _reportData = reportData;
        _loading = false;
      });
    } catch (e) {
      print('Error fetching report data: $e');
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Report Preview',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              onPressed: _generatePDF,
              tooltip: 'Download PDF',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _buildPreviewContent(),
    );
  }

  Widget _buildPreviewContent() {
    if (_reportData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'No data available for the selected period',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(),
          const SizedBox(height: 24),
          _buildSummarySection(),
          const SizedBox(height: 24),
          _buildMacronutrientsSection(),
          const SizedBox(height: 24),
          _buildMealDistributionSection(),
          const SizedBox(height: 24),
          _buildWeightTrackingSection(),
          const SizedBox(height: 24),
          _buildDailyCaloriesSection(),
          const SizedBox(height: 24),
          _buildTopMealsSection(),
          const SizedBox(height: 32),
          // Download Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generatePDF,
              icon: const Icon(Icons.download),
              label: const Text('Download PDF Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.assessment, color: Colors.green, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nutrition Report',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _reportData['userName'] ?? 'User',
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Period: ${DateFormat('MMM dd, yyyy').format(widget.startDate)} - ${DateFormat('MMM dd, yyyy').format(widget.endDate)}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  '${widget.endDate.difference(widget.startDate).inDays + 1} days',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.restaurant, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Total Meals: ${_reportData['totalMeals']}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Total Calories',
                    '${_reportData['totalCalories'].toStringAsFixed(0)}',
                    'kcal',
                    Colors.red,
                    Icons.local_fire_department,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Avg Daily',
                    '${_reportData['avgDailyCalories'].toStringAsFixed(0)}',
                    'kcal/day',
                    Colors.orange,
                    Icons.trending_up,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_reportData['targetCalories'] > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Daily Target: ${_reportData['targetCalories']} kcal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${((_reportData['avgDailyCalories'] / _reportData['targetCalories']) * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
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

  Widget _buildSummaryCard(
    String title,
    String value,
    String unit,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(unit, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildMacronutrientsSection() {
    final totalProtein = _reportData['totalProtein'];
    final totalCarbs = _reportData['totalCarbs'];
    final totalFat = _reportData['totalFat'];
    final totalMacros = totalProtein + totalCarbs + totalFat;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Macronutrients Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: SizedBox(
                    height: 150,
                    child: totalMacros > 0
                        ? PieChart(
                            PieChartData(
                              sections: [
                                PieChartSectionData(
                                  color: Colors.green,
                                  value: totalCarbs,
                                  title:
                                      '${((totalCarbs / totalMacros) * 100).toStringAsFixed(0)}%',
                                  radius: 50,
                                  titleStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                PieChartSectionData(
                                  color: Colors.blue,
                                  value: totalProtein,
                                  title:
                                      '${((totalProtein / totalMacros) * 100).toStringAsFixed(0)}%',
                                  radius: 50,
                                  titleStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                PieChartSectionData(
                                  color: Colors.orange,
                                  value: totalFat,
                                  title:
                                      '${((totalFat / totalMacros) * 100).toStringAsFixed(0)}%',
                                  radius: 50,
                                  titleStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                              centerSpaceRadius: 30,
                              sectionsSpace: 2,
                            ),
                          )
                        : Center(
                            child: Text(
                              'No data',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _buildMacroRow(
                        'Carbs',
                        totalCarbs,
                        _reportData['avgDailyCarbs'],
                        Colors.green,
                      ),
                      const SizedBox(height: 12),
                      _buildMacroRow(
                        'Protein',
                        totalProtein,
                        _reportData['avgDailyProtein'],
                        Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      _buildMacroRow(
                        'Fat',
                        totalFat,
                        _reportData['avgDailyFat'],
                        Colors.orange,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroRow(String label, double total, double avg, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Total: ${total.toStringAsFixed(1)}g',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        Text(
          'Avg: ${avg.toStringAsFixed(1)}g/day',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildMealDistributionSection() {
    final mealCounts = _reportData['mealTypeCounts'] as Map<String, dynamic>;
    final totalMeals = mealCounts.values.fold(
      0,
      (sum, count) => sum + (count as int),
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meal Distribution',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 16),
            if (totalMeals > 0)
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 150,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              color: Colors.orange,
                              value: (mealCounts['Breakfast'] ?? 0).toDouble(),
                              title: '${mealCounts['Breakfast']}',
                              radius: 50,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              color: Colors.teal,
                              value: (mealCounts['Lunch'] ?? 0).toDouble(),
                              title: '${mealCounts['Lunch']}',
                              radius: 50,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              color: Colors.purple,
                              value: (mealCounts['Dinner'] ?? 0).toDouble(),
                              title: '${mealCounts['Dinner']}',
                              radius: 50,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              color: Colors.blue,
                              value: (mealCounts['Snack'] ?? 0).toDouble(),
                              title: '${mealCounts['Snack']}',
                              radius: 50,
                              titleStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                          centerSpaceRadius: 30,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMealTypeRow(
                          'Breakfast',
                          mealCounts['Breakfast'] ?? 0,
                          totalMeals,
                          Colors.orange,
                        ),
                        const SizedBox(height: 8),
                        _buildMealTypeRow(
                          'Lunch',
                          mealCounts['Lunch'] ?? 0,
                          totalMeals,
                          Colors.teal,
                        ),
                        const SizedBox(height: 8),
                        _buildMealTypeRow(
                          'Dinner',
                          mealCounts['Dinner'] ?? 0,
                          totalMeals,
                          Colors.purple,
                        ),
                        const SizedBox(height: 8),
                        _buildMealTypeRow(
                          'Snack',
                          mealCounts['Snack'] ?? 0,
                          totalMeals,
                          Colors.blue,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No meal data',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealTypeRow(String label, int count, int total, Color color) {
    final percentage = total > 0
        ? (count / total * 100).toStringAsFixed(0)
        : '0';
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          '$count ($percentage%)',
          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildWeightTrackingSection() {
    final weightEntries =
        _reportData['weightEntries'] as List<Map<String, dynamic>>;

    if (weightEntries.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weight Tracking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'No weight data for this period',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final firstWeight = weightEntries.first['weight'];
    final lastWeight = weightEntries.last['weight'];
    final weightChange = lastWeight - firstWeight;
    final isMetric = weightEntries.first['isMetric'] == true;
    final unit = isMetric ? 'kg' : 'lbs';

    // Prepare chart data
    List<FlSpot> spots = [];
    for (int i = 0; i < weightEntries.length; i++) {
      spots.add(FlSpot(i.toDouble(), weightEntries[i]['weight'].toDouble()));
    }

    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 1;
    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 1;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weight Tracking',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWeightStat('Start', firstWeight, unit, Colors.blue),
                _buildWeightStat('Current', lastWeight, unit, Colors.green),
                _buildWeightStat(
                  'Change',
                  weightChange.abs(),
                  unit,
                  weightChange >= 0 ? Colors.red : Colors.green,
                  prefix: weightChange >= 0 ? '+' : '-',
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int idx = value.toInt();
                          if (idx >= 0 && idx < weightEntries.length) {
                            final date =
                                weightEntries[idx]['timestamp'] as DateTime;
                            return Text(
                              '${date.day}/${date.month}',
                              style: const TextStyle(fontSize: 10),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (spots.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightStat(
    String label,
    double value,
    String unit,
    Color color, {
    String prefix = '',
  }) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(
          '$prefix${value.toStringAsFixed(1)} $unit',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyCaloriesSection() {
    final dailyCalories = _reportData['dailyCalories'] as Map<String, double>;
    if (dailyCalories.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Calorie Intake',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No daily calorie data available.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final sortedDates = dailyCalories.keys.toList()..sort();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Calorie Intake',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 12),
            // Flutter Table widget for daily calories
            Table(
              border: TableBorder.all(color: Colors.grey[300]!),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey[200]),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        'Date',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        'Calories',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                ...sortedDates.map(
                  (date) => TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(date),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          '${dailyCalories[date]?.toStringAsFixed(0) ?? '0'}',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMealsSection() {
    final mealsDetails =
        _reportData['mealsDetails'] as List<Map<String, dynamic>>;
    if (mealsDetails.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top Meals by Calories',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'No meal data',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Sort meals by calories and take top 5
    final sortedMeals = List<Map<String, dynamic>>.from(mealsDetails);
    sortedMeals.sort(
      (a, b) => (b['calories'] as double).compareTo(a['calories'] as double),
    );
    final topMeals = sortedMeals.take(5).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Meals by Calories',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topMeals.length,
              separatorBuilder: (context, index) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final meal = topMeals[index];
                final mealType = meal['mealType'] as String;
                final color = mealTypeColors[mealType] ?? Colors.grey;
                final imageUrl = meal['imageUrl'] as String?;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show image if available (left side)
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                width: 48,
                                height: 48,
                                color: Colors.grey[200],
                                child: const Icon(
                                  Icons.image,
                                  color: Colors.grey,
                                ),
                              ),
                        ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meal['name'] as String,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  mealType,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat(
                                  'MMM dd',
                                ).format(meal['date'] as DateTime),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'P: ${(meal['protein'] as double).toStringAsFixed(1)}g',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'C: ${(meal['carbs'] as double).toStringAsFixed(1)}g',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'F: ${(meal['fat'] as double).toStringAsFixed(1)}g',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(meal['calories'] as double).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const Text(
                          'kcal',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
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

  Future<void> _generatePDF() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            _buildPDFHeader(),
            pw.SizedBox(height: 20),
            _buildPDFSummary(),
            pw.SizedBox(height: 20),
            _buildPDFMacronutrients(),
            pw.SizedBox(height: 20),
            _buildPDFMealDistribution(),
            pw.SizedBox(height: 20),
            _buildPDFWeightTracking(),
            pw.SizedBox(height: 20),
            _buildPDFDailyCalories(),
            pw.SizedBox(height: 20),
            _buildPDFTopMeals(),
            pw.SizedBox(height: 20),
            _buildPDFMealDetailsTable(),
            pw.SizedBox(height: 30),
            _buildPDFFooter(),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'NutriWise_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  pw.Widget _buildPDFHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NutriWise',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Nutrition Report',
                  style: pw.TextStyle(fontSize: 18, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Generated on',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey,
                  ),
                ),
                pw.Text(
                  DateFormat('MMM dd, yyyy').format(DateTime.now()),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 2, color: PdfColors.green),
        pw.SizedBox(height: 10),
        pw.Text(
          _reportData['userName'] ?? 'User',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _reportData['userEmail'] ?? '',
          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Report Period',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${DateFormat('MMM dd, yyyy').format(widget.startDate)} - ${DateFormat('MMM dd, yyyy').format(widget.endDate)}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Duration: ${widget.endDate.difference(widget.startDate).inDays + 1} days | Total Meals: ${_reportData['totalMeals']}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPDFSummary() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Summary',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildPDFSummaryCard(
                'Total Calories',
                '${_reportData['totalCalories'].toStringAsFixed(0)} kcal',
              ),
              _buildPDFSummaryCard(
                'Avg Daily Calories',
                '${_reportData['avgDailyCalories'].toStringAsFixed(0)} kcal',
              ),
              if (_reportData['targetCalories'] > 0)
                _buildPDFSummaryCard(
                  'Daily Target',
                  '${_reportData['targetCalories']} kcal',
                ),
            ],
          ),
          if (_reportData['targetCalories'] > 0) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'Target Achievement: ${((_reportData['avgDailyCalories'] / _reportData['targetCalories']) * 100).toStringAsFixed(0)}%',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildPDFSummaryCard(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  pw.Widget _buildPDFMacronutrients() {
    final totalProtein = _reportData['totalProtein'];
    final totalCarbs = _reportData['totalCarbs'];
    final totalFat = _reportData['totalFat'];

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Macronutrients Breakdown',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildPDFMacroColumn(
                'Carbohydrates',
                totalCarbs,
                _reportData['avgDailyCarbs'],
              ),
              _buildPDFMacroColumn(
                'Protein',
                totalProtein,
                _reportData['avgDailyProtein'],
              ),
              _buildPDFMacroColumn('Fat', totalFat, _reportData['avgDailyFat']),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPDFMacroColumn(String label, double total, double avg) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Total: ${total.toStringAsFixed(1)}g',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.Text(
          'Avg: ${avg.toStringAsFixed(1)}g/day',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget _buildPDFMealDistribution() {
    final mealCounts = _reportData['mealTypeCounts'] as Map<String, dynamic>;
    final totalMeals = mealCounts.values.fold(
      0,
      (sum, count) => sum + (count as int),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Meal Distribution',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 12),
          if (totalMeals > 0) ...[
            _buildPDFMealRow(
              'Breakfast',
              mealCounts['Breakfast'] ?? 0,
              totalMeals,
            ),
            pw.SizedBox(height: 8),
            _buildPDFMealRow('Lunch', mealCounts['Lunch'] ?? 0, totalMeals),
            pw.SizedBox(height: 8),
            _buildPDFMealRow('Dinner', mealCounts['Dinner'] ?? 0, totalMeals),
            pw.SizedBox(height: 8),
            _buildPDFMealRow('Snack', mealCounts['Snack'] ?? 0, totalMeals),
          ] else
            pw.Text(
              'No meal data available',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildPDFMealRow(String label, int count, int total) {
    final percentage = total > 0
        ? (count / total * 100).toStringAsFixed(0)
        : '0';
    final barWidth = total > 0 ? (count / total * 200) : 0.0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '$count meals ($percentage%)',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          height: 8,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey300,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              width: barWidth,
              height: 8,
              decoration: pw.BoxDecoration(
                color: PdfColors.green,
                borderRadius: pw.BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPDFWeightTracking() {
    final weightEntries =
        _reportData['weightEntries'] as List<Map<String, dynamic>>;

    if (weightEntries.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Text(
          'No weight data available for this period.',
          style: const pw.TextStyle(fontSize: 12),
        ),
      );
    }

    final firstWeight = weightEntries.first['weight'];
    final lastWeight = weightEntries.last['weight'];
    final weightChange = lastWeight - firstWeight;
    final isMetric = weightEntries.first['isMetric'] == true;
    final unit = isMetric ? 'kg' : 'lbs';

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Weight Tracking',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildPDFWeightStat('Starting', firstWeight, unit),
              _buildPDFWeightStat('Current', lastWeight, unit),
              _buildPDFWeightStat(
                'Change',
                weightChange.abs(),
                unit,
                prefix: weightChange >= 0 ? '+' : '-',
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: weightChange >= 0 ? PdfColors.red50 : PdfColors.green50,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              weightChange >= 0
                  ? 'Weight increased by ${weightChange.abs().toStringAsFixed(1)} $unit'
                  : 'Weight decreased by ${weightChange.abs().toStringAsFixed(1)} $unit',
              style: pw.TextStyle(
                fontSize: 11,
                color: weightChange >= 0
                    ? PdfColors.red700
                    : PdfColors.green700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPDFWeightStat(
    String label,
    double value,
    String unit, {
    String prefix = '',
  }) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '$prefix${value.toStringAsFixed(1)} $unit',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _buildPDFDailyCalories() {
    final dailyCalories = _reportData['dailyCalories'] as Map<String, double>;
    if (dailyCalories.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Text(
          'No daily calorie data available.',
          style: const pw.TextStyle(fontSize: 12),
        ),
      );
    }
    final sortedDates = dailyCalories.keys.toList()..sort();
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Daily Calorie Intake',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildPDFTableCell('Date', isHeader: true),
                  _buildPDFTableCell('Calories', isHeader: true),
                ],
              ),
              ...sortedDates.map(
                (date) => pw.TableRow(
                  children: [
                    _buildPDFTableCell(date),
                    _buildPDFTableCell(
                      '${dailyCalories[date]?.toStringAsFixed(0) ?? '0'}',
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

  pw.Widget _buildPDFTopMeals() {
    final mealsDetails =
        _reportData['mealsDetails'] as List<Map<String, dynamic>>;
    if (mealsDetails.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Text(
          'No meal data available.',
          style: const pw.TextStyle(fontSize: 12),
        ),
      );
    }
    final sortedMeals = List<Map<String, dynamic>>.from(mealsDetails);
    sortedMeals.sort(
      (a, b) => (b['calories'] as double).compareTo(a['calories'] as double),
    );
    final topMeals = sortedMeals.take(10).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Top ${topMeals.length} Meals by Calories',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildPDFTableCell('#', isHeader: true),
                  _buildPDFTableCell('Meal Name', isHeader: true),
                  _buildPDFTableCell('Type', isHeader: true),
                  _buildPDFTableCell('Date', isHeader: true),
                  _buildPDFTableCell('Calories', isHeader: true),
                ],
              ),
              ...topMeals.asMap().entries.map((entry) {
                final index = entry.key;
                final meal = entry.value;
                return pw.TableRow(
                  children: [
                    _buildPDFTableCell('${index + 1}'),
                    _buildPDFTableCell(meal['name'] as String),
                    _buildPDFTableCell(meal['mealType'] as String),
                    _buildPDFTableCell(
                      meal['date'] is DateTime
                          ? DateFormat('MM/dd').format(meal['date'] as DateTime)
                          : '',
                    ),
                    _buildPDFTableCell(
                      '${(meal['calories'] as double).toStringAsFixed(0)}',
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPDFMealDetailsTable() {
    final mealsDetails =
        _reportData['mealsDetails'] as List<Map<String, dynamic>>;
    if (mealsDetails.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Text(
          'No meal details available.',
          style: const pw.TextStyle(fontSize: 12),
        ),
      );
    }
    // Show all meals in a table with food names, meal type, date, calories, protein, carbs, fat
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'All Meals Details',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1),
              6: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildPDFTableCell('Food Names', isHeader: true),
                  _buildPDFTableCell('Type', isHeader: true),
                  _buildPDFTableCell('Date', isHeader: true),
                  _buildPDFTableCell('Created At', isHeader: true),
                  _buildPDFTableCell('Calories', isHeader: true),
                  _buildPDFTableCell('Protein', isHeader: true),
                  _buildPDFTableCell('Carbs', isHeader: true),
                  _buildPDFTableCell('Fat', isHeader: true),
                ],
              ),
              ...mealsDetails.map((meal) {
                // CreatedAt
                String createdAtStr = '';
                if (meal['date'] != null && meal['date'] is DateTime) {
                  createdAtStr = DateFormat(
                    'yyyy-MM-dd HH:mm',
                  ).format(meal['date'] as DateTime);
                } else if (meal['createdAt'] != null &&
                    meal['createdAt'] is DateTime) {
                  createdAtStr = DateFormat(
                    'yyyy-MM-dd HH:mm',
                  ).format(meal['createdAt'] as DateTime);
                }
                return pw.TableRow(
                  children: [
                    _buildPDFTableCell(meal['name'] as String),
                    _buildPDFTableCell(meal['mealType'] as String),
                    _buildPDFTableCell(
                      meal['date'] is DateTime
                          ? DateFormat('MM/dd').format(meal['date'] as DateTime)
                          : '',
                    ),
                    _buildPDFTableCell(createdAtStr),
                    _buildPDFTableCell(
                      '${(meal['calories'] as double).toStringAsFixed(0)}',
                    ),
                    _buildPDFTableCell(
                      '${(meal['protein'] as double).toStringAsFixed(1)}',
                    ),
                    _buildPDFTableCell(
                      '${(meal['carbs'] as double).toStringAsFixed(1)}',
                    ),
                    _buildPDFTableCell(
                      '${(meal['fat'] as double).toStringAsFixed(1)}',
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPDFTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  pw.Widget _buildPDFFooter() {
    return pw.Column(
      children: [
        pw.Divider(thickness: 1, color: PdfColors.grey300),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'NutriWise - Your Nutrition Companion',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
            pw.Text(
              'Generated on ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          ],
        ),
      ],
    );
  }
}

// Nutrients Page with 4 sections
class NutrientsPage extends StatefulWidget {
  const NutrientsPage({Key? key}) : super(key: key);

  @override
  State<NutrientsPage> createState() => _NutrientsPageState();
}

class _NutrientsPageState extends State<NutrientsPage> {
  List<Map<String, dynamic>> _weightEntries = [];
  bool _loading = true;
  final AuthService _authService = AuthService();

  // Intake trend state
  int _selectedWeekOffset = 0; // 0 = current week, -1 = previous, etc.
  Map<int, int> _weekCalorieIntake = {}; // dayOfWeek (1=Mon) -> calories
  int? _targetCalories;

  // Meal trend state
  int _selectedMealWeekOffset = 0;
  Map<String, int> _weekMealCounts = {
    'Breakfast': 0,
    'Lunch': 0,
    'Dinner': 0,
    'Snack': 0,
  };
  Map<String, List<Map<String, dynamic>>> _weekMealMacros = {
    'Breakfast': [],
    'Lunch': [],
    'Dinner': [],
    'Snack': [],
  };

  // Add state for nutrition trend week navigation and macro data
  int _selectedNutritionWeekOffset = 0;
  Map<String, double> _nutritionMacros = {'Carbs': 0, 'Protein': 0, 'Fat': 0};

  @override
  void initState() {
    super.initState();
    _fetchWeightEntries();
    _fetchTargetCalories();
    _fetchIntakeForWeek();
    _fetchMealTrendForWeek();
    _fetchNutritionMacrosForWeek();
  }

  Future<void> _fetchTargetCalories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    setState(() {
      _targetCalories = userDoc.data()?['calories']?.round();
    });
  }

  Future<void> _fetchIntakeForWeek() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _weekCalorieIntake = {};
      });
      return;
    }
    final now = DateTime.now();
    final monday = now
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: 7 * _selectedWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    final startDate = DateTime(monday.year, monday.month, monday.day);
    final endDate = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);

    // --- Fetch from barcodes ---
    final barcodeSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    // --- Fetch from meals ---
    final mealsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    Map<int, int> weekIntake = {};
    for (var doc in barcodeSnapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final calories = (data['calories'] ?? 0).round();
      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        final weekday = date.weekday; // 1=Mon, 7=Sun
        weekIntake[weekday] = ((weekIntake[weekday] ?? 0) + calories).toInt();
      }
    }
    for (var doc in mealsSnapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final calories = (data['totalCalories'] ?? 0).round();
      if (createdAt is Timestamp) {
        final date = createdAt.toDate();
        final weekday = date.weekday; // 1=Mon, 7=Sun
        weekIntake[weekday] = ((weekIntake[weekday] ?? 0) + calories).toInt();
      }
    }
    setState(() {
      _weekCalorieIntake = weekIntake;
    });
  }

  Future<void> _fetchMealTrendForWeek() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _weekMealCounts = {'Breakfast': 0, 'Lunch': 0, 'Dinner': 0, 'Snack': 0};
        _weekMealMacros = {
          'Breakfast': [],
          'Lunch': [],
          'Dinner': [],
          'Snack': [],
        };
      });
      return;
    }
    final now = DateTime.now();
    final monday = now
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: 7 * _selectedMealWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    final startDate = DateTime(monday.year, monday.month, monday.day);
    final endDate = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);

    // --- Fetch from barcodes ---
    final barcodeSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    // --- Fetch from meals ---
    final mealsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    Map<String, int> mealCounts = {
      'Breakfast': 0,
      'Lunch': 0,
      'Dinner': 0,
      'Snack': 0,
    };
    Map<String, List<Map<String, dynamic>>> mealMacros = {
      'Breakfast': [],
      'Lunch': [],
      'Dinner': [],
      'Snack': [],
    };

    for (var doc in barcodeSnapshot.docs) {
      final data = doc.data();
      String mealType = (data['mealType'] ?? 'Meal').toString().trim();
      if (mealType == 'Breakfast Snack' ||
          mealType == 'Afternoon Snack' ||
          mealType == 'Midnight Snack') {
        mealType = 'Snack';
      }
      if (mealCounts.containsKey(mealType)) {
        mealCounts[mealType] = mealCounts[mealType]! + 1;
        mealMacros[mealType]!.add(data);
      }
    }
    for (var doc in mealsSnapshot.docs) {
      final data = doc.data();
      String mealType = (data['mealType'] ?? 'Meal').toString().trim();
      if (mealType == 'Breakfast Snack' ||
          mealType == 'Afternoon Snack' ||
          mealType == 'Midnight Snack') {
        mealType = 'Snack';
      }
      if (mealCounts.containsKey(mealType)) {
        mealCounts[mealType] = mealCounts[mealType]! + 1;
        mealMacros[mealType]!.add(data);
      }
    }

    setState(() {
      _weekMealCounts = mealCounts;
      _weekMealMacros = mealMacros;
    });
  }

  Future<void> _fetchNutritionMacrosForWeek() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _nutritionMacros = {'Carbs': 0, 'Protein': 0, 'Fat': 0};
      });
      return;
    }
    final now = DateTime.now();
    final monday = now
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: 7 * _selectedNutritionWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    final startDate = DateTime(monday.year, monday.month, monday.day);
    final endDate = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);

    // --- Fetch from barcodes ---
    final barcodeSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('barcodes')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    // --- Fetch from meals ---
    final mealsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        )
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    double totalCarbs = 0;
    double totalProtein = 0;
    double totalFat = 0;
    for (var doc in barcodeSnapshot.docs) {
      final data = doc.data();
      totalCarbs += (data['carbohydrate'] ?? data['carbs'] ?? 0).toDouble();
      totalProtein += (data['protein'] ?? 0).toDouble();
      totalFat += (data['fat'] ?? 0).toDouble();
    }
    for (var doc in mealsSnapshot.docs) {
      final data = doc.data();
      totalCarbs += (data['totalCarbs'] ?? 0).toDouble();
      totalProtein += (data['totalProtein'] ?? 0).toDouble();
      totalFat += (data['totalFat'] ?? 0).toDouble();
    }
    setState(() {
      _nutritionMacros = {
        'Carbs': totalCarbs,
        'Protein': totalProtein,
        'Fat': totalFat,
      };
    });
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekOffset -= 1;
    });
    _fetchIntakeForWeek();
  }

  void _nextWeek() {
    if (_selectedWeekOffset < 0) {
      setState(() {
        _selectedWeekOffset += 1;
      });
      _fetchIntakeForWeek();
    }
  }

  void _previousMealWeek() {
    setState(() {
      _selectedMealWeekOffset -= 1;
    });
    _fetchMealTrendForWeek();
  }

  void _nextMealWeek() {
    if (_selectedMealWeekOffset < 0) {
      setState(() {
        _selectedMealWeekOffset += 1;
      });
      _fetchMealTrendForWeek();
    }
  }

  void _previousNutritionWeek() {
    setState(() {
      _selectedNutritionWeekOffset -= 1;
    });
    _fetchNutritionMacrosForWeek();
  }

  void _nextNutritionWeek() {
    if (_selectedNutritionWeekOffset < 0) {
      setState(() {
        _selectedNutritionWeekOffset += 1;
      });
      _fetchNutritionMacrosForWeek();
    }
  }

  Future<void> _fetchWeightEntries() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _weightEntries = [];
        _loading = false;
      });
      return;
    }
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('weight_entries')
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
        )
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfMonth))
        .orderBy('timestamp', descending: false)
        .get();

    setState(() {
      _weightEntries = snapshot.docs.map((doc) => doc.data()).toList();
      _loading = false;
    });
  }

  Future<void> _showUpdateWeightDialog(BuildContext context) async {
    if (_weightEntries.isEmpty) return;
    final latest = _weightEntries.last;
    double weight = (latest['weight'] ?? 0.0).toDouble();
    bool metric = latest['isMetric'] == true;
    final TextEditingController _weightController = TextEditingController(
      text: weight > 0 ? weight.toStringAsFixed(1) : '',
    );
    final _formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.monitor_weight, color: Colors.green, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    "Update Weight",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    metric
                        ? '${weight.toStringAsFixed(1)} kg'
                        : '${weight.toStringAsFixed(1)} lbs',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    metric ? 'Unit: kg' : 'Unit: lbs',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _weightController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: metric
                          ? 'Update Weight (kg)'
                          : 'Update Weight (lbs)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (v) {
                      double? val = double.tryParse(v ?? '');
                      if (val == null || val < 20 || val > 500)
                        return 'Enter realistic weight';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        if (_formKey.currentState?.validate() ?? false) {
                          double? newWeight = double.tryParse(
                            _weightController.text,
                          );
                          if (newWeight != null) {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user != null) {
                              // Update user profile weight
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .update({
                                    'weight': double.parse(
                                      newWeight.toStringAsFixed(2),
                                    ),
                                  });
                              // Save weight entry for trend
                              await _authService.saveWeightEntry(
                                user.uid,
                                double.parse(newWeight.toStringAsFixed(2)),
                                isMetric: metric,
                              );
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Weight updated!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              // Refresh weight entries and update graph
                              await _fetchWeightEntries();
                              setState(
                                () {},
                              ); // Force rebuild to update graph and value
                            }
                          }
                        }
                      },
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildWeightTrend(context),
        const SizedBox(height: 24),
        _buildIntakeTrend(),
        const SizedBox(height: 24),
        _buildMealTrend(),
        const SizedBox(height: 24),
        _buildNutritionTrend(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWeightTrend(BuildContext context) {
    if (_loading) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_weightEntries.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No weight data for this month.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    // Prepare chart data: use all entries for the current month
    List<FlSpot> spots = [];
    List<DateTime> entryDates = [];
    for (var entry in _weightEntries) {
      final ts = entry['timestamp'];
      if (ts is Timestamp) {
        final date = ts.toDate();
        entryDates.add(date);
      }
    }
    entryDates.sort((a, b) => a.compareTo(b));
    for (int i = 0; i < entryDates.length; i++) {
      final entry = _weightEntries[i];
      final ts = entry['timestamp'];
      if (ts is Timestamp) {
        final date = ts.toDate();
        final weight = (entry['weight'] ?? 0).toDouble();
        spots.add(FlSpot(i.toDouble(), weight));
      }
    }

    double minY = spots.isNotEmpty
        ? spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 1
        : 0;
    double maxY = spots.isNotEmpty
        ? spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 1
        : 0;
    double latestWeight = spots.isNotEmpty ? spots.last.y : 0;
    String unit = (_weightEntries.last['isMetric'] == true) ? 'kg' : 'lbs';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Weight Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Text(
                  '${latestWeight.toStringAsFixed(1)} $unit',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[400],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int idx = value.toInt();
                          if (idx >= 0 && idx < entryDates.length) {
                            final date = entryDates[idx];
                            return Text(
                              '${date.day}/${date.month}',
                              style: const TextStyle(fontSize: 10),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (spots.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _showUpdateWeightDialog(context);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Update Weight'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntakeTrend() {
    // Days of week
    // Prepare bar chart data for the selected week
    List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < 7; i++) {
      int weekday = i + 1; // 1=Mon, 7=Sun
      double actual = (_weekCalorieIntake[weekday] ?? 0).toDouble();
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: actual,
              color: Colors.green,
              width: 16,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    // Get target calories
    double target = (_targetCalories ?? 0).toDouble();

    // Week range label
    final now = DateTime.now();
    final monday = now
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: 7 * _selectedWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    String weekLabel =
        "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";

    bool hasData = _weekCalorieIntake.values.any((v) => v > 0);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Intake Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousWeek,
                    ),
                    Text(
                      weekLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        color: _selectedWeekOffset < 0
                            ? Colors.black
                            : Colors.grey,
                      ),
                      onPressed: _selectedWeekOffset < 0 ? _nextWeek : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: hasData
                  ? BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: (target > 0)
                            ? [
                                    target,
                                    ...barGroups.map(
                                      (g) => g.barRods.first.toY,
                                    ),
                                  ].reduce((a, b) => a > b ? a : b) +
                                  500
                            : 3000,
                        barGroups: barGroups,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                int idx = value.toInt();
                                if (idx >= 0 && idx < 7) {
                                  final now = DateTime.now();
                                  final monday = now
                                      .subtract(Duration(days: now.weekday - 1))
                                      .add(
                                        Duration(days: 7 * _selectedWeekOffset),
                                      );
                                  final date = monday.add(Duration(days: idx));
                                  return Text(
                                    '${date.day}/${date.month}',
                                    style: const TextStyle(fontSize: 10),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: target > 0
                            ? ExtraLinesData(
                                horizontalLines: [
                                  HorizontalLine(
                                    y: target,
                                    color: Colors.red,
                                    strokeWidth: 2,
                                    dashArray: [8, 4],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      alignment: Alignment.topRight,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                      labelResolver: (_) => 'Target',
                                    ),
                                  ),
                                ],
                              )
                            : ExtraLinesData(),
                      ),
                    )
                  : Center(
                      child: Text(
                        'No intake data for this week.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(Colors.green, 'Actual'),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.red, 'Target'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Removed unused _makeBarGroup method

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildMealTrend() {
    // Prepare pie chart data for the selected week
    final totalMeals = _weekMealCounts.values.fold(0, (a, b) => a + b);
    final List<PieChartSectionData> sections = [
      PieChartSectionData(
        color: Colors.orange,
        value: totalMeals > 0
            ? (_weekMealCounts['Breakfast']! * 100 / totalMeals)
            : 0,
        title: totalMeals > 0
            ? '${(_weekMealCounts['Breakfast']! * 100 / totalMeals).toStringAsFixed(0)}%'
            : '',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      PieChartSectionData(
        color: Colors.teal,
        value: totalMeals > 0
            ? (_weekMealCounts['Lunch']! * 100 / totalMeals)
            : 0,
        title: totalMeals > 0
            ? '${(_weekMealCounts['Lunch']! * 100 / totalMeals).toStringAsFixed(0)}%'
            : '',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      PieChartSectionData(
        color: Colors.green,
        value: totalMeals > 0
            ? (_weekMealCounts['Dinner']! * 100 / totalMeals)
            : 0,
        title: totalMeals > 0
            ? '${(_weekMealCounts['Dinner']! * 100 / totalMeals).toStringAsFixed(0)}%'
            : '',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      PieChartSectionData(
        color: Colors.blue,
        value: totalMeals > 0
            ? (_weekMealCounts['Snack']! * 100 / totalMeals)
            : 0,
        title: totalMeals > 0
            ? '${(_weekMealCounts['Snack']! * 100 / totalMeals).toStringAsFixed(0)}%'
            : '',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ];

    final now = DateTime.now();
    final monday = now
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: 7 * _selectedMealWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    String weekLabel =
        "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Meal Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousMealWeek,
                    ),
                    Text(
                      weekLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        color: _selectedMealWeekOffset < 0
                            ? Colors.black
                            : Colors.grey,
                      ),
                      onPressed: _selectedMealWeekOffset < 0
                          ? _nextMealWeek
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: totalMeals > 0
                  ? PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 50,
                        sectionsSpace: 2,
                      ),
                    )
                  : Center(
                      child: Text(
                        'No meal data for this week.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMealLegend(Colors.orange, 'Breakfast'),
                _buildMealLegend(Colors.teal, 'Lunch'),
                _buildMealLegend(Colors.green, 'Dinner'),
                _buildMealLegend(Colors.blue, 'Snack'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: totalMeals > 0
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MealDetailPage(
                              weekLabel: weekLabel,
                              mealMacros: _weekMealMacros,
                            ),
                          ),
                        );
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Show Detail'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealLegend(Color color, String label) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildNutritionTrend() {
    final now = DateTime.now();
    final monday = now
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: 7 * _selectedNutritionWeekOffset));
    final sunday = monday.add(const Duration(days: 6));
    String weekLabel =
        "${monday.month}/${monday.day} - ${sunday.month}/${sunday.day}";

    final totalMacros = _nutritionMacros.values.reduce((a, b) => a + b);
    final List<PieChartSectionData> sections = [
      PieChartSectionData(
        color: Colors.green,
        value: totalMacros > 0 ? _nutritionMacros['Carbs']! : 0,
        title: totalMacros > 0 ? 'Carbs' : '',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      PieChartSectionData(
        color: Colors.blue,
        value: totalMacros > 0 ? _nutritionMacros['Protein']! : 0,
        title: totalMacros > 0 ? 'Protein' : '',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      PieChartSectionData(
        color: Colors.orange,
        value: totalMacros > 0 ? _nutritionMacros['Fat']! : 0,
        title: totalMacros > 0 ? 'Fat' : '',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Nutrition Trend',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _previousNutritionWeek,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      Flexible(
                        child: Text(
                          weekLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          color: _selectedNutritionWeekOffset < 0
                              ? Colors.black
                              : Colors.grey,
                        ),
                        onPressed: _selectedNutritionWeekOffset < 0
                            ? _nextNutritionWeek
                            : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: totalMacros > 0
                  ? PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 50,
                        sectionsSpace: 2,
                      ),
                    )
                  : Center(
                      child: Text(
                        'No nutrition data for this week.',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMealLegend(Colors.green, 'Carbs'),
                _buildMealLegend(Colors.blue, 'Protein'),
                _buildMealLegend(Colors.orange, 'Fat'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// MealDetailPage remains the same
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: mealTypes.length,
        itemBuilder: (context, idx) {
          final type = mealTypes[idx];
          final meals = mealMacros[type] ?? [];
          if (meals.isEmpty) {
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No $type records for this week.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
            );
          }
          double totalCalories = 0;
          double totalProtein = 0;
          double totalCarbs = 0;
          double totalFat = 0;
          for (var macro in meals) {
            // Handle both barcode and meal field names
            totalCalories += (macro['calories'] ?? macro['totalCalories'] ?? 0)
                .toDouble();
            totalProtein += (macro['protein'] ?? macro['totalProtein'] ?? 0)
                .toDouble();
            totalCarbs +=
                (macro['carbohydrate'] ??
                        macro['carbs'] ??
                        macro['totalCarbs'] ??
                        0)
                    .toDouble();
            totalFat += (macro['fat'] ?? macro['totalFat'] ?? 0).toDouble();
          }
          final totalMacros = totalProtein + totalCarbs + totalFat;
          final List<PieChartSectionData> macroSections = [
            PieChartSectionData(
              color: Colors.green,
              value: totalMacros > 0 ? totalCarbs : 0,
              title: totalMacros > 0 ? 'Carbs' : '',
              radius: 40,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            PieChartSectionData(
              color: Colors.blue,
              value: totalMacros > 0 ? totalProtein : 0,
              title: totalMacros > 0 ? 'Protein' : '',
              radius: 40,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            PieChartSectionData(
              color: Colors.orange,
              value: totalMacros > 0 ? totalFat : 0,
              title: totalMacros > 0 ? 'Fat' : '',
              radius: 40,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        type,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${meals.length} meal${meals.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Pie Chart
                  Center(
                    child: SizedBox(
                      height: 150,
                      width: 150,
                      child: totalMacros > 0
                          ? PieChart(
                              PieChartData(
                                sections: macroSections,
                                centerSpaceRadius: 40,
                                sectionsSpace: 2,
                              ),
                            )
                          : Center(
                              child: Text(
                                'No macro data',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Calories - Full width, prominent
                  _buildCaloriesCard(totalCalories),
                  const SizedBox(height: 16),
                  // Macros in horizontal row
                  Row(
                    children: [
                      Expanded(
                        child: _buildMacroCard(
                          'Protein',
                          totalProtein,
                          Colors.blue,
                          Icons.fitness_center,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMacroCard(
                          'Carbs',
                          totalCarbs,
                          Colors.green,
                          Icons.grain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMacroCard(
                          'Fat',
                          totalFat,
                          Colors.orange,
                          Icons.opacity,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaloriesCard(double calories) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Calories',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                calories.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
          Text(
            'kcal',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroCard(
    String label,
    double value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'g',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
