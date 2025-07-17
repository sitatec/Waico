import 'package:objectbox/objectbox.dart';

@Entity()
class User {
  @Id()
  int id;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  /// The preferred name of the user
  /// This is the name that will be used in conversations and interactions
  String preferredName;

  /// User preferences stored as key-value pairs
  /// This can include settings like theme, language, notification preferences, etc.
  Map<String, String> preferences;

  User({
    this.id = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.preferredName,
    Map<String, String>? preferences,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       preferences = preferences ?? {};

  void touch() {
    updatedAt = DateTime.now();
  }

  @override
  String toString() {
    return 'User('
        'id: $id, '
        'createdAt: $createdAt, '
        'updatedAt: $updatedAt, '
        'name: $preferredName, '
        'preferences: $preferences)';
  }
}
