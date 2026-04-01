import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutriwise/food/edit_food_log.dart';
import 'package:nutriwise/services/food_collections.dart';

// ─────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────

class FoodLog {
  final String id;
  final String mealType;
  final String time;
  final String foodName;
  final int calories;
  final DateTime createdAt;
  final String source;
  final String? imageUrl;
  final bool isMeal;
  final List<Map<String, dynamic>>? foodItems;
  final bool canEdit;
  final bool fromManualFlow;

  FoodLog({
    required this.id,
    required this.mealType,
    required this.time,
    required this.foodName,
    required this.calories,
    required this.createdAt,
    this.source = 'Barcode',
    this.imageUrl,
    this.isMeal = false,
    this.foodItems,
    this.canEdit = true,
    this.fromManualFlow = false,
  });
}

enum SectionType { day, weekChild, monthParent, dayChild }

class TimelineSection {
  final String id;
  final String title;
  final DateTime sortDate;
  final List<FoodLog> logs;
  final SectionType type;
  final String? parentId;

  TimelineSection({
    required this.id,
    required this.title,
    required this.sortDate,
    required this.type,
    this.parentId,
    List<FoodLog>? logs,
  }) : logs = logs ?? [];

  int get totalCalories => logs.fold(0, (sum, log) => sum + log.calories);
}

// ─────────────────────────────────────────────────────────────────
// Data Fetching
// ─────────────────────────────────────────────────────────────────

Future<List<FoodLog>> fetchLoggedFoods() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('barcodes')
      .orderBy('createdAt', descending: true)
      .get();
  final manualSnapshot = await userManualFoodsCollection(
    user.uid,
  ).orderBy('createdAt', descending: true).get();

  final logs = [
    ...snapshot.docs.map((doc) {
      final data = doc.data();
      final date = _parseCreatedAt(data['createdAt']);
      return FoodLog(
        id: doc.id,
        mealType: (data['mealType'] ?? 'Meal').toString(),
        time: _formatTimeFromDate(date),
        foodName: (data['foodName'] ?? data['name'] ?? 'Unknown').toString(),
        calories: (data['calories'] ?? 0).round(),
        createdAt: date,
        source: (data['source'] ?? 'Barcode').toString(),
        isMeal: false,
      );
    }),
    ..._buildGroupedManualLogs(manualSnapshot.docs),
  ];

  logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return logs;
}

