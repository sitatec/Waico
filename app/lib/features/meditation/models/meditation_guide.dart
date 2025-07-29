import 'dart:convert';
import 'package:objectbox/objectbox.dart';

@Entity()
class MeditationGuide {
  @Id()
  int id;

  String title;
  String type;
  String description;
  int durationMinutes;
  String script;
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
  mindfulness('Mindfulness', 'Focus on present moment awareness and breathing'),
  bodyScanning('Body Scanning', 'Progressive relaxation through body awareness'),
  lovingKindness('Loving Kindness', 'Cultivate compassion and positive emotions'),
  breathwork('Breathwork', 'Focus on different breathing techniques'),
  visualization('Visualization', 'Guided imagery and mental visualization'),
  walking('Walking Meditation', 'Mindful movement and awareness'),
  mantra('Mantra', 'Repetition of sacred words or phrases'),
  beginner('Beginner Friendly', 'Perfect introduction to meditation practice');

  const MeditationType(this.title, this.description);

  final String title;
  final String description;
}
