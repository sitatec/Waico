import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:waico/app.dart';
import 'package:waico/core/services/database/db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.init();
  runApp(const App());
}