List<FoodLog> _buildGroupedManualLogs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  final standalone = <FoodLog>[];

  for (final doc in docs) {
    final data = doc.data();
    final mealGroupId = (data['mealGroupId'] ?? '').toString().trim();
    if (mealGroupId.isEmpty) {
      final date = _parseCreatedAt(data['createdAt']);
      final itemSource =
          (data['itemSource'] ?? data['source'] ?? 'Manually Added').toString();
      final hasBarcodeItem = _isBarcodeItemSource(itemSource);
      standalone.add(
        FoodLog(
          id: doc.id,
          mealType: (data['mealType'] ?? 'Meal').toString(),
          time: _formatTimeFromDate(date),
          foodName: (data['foodName'] ?? data['name'] ?? 'Unknown').toString(),
          calories: (data['calories'] ?? 0).round(),
          createdAt: date,
          source: _resolveGroupedManualSource(!hasBarcodeItem, hasBarcodeItem),
          isMeal: false,
          fromManualFlow: true,
        ),
      );
      continue;
    }
    grouped.putIfAbsent(mealGroupId, () => []).add(doc);
  }

  final groupedLogs = grouped.entries.map((entry) {
    final groupDocs = entry.value;
    final first = groupDocs.first.data();
    final createdAt = _parseCreatedAt(first['createdAt']);
    final foodNames = groupDocs
        .map((doc) => (doc.data()['foodName'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final totalCalories = groupDocs.fold<int>(
      0,
      (sum, doc) => sum + ((doc.data()['calories'] ?? 0) as num).round(),
    );
    final hasBarcodeItem = groupDocs.any(
      (doc) => _isBarcodeItemSource(
        (doc.data()['itemSource'] ?? doc.data()['source'] ?? '').toString(),
      ),
    );
    final resolvedSource = _resolveGroupedManualSource(
      !hasBarcodeItem,
      hasBarcodeItem,
    );

    return FoodLog(
      id: groupDocs.first.id,
      mealType: (first['mealType'] ?? 'Meal').toString(),
      time: _formatTimeFromDate(createdAt),
      foodName:
          (first['combinedFoodName'] ??
                  (foodNames.isEmpty ? 'Meal' : foodNames.join(', ')))
              .toString(),
      calories: totalCalories,
      createdAt: createdAt,
      source: resolvedSource,
      isMeal: false,
      canEdit: false,
      fromManualFlow: true,
      foodItems: foodNames.map((name) => {'foodName': name}).toList(),
    );
  });

  return [...standalone, ...groupedLogs];
}

bool _isBarcodeItemSource(String source) {
  final normalized = source.trim().toLowerCase();
  return normalized.contains('barcode');
}

bool _isManualMealsCollectionItemSource(String source) {
  final normalized = source.trim().toLowerCase();
  return normalized.contains('manual');
}

String _resolveMealsCollectionSource(List<dynamic> foodItems) {
  bool hasAIDetected = false;
  bool hasManual = false;
  bool hasBarcode = false;

  for (final item in foodItems) {
    if (item is! Map<String, dynamic>) continue;
    final source = (item['itemSource'] ?? item['segmentationSource'] ?? '')
        .toString()
        .trim();
    if (source.isEmpty) {
      hasAIDetected = true;
      continue;
    }
    if (_isBarcodeItemSource(source)) {
      hasBarcode = true;
    } else if (_isManualMealsCollectionItemSource(source)) {
      hasManual = true;
    } else {
      hasAIDetected = true;
    }
  }

  if ((hasAIDetected && (hasManual || hasBarcode)) ||
      (hasManual && hasBarcode)) {
    return 'Mixed Entry';
  }
  if (hasBarcode) return 'Barcode Scanned';
  if (hasManual) return 'Manually Added';
  return 'AI Detection';
}

String _resolveGroupedManualSource(bool hasManual, bool hasBarcode) {
  if (hasManual && hasBarcode) return 'Mixed Entry';
  if (hasBarcode) return 'Barcode Scanned';
  return 'Manually Added';
}

Future<List<FoodLog>> fetchMealLogs() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('meals')
      .orderBy('createdAt', descending: true)
      .get();

  return snapshot.docs.map((doc) {
    final data = doc.data();
    final date = _parseCreatedAt(data['createdAt']);
    String foodName = 'Meal';
    if (data['foodItems'] is List && (data['foodItems'] as List).isNotEmpty) {
      foodName = (data['foodItems'][0]['foodName'] ?? 'Meal').toString();
    }
    return FoodLog(
      id: doc.id,
      mealType: (data['mealType'] ?? 'Meal').toString(),
      time: _formatTimeTo12Hour(
        (data['time'] ?? '').toString(),
        fallback: date,
      ),
      foodName: foodName,
      calories: (data['totalCalories'] ?? 0).round(),
      createdAt: date,
      source:
          (data['source'] ??
                  _resolveMealsCollectionSource(
                    (data['foodItems'] as List<dynamic>?) ?? const [],
                  ))
              .toString(),
      imageUrl: data['originalImageUrl'] as String?,
      isMeal: true,
      foodItems: (data['foodItems'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }).toList();
}

// ─────────────────────────────────────────────────────────────────
// Timeline Grouping Logic
// ─────────────────────────────────────────────────────────────────

List<TimelineSection> groupLogsByTimeline(List<FoodLog> logs) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final Map<String, TimelineSection> grouped = {};
  final Map<String, Map<String, TimelineSection>> monthWeekGrouped = {};

  for (final log in logs) {
    final logDate = DateTime(
      log.createdAt.year,
      log.createdAt.month,
      log.createdAt.day,
    );
    final diff = today.difference(logDate).inDays;

    if (diff == 0) {
      grouped.putIfAbsent(
        'today',
        () => TimelineSection(
          id: 'today',
          title: 'Today',
          sortDate: today,
          type: SectionType.day,
        ),
      );
      grouped['today']!.logs.add(log);
    } else if (diff == 1) {
      grouped.putIfAbsent(
        'yesterday',
        () => TimelineSection(
          id: 'yesterday',
          title: 'Yesterday',
          sortDate: today.subtract(const Duration(days: 1)),
          type: SectionType.day,
        ),
      );
      grouped['yesterday']!.logs.add(log);
    } else if (diff >= 2 && diff <= 6) {
      final sectionId = 'day-${_isoDate(logDate)}';
      grouped.putIfAbsent(
        sectionId,
        () => TimelineSection(
          id: sectionId,
          title: '${_weekdayName(logDate.weekday)}, ${_dayMonth(logDate)}',
          sortDate: logDate,
          type: SectionType.day,
        ),
      );
      grouped[sectionId]!.logs.add(log);
    } else if (diff >= 7 && diff <= 13) {
      final sectionId = 'lastweek-${_isoDate(logDate)}';
      grouped.putIfAbsent(
        sectionId,
        () => TimelineSection(
          id: sectionId,
          title:
              'Last Week · ${_weekdayName(logDate.weekday)}, ${_dayMonth(logDate)}',
          sortDate: logDate,
          type: SectionType.day,
        ),
      );
      grouped[sectionId]!.logs.add(log);
    } else {
      final monthKey =
          'month-${logDate.year}-${logDate.month.toString().padLeft(2, '0')}';
      final monthTitle = _monthYear(logDate);
      final weekOfMonth = ((logDate.day - 1) ~/ 7) + 1;
      final weekKey = '$monthKey-week$weekOfMonth';
      final weekRangeLabel = _weekRangeLabel(logDate);

      grouped.putIfAbsent(
        monthKey,
        () => TimelineSection(
          id: monthKey,
          title: monthTitle,
          sortDate: DateTime(logDate.year, logDate.month, 1),
          type: SectionType.monthParent,
        ),
      );

      monthWeekGrouped.putIfAbsent(monthKey, () => {});
      monthWeekGrouped[monthKey]!.putIfAbsent(
        weekKey,
        () => TimelineSection(
          id: weekKey,
          title: weekRangeLabel,
          sortDate: logDate,
          type: SectionType.weekChild,
          parentId: monthKey,
        ),
      );
      monthWeekGrouped[monthKey]![weekKey]!.logs.add(log);
    }
  }

  final List<TimelineSection> sections = [];

  final recentSections =
      grouped.values.where((s) => s.type == SectionType.day).toList()
        ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
  sections.addAll(recentSections);

  final monthSections =
      grouped.values.where((s) => s.type == SectionType.monthParent).toList()
        ..sort((a, b) => b.sortDate.compareTo(a.sortDate));

  for (final month in monthSections) {
    sections.add(month);
    final weeks = (monthWeekGrouped[month.id]?.values.toList() ?? [])
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
    sections.addAll(weeks);
  }

  for (final section in sections) {
    section.logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  return sections;
}

// ─────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────

String _isoDate(DateTime d) => d.toIso8601String().split('T').first;

String _weekdayName(int weekday) {
  const names = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };
  return names[weekday] ?? '';
}

String _monthYear(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String _shortMonth(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[date.month - 1];
}

String _dayMonth(DateTime date) {
  return '${_ordinal(date.day)} ${_shortMonth(date)}';
}

String _weekRangeLabel(DateTime date) {
  final daysInMonth = [
    0,
    31,
    date.year % 4 == 0 ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];
  final weekOfMonth = ((date.day - 1) ~/ 7) + 1;
  final startDay = (weekOfMonth - 1) * 7 + 1;
  final endDay = (startDay + 6).clamp(startDay, daysInMonth[date.month]);
  return '${_ordinal(startDay)} – ${_ordinal(endDay)} ${_shortMonth(date)}';
}

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  switch (day % 10) {
    case 1:
      return '${day}st';
    case 2:
      return '${day}nd';
    case 3:
      return '${day}rd';
    default:
      return '${day}th';
  }
}

DateTime _parseCreatedAt(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

String _formatTimeFromDate(DateTime date) {
  final period = date.hour >= 12 ? 'PM' : 'AM';
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$hour12:${date.minute.toString().padLeft(2, '0')} $period';
}

String _formatTimeTo12Hour(String raw, {required DateTime fallback}) {
  final value = raw.trim();
  if (value.isEmpty) return _formatTimeFromDate(fallback);
  final regex = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?$');
  final match = regex.firstMatch(value);
  if (match == null) return _formatTimeFromDate(fallback);
  int hour = int.tryParse(match.group(1) ?? '') ?? fallback.hour;
  final minute = int.tryParse(match.group(2) ?? '') ?? fallback.minute;
  final amPm = match.group(3)?.toUpperCase();
  if (minute < 0 || minute > 59) return _formatTimeFromDate(fallback);
  if (amPm != null) {
    if (hour < 1 || hour > 12) return _formatTimeFromDate(fallback);
    if (amPm == 'AM' && hour == 12)
      hour = 0;
    else if (amPm == 'PM' && hour != 12)
      hour += 12;
  } else {
    if (hour < 0 || hour > 23) return _formatTimeFromDate(fallback);
  }
  return _formatTimeFromDate(
    DateTime(fallback.year, fallback.month, fallback.day, hour, minute),
  );
}

// ─────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<TimelineSection>> _sectionsFuture;
  final Map<String, bool> _expandedSections = {};

  @override
  void initState() {
    super.initState();
    _sectionsFuture = _fetchAndGroup();
  }

  Future<List<TimelineSection>> _fetchAndGroup() async {
    final results = await Future.wait([fetchLoggedFoods(), fetchMealLogs()]);
    final allLogs = [...results[0], ...results[1]]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return groupLogsByTimeline(allLogs);
  }

  void _refreshLogs() {
    setState(() {
      _sectionsFuture = _fetchAndGroup();
    });
  }

  bool _isSectionExpanded(TimelineSection section) {
    if (_expandedSections.containsKey(section.id)) {
      return _expandedSections[section.id]!;
    }
    return section.type == SectionType.day;
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
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Timeline',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<TimelineSection>>(
        future: _sectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No foods logged yet.'));
          }

          final sections = snapshot.data!;

          return RefreshIndicator(
            color: Colors.green,
            onRefresh: () async => _refreshLogs(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: sections.length,
              itemBuilder: (context, idx) {
                final section = sections[idx];
                final isFirstSection = idx == 0;
                final isLastSection = idx == sections.length - 1;

                if (section.type == SectionType.monthParent) {
                  return _buildMonthHeader(section);
                }

                if (section.type == SectionType.weekChild) {
                  final parentExpanded =
                      _expandedSections[section.parentId] ?? false;
                  if (!parentExpanded) return const SizedBox.shrink();
                  return _buildWeekSection(section);
                }

                return _buildDaySection(
                  section,
                  isFirst: isFirstSection,
                  isLast: isLastSection,
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ── Month parent header ────────────────────────────────────────

  Widget _buildMonthHeader(TimelineSection section) {
    final isExpanded = _expandedSections[section.id] ?? false;

    return GestureDetector(
      onTap: () => setState(() {
        _expandedSections[section.id] = !isExpanded;
      }),
      child: Container(
        margin: const EdgeInsets.only(top: 20, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withOpacity(0.20)),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              color: Colors.green,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              section.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.green,
              ),
            ),
            const Spacer(),
            Text(
              isExpanded ? 'Collapse' : 'Expand',
              style: TextStyle(fontSize: 11, color: Colors.green.shade400),
            ),
          ],
        ),
      ),
    );
  }

  // ── Week child section ─────────────────────────────────────────

  Widget _buildWeekSection(TimelineSection section) {
    final isExpanded = _expandedSections[section.id] ?? false;
    final mealCount = section.logs.length;
    final calTotal = section.totalCalories;

    // Group logs by individual day within this week
    final Map<String, List<FoodLog>> dayGroups = {};
    final Map<String, DateTime> dayDates = {};

    for (final log in section.logs) {
      final logDate = DateTime(
        log.createdAt.year,
        log.createdAt.month,
        log.createdAt.day,
      );
      final dayKey = _isoDate(logDate);
      dayGroups.putIfAbsent(dayKey, () => []).add(log);
      dayDates[dayKey] = logDate;
    }

    final sortedDayKeys = dayGroups.keys.toList()
      ..sort((a, b) => dayDates[b]!.compareTo(dayDates[a]!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Week header ──
        GestureDetector(
          onTap: () => setState(() {
            _expandedSections[section.id] = !isExpanded;
          }),
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4, left: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$mealCount meal${mealCount == 1 ? '' : 's'}  ·  $calTotal kcal',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),

        // ── Expanded: individual days within this week ──
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sortedDayKeys.map((dayKey) {
                final dayDate = dayDates[dayKey]!;
                final dayLogs = dayGroups[dayKey]!;
                final dayId = '${section.id}-$dayKey';
                final isDayExpanded = _expandedSections[dayId] ?? true;
                final dayMealCount = dayLogs.length;
                final dayCalTotal = dayLogs.fold(
                  0,
                  (sum, l) => sum + l.calories,
                );
                final dayLabel =
                    '${_weekdayName(dayDate.weekday)}, ${_ordinal(dayDate.day)} ${_shortMonth(dayDate)}';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Day sub-header ──
                    GestureDetector(
                      onTap: () => setState(() {
                        _expandedSections[dayId] = !isDayExpanded;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dayLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$dayMealCount meal${dayMealCount == 1 ? '' : 's'}  ·  $dayCalTotal kcal',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              isDayExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Meal cards for this day ──
                    if (isDayExpanded)
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Column(
                          children: dayLogs
                              .map(
                                (meal) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: meal.isMeal
                                      ? _buildMealLogCard(context, meal)
                                      : _buildFoodLogCard(context, meal),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // ── Day section (recent) ───────────────────────────────────────

  Widget _buildDaySection(
    TimelineSection section, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isExpanded = _isSectionExpanded(section);
    final mealCount = section.logs.length;
    final calTotal = section.totalCalories;

    return Stack(
      children: [
        if (!isFirst)
          Positioned(
            left: 3.5,
            top: 0,
            child: Container(
              width: 1,
              height: 28,
              color: Colors.green.withOpacity(0.3),
            ),
          ),
        if (!isLast)
          Positioned(
            left: 3.5,
            top: 36,
            bottom: 0,
            child: Container(width: 1, color: Colors.green.withOpacity(0.3)),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isFirst) const SizedBox(height: 28),
            GestureDetector(
              onTap: () => setState(() {
                _expandedSections[section.id] =
                    !(_expandedSections[section.id] ?? isExpanded);
              }),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    '$mealCount meal${mealCount == 1 ? '' : 's'}  ·  $calTotal kcal',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  children: section.logs
                      .map(
                        (meal) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: meal.isMeal
                              ? _buildMealLogCard(context, meal)
                              : _buildFoodLogCard(context, meal),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }

  // ── Meal log card ──────────────────────────────────────────────

  Widget _buildMealLogCard(BuildContext context, FoodLog log) {
    return GestureDetector(
      onTap: () async {
        // TODO: Navigate to meal edit page
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: log.imageUrl != null
                  ? Image.network(
                      log.imageUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            log.mealType,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        Text(
                          log.time,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      log.foodItems != null && log.foodItems!.isNotEmpty
                          ? log.foodItems!
                                .map((f) => (f['foodName'] as String?) ?? '')
                                .where((n) => n.isNotEmpty)
                                .join(', ')
                          : log.foodName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${log.calories} kcal',
                      style: TextStyle(fontSize: 13, color: Colors.green[700]),
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

  Widget _imagePlaceholder() => Container(
    width: 80,
    height: 80,
    color: Colors.grey[200],
    child: const Icon(Icons.image, color: Colors.grey),
  );

  // ── Barcode scanned food card ──────────────────────────────────

  Widget _buildFoodLogCard(BuildContext context, FoodLog log) {
    final isManual = log.source == 'Manually Added';
    final isAi = log.source == 'AI Detection';
    final isMixed = log.source == 'Mixed Entry';
    final isManualFlow = log.fromManualFlow;
    final icon = isAi
        ? Icons.camera_alt
        : (isMixed
              ? Icons.add_link
              : ((isManualFlow || isManual)
                    ? Icons.edit_note
                    : Icons.qr_code_2));
    final accentColor = isAi
        ? Colors.green
        : (isMixed
              ? Colors.teal
              : ((isManualFlow || isManual) ? Colors.purple : Colors.green));
    final sourceLabel = isManual
        ? 'Manually Added'
        : (isAi
              ? 'AI Detected'
              : (isMixed
                    ? 'Manual + Barcode'
                    : (isManualFlow
                          ? 'Manual entry + barcode'
                          : 'Barcode Scanned')));

    return GestureDetector(
      onTap: log.canEdit
          ? () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditFoodLogPage(foodLogId: log.id),
                ),
              );
              _refreshLogs();
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Column(
                children: [
                  Icon(icon, size: 36, color: accentColor),
                  const SizedBox(height: 4),
                  Text(
                    (isManualFlow || isManual)
                        ? 'Manual'
                        : (isAi ? 'AI' : 'Scanned'),
                    style: TextStyle(
                      fontSize: 12,
                      color: accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            log.mealType,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        Text(
                          log.time,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      log.foodName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${log.calories} kcal',
                      style: TextStyle(fontSize: 13, color: Colors.green[700]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
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
}
