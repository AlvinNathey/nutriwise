import 'package:flutter/material.dart';
import 'food/log_food.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onLogPressed;
  
  const BottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    required this.onLogPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Home Button
          Expanded(
            child: _buildNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              label: 'Home',
              isSelected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
          ),
          
          // Log Meal Button (Center - Elevated)
          Expanded(
            child: _buildCenterNavItem(
              icon: Icons.restaurant_outlined,
              activeIcon: Icons.restaurant,
              label: 'Log Meal',
              isSelected: currentIndex == 1,
              onTap: onLogPressed, // Only call the callback
            ),
          ),
          
          // More Button
          Expanded(
            child: _buildNavItem(
              icon: Icons.menu,
              activeIcon: Icons.menu,
              label: 'More',
              isSelected: currentIndex == 2,
              onTap: () => onTap(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? Colors.green : const Color.fromARGB(255, 0, 0, 0),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.green : const Color.fromARGB(255, 0, 0, 0),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          // Move the center button up
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: const Offset(0, -16), // Move up by 16 pixels
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.green : Colors.grey.shade100,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.green : Colors.grey.shade300,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    color: isSelected ? Colors.white : Colors.grey,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 0),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.green : const Color.fromARGB(255, 0, 0, 0),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}