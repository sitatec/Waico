import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:waico/app.dart';
import 'package:waico/core/services/database/db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set app-wide orientation to portrait only
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await DB.init();
  runApp(const App());
}
