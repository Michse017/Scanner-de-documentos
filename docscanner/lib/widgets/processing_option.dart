import 'package:flutter/material.dart';

class ProcessingOption extends StatelessWidget {
  final String title;
  final Widget widget;

  const ProcessingOption({
    super.key,
    required this.title,
    required this.widget,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(flex: 3, child: widget),
        ],
      ),
    );
  }
}
