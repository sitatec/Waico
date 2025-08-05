import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/core/services/app_preferences.dart';
import 'package:waico/generated/locale_keys.g.dart';

/// Language model representing supported languages
class Language {
  final String code;
  final String name;
  final String nativeName;
  final String flag;

  const Language({required this.code, required this.name, required this.nativeName, required this.flag});
}

/// Widget for selecting app language
class LanguageSelectionWidget extends StatefulWidget {
  final Function(String languageCode)? onLanguageChanged;
  final bool showContinueButton;

  const LanguageSelectionWidget({super.key, this.onLanguageChanged, this.showContinueButton = false});

  @override
  State<LanguageSelectionWidget> createState() => _LanguageSelectionWidgetState();
}

class _LanguageSelectionWidgetState extends State<LanguageSelectionWidget> {
  static const List<Language> supportedLanguages = [
    Language(code: 'en', name: 'English', nativeName: 'English', flag: '🇺🇸'),
    Language(code: 'es', name: 'Spanish', nativeName: 'Español', flag: '🇪🇸'),
    Language(code: 'fr', name: 'French', nativeName: 'Français', flag: '🇫🇷'),
  ];

  String selectedLanguageCode = 'en';

  @override
  void initState() {
    super.initState();
    selectedLanguageCode = AppPreferences.getLanguageCode() ?? context.locale.languageCode;
  }

  Future<void> _changeLanguage(String languageCode) async {
    setState(() {
      selectedLanguageCode = languageCode;
    });

    // Save to preferences
    await AppPreferences.setLanguageCode(languageCode);

    // Change app locale
    if (mounted) {
      await context.setLocale(Locale(languageCode));
    }

    // Notify parent if callback provided
    widget.onLanguageChanged?.call(languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Language options
        ...supportedLanguages.map((language) => _buildLanguageOption(language)),

        if (widget.showContinueButton) ...[
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                LocaleKeys.language_selection_continue.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLanguageOption(Language language) {
    final isSelected = selectedLanguageCode == language.code;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _changeLanguage(language.code),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? theme.colorScheme.primary : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
            ),
            child: Row(
              children: [
                Text(language.flag, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language.nativeName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? theme.colorScheme.primary : Colors.black87,
                        ),
                      ),
                      Text(
                        language.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: isSelected ? theme.colorScheme.primary : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 24)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
