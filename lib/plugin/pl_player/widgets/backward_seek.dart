import 'dart:async';

import 'package:flutter/material.dart';

class BackwardSeekIndicator extends StatefulWidget {
  // final void Function(Duration) onChanged;
  final void Function(Duration) onSubmitted;
  const BackwardSeekIndicator({
    super.key,
    // required this.onChanged,
    required this.onSubmitted,
  });

  @override
  State<BackwardSeekIndicator> createState() => BackwardSeekIndicatorState();
}

class BackwardSeekIndicatorState extends State<BackwardSeekIndicator> {
  Duration value = const Duration(seconds: 10);

  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 400), () {
      widget.onSubmitted.call(value);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void increment() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 400), () {
      widget.onSubmitted.call(value);
    });
    // widget.onChanged.call(value);
    // 重复点击 快退秒数累加10
    setState(() {
      value += const Duration(seconds: 10);
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: const Color(0x44767676),
      onTap: increment,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0x88767676),
              Color(0x00767676),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.fast_rewind,
              size: 24.0,
              color: Colors.white,
            ),
            const SizedBox(height: 8.0),
            Text(
              '快退${value.inSeconds}秒',
              style: const TextStyle(
                fontSize: 12.0,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
