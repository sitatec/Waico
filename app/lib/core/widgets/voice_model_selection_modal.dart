import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/services/app_preferences.dart';
import 'package:waico/core/ai_models/tts_model.dart';
import 'package:waico/generated/locale_keys.g.dart';

class ModelSelectionModal extends StatefulWidget {
  final VoidCallback onContinue;

  const ModelSelectionModal({super.key, required this.onContinue});

  @override
  State<ModelSelectionModal> createState() => _ModelSelectionModalState();
}

class _ModelSelectionModalState extends State<ModelSelectionModal> {
  VoiceModelType _selectedVoiceModel = VoiceModelType.advanced;
  ChatModelType _selectedChatModel = ChatModelType.advanced;

  bool _isRecommended(dynamic type) {
    // TODO: Use device_info_plus to get more detailed info about the device
    return false;
  }

  void _onContinue() async {
    await AppPreferences.setVoiceModelType(_selectedVoiceModel);
    await AppPreferences.setChatModelType(_selectedChatModel);
    await AppPreferences.setHasShownDevicePerfSelection(true);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(LocaleKeys.ai_models_voice_model_selection_title.tr(), style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            LocaleKeys.ai_models_voice_model_selection_description.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          // Gemma Model Selection
          Text(LocaleKeys.ai_models_voice_model_selection_chat_model_title.tr(), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          // Gemma Models Preview Warning
          Text(
            LocaleKeys.ai_models_voice_model_selection_gemma_models_preview_warning.tr(),
            style: theme.textTheme.labelMedium?.copyWith(color: Colors.orangeAccent),
          ),
          const SizedBox(height: 12),
          // E4B Option
          _buildModelOption(
            type: ChatModelType.advanced,
            title: 'Gemma 3n E4B',
            description: LocaleKeys.ai_models_voice_model_selection_chat_model_advanced_description.tr(),
            performance: LocaleKeys.ai_models_voice_model_selection_chat_model_advanced_performance.tr(),
            icon: Icons.psychology,
            theme: theme,
          ),
          const SizedBox(height: 12),
          // E2B Option
          _buildModelOption(
            type: ChatModelType.lite,
            title: 'Gemma 3n E2B',
            description: LocaleKeys.ai_models_voice_model_selection_chat_model_lite_description.tr(),
            performance: LocaleKeys.ai_models_voice_model_selection_chat_model_lite_performance.tr(),
            icon: Icons.flash_on,
            theme: theme,
            iconSize: 18,
            titleTextHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false),
          ),
          const SizedBox(height: 24),

          // Voice Model Selection
          Text(LocaleKeys.ai_models_voice_model_selection_voice_model_title.tr(), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          // advanced Voice Option
          _buildModelOption(
            type: VoiceModelType.advanced,
            title: LocaleKeys.ai_models_voice_model_selection_advanced_title.tr(),
            description: LocaleKeys.ai_models_voice_model_selection_advanced_description.tr(),
            performance: LocaleKeys.ai_models_voice_model_selection_advanced_performance.tr(),
            icon: Icons.high_quality,
            theme: theme,
          ),
          const SizedBox(height: 12),
          // Lite Voice Option
          _buildModelOption(
            type: VoiceModelType.lite,
            title: LocaleKeys.ai_models_voice_model_selection_lite_title.tr(),
            description: LocaleKeys.ai_models_voice_model_selection_lite_description.tr(),
            performance: LocaleKeys.ai_models_voice_model_selection_lite_performance.tr(),
            icon: Icons.speed,
            iconSize: 20,
            theme: theme,
          ),
          const SizedBox(height: 24),
          // Continue Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                LocaleKeys.ai_models_voice_model_selection_continue.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelOption<T>({
    required T type,
    required String title,
    required String description,
    required String performance,
    required IconData icon,
    required ThemeData theme,
    double iconSize = 21,
    TextHeightBehavior? titleTextHeightBehavior,
  }) {
    final isSelected = type is VoiceModelType ? _selectedVoiceModel == type : _selectedChatModel == type;
    final isRecommendedModel = _isRecommended(type);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (type is VoiceModelType) {
            _selectedVoiceModel = type;
          } else if (type is ChatModelType) {
            _selectedChatModel = type;
          }
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.05) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  size: iconSize,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                      fontSize: 14.5,
                    ),
                    textHeightBehavior: titleTextHeightBehavior,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
            if (isRecommendedModel) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  LocaleKeys.ai_models_voice_model_selection_recommendation.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700, fontWeight: FontWeight.w500),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              performance,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.blueGrey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
