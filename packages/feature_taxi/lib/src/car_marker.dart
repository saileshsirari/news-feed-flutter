import 'package:flutter/material.dart';

/// The car on the ride map, seen from above and turned to face the way
/// it's driving, as Ola and Uber draw it. [headingDegrees] is a compass
/// bearing: 0 is north (up the map), 90 east.
///
/// Painted rather than an image, so it's sharp at any size and needs no
/// asset: a body, the windscreen at the front, the rear window, four
/// wheels and two headlights.
class CarMarker extends StatefulWidget {
  const CarMarker({super.key, this.headingDegrees = 0, this.size = 44, this.color = const Color(0xFF263238)});

  final double headingDegrees;
  final double size;
  final Color color;

  @override
  State<CarMarker> createState() => _CarMarkerState();
}

class _CarMarkerState extends State<CarMarker> {
  /// The angle drawn, not wrapped to 0..360, so a turn from 350° to 10°
  /// goes 20° clockwise (to 370°) rather than 340° the long way round.
  late double _turnedDegrees = widget.headingDegrees;

  @override
  void didUpdateWidget(CarMarker old) {
    super.didUpdateWidget(old);
    final shortest = ((widget.headingDegrees - _turnedDegrees) % 360 + 540) % 360 - 180;
    _turnedDegrees += shortest;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      // Turning smoothly to the new heading, not jumping.
      child: AnimatedRotation(
        turns: _turnedDegrees / 360,
        duration: const Duration(milliseconds: 400),
        child: CustomPaint(painter: _CarPainter(widget.color)),
      ),
    );
  }
}

class _CarPainter extends CustomPainter {
  _CarPainter(this.body);

  final Color body;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // The car is narrower than it is long: ~0.42 wide, ~0.86 long, nose up.
    final car = Rect.fromCenter(center: Offset(w / 2, h / 2), width: w * 0.42, height: h * 0.86);
    final r = Radius.circular(w * 0.12);

    // Shadow, so it stands out on any map.
    canvas.drawRRect(
      RRect.fromRectAndRadius(car.shift(Offset(0, h * 0.03)), r),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Wheels, peeking out at the sides.
    final wheel = Paint()..color = Colors.black;
    final ww = w * 0.07;
    final wh = h * 0.16;
    for (final y in [car.top + h * 0.12, car.bottom - h * 0.12 - wh]) {
      canvas.drawRRect(
        RRect.fromLTRBR(car.left - ww * 0.5, y, car.left + ww * 0.5, y + wh, Radius.circular(ww)),
        wheel,
      );
      canvas.drawRRect(
        RRect.fromLTRBR(car.right - ww * 0.5, y, car.right + ww * 0.5, y + wh, Radius.circular(ww)),
        wheel,
      );
    }

    // Body, with a thin white edge.
    final bodyShape = RRect.fromRectAndRadius(car, r);
    canvas.drawRRect(bodyShape, Paint()..color = body);
    canvas.drawRRect(
      bodyShape,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025,
    );

    final glass = Paint()..color = const Color(0xFFB3E5FC);
    // Windscreen (front, at the top) and rear window.
    final windscreen = Path()
      ..moveTo(car.left + car.width * 0.14, car.top + car.height * 0.24)
      ..lineTo(car.right - car.width * 0.14, car.top + car.height * 0.24)
      ..lineTo(car.right - car.width * 0.22, car.top + car.height * 0.36)
      ..lineTo(car.left + car.width * 0.22, car.top + car.height * 0.36)
      ..close();
    canvas.drawPath(windscreen, glass);
    canvas.drawRRect(
      RRect.fromLTRBR(
        car.left + car.width * 0.2,
        car.bottom - car.height * 0.2,
        car.right - car.width * 0.2,
        car.bottom - car.height * 0.12,
        Radius.circular(w * 0.03),
      ),
      glass,
    );

    // Headlights.
    final light = Paint()..color = const Color(0xFFFFF59D);
    canvas.drawCircle(Offset(car.left + car.width * 0.22, car.top + h * 0.04), w * 0.035, light);
    canvas.drawCircle(Offset(car.right - car.width * 0.22, car.top + h * 0.04), w * 0.035, light);
  }

  @override
  bool shouldRepaint(_CarPainter old) => old.body != body;
}
