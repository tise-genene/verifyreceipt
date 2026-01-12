import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';

class VerifyReceiptApp extends StatelessWidget {
  const VerifyReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VerifyReceipt',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
