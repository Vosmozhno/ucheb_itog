import 'package:flutter/material.dart';

const rentalStatuses = {
  'reserved': 'Забронировано',
  'issued': 'Выдано',
  'returned': 'Возвращено',
  'cancelled': 'Отменено',
};
const unitStates = {
  'ready': 'Готов к аренде',
  'maintenance': 'На проверке',
  'retired': 'Списан',
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (value) {
      'ready' ||
      'returned' => (const Color(0xFF24543D), const Color(0xFFE3F0E6)),
      'reserved' => (const Color(0xFF344D81), const Color(0xFFE8EDF9)),
      'issued' ||
      'maintenance' => (const Color(0xFF805015), const Color(0xFFFFEECF)),
      _ => (const Color(0xFF59615B), const Color(0xFFEDF0EC)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        rentalStatuses[value] ?? unitStates[value] ?? value,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
