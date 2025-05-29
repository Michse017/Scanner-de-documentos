import 'package:flutter/material.dart';

class ScanButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isSecondary;

  const ScanButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: isSecondary ? Colors.indigo : Colors.white),
        label: Text(
          label,
          style: TextStyle(
            color: isSecondary ? Colors.indigo : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSecondary ? Colors.white : Colors.indigo,
          foregroundColor: isSecondary ? Colors.indigo : Colors.white,
          elevation: isSecondary ? 0 : 2,
          side:
              isSecondary
                  ? const BorderSide(color: Colors.indigo, width: 2)
                  : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
