import 'dart:async';
import 'dart:developer';

import 'package:health/health.dart' show HealthDataType, HealthDataPoint, NumericHealthValue;
import 'package:waico/core/services/calendar_service.dart';
import 'package:waico/core/services/communication_service.dart';
import 'package:waico/core/services/health_service.dart' show HealthService;

abstract class Tool {
  String get name;
  String get definition;

  FutureOr<String> call(Map<String, dynamic> arguments);
}

class PhoneCallTool extends Tool {
  @override
  String get definition =>
      'make_phone_call(required String phone_number):\nInitiate a phone call to the specified phone number. This function should only be called upon the user’s request or with their explicit approval.';

  @override
  String get name => 'make_phone_call';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    final String phoneNumber = arguments["phone_number"];
    final result = await CommunicationService.makePhoneCall(phoneNumber);
    final success = result != false; // In so platform result is alway null (the pkg is not well documented)

    return success ? 'Phone call initiated' : 'Failed to initiate phone call';
  }
}

class ReportTool extends Tool {
  @override
  String get definition =>
      'send_report_to(required String recipient_email):\nSend a report generated based on observations from previous conversations. This can be sent to a health or wellbeing professional trusted by the user. This function should only be called upon the user’s request or with their explicit approval.';

  @override
  String get name => 'send_report_to';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) {
    // TODO: implement call
    throw UnimplementedError("ReportTool.call is not implemented yet. Need vector db");
  }
}

class SearchMemoryTool extends Tool {
  @override
  String get definition =>
      'search_memory(required String query):\nSearch your memory (Waico’s memory, not the user’s) from past conversations for relevant information.\nThe query parameter is a relevant fact, expression, event, person, expression.';

  @override
  String get name => 'search_memory';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) {
    throw UnimplementedError('SearchMemoryTool.call is not implemented yet. Need vector db');
  }
}

class GetHealthDataTool extends Tool {
  static const healthDataTypeMap = {
    'SLEEP': HealthDataType.SLEEP_ASLEEP,
    'WATER': HealthDataType.WATER,
    'STEPS_COUNT': HealthDataType.STEPS,
    'ACTIVE_ENERGY_BURNED': HealthDataType.ACTIVE_ENERGY_BURNED,
    'WEIGHT': HealthDataType.WEIGHT,
  };

  final HealthService healthService;

  GetHealthDataTool({required this.healthService});

  @override
  String get definition =>
      'get_health_data(required String health_data_type, required String period):\nRetrieve health-related data for a specified category and time period.\nThe health_data_type parameter must be one of the following: SLEEP, WATER, STEPS_COUNT, ACTIVE_ENERGY_BURNED, or WEIGHT.\nThe period parameter must be one of: TODAY (from midnight to now) or LAST_24_HOURS.';

  @override
  String get name => 'get_health_data';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    try {
      // Validate required parameters and return an error message if any are missing
      if (!arguments.containsKey("health_data_type") || !arguments.containsKey("period")) {
        return 'Error: Missing required parameters for retrieving health data.';
      }

      final String healthDataType = arguments["health_data_type"];
      final String period = arguments["period"];

      if (!healthDataTypeMap.containsKey(healthDataType)) {
        return 'Error: Invalid health_data_type. Must be one of: ${healthDataTypeMap.keys.join(', ')}';
      }

      final endTime = DateTime.now();
      final startTime = _getStartTimeFromPeriod(period, endTime);

      final healthData = await healthService.getHealthDataForRange(
        startTime: startTime,
        endTime: endTime,
        types: [healthDataTypeMap[healthDataType]!],
      );

      return _formatHealthData(healthData, healthDataTypeMap[healthDataType]!);
    } catch (e, s) {
      log('Error while handling GetHealthDataTool.call: $e', error: e, stackTrace: s);
      return 'Error: $e';
    }
  }

  DateTime _getStartTimeFromPeriod(String period, DateTime endTime) {
    return switch (period) {
      'TODAY' => DateTime(endTime.year, endTime.month, endTime.day), // Reset to midnight of today
      'LAST_24_HOURS' => endTime.subtract(const Duration(hours: 24)),
      _ => throw ArgumentError('Error: Invalid period. Must be either TODAY or LAST_24_HOURS.'),
    };
  }

  String _formatHealthData(List<HealthDataPoint> healthData, HealthDataType type) {
    if (healthData.isEmpty) {
      return 'No health data found for the specified period.';
    }

    final total = healthData.fold<double>(0, (sum, point) {
      if (point.value is NumericHealthValue) {
        return sum + (point.value as NumericHealthValue).numericValue;
      }
      // Less likely to reach here, currently only data points with numeric values are expected
      return sum;
    });

    return switch (type) {
      HealthDataType.SLEEP_ASLEEP => 'Sleep hours: ${total / 60}', // Convert minutes to hours
      HealthDataType.WATER => 'Water intake: $total L',
      HealthDataType.STEPS => 'Steps count: $total',
      HealthDataType.ACTIVE_ENERGY_BURNED => 'Active energy burned: $total calories',
      HealthDataType.WEIGHT => 'Weight: $total kg',
      _ => 'Total: $total', // Fallback for any other type, though currently not expected
    };
  }
}

class DisplayUserProgressTool extends Tool {
  final HealthService healthService;
  final void Function(Map<String, dynamic>) displayHealthData;
  DisplayUserProgressTool({required this.healthService, required this.displayHealthData});

