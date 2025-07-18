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
  ///
  /// This is the name that will be used in conversations and interactions
  String preferredName;

  /// User preferences and additional info stored as key-value pairs
  ///
  /// This can include environment/settings that calms the user, their wellbeing professional (therapist, coach,..)
  /// contact info, things that stresses them...
  String? userInfo;

  User({this.id = 0, DateTime? createdAt, DateTime? updatedAt, required this.preferredName, this.userInfo})
    : createdAt = createdAt ?? DateTime.now(),
      updatedAt = updatedAt ?? DateTime.now();

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
        'userInfo: $userInfo)';
  }
}
