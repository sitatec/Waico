import 'package:shared_preferences/shared_preferences.dart';
import 'package:waico/core/ai_models/tts_model.dart';

/// Service for managing app preferences using SharedPreferences
class AppPreferences {
  static const String _voiceModelTypeKey = 'voice_model_type';
  static const String _hasShownDevicePerfSelectionKey = 'has_shown_device_performance_selection';

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
    return value == 'lite' ? VoiceModelType.lite : VoiceModelType.premium;
  }

  /// Set the selected voice model type
  static Future<void> setVoiceModelType(VoiceModelType type) async {
    _ensureInitialized();
    await _preferences!.setString(_voiceModelTypeKey, type == VoiceModelType.lite ? 'lite' : 'premium');
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

  /// Clear all preferences (useful for testing/reset)
  static Future<void> clear() async {
    _ensureInitialized();
    await _preferences!.clear();
  }
}
