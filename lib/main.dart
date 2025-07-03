import 'package:flutter/material.dart';
import 'package:waico/pages/home_page.dart';

void main() async {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final defaultTheme = Theme.of(context);
    final primaryColor = Color(0xFF4B9B6E);
    return MaterialApp(
      title: 'Gemma 3n Chat',
      theme: defaultTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor).copyWith(primary: primaryColor),
        appBarTheme: defaultTheme.appBarTheme.copyWith(backgroundColor: primaryColor, foregroundColor: Colors.white),
      ),
      home: HomePage(),
    );
  }
}
