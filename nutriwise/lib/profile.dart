import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nutriwise/auth/login_screen.dart';
import 'package:intl/intl.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.logout, color: Colors.red, size: 32),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign out?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will need to log in again to access your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black.withOpacity(0.7),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Sign Out',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
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
    if (confirmed == true) {
      try {
        await FirebaseAuth.instance.signOut();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => false,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return doc.data();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchUserData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return const Scaffold(
            body: Center(child: Text('No account data found.')),
          );
        }
        final data = snapshot.data!;
        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text('My Profile'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 28),
                _menuCard(
                  context,
                  icon: Icons.person_outline,
                  title: 'Personal Information',
                  onTap: () async {
                    // Always fetch latest data before opening PersonalInfoPage
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) {
                      final doc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .get();
                      final latestData = doc.data();
                      if (latestData != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PersonalInfoPage(data: latestData),
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                _menuCard(
                  context,
                  icon: Icons.flag_outlined,
                  title: 'My Goals',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyGoalsPage(data: data),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _menuCard(
                  context,
                  icon: Icons.restaurant_menu_outlined,
                  title: 'My Plans',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyPlansPage(data: data),
                      ),
                    );
                  },
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text(
                      'Logout',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _signOut(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
          child: Row(
            children: [
              Icon(icon, color: Colors.green, size: 28),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PersonalInfoPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const PersonalInfoPage({Key? key, required this.data}) : super(key: key);

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // Return an empty stream if not logged in
      return const Stream.empty();
    }
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  void _editInfo(Map<String, dynamic> data) async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditPersonalInfoPage(data: data)),
    );
    if (updated == true) {
      // No need to manually refresh, StreamBuilder will update automatically
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Personal Information'),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData ||
            !snapshot.data!.exists ||
            snapshot.data!.data() == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Personal Information'),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: Text('No account data found.')),
          );
        }
        final data = snapshot.data!.data()!;
        String formattedDob = _formatDate(data['dateOfBirth']);
        String heightStr = '';
        if (data['height'] != null) {
          if (data['isMetric'] == true) {
            double cm = double.tryParse(data['height'].toString()) ?? 0;
            heightStr = '${cm.round()} cm';
          } else {
            double ft = double.tryParse(data['height'].toString()) ?? 0;
            int feet = ft.floor();
            int inches = ((ft % 1) * 12).round();
            heightStr = '${feet} foot ${inches} inches';
          }
        }
        String weightStr = '';
        if (data['weight'] != null) {
          double weight = double.tryParse(data['weight'].toString()) ?? 0;
          if (data['isWeightMetric'] == true) {
            weightStr = '${weight.toStringAsFixed(1)} kg';
          } else {
            weightStr = '${weight.toStringAsFixed(1)} lbs';
          }
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Personal Information'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editInfo(data),
                tooltip: 'Edit',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Profile',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                _infoCard(Icons.person, 'Name', data['name'] ?? ''),
                const SizedBox(height: 12),
                _infoCard(Icons.email, 'Email', data['email'] ?? ''),
                const SizedBox(height: 12),
                _infoCard(Icons.wc, 'Gender', data['gender'] ?? ''),
                const SizedBox(height: 12),
                _infoCard(Icons.cake, 'Date of Birth', formattedDob),
                const SizedBox(height: 12),
                _infoCard(Icons.height, 'Height', heightStr),
                const SizedBox(height: 12),
                _infoCard(Icons.monitor_weight, 'Weight', weightStr),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate);
      final day = date.day;
      final month = _monthName(date.month);
      final year = date.year;
      final suffix = _ordinalSuffix(day);
      return '$day$suffix $month $year';
    } catch (_) {
      return isoDate;
    }
  }

  String _monthName(int month) {
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
    return months[month - 1];
  }

  String _ordinalSuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }
}

class EditPersonalInfoPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const EditPersonalInfoPage({Key? key, required this.data}) : super(key: key);

  @override
  State<EditPersonalInfoPage> createState() => _EditPersonalInfoPageState();
}

