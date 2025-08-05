import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/app.dart';
import 'package:waico/core/services/database/db.dart';
import 'package:waico/core/services/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EasyLocalization.ensureInitialized();

  // Set app-wide orientation to portrait only
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await DB.init();
  await AppPreferences.initialize();

  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en'), Locale('fr'), Locale('es')],
      path: 'assets/translations',
      fallbackLocale: Locale('en'),
      startLocale: Locale(AppPreferences.getLanguageCode()),
      child: const App(),
    ),
  );
}
