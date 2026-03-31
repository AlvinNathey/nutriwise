import 'dart:math' as math;

import 'package:flutter/material.dart';

class AfterMealSummary extends StatelessWidget {
  final int dailyGoal;
  final int carbsTarget;
  final int proteinTarget;
  final int fatTarget;
  final int todayCaloriesConsumed;
  final int todayCarbsConsumed;
  final int todayProteinConsumed;
  final int todayFatConsumed;
  final int mealCalories;
  final int mealCarbs;
  final int mealProtein;
  final int mealFat;
  final EdgeInsetsGeometry margin;

  const AfterMealSummary({
    super.key,
    required this.dailyGoal,
    required this.carbsTarget,
    required this.proteinTarget,
    required this.fatTarget,
    required this.todayCaloriesConsumed,
    required this.todayCarbsConsumed,
    required this.todayProteinConsumed,
    required this.todayFatConsumed,
    required this.mealCalories,
    required this.mealCarbs,
    required this.mealProtein,
    required this.mealFat,
    this.margin = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final caloriesAfterMeal = todayCaloriesConsumed + mealCalories;
    final carbsAfterMeal = todayCarbsConsumed + mealCarbs;
    final proteinAfterMeal = todayProteinConsumed + mealProtein;
    final fatAfterMeal = todayFatConsumed + mealFat;

    final caloriesLeft = dailyGoal - caloriesAfterMeal;
    final carbsLeft = carbsTarget - carbsAfterMeal;
    final proteinLeft = proteinTarget - proteinAfterMeal;
    final fatLeft = fatTarget - fatAfterMeal;
    final calorieProgress = dailyGoal > 0
        ? (caloriesAfterMeal / dailyGoal).clamp(0.0, 1.2)
        : 0.0;

    const double ringWidth = 180;
    const double ringHeight = 120;
    const double ringStrokeWidth = 8;
    final double ringRadius = math.min(
      (ringWidth / 2) - ringStrokeWidth / 2,
      ringHeight - ringStrokeWidth / 2,
    );
    final double ringArcTop = (ringHeight - ringStrokeWidth / 2) - ringRadius;
    final double ringTextTop = ringArcTop + ringRadius * 0.25;

    return Container(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'After This Meal',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
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
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildBreakdownRow(
                  label: 'Already consumed today:',
                  value: '$todayCaloriesConsumed kcal',
                  valueColor: Colors.grey[700]!,
                ),
                const SizedBox(height: 4),
                _buildBreakdownRow(
                  label: 'This meal:',
                  value: '+$mealCalories kcal',
                  labelColor: Colors.green[700]!,
                  valueColor: Colors.green[700]!,
                ),
                const Divider(height: 16),
                _buildBreakdownRow(
                  label: 'Total after meal:',
                  value: '$caloriesAfterMeal kcal',
                  labelColor: Colors.black,
                  valueColor: Colors.black,
                  bold: true,
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
                  size: const Size(ringWidth, ringHeight),
                  painter: _AfterMealSemiCirclePainter(
                    progress: calorieProgress,
                    backgroundColor: Colors.grey[200]!,
                    progressColor:
                        caloriesLeft >= 0 ? Colors.green : Colors.red,
                    strokeWidth: ringStrokeWidth,
                  ),
                ),
                Positioned(
                  top: ringTextTop,
                  left: 0,
                  right: 0,
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
                      ),
                      Text(
                        caloriesLeft >= 0 ? 'kcal left' : 'kcal over',
                        style: TextStyle(
                          fontSize: 12,
                          color: caloriesLeft >= 0
                              ? Colors.grey[600]
                              : Colors.red[400],
                        ),
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
              _MacroCircle(
                label: 'Carbs',
                current: carbsAfterMeal,
                target: carbsTarget,
                left: carbsLeft,
                color: Colors.orange,
              ),
              _MacroCircle(
                label: 'Protein',
                current: proteinAfterMeal,
                target: proteinTarget,
                left: proteinLeft,
                color: Colors.red,
              ),
              _MacroCircle(
                label: 'Fat',
                current: fatAfterMeal,
                target: fatTarget,
                left: fatLeft,
                color: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow({
    required String label,
    required String value,
    Color? labelColor,
    required Color valueColor,
    bool bold = false,
  }) {
    final labelStyle = TextStyle(
      fontSize: bold ? 14 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: labelColor ?? Colors.grey[700],
    );
    final valueStyle = TextStyle(
      fontSize: bold ? 14 : 13,
      fontWeight: FontWeight.w600,
      color: valueColor,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: labelStyle),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _MacroCircle extends StatelessWidget {
  final String label;
  final int current;
  final int target;
  final int left;
  final Color color;

  const _MacroCircle({
    required this.label,
    required this.current,
    required this.target,
    required this.left,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 70;
    const double strokeWidth = 4;
    final double chartHeight = size * 0.82;
    final double progress = target > 0 ? (current / target).clamp(0.0, 1.2) : 0.0;
    final double radius = math.min(
      (size / 2) - strokeWidth / 2,
      chartHeight - strokeWidth / 2,
    );
    final double arcTop = (chartHeight - strokeWidth / 2) - radius;
    final double textTop = arcTop + radius * 0.20;

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
          height: chartHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, chartHeight),
                painter: _AfterMealSemiCirclePainter(
                  progress: progress,
                  backgroundColor: Colors.grey[200]!,
                  progressColor: left >= 0 ? color : Colors.red,
                  strokeWidth: strokeWidth,
                ),
              ),
              Positioned(
                top: textTop,
                left: 0,
                right: 0,
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
}

class _AfterMealSemiCirclePainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  const _AfterMealSemiCirclePainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = math.min(
      (size.width / 2) - strokeWidth / 2,
      size.height - strokeWidth / 2,
    );
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
        totalSweep * progress.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AfterMealSemiCirclePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        backgroundColor != oldDelegate.backgroundColor ||
        progressColor != oldDelegate.progressColor ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}