  @override
  String get definition =>
      'display_user_progress(required String health_data_type, required String period):\nDisplay a Line Chart of the user’s daily data for a given type and time period. It also shows the total for the given period.\nThe health_data_type parameter must be one of: SLEEP, WATER, STEPS_COUNT, ACTIVE_ENERGY_BURNED, or WEIGHT.\nThe period parameter must be one of: LAST_7_DAYS or LAST_30_DAYS.';

  @override
  String get name => 'display_user_progress';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    try {
      // Validate required parameters and return an error message if any are missing
      if (!arguments.containsKey("health_data_type") || !arguments.containsKey("period")) {
        return 'Error: Missing required parameters for displaying user progress.';
      }

      throw UnimplementedError('DisplayUserProgressTool.call is not implemented yet.');
    } catch (e, s) {
      log('Error while handling DisplayUserProgressTool.call: $e', error: e, stackTrace: s);
      return 'Error: $e';
    }
  }
}

class CreateCalendarSingleEventTool extends Tool {
  final CalendarService _calendarService;

  CreateCalendarSingleEventTool({CalendarService? calendarService})
    : _calendarService = calendarService ?? CalendarService();

  @override
  String get definition =>
      'create_calendar_single_event(required String event_name, required String starts_at, required String ends_at, optional String description, optional String location):\nCreate a single (non-recurring) calendar event.\nThe starts_at and ends_at parameters should be in ISO 8601 format (e.g. 2024-08-01T10:00:00Z).';

  @override
  String get name => 'create_calendar_single_event';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    try {
      // Validate required parameters and return an error message if any are missing
      if (!arguments.containsKey("event_name") ||
          !arguments.containsKey("starts_at") ||
          !arguments.containsKey("ends_at")) {
        return 'Error: Missing required parameters for creating a calendar event.';
      }

      final String eventName = arguments["event_name"];
      // replaceAll('Z', '') removes the timezone from the startsAt and endsAt strings to use the local timezone
      final String startsAt = arguments["starts_at"].replaceAll('Z', '');
      final String endsAt = arguments["ends_at"];
      final String? description = arguments["description"];
      final String? location = arguments["location"];

      await _calendarService.createEvent(
        title: eventName,
        startTime: DateTime.parse(startsAt),
        endTime: DateTime.parse(endsAt),
        description: description,
        location: location,
      );

      return 'Event "$eventName" created successfully';
    } catch (e, s) {
      log('Error while handling CreateCalendarSingleEventTool.call: $e', error: e, stackTrace: s);
      return 'Error: $e';
    }
  }
}

class ScheduleRecurringCalendarEventTool extends Tool {
  final CalendarService _calendarService;

  ScheduleRecurringCalendarEventTool({CalendarService? calendarService})
    : _calendarService = calendarService ?? CalendarService();

  @override
  String get definition =>
      'schedule_recurring_calendar_event(required String event_name, required String starts_at, required String ends_at, required String frequency, optional String recurrence_ends_at, optional String description, optional String location):\nSchedule a recurring calendar event.\nThe starts_at and ends_at parameters should be in ISO 8601 format (e.g. 2024-08-01T10:00:00Z).\nThe frequency parameter must be one of the following: DAILY, WEEKLY, MONTHLY, or YEARLY.\nThe recurrence_ends_at parameter is optional and specifies the end date of the recurrence in ISO 8601 format (e.g. 2024-08-01T10:00:00Z). If not provided, the event will recur indefinitely.';

  @override
  String get name => 'schedule_recurring_calendar_event';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    try {
      // Validate required parameters and return an error message if any are missing
      if (!arguments.containsKey("event_name") ||
          !arguments.containsKey("starts_at") ||
          !arguments.containsKey("ends_at") ||
          !arguments.containsKey("frequency")) {
        return 'Error: Missing required parameters for scheduling a recurring calendar event.';
      }

      final String eventName = arguments["event_name"];
      // replaceAll('Z', '') removes the timezone from the startsAt and endsAt strings to use the local timezone
      final String startsAt = arguments["starts_at"].replaceAll('Z', '');
      final String endsAt = arguments["ends_at"];
      final String? recurrenceEndsAt = arguments["recurrence_ends_at"]?.replaceAll('Z', '');
      final RecurringPattern recurrencePattern = _getRecurrencePattern(arguments["frequency"]);
      final String? description = arguments["description"];
      final String? location = arguments["location"];

      await _calendarService.createEvent(
        title: eventName,
        startTime: DateTime.parse(startsAt),
        endTime: DateTime.parse(endsAt),
        recurring: recurrencePattern,
        description: description,
        location: location,
        recurringEndDate: recurrenceEndsAt != null ? DateTime.parse(recurrenceEndsAt) : null,
      );

      return 'Recurring event "$eventName" scheduled successfully';
    } catch (e, s) {
      log('Error while handling ScheduleRecurringCalendarEventTool.call: $e', error: e, stackTrace: s);
      return 'Error: $e';
    }
  }

  RecurringPattern _getRecurrencePattern(String frequency) {
    return switch (frequency.toUpperCase()) {
      'DAILY' => RecurringPattern.daily,
      'WEEKLY' => RecurringPattern.weekly,
      'MONTHLY' => RecurringPattern.monthly,
      'YEARLY' => RecurringPattern.yearly,
      _ => throw ArgumentError('Invalid frequency: $frequency'),
    };
  }
}
