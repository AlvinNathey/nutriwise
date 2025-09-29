import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomSliderThumb extends SliderComponentShape {
  final double thumbRadius;

  const CustomSliderThumb({required this.thumbRadius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center + const Offset(0, 2), thumbRadius, shadowPaint);

    // Draw outer ring
    final outerPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, thumbRadius, outerPaint);

    // Draw inner circle
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, thumbRadius - 3, innerPaint);

    // Draw center dot
    final centerPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 3, centerPaint);
  }
}

class GoalSetupScreen extends StatefulWidget {
  final double weight;
  final bool isWeightMetric;
  final int previousCalories;
  final Map<String, dynamic> signupData;
  final Function(Map<String, dynamic> goalData) onGoalComplete;
  const GoalSetupScreen({
    Key? key,
    required this.weight,
    this.isWeightMetric = false,
    required this.previousCalories,
    required this.signupData,
    required this.onGoalComplete,
  }) : super(key: key);

  @override
  State<GoalSetupScreen> createState() => _GoalSetupScreenState();
}

class _GoalSetupScreenState extends State<GoalSetupScreen> {
  final PageController _pageController = PageController();
  String _mainGoal = '';
  double _targetWeight = 0.0;
  String _pace = '';
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _targetWeight = widget.weight;
  }

  void _nextStep() {
    setState(() {
      _currentStep++;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _previousStep() {
    setState(() {
      _currentStep--;
    });
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _stepTarget(
    bool isMetric,
    double minWeight,
    double maxWeight, {
    required bool up,
  }) {
    final double step = isMetric ? 0.1 : 0.5;
    final double next = up ? _targetWeight + step : _targetWeight - step;
    setState(() {
      _targetWeight = double.parse(
        next.clamp(minWeight, maxWeight).toStringAsFixed(1),
      );
    });
  }

  Future<void> _openWeightEditor(
    BuildContext context,
    bool isMetric,
    double minWeight,
    double maxWeight,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: _targetWeight.toStringAsFixed(1),
    );
    String? error;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final String unit = isMetric ? 'kg' : 'lbs';
        const keyboardType = TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        );
        final formatter = FilteringTextInputFormatter.allow(
          RegExp(r'^\d{0,3}(\.\d{0,1})?$'),
        );
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Enter target weight ($unit)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    inputFormatters: [formatter],
                    decoration: InputDecoration(
                      suffixText: ' $unit',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final String raw = controller.text.trim();
                        final double? parsed = double.tryParse(raw);
                        if (parsed == null) {
                          setSheetState(() => error = 'Enter a valid number');
                          return;
                        }
                        final double clamped = double.parse(
                          parsed.clamp(minWeight, maxWeight).toStringAsFixed(1),
                        );
                        setState(() => _targetWeight = clamped);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  int get totalSteps {
    // 3 steps for maintain, 4 for lose/gain
    return (_mainGoal == 'Lose weight' || _mainGoal == 'Gain weight') ? 4 : 2;
  }

  void _finishGoalSetup() {
    final goalData = {
      'mainGoal': _mainGoal,
      'targetWeight': _targetWeight,
      'pace': _pace,
    };
    widget.onGoalComplete(goalData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Set My Goal'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_pageController.page == 0) {
              Navigator.pop(context);
            } else {
              _previousStep();
            }
          },
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildProgressBar(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildGoalStep(),
                if (_mainGoal == 'Lose weight' || _mainGoal == 'Gain weight')
                  _buildTargetWeightStep(),
                _buildNutriWiseMotivationStep(),
                if (_mainGoal != 'Maintain weight') _buildPaceStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(totalSteps, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: index <= _currentStep ? Colors.black : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGoalStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'What is your main goal?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 40),
          _buildGoalOption('Lose weight'),
          const SizedBox(height: 16),
          _buildGoalOption('Gain weight'),
          const SizedBox(height: 16),
          _buildGoalOption('Maintain weight'),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _mainGoal.isNotEmpty ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalOption(String goal) {
    final isSelected = _mainGoal == goal;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mainGoal = goal;
          if (goal == 'Maintain weight') _targetWeight = widget.weight;
        });
      },
      child: SizedBox(
        width: double.infinity,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.transparent,
            border: Border.all(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            goal,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetWeightStep() {
    bool isMetric = widget.isWeightMetric;
    double currentWeight = widget.weight;
    double minWeight = _mainGoal == 'Lose weight'
        ? (isMetric
              ? (currentWeight * 0.7).clamp(30.0, currentWeight)
              : (currentWeight * 0.7).clamp(66.0, currentWeight))
        : currentWeight;
    double maxWeight = _mainGoal == 'Gain weight'
        ? (isMetric
              ? (currentWeight * 1.3).clamp(currentWeight, 200.0)
              : (currentWeight * 1.3).clamp(currentWeight, 440.0))
        : currentWeight;

    // Ensure target weight is within bounds
    if (_targetWeight < minWeight || _targetWeight > maxWeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _targetWeight = _targetWeight.clamp(minWeight, maxWeight);
        });
      });
    }

    bool canProceed = false;
    if (_mainGoal == 'Lose weight') {
      canProceed =
          _targetWeight < currentWeight &&
          (_targetWeight >= minWeight && _targetWeight <= currentWeight - 0.1);
    } else if (_mainGoal == 'Gain weight') {
      canProceed =
          _targetWeight > currentWeight &&
          (_targetWeight <= maxWeight && _targetWeight >= currentWeight + 0.1);
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'What is your target weight?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 40),

          // Current value display with edit action
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMetric
                            ? '${_targetWeight.toStringAsFixed(1)} kg'
                            : '${_targetWeight.toStringAsFixed(1)} lbs',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Target Weight',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.black),
                  tooltip: 'Edit',
                  onPressed: () => _openWeightEditor(
                    context,
                    isMetric,
                    minWeight,
                    maxWeight,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Fine adjustment steppers
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () =>
                    _stepTarget(isMetric, minWeight, maxWeight, up: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.black,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                child: const Icon(Icons.remove),
              ),
              const SizedBox(width: 24),
              ElevatedButton(
                onPressed: () =>
                    _stepTarget(isMetric, minWeight, maxWeight, up: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.black,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                child: const Icon(Icons.add),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Custom Weight Slider
          _buildWeightSlider(minWeight, maxWeight, isMetric),

          const SizedBox(height: 20),

          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canProceed ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canProceed ? Colors.black : Colors.grey[300],
                foregroundColor: canProceed ? Colors.white : Colors.grey[600],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightSlider(double minWeight, double maxWeight, bool isMetric) {
    return Column(
      children: [
        // Weight range indicators
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMetric
                    ? '${minWeight.toStringAsFixed(1)} kg'
                    : '${minWeight.toStringAsFixed(1)} lbs',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                isMetric
                    ? '${maxWeight.toStringAsFixed(1)} kg'
                    : '${maxWeight.toStringAsFixed(1)} lbs',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Custom styled slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            thumbShape: const CustomSliderThumb(thumbRadius: 14),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: Colors.black,
            inactiveTrackColor: Colors.grey[300],
            thumbColor: Colors.white,
            valueIndicatorColor: Colors.black,
            valueIndicatorTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            showValueIndicator: ShowValueIndicator.always,
          ),
          child: Slider(
            value: _targetWeight,
            min: minWeight,
            max: maxWeight,
            divisions: ((maxWeight - minWeight) * (isMetric ? 10 : 2)).round(),
            label: isMetric
                ? '${_targetWeight.toStringAsFixed(1)} kg'
                : '${_targetWeight.toStringAsFixed(1)} lbs',
            onChanged: (double value) {
              setState(() {
                _targetWeight = value;
              });
            },
          ),
        ),

        const SizedBox(height: 10),

        // Tick marks and labels
        _buildTickMarks(minWeight, maxWeight, isMetric),
      ],
    );
  }

  Widget _buildTickMarks(double minWeight, double maxWeight, bool isMetric) {
    return Container(
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double sliderWidth = constraints.maxWidth - 32; // Account for padding
          double range = maxWeight - minWeight;

          List<Widget> tickMarks = [];

          // Generate tick marks for whole numbers
          for (int i = minWeight.ceil(); i <= maxWeight.floor(); i++) {
            double position = ((i - minWeight) / range) * sliderWidth + 16;
            bool isCurrentValue = (i - _targetWeight).abs() < 0.5;
            bool showLabel =
                i % (isMetric ? 2 : 5) == 0 ||
                i == minWeight.ceil() ||
                i == maxWeight.floor() ||
                isCurrentValue;

            tickMarks.add(
              Positioned(
                left: position - 1,
                top: 0,
                child: Container(
                  width: 2,
                  height: 15,
                  decoration: BoxDecoration(
                    color: isCurrentValue ? Colors.black : Colors.grey[400],
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            );

            if (showLabel) {
              tickMarks.add(
                Positioned(
                  left: position - 15,
                  top: 18,
                  child: SizedBox(
                    width: 30,
                    child: Text(
                      i.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCurrentValue ? 13 : 11,
                        fontWeight: isCurrentValue
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrentValue ? Colors.black : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // Generate smaller tick marks for half values (metric only)
          if (isMetric) {
            for (
              double i = minWeight.ceilToDouble();
              i <= maxWeight.floorToDouble();
              i += 0.5
            ) {
              if (i != i.round().toDouble()) {
                // Only half values
                double position = ((i - minWeight) / range) * sliderWidth + 16;
                tickMarks.add(
                  Positioned(
                    left: position - 0.5,
                    top: 5,
                    child: Container(
                      width: 1,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(0.5),
                      ),
                    ),
                  ),
                );
              }
            }
          }

          return Stack(children: tickMarks);
        },
      ),
    );
  }

  Widget _buildNutriWiseMotivationStep() {
    String action = _mainGoal == 'Lose weight'
        ? 'lose'
        : _mainGoal == 'Gain weight'
        ? 'gain'
        : 'maintain';
    String value = (_mainGoal == 'Maintain weight')
        ? ''
        : (widget.isWeightMetric
              ? ' ${(widget.weight - _targetWeight).abs().toStringAsFixed(1)} kg'
              : ' ${(widget.weight - _targetWeight).abs().toStringAsFixed(1)} lbs');

    String message;
    if (_mainGoal == 'Lose weight') {
      message =
          "You're about to start your journey to a healthier you. NutriWise will guide you to lose$value safely and sustainably. Every step counts!";
    } else if (_mainGoal == 'Gain weight') {
      message =
          "Ready to build strength and confidence? NutriWise will help you gain$value with a personalized plan. Progress is made one day at a time!";
    } else {
      message =
          "Maintaining your healthy weight is a great goal! NutriWise will support you in staying on track and feeling your best every day.";
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                Icons.emoji_events,
                key: ValueKey(action),
                color: Colors.orange[700],
                size: 80,
              ),
            ),
            const SizedBox(height: 32),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Text(
                message,
                key: ValueKey('$action$value'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 40),
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 700),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue[200]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb, color: Colors.blue, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Stay motivated! Small steps every day lead to big results. NutriWise is with you at every step.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_mainGoal == 'Maintain weight') {
                    _finishGoalSetup();
                  } else {
                    _nextStep();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  _mainGoal == 'Maintain weight' ? 'Save My Set Goals' : 'Next',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPaceStep() {
    String verb = _mainGoal == 'Lose weight' ? 'lose' : 'gain';
    bool isMetric = widget.isWeightMetric;
    String unit = isMetric ? 'kg' : 'lbs';
    List<Map<String, String>> paceOptions = [
      {
        'label': 'Relaxed',
        'desc': isMetric
            ? '$verb 0.125 $unit per week'
            : '$verb 0.25 $unit per week',
      },
      {
        'label': 'Steady',
        'desc': isMetric
            ? '$verb 0.25 $unit per week'
            : '$verb 0.5 $unit per week',
      },
      {
        'label': 'Accelerated',
        'desc': isMetric
            ? '$verb 0.5 $unit per week'
            : '$verb 1 $unit per week',
      },
      {
        'label': 'Intense',
        'desc': isMetric ? '$verb 1 $unit per week' : '$verb 2 $unit per week',
      },
    ];
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Text(
              'How fast do you want to $verb weight?',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 40),
            ...paceOptions.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildPaceOption(p['label']!, p['desc']!),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _pace.isNotEmpty ? _finishGoalSetup : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save My Set Goals',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaceOption(String pace, String desc) {
    final isSelected = _pace == pace;
    return GestureDetector(
      onTap: () {
        setState(() {
          _pace = pace;
        });
      },
      child: SizedBox(
        width: double.infinity,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.transparent,
            border: Border.all(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pace,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
