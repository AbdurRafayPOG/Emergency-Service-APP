import 'package:flutter/material.dart';

class PremiumLoadingIndicator extends StatefulWidget {
  final double size;
  final Color color;

  const PremiumLoadingIndicator({
    Key? key,
    this.size = 60,
    this.color = Colors.white,
  }) : super(key: key);

  @override
  State<PremiumLoadingIndicator> createState() =>
      _PremiumLoadingIndicatorState();
}

class _PremiumLoadingIndicatorState extends State<PremiumLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      width: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer spinning circle
          RotationTransition(
            turns: _controller,
            child: Container(
              height: widget.size,
              width: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withOpacity(0.1),
                  width: 4,
                ),
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                strokeWidth: 4,
                backgroundColor: widget.color.withOpacity(0.1),
              ),
            ),
          ),
          
          // Inner pulsing dot
          ScaleTransition(
            scale: _controller.drive(
              Tween<double>(begin: 0.8, end: 1.2)
            ),
            child: Container(
              height: widget.size * 0.3,
              width: widget.size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
              child: Icon(
                Icons.emergency_rounded,
                color: const Color(0xFF0F4C5C),
                size: widget.size * 0.2,
              ),
            ),
          ),
          
          // Spinning dots around the circle
          ...List.generate(8, (index) {
            final angle = (index / 8) * 2 * 3.14159;
            return RotationTransition(
              turns: _controller,
              child: Transform.rotate(
                angle: angle,
                child: Transform.translate(
                  offset: Offset(0, -(widget.size / 2 - 2)),
                  child: Container(
                    height: widget.size * 0.1,
                    width: widget.size * 0.1,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}