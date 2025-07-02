import 'package:flutter/material.dart';
import 'package:waico/pages/ai_model_init_page.dart';
import 'package:waico/pages/home_page.dart';

void main() async {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Gemma 3n Chat',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: HomePage(),
  );
}
