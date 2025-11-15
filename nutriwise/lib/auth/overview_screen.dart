import 'package:flutter/material.dart';
import '../auth/signup_screen.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({Key? key}) : super(key: key);

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _iconAnimationController;
  late AnimationController _fadeAnimationController;
  late Animation<double> _iconAnimation;
  late Animation<double> _fadeAnimation;

  final List<_PageData> _pages = [
    _PageData(
      icon: Icons.fastfood,
      title: "Welcome to NutriWise",
      description:
          "Your personal nutrition assistant. Let's embark on a journey to better health together!",
      gradient: [Color(0xFF4CAF50), Color(0xFF81C784), Color(0xFFA5D6A7)],
    ),
    _PageData(
      icon: Icons.analytics,
      title: "Track Your Nutrition",
      description:
          "Log your meals and track calories, macros, and micronutrients with an easy-to-use food diary.",
      gradient: [Color(0xFF2196F3), Color(0xFF64B5F6), Color(0xFF90CAF9)],
    ),
    _PageData(
      icon: Icons.fitness_center,
      title: "Achieve Your Goals",
      description:
          "Stay motivated with progress tracking and reminders designed to help you reach your fitness and health objectives.",
      gradient: [Color(0xFFFF9800), Color(0xFFFFB74D), Color(0xFFFFCC80)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _fadeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _iconAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _iconAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeAnimationController, curve: Curves.easeIn),
    );

    _fadeAnimationController.forward();
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    _fadeAnimationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SignupScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentGradient = _pages[_currentPage].gradient;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              currentGradient[0].withOpacity(0.1),
              currentGradient[1].withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Decorative background circles
              Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        currentGradient[0].withOpacity(0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -150,
                left: -150,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        currentGradient[2].withOpacity(0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentPage = index;
                        });
                        _fadeAnimationController.reset();
                        _fadeAnimationController.forward();
                      },
                      itemBuilder: (context, index) {
                        final page = _pages[index];
                        return FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Animated Icon/Logo Container
                                AnimatedBuilder(
                                  animation: _iconAnimation,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _iconAnimation.value,
                                      child: index == 0
                                          ? // Logo for first page
                                            Container(
                                              width: 200,
                                              height: 200,
                                              decoration: BoxDecoration(
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: page.gradient[0]
                                                        .withOpacity(0.3),
                                                    blurRadius: 30,
                                                    spreadRadius: 5,
                                                    offset: const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              padding: const EdgeInsets.all(20),
                                              child: Image.asset(
                                                'assets/logo2.png',
                                                fit: BoxFit.contain,
                                              ),
                                            )
                                          : // Icon for other pages
                                            Container(
                                              width: 180,
                                              height: 180,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: page.gradient,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: page.gradient[0]
                                                        .withOpacity(0.4),
                                                    blurRadius: 30,
                                                    spreadRadius: 5,
                                                    offset: const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                page.icon,
                                                size: 100,
                                                color: Colors.white,
                                              ),
                                            ),
                                    );
                                  },
                                ),

                                const SizedBox(height: 60),

                                // Title with gradient text effect
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: page.gradient,
                                  ).createShader(bounds),
                                  child: Text(
                                    page.title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Description
                                Text(
                                  page.description,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: Colors.grey[700],
                                    height: 1.6,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Animated Dots indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: _currentPage == index ? 32 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          gradient: _currentPage == index
                              ? LinearGradient(
                                  colors: _pages[_currentPage].gradient,
                                )
                              : null,
                          color: _currentPage == index
                              ? null
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: _currentPage == index
                              ? [
                                  BoxShadow(
                                    color: _pages[_currentPage].gradient[0]
                                        .withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Next / Get Started button with gradient
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: currentGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: currentGradient[0].withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _nextPage,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _currentPage == _pages.length - 1
                                      ? "Get Started"
                                      : "Next",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                                if (_currentPage < _pages.length - 1) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ] else ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 50),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradient;

  _PageData({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
  });
}
