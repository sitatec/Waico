import 'dart:developer';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_timezone/flutter_timezone.dart' show FlutterTimezone;
import 'package:waico/core/constants.dart';

/// Enum for recurring event patterns
enum RecurringPattern { none, daily, weekly, monthly, yearly }

/// A service class that provides a simple API for managing calendar events
/// specific to this application. It creates and manages a dedicated calendar
/// for the app and ensures all operations are scoped to app-created events.
class CalendarService {
  static const String _appCalendarName = 'Waico Calendar';
  static const String _appEventPrefix = '[Waico]';

  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  Calendar? _appCalendar;
  Location? _localTimeZone;
  bool _isInitialized = false;

  /// Initialize the calendar service. Must be called before using other methods.
  Future<bool> initialize() async {
    try {
      // Initialize timezone
      await _initializeTimeZone();

      // Request calendar permissions
      final permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        throw Exception('Calendar permissions not granted');
      }

      // Get or create the app's dedicated calendar
      await _getOrCreateAppCalendar();

      _isInitialized = true;
      return true;
    } catch (e, s) {
      log('Error initializing calendar service:', error: e, stackTrace: s);
      return false;
    }
  }

  /// Check if the service is properly initialized
  bool get isInitialized => _isInitialized;

  /// Request calendar permissions from the user
  Future<bool> _requestPermissions() async {
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && permissionsGranted.data == true) {
      return true;
    }

    permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
    return permissionsGranted.isSuccess && permissionsGranted.data == true;
  }

  /// Initialize the local timezone
  Future<void> _initializeTimeZone() async {
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      _localTimeZone = getLocation(timeZoneName);
    } catch (e, s) {
      log('Could not get local timezone, using UTC:', error: e, stackTrace: s);
      _localTimeZone = getLocation('Etc/UTC');
    }
  }

  /// Get or create the app's dedicated calendar
  Future<void> _getOrCreateAppCalendar() async {
    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    if (!calendarsResult.isSuccess) {
      throw Exception('Failed to retrieve calendars: ${calendarsResult.errors}');
    }

    // Look for existing app calendar
    final calendars = calendarsResult.data ?? [];
    try {
      _appCalendar = calendars.cast<Calendar>().firstWhere((calendar) => calendar.name == _appCalendarName);
    } catch (e) {
      // Calendar doesn't exist, will be created below
      _appCalendar = null;
    }

    // Create calendar if it doesn't exist
    if (_appCalendar?.id == null) {
      await _createAppCalendar();
    }
  }

  /// Create a new calendar dedicated to this app
  Future<void> _createAppCalendar() async {
    final createResult = await _deviceCalendarPlugin.createCalendar(_appCalendarName);
    if (!createResult.isSuccess) {
      throw Exception('Failed to create app calendar: ${createResult.errors}');
    }

    _appCalendar = Calendar()
      ..id = createResult.data
      ..name = _appCalendarName
      ..color = primaryColor.toARGB32();
  }

  /// Create a new event in the app's calendar
  ///
  /// [title] - The event title
  /// [description] - Optional event description
  /// [startTime] - Event start time
  /// [endTime] - Event end time
  /// [isAllDay] - Whether the event is all-day (default: false)
  /// [reminderMinutes] - Minutes before event to remind (default: 15 minutes)
  /// [location] - Optional event location
  /// [recurring] - Recurring pattern (default: none)
  /// [recurringEndDate] - End date for recurring events (optional)
  /// [recurringCount] - Number of occurrences for recurring events (optional)
  ///
  /// Returns the created event ID if successful
  Future<String?> createEvent({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    bool isAllDay = false,
    int reminderMinutes = 15,
    String? location,
    RecurringPattern recurring = RecurringPattern.none,
    DateTime? recurringEndDate,
    int? recurringCount,
  }) async {
    _ensureInitialized();

    try {
      final event = Event(_appCalendar?.id);
      event.title = '$_appEventPrefix $title';
      event.description = description;
      event.start = TZDateTime.from(startTime, _localTimeZone!);
      event.end = TZDateTime.from(endTime, _localTimeZone!);
      event.allDay = isAllDay;
      event.location = location;

      // Add reminder if specified
      if (reminderMinutes > 0) {
        event.reminders = [Reminder(minutes: reminderMinutes)];
      }

      // Add recurring rule if specified
      if (recurring != RecurringPattern.none) {
        event.recurrenceRule = _buildRecurrenceRule(recurring, recurringEndDate, recurringCount);
      }

      final createResult = await _deviceCalendarPlugin.createOrUpdateEvent(event);
      if (createResult?.isSuccess == true) {
        return createResult?.data;
      } else {
        throw Exception(createResult?.errors.toString() ?? 'Failed to create event: $title');
      }
    } catch (e, s) {
      log('Error creating event:', error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Build a recurrence rule based on the recurring pattern
  RecurrenceRule? _buildRecurrenceRule(RecurringPattern pattern, DateTime? endDate, int? count) {
    switch (pattern) {
      case RecurringPattern.none:
        return null;
      case RecurringPattern.daily:
        return RecurrenceRule(
          RecurrenceFrequency.Daily,
          endDate: endDate != null ? TZDateTime.from(endDate, _localTimeZone!) : null,
          totalOccurrences: count,
        );
      case RecurringPattern.weekly:
        return RecurrenceRule(
          RecurrenceFrequency.Weekly,
          endDate: endDate != null ? TZDateTime.from(endDate, _localTimeZone!) : null,
          totalOccurrences: count,
        );
      case RecurringPattern.monthly:
        return RecurrenceRule(
          RecurrenceFrequency.Monthly,
          endDate: endDate != null ? TZDateTime.from(endDate, _localTimeZone!) : null,
          totalOccurrences: count,
        );
      case RecurringPattern.yearly:
        return RecurrenceRule(
          RecurrenceFrequency.Yearly,
          endDate: endDate != null ? TZDateTime.from(endDate, _localTimeZone!) : null,
          totalOccurrences: count,
        );
    }
  }

  /// Update an existing app event
  ///
  /// [eventId] - The ID of the event to update
  /// [title] - The new event title
  /// [description] - The new event description
  /// [startTime] - The new event start time
  /// [endTime] - The new event end time
  /// [isAllDay] - Whether the event is all-day
  /// [reminderMinutes] - Minutes before event to remind
  /// [location] - The new event location
  /// [recurring] - New recurring pattern
  /// [recurringEndDate] - New end date for recurring events
  /// [recurringCount] - New number of occurrences for recurring events
  ///
  /// Returns true if successful
  Future<bool> updateEvent({
    required String eventId,
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    bool? isAllDay,
    int? reminderMinutes,
    String? location,
    RecurringPattern? recurring,
    DateTime? recurringEndDate,
    int? recurringCount,
  }) async {
    _ensureInitialized();

    try {
      // First, retrieve the existing event
      final existingEvent = await _getEventById(eventId);
      if (existingEvent == null) {
        throw Exception('Event with ID $eventId not found');
      }

      // Update only the provided fields
      if (title != null) {
        existingEvent.title = '$_appEventPrefix $title';
      }
      if (description != null) {
        existingEvent.description = description;
      }
      if (startTime != null) {
        existingEvent.start = TZDateTime.from(startTime, _localTimeZone!);
      }
      if (endTime != null) {
        existingEvent.end = TZDateTime.from(endTime, _localTimeZone!);
      }
      if (isAllDay != null) {
        existingEvent.allDay = isAllDay;
      }
      if (location != null) {
        existingEvent.location = location;
      }
      if (reminderMinutes != null) {
        if (reminderMinutes > 0) {
          existingEvent.reminders = [Reminder(minutes: reminderMinutes)];
        } else {
          existingEvent.reminders = [];
        }
      }
      if (recurring != null) {
        existingEvent.recurrenceRule = _buildRecurrenceRule(recurring, recurringEndDate, recurringCount);
      }

      final updateResult = await _deviceCalendarPlugin.createOrUpdateEvent(existingEvent);
      if (updateResult?.isSuccess == true) {
        return true;
      } else {
        throw Exception(updateResult?.errors.toString() ?? 'Failed to update event: $eventId');
      }
    } catch (e, s) {
      log('Error updating event:', error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Delete an app event by ID
  ///
  /// [eventId] - The ID of the event to delete
  ///
  /// Returns true if successful
  Future<bool> deleteEvent(String eventId) async {
    _ensureInitialized();

    try {
      // Verify the event belongs to our app before deleting
      final event = await _getEventById(eventId);
      if (event == null || !_isAppEvent(event)) {
        throw Exception('Event with ID $eventId not found or does not belong to this app');
      }

      final deleteResult = await _deviceCalendarPlugin.deleteEvent(_appCalendar?.id, eventId);
      if (deleteResult.isSuccess == true) {
        return true;
      } else {
        throw Exception(deleteResult.errors.toString());
      }
    } catch (e, s) {
      log('Error deleting event:', error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Get all events created by this app
  ///
  /// [startDate] - Optional start date filter
  /// [endDate] - Optional end date filter
  ///
  /// Returns a list of app events
  Future<List<Event>> getAppEvents({DateTime? startDate, DateTime? endDate}) async {
    _ensureInitialized();

    try {
      if (_appCalendar?.id == null) {
        throw Exception('App calendar not available');
      }

      final retrieveEventsParams = RetrieveEventsParams(startDate: startDate, endDate: endDate);

      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(_appCalendar!.id!, retrieveEventsParams);

      if (!eventsResult.isSuccess) {
        throw Exception(eventsResult.errors.toString());
      }

      final events = eventsResult.data ?? [];
      return events.cast<Event>().where(_isAppEvent).toList();
    } catch (e, s) {
      log('Error retrieving app events:', error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Get a specific event by ID (only if it belongs to this app)
  Future<Event?> _getEventById(String eventId) async {
    try {
      final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        _appCalendar!.id!,
        RetrieveEventsParams(eventIds: [eventId]),
      );

      if (!eventsResult.isSuccess) {
        throw Exception(eventsResult.errors.firstOrNull ?? "Error");
      }

      final events = eventsResult.data ?? [];
      final foundEvent = events
          .cast<Event>()
          .where((event) => event.eventId == eventId && _isAppEvent(event))
          .firstOrNull;

      return foundEvent;
    } catch (e, s) {
      log("Failed to get event by id: $eventId :", error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Check if an event belongs to this app
  bool _isAppEvent(Event event) {
    return event.title?.startsWith(_appEventPrefix) == true;
  }

  /// Ensure the service is initialized before operations
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('CalendarService not initialized. Call initialize() first.');
    }
  }

  /// Get upcoming event (next event in the next 30 days)
  Future<Event?> getUpcomingEvent() async {
    final now = DateTime.now();
    final endDate = now.add(const Duration(days: 30));
    final events = await getAppEvents(startDate: now, endDate: endDate);

    // Sort events by start time and return the first (earliest) one
    if (events.isEmpty) return null;

    events.sort((a, b) {
      if (a.start == null && b.start == null) return 0;
      if (a.start == null) return 1;
      if (b.start == null) return -1;
      return a.start!.compareTo(b.start!);
    });

    return events.first;
  }

  /// Get events for today
  Future<List<Event>> getTodayEvents() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getAppEvents(startDate: startOfDay, endDate: endOfDay);
  }

  /// Helper method to create a daily recurring event
  /// Convenient wrapper for common daily events like medication reminders
  Future<String?> createDailyReminder({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    int reminderMinutes = 15,
    String? location,
    int durationInDays = 30,
  }) async {
    return createEvent(
      title: title,
      description: description,
      startTime: startTime,
      endTime: endTime,
      reminderMinutes: reminderMinutes,
      location: location,
      recurring: RecurringPattern.daily,
      recurringEndDate: startTime.add(Duration(days: durationInDays)),
    );
  }

  /// Helper method to create a weekly recurring event
  /// Convenient wrapper for weekly events like workout sessions
  Future<String?> createWeeklyEvent({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    int reminderMinutes = 30,
    String? location,
    int occurrences = 12,
  }) async {
    return createEvent(
      title: title,
      description: description,
      startTime: startTime,
      endTime: endTime,
      reminderMinutes: reminderMinutes,
      location: location,
      recurring: RecurringPattern.weekly,
      recurringCount: occurrences,
    );
  }

  /// Helper method to create a monthly recurring event
  /// Convenient wrapper for monthly events like health checkups
  Future<String?> createMonthlyEvent({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    int reminderMinutes = 1440, // 24 hours
    String? location,
    int occurrences = 6,
  }) async {
    return createEvent(
      title: title,
      description: description,
      startTime: startTime,
      endTime: endTime,
      reminderMinutes: reminderMinutes,
      location: location,
      recurring: RecurringPattern.monthly,
      recurringCount: occurrences,
    );
  }

  /// Clean up resources
  void dispose() {
    _isInitialized = false;
    _appCalendar = null;
    _localTimeZone = null;
  }
}
