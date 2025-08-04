import 'package:flutter/widgets.dart';

extension LocalizationUtils on Locale {
  String get languageName => switch (languageCode) {
    'en' => 'English',
    'es' => 'Spanish',
    'fr' => 'French',
    'de' => 'German',
    _ => languageCode.toUpperCase(),
  };

  String get localizedLanguageName {
    return switch (languageCode) {
      'en' => 'English',
      'es' => 'Español',
      'fr' => 'Français',
      'de' => 'Deutsch',
      _ => languageCode.toUpperCase(),
    };
  }
}
