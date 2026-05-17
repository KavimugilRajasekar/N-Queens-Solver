import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import '../constants/colors.dart';

class FunkyLoaderDialog extends StatefulWidget {
  final String title;
  final List<String> statusSteps;
  final String cancelLabel;
  final Duration stepDuration;
  final Duration totalDuration;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final double rotationAngle;

  const FunkyLoaderDialog({
    super.key,
    required this.onComplete,
    required this.onCancel,
    this.title = "TRANSMITTING CO-OP...",
    this.statusSteps = const [
      "Weaving solvable board series...",
      "Lobby located! ",
      "Syncing puzzle blueprints... ",
      "Waiting for opponent to accept... ",
    ],
    this.cancelLabel = "CANCEL INVITE",
    this.stepDuration = const Duration(milliseconds: 1500),
    this.totalDuration = const Duration(seconds: 5),
    this.rotationAngle = -0.01,
  });

  @override
  State<FunkyLoaderDialog> createState() => _FunkyLoaderDialogState();
}

class _FunkyLoaderDialogState extends State<FunkyLoaderDialog> {
  late String _statusText;
  Timer? _statusTimer;
  Timer? _completeTimer;

  @override
  void initState() {
    super.initState();
    _statusText = widget.statusSteps.isNotEmpty ? widget.statusSteps.first : "Loading...";
    _startSimulation();
  }

  void _startSimulation() {
    int step = 0;
    if (widget.statusSteps.length > 1) {
      _statusTimer = Timer.periodic(widget.stepDuration, (timer) {
        step++;
        if (step < widget.statusSteps.length) {
          if (mounted) {
            setState(() {
              _statusText = widget.statusSteps[step];
            });
          }
        } else {
          _statusTimer?.cancel();
        }
      });
    }

    _completeTimer = Timer(widget.totalDuration, () {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _completeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Transform.rotate(
          angle: widget.rotationAngle,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: AppColors.navyBlue, width: 3.5),
              boxShadow: const [
                BoxShadow(color: AppColors.navyBlue, offset: Offset(8, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Funky header
                Text(
                  widget.title.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyBlue,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                // Float the cat animation organically directly on the notebook paper page!
                SizedBox(
                  width: 175,
                  height: 175,
                  child: Lottie.asset(
                    'assets/json/cat_playing.json',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),
                // Animated text status
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusText,
                    key: ValueKey(_statusText),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Comfortaa',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                // Cancel button
                GestureDetector(
                  onTap: widget.onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE), // soft pink
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.redAccent, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.redAccent, offset: Offset(3, 3)),
                      ],
                    ),
                    child: Text(
                      widget.cancelLabel.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'DynaPuff',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
