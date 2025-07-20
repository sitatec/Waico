/// Represents the status of a user's workout journey
enum WorkoutStatus {
  /// User hasn't completed the workout setup yet
  noSetup,

  /// User has completed setup but no workout plan has been generated
  setupCompleteNoPlan,

  /// User has a complete workout plan ready to use
  planReady,
}
