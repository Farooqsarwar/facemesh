import 'package:flutter/material.dart';

Widget buildConditionsPanel(
    bool areAllConditionsSatisfied,
    bool isCenter,
    bool isGoodSizee,
    bool goodPose,
    bool eyesOpen,
    ) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: areAllConditionsSatisfied ? Colors.green : Colors.grey,
        width: 2,
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildConditionIndicator("CENTER", isCenter),
        _buildConditionIndicator("DISTANCE", isGoodSizee),
        _buildConditionIndicator("POSE", goodPose),
        _buildConditionIndicator("EYES", eyesOpen),
      ],
    ),
  );
}

Widget _buildConditionIndicator(String label, bool isSatisfied) {
  return Column(
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: isSatisfied ? Colors.green : Colors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: isSatisfied ? Colors.green : Colors.red,
              blurRadius: 8,
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          color: isSatisfied ? Colors.green : Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}