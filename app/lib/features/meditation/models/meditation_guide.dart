import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import 'package:waico/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';

@Entity()
class MeditationGuide {
  @Id()
  int id;

  String title;
  String type;
  String description;
  int durationMinutes;
  String script;
  String? audioId; // ID used for audio files folder
  String? backgroundSound; // Background sound filename (e.g., "meditation_bg_1.m4a")
  DateTime createdAt;
  DateTime updatedAt;
  bool isCompleted;

  MeditationGuide({
    this.id = 0,
    required this.title,
    required this.type,
    required this.description,
    required this.durationMinutes,
    required this.script,
    this.audioId,
    this.backgroundSound,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isCompleted = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory MeditationGuide.fromJson(Map<String, dynamic> json) {
    return MeditationGuide(
      title: json['title'] as String,
      type: json['type'] as String,
      description: json['description'] as String,
      durationMinutes: json['durationMinutes'] as int,
      script: json['script'] as String,
      audioId: json['audioId'] as String?,
      backgroundSound: json['backgroundSound'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'type': type,
      'description': description,
      'durationMinutes': durationMinutes,
      'script': script,
      'audioId': audioId,
      'backgroundSound': backgroundSound,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isCompleted': isCompleted,
    };
  }

  factory MeditationGuide.fromJsonString(String jsonString) {
    return MeditationGuide.fromJson(json.decode(jsonString));
  }

  String toJsonString() {
    return json.encode(toJson());
  }

  void touch() {
    updatedAt = DateTime.now();
  }
}

enum MeditationType {
  mindfulness,
  bodyScanning,
  lovingKindness,
  breathwork,
  visualization,
  walking,
  mantra,
  beginner;

  String get title {
    switch (this) {
      case MeditationType.mindfulness:
        return LocaleKeys.meditation_generator_titles_mindfulness.tr();
      case MeditationType.bodyScanning:
        return LocaleKeys.meditation_generator_titles_body_scanning.tr();
      case MeditationType.lovingKindness:
        return LocaleKeys.meditation_generator_titles_loving_kindness.tr();
      case MeditationType.breathwork:
        return LocaleKeys.meditation_generator_titles_breathwork.tr();
      case MeditationType.visualization:
        return LocaleKeys.meditation_generator_titles_visualization.tr();
      case MeditationType.walking:
        return LocaleKeys.meditation_generator_titles_walking.tr();
      case MeditationType.mantra:
        return LocaleKeys.meditation_generator_titles_mantra.tr();
      case MeditationType.beginner:
        return LocaleKeys.meditation_generator_titles_beginner.tr();
    }
  }

  String get description {
    switch (this) {
      case MeditationType.mindfulness:
        return LocaleKeys.meditation_generator_descriptions_mindfulness.tr();
      case MeditationType.bodyScanning:
        return LocaleKeys.meditation_generator_descriptions_body_scanning.tr();
      case MeditationType.lovingKindness:
        return LocaleKeys.meditation_generator_descriptions_loving_kindness.tr();
      case MeditationType.breathwork:
        return LocaleKeys.meditation_generator_descriptions_breathwork.tr();
      case MeditationType.visualization:
        return LocaleKeys.meditation_generator_descriptions_visualization.tr();
      case MeditationType.walking:
        return LocaleKeys.meditation_generator_descriptions_walking.tr();
      case MeditationType.mantra:
        return LocaleKeys.meditation_generator_descriptions_mantra.tr();
      case MeditationType.beginner:
        return LocaleKeys.meditation_generator_descriptions_beginner.tr();
    }
  }
}
