import 'package:shared_preferences/shared_preferences.dart';
import 'package:waico/core/ai_models/chat_model.dart' show ChatModelType;
import 'package:waico/core/ai_models/tts_model.dart';

/// Service for managing app preferences using SharedPreferences
class AppPreferences {
  static const String _voiceModelTypeKey = 'voice_model_type';
  static const String _chatModelTypeKey = 'chat_model_type';
  static const String _hasShownDevicePerfSelectionKey = 'has_shown_device_performance_selection';
  static const String _languageCodeKey = 'language_code';
  static const String _hasShownLanguageSelectionKey = 'has_shown_language_selection';

  static SharedPreferences? _preferences;

  /// Initialize shared preferences
  static Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();
  }

  /// Ensure preferences are initialized
  static void _ensureInitialized() {
    if (_preferences == null) {
      throw StateError('AppPreferences not initialized. Call AppPreferences.initialize() first.');
    }
  }

  /// Get the selected voice model type
  static VoiceModelType getVoiceModelType() {
    _ensureInitialized();
    final value = _preferences!.getString(_voiceModelTypeKey);
    return value == 'lite' ? VoiceModelType.lite : VoiceModelType.advanced;
  }

  /// Set the selected voice model type
  static Future<void> setVoiceModelType(VoiceModelType type) async {
    _ensureInitialized();
    await _preferences!.setString(_voiceModelTypeKey, type == VoiceModelType.lite ? 'lite' : 'premium');
  }

  /// Get the selected Gemma model type
  static ChatModelType getChatModelType() {
    _ensureInitialized();
    final value = _preferences!.getString(_chatModelTypeKey);
    return value == 'lite' ? ChatModelType.lite : ChatModelType.advanced;
  }

  /// Set the selected Gemma model type
  static Future<void> setChatModelType(ChatModelType type) async {
    _ensureInitialized();
    await _preferences!.setString(_chatModelTypeKey, type == ChatModelType.lite ? 'lite' : 'advanced');
  }

  /// Check if voice model selection has been shown before
  static bool hasShownDevicePerfSelection() {
    _ensureInitialized();
    return _preferences!.getBool(_hasShownDevicePerfSelectionKey) ?? false;
  }

  /// Mark that voice model selection has been shown
  static Future<void> setHasShownDevicePerfSelection(bool value) async {
    _ensureInitialized();
    await _preferences!.setBool(_hasShownDevicePerfSelectionKey, value);
  }

  /// Get the selected language code (default: 'en')
  static String? getLanguageCode() {
    _ensureInitialized();
    return _preferences!.getString(_languageCodeKey);
  }

  /// Set the selected language code
  static Future<void> setLanguageCode(String languageCode) async {
    _ensureInitialized();
    await _preferences!.setString(_languageCodeKey, languageCode);
  }

  /// Check if language selection has been shown before
  static bool hasShownLanguageSelection() {
    _ensureInitialized();
    return _preferences!.getBool(_hasShownLanguageSelectionKey) ?? false;
  }

  /// Mark that language selection has been shown
  static Future<void> setHasShownLanguageSelection(bool value) async {
    _ensureInitialized();
    await _preferences!.setBool(_hasShownLanguageSelectionKey, value);
  }

  /// Clear all preferences (useful for testing/reset)
  static Future<void> clear() async {
    _ensureInitialized();
    await _preferences!.clear();
  }
}
