import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class EquipmentIllustration extends StatelessWidget {
  const EquipmentIllustration({super.key, required this.category});
  final int? category;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: category == 1
          ? CustomPaint(size: const Size(68, 68), painter: _TentPainter())
          : Icon(
              switch (category) {
                2 => Icons.bed_outlined,
                3 => Icons.backpack_outlined,
                _ => Icons.local_fire_department_outlined,
              },
              size: 68,
              color: AppTheme.forest,
            ),
    ),
  );
}

class _TentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outline = Paint()
      ..color = AppTheme.forest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final tent = Path()
      ..moveTo(w * .09, h * .86)
      ..lineTo(w * .5, h * .14)
      ..lineTo(w * .91, h * .86)
      ..close();
    canvas.drawPath(
      tent,
      Paint()..color = AppTheme.forest.withValues(alpha: .08),
    );
    canvas.drawPath(tent, outline);
    final door = Path()
      ..moveTo(w * .34, h * .86)
      ..lineTo(w * .5, h * .55)
      ..lineTo(w * .66, h * .86);
    canvas.drawPath(door, Paint()..color = Colors.white);
    canvas.drawPath(door, outline);
    canvas.drawLine(
      Offset(w * .03, h * .92),
      Offset(w * .97, h * .92),
      outline,
    );
  }

  @override
  bool shouldRepaint(covariant _TentPainter oldDelegate) => false;
}