class _EditPersonalInfoPageState extends State<EditPersonalInfoPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late DateTime? _dob;
  late TextEditingController _heightCmController;
  late TextEditingController _heightFeetController;
  late TextEditingController _heightInchController;
  late TextEditingController _weightController;
  late bool _isMetric;
  late bool _isWeightMetric;
  bool _loading = false;
  double? _originalHeight;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data['name'] ?? '');
    _dob = widget.data['dateOfBirth'] != null
        ? DateTime.tryParse(widget.data['dateOfBirth'])
        : null;
    _isMetric = widget.data['isMetric'] == true;
    _isWeightMetric = widget.data['isWeightMetric'] == true;
    _originalHeight = widget.data['height'] != null
        ? double.tryParse(widget.data['height'].toString())
        : null;
    if (_isMetric) {
      _heightCmController = TextEditingController(
        text: _originalHeight != null
            ? _originalHeight!.toStringAsFixed(2)
            : '',
      );
      _heightFeetController = TextEditingController();
      _heightInchController = TextEditingController();
    } else {
      double feet = _originalHeight != null
          ? _originalHeight!.floorToDouble()
          : 0;
      double inches = _originalHeight != null
          ? ((_originalHeight! - feet) * 12)
          : 0;
      _heightFeetController = TextEditingController(
        text: feet > 0 ? feet.toStringAsFixed(0) : '',
      );
      _heightInchController = TextEditingController(
        text: inches > 0 ? inches.round().toString() : '',
      );
      _heightCmController = TextEditingController();
    }
    _weightController = TextEditingController(
      text: widget.data['weight'] != null
          ? double.tryParse(
                  widget.data['weight'].toString(),
                )?.toStringAsFixed(2) ??
                ''
          : '',
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    String dobStr = _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : '';
    double? height;
    if (_isMetric) {
      height = double.tryParse(_heightCmController.text);
      if (height != null) height = double.parse(height.toStringAsFixed(2));
    } else {
      int feet = int.tryParse(_heightFeetController.text) ?? 0;
      int inches = int.tryParse(_heightInchController.text) ?? 0;
      if (inches > 11) inches = 11;
      height = feet + (inches / 12);
      height = double.parse(height.toStringAsFixed(2));
    }
    double? weight = double.tryParse(_weightController.text);
    if (weight != null) weight = double.parse(weight.toStringAsFixed(2));

    // Prepare merged data with recalculated calories/macros
    Map<String, dynamic> updateData = {
      'name': _nameController.text.trim(),
      'dateOfBirth': dobStr,
      'isMetric': _isMetric,
      'weight': weight,
      'isWeightMetric': _isWeightMetric,
    };
    if (height != null && (height != _originalHeight)) {
      updateData['height'] = height;
    }

    try {
      // Merge with existing server data to compute accurate recalculations
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final current = doc.data() ?? {};

      // Build inputs for recalculation using updated values where present
      final String gender = (current['gender'] ?? 'Male').toString();
      final String mainGoal = (current['mainGoal'] ?? 'Maintain weight')
          .toString();
      final String pace = (current['pace'] ?? 'Steady').toString();
      final String dietType = (current['dietType'] ?? 'Balanced').toString();
      final String proteinIntake =
          (current['proteinIntake'] ?? 'Moderate Intake').toString();
      final String trainingType =
          (current['trainingType'] ?? 'None or Related Activity').toString();

      // Height and weight units: height is cm if isMetric, or feet-decimal if not; weight is in kg if isWeightMetric, else lbs
      final bool isWeightMetric = _isWeightMetric;
      final double heightVal =
          (height ??
                  (double.tryParse(current['height']?.toString() ?? '') ?? 170))
              .toDouble();
      final double weightVal =
          (weight ??
                  (double.tryParse(current['weight']?.toString() ?? '') ?? 70))
              .toDouble();

      // Age calculation from DOB
      int age = 30;
      try {
        if (dobStr.isNotEmpty) {
          final d = DateTime.parse(dobStr);
          age = calculateAge(d);
        } else if ((current['dateOfBirth'] ?? '').toString().isNotEmpty) {
          final d = DateTime.parse((current['dateOfBirth']).toString());
          age = calculateAge(d);
        }
      } catch (_) {}

      // BMR and TDEE
      final double bmr = calculateBMR(
        gender: gender,
        weight: weightVal,
        height: heightVal,
        age: age,
        isMetric: isWeightMetric,
      );
      final double activity = getActivityFactor(trainingType);
      final double tdee = bmr * activity;
      final double goalAdj = getGoalAdjustment(mainGoal, pace, isWeightMetric);
      double calories = tdee + goalAdj;
      if (calories < 1200) calories = 1200;

      // Macro percents and grams
      final macroPercents = getMacroPercents(dietType, proteinIntake);
      final int carbG = (calories * macroPercents['carb']! / 4).round();
      final int proteinG = (calories * macroPercents['protein']! / 4).round();
      final int fatG = (calories * macroPercents['fat']! / 9).round();

      updateData.addAll({
        'calories': calories.round(),
        'carbG': carbG,
        'proteinG': proteinG,
        'fatG': fatG,
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(updateData);
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    DateTime initialDate = _dob ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Personal Info'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _editField(
                      label: 'Name',
                      controller: _nameController,
                      icon: Icons.person,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _editDateField(
                      label: 'Date of Birth',
                      value: _dob != null
                          ? DateFormat('d MMM yyyy').format(_dob!)
                          : '',
                      icon: Icons.cake,
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 16),
                    // Height field in user's chosen unit, realistic input
                    if (_isMetric)
                      _editField(
                        label: 'Height (cm)',
                        controller: _heightCmController,
                        icon: Icons.height,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          double? val = double.tryParse(v ?? '');
                          if (val == null || val < 50 || val > 300)
                            return 'Enter realistic height in cm';
                          return null;
                        },
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _editField(
                              label: 'Feet',
                              controller: _heightFeetController,
                              icon: Icons.height,
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                int? val = int.tryParse(v ?? '');
                                if (val == null || val < 3 || val > 8)
                                  return 'Feet (3-8)';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _editField(
                              label: 'Inches',
                              controller: _heightInchController,
                              icon: Icons.height,
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                int? val = int.tryParse(v ?? '');
                                if (val == null || val < 0 || val > 11)
                                  return 'Inches (0-11)';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    // Weight field in user's chosen unit, no toggle
                    _editField(
                      label: _isWeightMetric ? 'Weight (kg)' : 'Weight (lbs)',
                      controller: _weightController,
                      icon: Icons.monitor_weight,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
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
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text(
                          'Save',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _editField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _editDateField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.green),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
        child: Text(
          value.isNotEmpty ? value : 'Select date',
          style: TextStyle(
            fontSize: 16,
            color: value.isNotEmpty ? Colors.black87 : Colors.black38,
          ),
        ),
      ),
    );
  }
}

class MyGoalsPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const MyGoalsPage({Key? key, required this.data}) : super(key: key);

  @override
  State<MyGoalsPage> createState() => _MyGoalsPageState();
}

class _MyGoalsPageState extends State<MyGoalsPage> {
  late Map<String, dynamic> userData;

  @override
  void initState() {
    super.initState();
    userData = Map<String, dynamic>.from(widget.data);
  }

  Future<void> _editGoal(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditGoalSheet(data: userData),
    );
    if (result != null) {
      setState(() {
        userData = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String mainGoal = userData['mainGoal'] ?? 'Not set';
    double? targetWeight = userData['targetWeight'] != null
        ? double.tryParse(userData['targetWeight'].toString())
        : null;
    double? currentWeight = userData['weight'] != null
        ? double.tryParse(userData['weight'].toString())
        : null;
    bool isMetric = userData['isWeightMetric'] == true;
    String pace = userData['pace'] ?? '';
    double diff = 0;
    String progressText = '';
    String timelineText = '';

    if (mainGoal == 'Gain weight' &&
        targetWeight != null &&
        currentWeight != null) {
      diff = targetWeight - currentWeight;
      if (diff > 0) {
        progressText =
            'You need to gain ${diff.toStringAsFixed(1)} ${isMetric ? 'kg' : 'lbs'}';
      }
    } else if (mainGoal == 'Lose weight' &&
        targetWeight != null &&
        currentWeight != null) {
      diff = currentWeight - targetWeight;
      if (diff > 0) {
        progressText =
            'You need to lose ${diff.toStringAsFixed(1)} ${isMetric ? 'kg' : 'lbs'}';
      }
    }

    // Calculate estimated timeline
    if (diff > 0 && pace.isNotEmpty) {
      Map<String, double> paceWeeks = {
        'Relaxed': 0.125,
        'Steady': 0.25,
        'Accelerated': 0.5,
        'Intense': 1,
      };
      double weeklyRate = paceWeeks[pace] ?? 0.25;
      int estimatedWeeks = (diff / weeklyRate).ceil();
      if (estimatedWeeks < 4) {
        timelineText = 'Estimated: ${estimatedWeeks} weeks';
      } else if (estimatedWeeks < 52) {
        int months = (estimatedWeeks / 4.33).ceil();
        timelineText = 'Estimated: $months months';
      } else {
        int years = (estimatedWeeks / 52).ceil();
        timelineText = 'Estimated: $years year${years > 1 ? 's' : ''}';
      }
    }

    String targetWeightStr = targetWeight != null
        ? (isMetric
              ? '${targetWeight.toStringAsFixed(1)} kg'
              : '${targetWeight.toStringAsFixed(1)} lbs')
        : 'Not set';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('My Goals'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Goal',
            onPressed: () => _editGoal(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.flag, color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Your Goal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    mainGoal.isNotEmpty ? mainGoal : 'No goal set yet',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (progressText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      progressText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Goal Details Cards
            if (mainGoal == 'Gain weight' || mainGoal == 'Lose weight') ...[
              _goalCard(
                icon: Icons.track_changes,
                title: 'Target Weight',
                value: targetWeightStr,
                subtitle: 'Your ideal weight goal',
                color: Colors.blue,
              ),
              const SizedBox(height: 16),

              if (pace.isNotEmpty) ...[
                _goalCard(
                  icon: Icons.speed,
                  title: 'Pace',
                  value: _getPaceDescription(pace),
                  subtitle: _getPaceExplanation(pace),
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
              ],

              if (timelineText.isNotEmpty) ...[
                _goalCard(
                  icon: Icons.schedule,
                  title: 'Timeline',
                  value: timelineText,
                  subtitle: 'Based on your chosen pace',
                  color: Colors.purple,
                ),
                const SizedBox(height: 16),
              ],
            ] else if (mainGoal == 'Maintain weight') ...[
              _goalCard(
                icon: Icons.straighten,
                title: 'Maintenance Goal',
                value: 'Keep current weight',
                subtitle: 'Focus on maintaining your current weight',
                color: Colors.teal,
              ),
            ],

            const SizedBox(height: 32),

            // Tips Section
            _tipsSection(mainGoal),
          ],
        ),
      ),
    );
  }

  Widget _goalCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipsSection(String mainGoal) {
    List<String> tips = [];
    IconData tipIcon = Icons.lightbulb_outline;

    switch (mainGoal) {
      case 'Lose weight':
        tips = [
          'Create a moderate calorie deficit through diet and exercise',
          'Focus on whole foods: vegetables, lean proteins, and whole grains',
          'Stay hydrated and get adequate sleep',
          'Be patient - healthy weight loss is 1-2 pounds per week',
        ];
        break;
      case 'Gain weight':
        tips = [
          'Eat in a slight calorie surplus with nutrient-dense foods',
          'Include protein-rich foods at every meal',
          'Add strength training to build muscle mass',
          'Be consistent - healthy weight gain takes time',
        ];
        break;
      case 'Maintain weight':
        tips = [
          'Balance your calories in vs calories out',
          'Continue regular physical activity',
          'Monitor your weight weekly, not daily',
          'Focus on building healthy habits long-term',
        ];
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(tipIcon, color: Colors.amber.shade700, size: 24),
              const SizedBox(width: 12),
              Text(
                'Tips for Success',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...tips
              .map(
                (tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade600,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tip,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  String _getPaceDescription(String pace) {
    switch (pace) {
      case 'Relaxed':
        return 'Slow & Steady';
      case 'Steady':
        return 'Moderate Pace';
      case 'Accelerated':
        return 'Active Pace';
      case 'Intense':
        return 'Fast Track';
      default:
        return pace;
    }
  }

  String _getPaceExplanation(String pace) {
    switch (pace) {
      case 'Relaxed':
        return 'Small changes, sustainable approach';
      case 'Steady':
        return 'Balanced progress with good habits';
      case 'Accelerated':
        return 'More focused effort required';
      case 'Intense':
        return 'Requires dedication and discipline';
      default:
        return '';
    }
  }
}

class MyPlansPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const MyPlansPage({Key? key, required this.data}) : super(key: key);

  @override
  State<MyPlansPage> createState() => _MyPlansPageState();
}

class _MyPlansPageState extends State<MyPlansPage> {
  late Map<String, dynamic> userData;

  @override
  void initState() {
    super.initState();
    userData = Map<String, dynamic>.from(widget.data);
  }

  Future<void> _editPlan(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditPlanSheet(data: userData),
    );
    if (result != null) {
      setState(() {
        userData = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dietType = userData['dietType'] ?? 'Balanced';
    final trainingType = userData['trainingType'] ?? 'None or Related Activity';
    final proteinIntake = userData['proteinIntake'] ?? 'Moderate Intake';
    final calories = userData['calories']?.toString() ?? '0';
    final carbsTarget = userData['carbG']?.toString() ?? '0';
    final proteinTarget = userData['proteinG']?.toString() ?? '0';
    final fatTarget = userData['fatG']?.toString() ?? '0';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('My Plans'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Plan',
            onPressed: () => _editPlan(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Daily Calories Card
            _planCard(
              icon: Icons.local_fire_department,
              title: 'Daily Calories',
              value: '$calories kcal',
              subtitle: 'Your target daily energy intake',
              color: Colors.red,
              explanation: _getCalorieExplanation(calories),
            ),

            const SizedBox(height: 16),

            // Macronutrients Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.pie_chart,
                          color: Colors.purple,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Macronutrients',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Your daily breakdown',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _macroItem(
                          'Carbs',
                          carbsTarget,
                          Colors.orange,
                          'Energy source',
                        ),
                      ),
                      Expanded(
                        child: _macroItem(
                          'Protein',
                          proteinTarget,
                          Colors.blue,
                          'Muscle building',
                        ),
                      ),
                      Expanded(
                        child: _macroItem(
                          'Fat',
                          fatTarget,
                          Colors.green,
                          'Essential nutrients',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Tip: These are daily targets. Don\'t worry about hitting them exactly - aim to get close over time!',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Diet Type Card
            _planCard(
              icon: Icons.restaurant,
              title: 'Diet Approach',
              value: dietType,
              subtitle: _getDietDescription(dietType),
              color: Colors.teal,
              explanation: _getDietExplanation(dietType),
            ),

            const SizedBox(height: 16),

            // Training Type Card
            _planCard(
              icon: Icons.fitness_center,
              title: 'Training Focus',
              value: trainingType,
              subtitle: _getTrainingDescription(trainingType),
              color: Colors.indigo,
              explanation: _getTrainingExplanation(trainingType),
            ),

            const SizedBox(height: 16),

            // Protein Intake Card
            _planCard(
              icon: Icons.egg_alt,
              title: 'Protein Strategy',
              value: proteinIntake,
              subtitle: _getProteinDescription(proteinIntake),
              color: Colors.amber,
              explanation: _getProteinExplanation(proteinIntake),
            ),

            const SizedBox(height: 32),

            // Success Tips Section
            _successTipsSection(),
          ],
        ),
      ),
    );
  }

  Widget _planCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    String? explanation,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (explanation != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                explanation,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _macroItem(
    String name,
    String value,
    Color color,
    String description,
  ) {
    return Column(
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${value}g',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _successTipsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates,
                color: Colors.green.shade700,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Success Tips',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _tipItem('Start small and build habits gradually'),
          _tipItem(
            'Track your progress but don\'t obsess over daily fluctuations',
          ),
          _tipItem('Focus on whole, unprocessed foods when possible'),
          _tipItem('Stay hydrated - aim for 8 glasses of water daily'),
          _tipItem('Be patient and consistent - results take time'),
        ],
      ),
    );
  }

  Widget _tipItem(String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for descriptions and explanations
  String _getCalorieExplanation(String calories) {
    return 'This is your daily calorie target based on your goals, activity level, and body composition. It includes the right balance to help you reach your weight goal safely.';
  }

  String _getDietDescription(String dietType) {
    switch (dietType) {
      case 'Balanced':
        return 'All food groups included';
      case 'Low-fat':
        return 'Reduced fat, higher carbs';
      case 'Low-carb':
        return 'Reduced carbs, higher protein';
      case 'Keto':
        return 'Very low carb, high fat';
      default:
        return '';
    }
  }

  String _getDietExplanation(String dietType) {
    switch (dietType) {
      case 'Balanced':
        return 'A well-rounded approach that includes all macronutrients in moderate proportions. This is sustainable long-term and provides all essential nutrients.';
      case 'Low-fat':
        return 'Focuses on reducing fat intake while emphasizing carbohydrates and protein. Good for those who prefer higher carb foods and want to reduce calorie density.';
      case 'Low-carb':
        return 'Reduces carbohydrate intake while increasing protein and fat. Can help with appetite control and may improve blood sugar levels.';
      case 'Keto':
        return 'Very low carbohydrate (under 50g), moderate protein, high fat. Puts body into ketosis for fat burning. Requires careful planning and monitoring.';
      default:
        return '';
    }
  }

  String _getTrainingDescription(String trainingType) {
    switch (trainingType) {
      case 'None or Related Activity':
        return 'Light daily activities';
      case 'Lifting':
        return 'Strength training focus';
      case 'Cardio':
        return 'Aerobic exercise focus';
      case 'Cardio and Lifting':
        return 'Mixed training approach';
      default:
        return '';
    }
  }

  String _getTrainingExplanation(String trainingType) {
    switch (trainingType) {
      case 'None or Related Activity':
        return 'Your plan accounts for basic daily activities. Consider adding light exercise like walking as you progress.';
      case 'Lifting':
        return 'Strength training helps build and maintain muscle mass. Your nutrition plan supports muscle growth and recovery.';
      case 'Cardio':
        return 'Cardiovascular exercise improves heart health and burns calories. Your nutrition supports endurance and recovery.';
      case 'Cardio and Lifting':
        return 'The best of both worlds! Your nutrition plan balances the needs for both muscle building and cardiovascular performance.';
      default:
        return '';
    }
  }

  String _getProteinDescription(String proteinIntake) {
    switch (proteinIntake) {
      case 'Low Intake':
        return 'Basic protein needs';
      case 'Moderate Intake':
        return 'Standard protein target';
      case 'High Intake':
        return 'Elevated protein focus';
      case 'Very High Intake':
        return 'Maximum protein emphasis';
      default:
        return '';
    }
  }

  String _getProteinExplanation(String proteinIntake) {
    switch (proteinIntake) {
      case 'Low Intake':
        return 'Meets basic protein requirements for general health. Good for those with lower activity levels or specific dietary preferences.';
      case 'Moderate Intake':
        return 'Balanced protein intake that supports muscle maintenance and general health. Suitable for most people and activity levels.';
      case 'High Intake':
        return 'Elevated protein to support muscle building, recovery, and appetite control. Great for active individuals and strength training.';
      case 'Very High Intake':
        return 'Maximum protein focus for serious muscle building or aggressive fat loss. Requires careful meal planning and may need supplementation.';
      default:
        return '';
    }
  }
}

// --- Utility for BMR, TDEE, Calories, Macros ---
int calculateAge(DateTime dob) {
  final now = DateTime.now();
  int age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age;
}

double calculateBMR({
  required String gender,
  required double weight,
  required double height,
  required int age,
  required bool isMetric,
}) {
  // Convert to metric if needed
  double w = isMetric ? weight : weight * 0.453592;
  double h;
  if (isMetric) {
    h = height; // already in cm
  } else {
    // height is in feet (possibly with decimals), convert to inches then cm
    h = height * 30.48; // 1 foot = 30.48 cm
  }
  if (gender == 'Male') {
    return 88.362 + (13.397 * w) + (4.799 * h) - (5.677 * age);
  } else {
    return 447.593 + (9.247 * w) + (3.098 * h) - (4.330 * age);
  }
}

double getActivityFactor(String trainingType) {
  switch (trainingType) {
    case 'Lifting':
      return 1.55;
    case 'Cardio':
      return 1.375;
    case 'Cardio and Lifting':
      return 1.725;
    case 'None or Related Activity':
    default:
      return 1.2;
  }
}

double getGoalAdjustment(String mainGoal, String pace, bool isMetric) {
  // Returns kcal/day adjustment
  // 1 kg fat = ~7700 kcal, 1 lb = ~3500 kcal
  double perWeek = 0;
  if (pace == 'Relaxed') perWeek = isMetric ? 0.125 : 0.25;
  if (pace == 'Steady') perWeek = isMetric ? 0.25 : 0.5;
  if (pace == 'Accelerated') perWeek = isMetric ? 0.5 : 1.0;
  if (pace == 'Intense') perWeek = isMetric ? 1.0 : 2.0;
  double kcalPerUnit = isMetric ? 7700 : 3500;
  double kcalPerDay = perWeek * kcalPerUnit / 7.0;
  if (mainGoal == 'Lose weight') return -kcalPerDay;
  if (mainGoal == 'Gain weight') return kcalPerDay;
  return 0;
}

Map<String, double> getMacroPercents(String dietType, String proteinIntake) {
  // Returns {carb, protein, fat}
  double carb = 0.5, protein = 0.25, fat = 0.25;
  if (dietType == 'Low-fat') {
    carb = 0.55;
    protein = 0.25;
    fat = 0.20;
  } else if (dietType == 'Low-carb') {
    carb = 0.25;
    protein = 0.35;
    fat = 0.40;
  } else if (dietType == 'Keto') {
    carb = 0.05;
    protein = 0.20;
    fat = 0.75;
  }
  if (proteinIntake == 'High Intake') protein += 0.05;
  if (proteinIntake == 'Very High Intake') protein += 0.10;
  // Normalize if sum > 1
  double sum = carb + protein + fat;
  if (sum > 1.0) {
    carb /= sum;
    protein /= sum;
    fat /= sum;
  }
  return {'carb': carb, 'protein': protein, 'fat': fat};
}

// --- Edit Goal Sheet ---
class _EditGoalSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  const _EditGoalSheet({required this.data});

  @override
  State<_EditGoalSheet> createState() => _EditGoalSheetState();
}

class _EditGoalSheetState extends State<_EditGoalSheet> {
  late String mainGoal;
  late String pace;
  late bool isMetric;
  late TextEditingController targetWeightController;
  double? currentWeight;

  final List<String> mainGoals = [
    'Lose weight',
    'Gain weight',
    'Maintain weight',
  ];
  final List<String> paces = ['Relaxed', 'Steady', 'Accelerated', 'Intense'];
  String? _validationMessage;

  // Updated pace descriptions to handle both kg and lbs
  Map<String, String> get paceDescriptions {
    if (isMetric) {
      return {
        'Relaxed': 'Relaxed: Very slow, gentle changes (approx. 0.125 kg/week)',
        'Steady': 'Steady: Moderate, sustainable pace (approx. 0.25 kg/week)',
        'Accelerated':
            'Accelerated: Fast, requires focus (approx. 0.5 kg/week)',
        'Intense': 'Intense: Very fast, aggressive changes (approx. 1 kg/week)',
      };
    } else {
      return {
        'Relaxed': 'Relaxed: Very slow, gentle changes (approx. 0.25 lbs/week)',
        'Steady': 'Steady: Moderate, sustainable pace (approx. 0.5 lbs/week)',
        'Accelerated': 'Accelerated: Fast, requires focus (approx. 1 lbs/week)',
        'Intense':
            'Intense: Very fast, aggressive changes (approx. 2 lbs/week)',
      };
    }
  }

  @override
  void initState() {
    super.initState();
    mainGoal = widget.data['mainGoal'] ?? 'Maintain weight';
    pace = widget.data['pace'] ?? 'Steady';
    isMetric = widget.data['isWeightMetric'] == true;
    currentWeight = widget.data['weight'] != null
        ? double.tryParse(widget.data['weight'].toString())
        : null;
    targetWeightController = TextEditingController(
      text: widget.data['targetWeight'] != null
          ? widget.data['targetWeight'].toString()
          : '',
    );
  }

  String? _validateTargetWeight() {
    double? targetWeight = double.tryParse(targetWeightController.text);
    if (mainGoal == 'Gain weight') {
      if (targetWeight == null) return 'Enter a valid target weight';
      if (currentWeight != null && targetWeight <= currentWeight!) {
        return 'Target weight must be greater than current weight (${currentWeight!.toStringAsFixed(1)} ${isMetric ? "kg" : "lbs"})';
      }
      if (targetWeight < 20 || targetWeight > 500)
        return 'Enter a realistic target weight';
    } else if (mainGoal == 'Lose weight') {
      if (targetWeight == null) return 'Enter a valid target weight';
      if (currentWeight != null && targetWeight >= currentWeight!) {
        return 'Target weight must be less than current weight (${currentWeight!.toStringAsFixed(1)} ${isMetric ? "kg" : "lbs"})';
      }
      if (targetWeight < 20 || targetWeight > 500)
        return 'Enter a realistic target weight';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _validationMessage = null;
    });
    double? targetWeight = double.tryParse(targetWeightController.text);
    String? validation = _validateTargetWeight();
    if ((mainGoal == 'Lose weight' || mainGoal == 'Gain weight') &&
        validation != null) {
      setState(() {
        _validationMessage = validation;
      });
      return;
    }

    // --- Get user info for calculation ---
    final gender = widget.data['gender'] ?? 'Male';
    final dobStr = widget.data['dateOfBirth'];
    final dob = dobStr != null ? DateTime.tryParse(dobStr) : null;
    final age = dob != null ? calculateAge(dob) : 30;
    final height = widget.data['height'] != null
        ? double.tryParse(widget.data['height'].toString()) ?? 170
        : 170;
    final weight = widget.data['weight'] != null
        ? double.tryParse(widget.data['weight'].toString()) ?? 70
        : 70;
    final isMetric = widget.data['isWeightMetric'] == true;
    final trainingType =
        widget.data['trainingType'] ?? 'None or Related Activity';
    final dietType = widget.data['dietType'] ?? 'Balanced';
    final proteinIntake = widget.data['proteinIntake'] ?? 'Moderate Intake';

    // --- Calculate BMR, TDEE, Calories ---
    double bmr = calculateBMR(
      gender: gender,
      weight: weight.toDouble(),
      height: height.toDouble(),
      age: age,
      isMetric: isMetric,
    );
    double activity = getActivityFactor(trainingType);
    double tdee = bmr * activity;
    double goalAdj = getGoalAdjustment(mainGoal, pace, isMetric);
    double calories = tdee + goalAdj;

    // --- Macro calculation ---
    final macroPercents = getMacroPercents(dietType, proteinIntake);
    int carbG = (calories * macroPercents['carb']! / 4).round();
    int proteinG = (calories * macroPercents['protein']! / 4).round();
    int fatG = (calories * macroPercents['fat']! / 9).round();

    // Prepare update map
    Map<String, dynamic> update = {
      'mainGoal': mainGoal,
      'pace': pace,
      'calories': calories.round(),
      'carbG': carbG,
      'proteinG': proteinG,
      'fatG': fatG,
    };
    if (mainGoal == 'Lose weight' || mainGoal == 'Gain weight') {
      update['targetWeight'] = targetWeight;
    } else {
      update['targetWeight'] = null;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(update);
    }

    Navigator.of(context).pop({...widget.data, ...update});
  }

  @override
  Widget build(BuildContext context) {
    String infoMsg = '';
    if (mainGoal == 'Gain weight') {
      infoMsg = currentWeight != null
          ? 'Your target weight must be greater than your current weight (${currentWeight!.toStringAsFixed(1)} ${isMetric ? "kg" : "lbs"}).'
          : '';
    } else if (mainGoal == 'Lose weight') {
      infoMsg = currentWeight != null
          ? 'Your target weight must be less than your current weight (${currentWeight!.toStringAsFixed(1)} ${isMetric ? "kg" : "lbs"}).'
          : '';
    } else if (mainGoal == 'Maintain weight') {
      infoMsg = 'No target weight required for maintenance.';
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        // <-- fix: wrap with scroll view to prevent overflow
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Edit Goal',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: mainGoal,
              items: mainGoals
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  mainGoal = v!;
                  if (mainGoal == 'Maintain weight') {
                    targetWeightController.text = '';
                  }
                  _validationMessage = null;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Main Goal',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (mainGoal == 'Lose weight' || mainGoal == 'Gain weight')
              TextFormField(
                controller: targetWeightController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isMetric
                      ? 'Target Weight (kg)'
                      : 'Target Weight (lbs)',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {
                    _validationMessage = null;
                  });
                },
              ),
            if (mainGoal == 'Lose weight' || mainGoal == 'Gain weight')
              const SizedBox(height: 8),
            if (infoMsg.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        infoMsg,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_validationMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _validationMessage!,
                        style: const TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            DropdownButtonFormField<String>(
              value: pace,
              items: paces
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => pace = v!),
              decoration: const InputDecoration(
                labelText: 'Pace',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // Show pace descriptions (kg or lbs depending on user unit)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: paces
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            pace == p
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: pace == p ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              paceDescriptions[p]!,
                              style: TextStyle(
                                fontSize: 13,
                                color: pace == p
                                    ? Colors.green[800]
                                    : Colors.grey[700],
                                fontWeight: pace == p
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Edit Plan Sheet ---
class _EditPlanSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  const _EditPlanSheet({required this.data});

  @override
  State<_EditPlanSheet> createState() => _EditPlanSheetState();
}

class _EditPlanSheetState extends State<_EditPlanSheet> {
  late String dietType;
  late String trainingType;
  late String proteinIntake;
  bool _saving = false;

  final List<String> dietTypes = ['Balanced', 'Low-fat', 'Low-carb', 'Keto'];
  final List<String> trainingTypes = [
    'None or Related Activity',
    'Lifting',
    'Cardio',
    'Cardio and Lifting',
  ];
  final List<String> proteinIntakes = [
    'Low Intake',
    'Moderate Intake',
    'High Intake',
    'Very High Intake',
  ];

  @override
  void initState() {
    super.initState();
    dietType = widget.data['dietType'] ?? 'Balanced';
    trainingType = widget.data['trainingType'] ?? 'None or Related Activity';
    proteinIntake = widget.data['proteinIntake'] ?? 'Moderate Intake';
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // --- Get user info for calculation ---
    final gender = widget.data['gender'] ?? 'Male';
    final dobStr = widget.data['dateOfBirth'];
    final dob = dobStr != null ? DateTime.tryParse(dobStr) : null;
    final age = dob != null ? calculateAge(dob) : 30;
    final height = widget.data['height'] != null
        ? double.tryParse(widget.data['height'].toString()) ?? 170
        : 170;
    final weight = widget.data['weight'] != null
        ? double.tryParse(widget.data['weight'].toString()) ?? 70
        : 70;
    final isMetric = widget.data['isWeightMetric'] == true;
    final mainGoal = widget.data['mainGoal'] ?? 'Maintain weight';
    final pace = widget.data['pace'] ?? 'Steady';

    // --- Calculate BMR, TDEE, Calories ---
    double bmr = calculateBMR(
      gender: gender,
      weight: weight.toDouble(),
      height: height.toDouble(),
      age: age,
      isMetric: isMetric,
    );
    double activity = getActivityFactor(trainingType);
    double tdee = bmr * activity;
    double goalAdj = getGoalAdjustment(mainGoal, pace, isMetric);
    double calories = tdee + goalAdj;

    // --- Macro calculation ---
    final macroPercents = getMacroPercents(dietType, proteinIntake);
    int carbG = (calories * macroPercents['carb']! / 4).round();
    int proteinG = (calories * macroPercents['protein']! / 4).round();
    int fatG = (calories * macroPercents['fat']! / 9).round();

    // Save to Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid;
    Map<String, dynamic> update = {
      'dietType': dietType,
      'trainingType': trainingType,
      'proteinIntake': proteinIntake,
      'calories': calories.round(),
      'carbG': carbG,
      'proteinG': proteinG,
      'fatG': fatG,
    };
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(update);
    }

    setState(() => _saving = false);

    Navigator.of(context).pop({...widget.data, ...update});
  }

  String _dietApproachExplanation(String dietType) {
    switch (dietType) {
      case 'Balanced':
        return 'A well-rounded approach including all food groups and macronutrients in moderate proportions. Suitable for most people and sustainable long-term.';
      case 'Low-fat':
        return 'Focuses on reducing fat intake while emphasizing carbohydrates and protein. Good for those who prefer higher carb foods or want to reduce calorie density.';
      case 'Low-carb':
        return 'Reduces carbohydrate intake while increasing protein and fat. Can help with appetite control and may improve blood sugar levels.';
      case 'Keto':
        return 'Very low carbohydrate (under 50g), moderate protein, and high fat. Puts the body into ketosis for fat burning. Requires careful planning and monitoring.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Edit Plan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: dietType,
              items: dietTypes
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() => dietType = v!),
              decoration: const InputDecoration(
                labelText: 'Diet Approach',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            // Explanation for selected diet approach
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _dietApproachExplanation(dietType),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: trainingType,
              items: trainingTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => trainingType = v!),
              decoration: const InputDecoration(
                labelText: 'Training Focus',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: proteinIntake,
              items: proteinIntakes
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => proteinIntake = v!),
              decoration: const InputDecoration(
                labelText: 'Protein Strategy',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
