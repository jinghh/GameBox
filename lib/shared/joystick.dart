 // Shared virtual joystick — 4-direction drag control.
 // Extracted from the tank game; reused by snake and bomberman.
 import 'dart:math' as math;
 import 'package:flutter/material.dart';
 
 /// Direction reported by the joystick.
 // ignore: constant_identifier_names
 enum JoyDir { up, down, left, right }
 
 /// Virtual joystick: press anywhere in the area to show a base circle,
 /// then drag to control 4 directions; release to return to neutral.
 class Joystick extends StatefulWidget {
   final ValueChanged<JoyDir?> onDir;
   final double baseRadius;
   final double deadZone;
   final double knobRadius;
   final Color? baseColor;
   final Color? strokeColor;
   final Color? knobColor;
 
   const Joystick({
     super.key,
     required this.onDir,
     this.baseRadius = 60,
     this.deadZone = 12,
     this.knobRadius = 24,
     this.baseColor,
     this.strokeColor,
     this.knobColor,
   });
 
   @override
   State<Joystick> createState() => _JoystickState();
 }
 
 class _JoystickState extends State<Joystick> {
   Offset? _origin;
   Offset? _knob;
 
   void _update(Offset o, {required bool isNew}) {
     final origin = isNew ? o : (_origin ?? o);
     final dx = o.dx - origin.dx;
     final dy = o.dy - origin.dy;
     final len2 = dx * dx + dy * dy;
     JoyDir? dir;
     Offset knob = origin;
     if (len2 >= widget.deadZone * widget.deadZone) {
       final len = math.sqrt(len2);
       final cl = len > widget.baseRadius ? widget.baseRadius / len : 1.0;
       knob = Offset(origin.dx + dx * cl, origin.dy + dy * cl);
       dir = dx.abs() > dy.abs()
           ? (dx > 0 ? JoyDir.right : JoyDir.left)
           : (dy > 0 ? JoyDir.down : JoyDir.up);
     }
     setState(() {
       _origin = origin;
       _knob = knob;
     });
     widget.onDir(dir);
   }
 
   void _reset() {
     setState(() {
       _origin = null;
       _knob = null;
     });
     widget.onDir(null);
   }
 
   @override
   Widget build(BuildContext context) {
     return GestureDetector(
       behavior: HitTestBehavior.translucent,
       onPanDown: (d) => _update(d.localPosition, isNew: true),
       onPanUpdate: (d) => _update(d.localPosition, isNew: false),
       onPanEnd: (_) => _reset(),
       onPanCancel: _reset,
       child: CustomPaint(
         painter: _JoystickPainter(
           _origin,
           _knob,
           baseRadius: widget.baseRadius,
           knobRadius: widget.knobRadius,
           baseColor: widget.baseColor,
           strokeColor: widget.strokeColor,
           knobColor: widget.knobColor,
         ),
         child: const SizedBox.expand(),
       ),
     );
   }
 }
 
 class _JoystickPainter extends CustomPainter {
   final Offset? origin;
   final Offset? knob;
   final double baseRadius;
   final double knobRadius;
   final Color? baseColor;
   final Color? strokeColor;
   final Color? knobColor;
 
   _JoystickPainter(
     this.origin,
     this.knob, {
     required this.baseRadius,
     required this.knobRadius,
     this.baseColor,
     this.strokeColor,
     this.knobColor,
   });
 
   @override
   void paint(Canvas canvas, Size size) {
     if (origin == null) return;
     canvas.drawCircle(
       origin!,
       baseRadius,
       Paint()..color = baseColor ?? const Color(0x22FFFFFF),
     );
     canvas.drawCircle(
       origin!,
       baseRadius,
       Paint()
         ..color = strokeColor ?? const Color(0x66FFFFFF)
         ..style = PaintingStyle.stroke
         ..strokeWidth = 2,
     );
     canvas.drawCircle(
       knob ?? origin!,
       knobRadius,
       Paint()..color = knobColor ?? const Color(0xCCFFFFFF),
     );
   }
 
   @override
   bool shouldRepaint(covariant _JoystickPainter oldDelegate) => true;
 }
