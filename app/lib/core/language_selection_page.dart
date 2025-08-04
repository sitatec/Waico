import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/core/services/app_preferences.dart';
import 'package:waico/core/widgets/language_selection_widget.dart';
import 'package:waico/generated/locale_keys.g.dart';

/// Page for selecting app language on first startup
class LanguageSelectionPage extends StatefulWidget {
  final VoidCallback? onComplete;

  const LanguageSelectionPage({super.key, this.onComplete});

  @override
  State<LanguageSelectionPage> createState() => _LanguageSelectionPageState();
}

class _LanguageSelectionPageState extends State<LanguageSelectionPage> {
  String selectedLanguageCode = 'en';

  @override
  void initState() {
    super.initState();
    selectedLanguageCode = AppPreferences.getLanguageCode();
  }

  void _onLanguageChanged(String languageCode) {
    setState(() {
      selectedLanguageCode = languageCode;
    });
  }

  Future<void> _continue() async {
    // Mark that language selection has been shown
    await AppPreferences.setHasShownLanguageSelection(true);

    if (widget.onComplete != null) {
      widget.onComplete!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              // Header
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App logo or icon (you can replace with actual logo)
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary),
                      child: const Icon(Icons.language, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      LocaleKeys.language_selection_title.tr(),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LocaleKeys.language_selection_subtitle.tr(),
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // Language selection
              Expanded(
                flex: 3,
                child: SingleChildScrollView(child: LanguageSelectionWidget(onLanguageChanged: _onLanguageChanged)),
              ),

              // Continue button
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _continue,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
