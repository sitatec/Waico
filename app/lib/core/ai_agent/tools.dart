import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:health/health.dart' show HealthDataType, HealthDataPoint, NumericHealthValue;
import 'package:intl/intl.dart' show DateFormat;
import 'package:waico/core/ai_models/embedding_model.dart';
import 'package:waico/core/repositories/conversation_memory_repository.dart';
import 'package:waico/core/repositories/conversation_repository.dart';
import 'package:waico/core/services/calendar_service.dart';
import 'package:waico/core/services/communication_service.dart';
import 'package:waico/core/services/health_service.dart' show HealthService;
import 'package:waico/core/widgets/chart_widget.dart' show ChartDataPoint;

abstract class Tool {
  String get name;
  String get definition;
  String get usageExample;

  FutureOr<String> call(Map<String, dynamic> arguments);
}

class PhoneCallTool extends Tool {
  @override
  String get name => 'make_phone_call';

  @override
  String get definition =>
      'make_phone_call(required String phone_number):\nMake a phone call to the specified phone number. When the user requests a phone call, you must use use this tool.';

  @override
  String get usageExample =>
      'User: My therapist phone number is +1234567890, can you call him?\n'
      'Assistant: Sure, I will call your therapist now.'
      '\n```tool_call\nmake_phone_call(phone_number="+1234567890")\n```\n\n'
      "If you don't know the phone number, ask the user to provide it:\n"
      'User: Can you call my gym coach?\n'
      'Assistant: Sure, please provide me with your coach phone number so I can call them for you.';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    final String phoneNumber = arguments["phone_number"];
    final result = await CommunicationService.makePhoneCall(phoneNumber);
    final success = result != false; // In so platform result is alway null (the pkg is not well documented)

    return success ? 'Phone call initiated successfully' : 'Failed to initiate phone call';
  }
}

class ReportTool extends Tool {
  final ConversationRepository _conversationRepository;
  final dateFormatter = DateFormat('EEEE, MMMM d, y – HH:mm');

  ReportTool({ConversationRepository? conversationRepository})
    : _conversationRepository = conversationRepository ?? ConversationRepository();

  @override
  String get name => 'send_report_to';

  @override
  String get definition =>
      'send_report_to(required String recipient_email):\nSend a report generated based on observations from previous conversations. This can be sent to a health or wellbeing professional trusted by the user.';

  @override
  String get usageExample =>
      'System: The user doctor email is alex@example.com\n'
      'User: Can you send a report of my wellbeing to my doctor?\n'
      "Assistant: Okay, one moment please, I'm sending the report."
      '```tool_call\nsend_report_to(recipient_email="alex@example.com")\n```\n\n'
      "If you don't know the recipient email, ask the user to provide it.";

  @override
  Future<String> call(Map<String, dynamic> arguments) async {
    try {
      if (!arguments.containsKey("recipient_email")) {
        return 'Error: Missing required parameter "recipient_email" for sending report.';
      }

      final String recipientEmail = arguments["recipient_email"];
      final conversations = await _conversationRepository.getLatestConversations(count: 5);

      if (conversations.isEmpty) {
        return 'No conversations found to generate a report.';
      }

      // Generate a report based on the conversations
      final String reportContent = conversations
          .map((conversation) {
            return 'Date: ${dateFormatter.format(conversation.createdAt)}\n\n'
                'Observation: ${conversation.observations}\n\n'
                'Conversation Summary: ${conversation.summary}\n\n';
          })
          .join('\n\n------------------------------------------\n\n');

      // Send the report via email
      final response = await CommunicationService.sendEmail(
        body: reportContent,
        subject: "[Username]'s Wellbeing Report", // TODO: Replace [Username] with the actual username
        recipients: [recipientEmail],
      );

      return response.message;
    } catch (e, s) {
      log('Error while handling ReportTool.call: $e', error: e, stackTrace: s);
      return 'Error: $e';
    }
  }
}

class SearchMemoryTool extends Tool {
  final ConversationMemoryRepository _conversationMemoryRepository;
  final EmbeddingModel _embeddingModel;

  SearchMemoryTool({ConversationMemoryRepository? conversationMemoryRepository, EmbeddingModel? embeddingModel})
    : _conversationMemoryRepository = conversationMemoryRepository ?? ConversationMemoryRepository(),
      _embeddingModel = embeddingModel ?? EmbeddingModel();

  @override
  String get name => 'search_memory';

  @override
  String get definition =>
      "search_memory(required String query):\nSearch your own memory (the AI assistant memory, not the user’s) from past conversations for relevant information.\nThe query parameter is a relevant fact, expression, event, person, expression. You should use this function when the user evokes an event, person, or period of time that you haven't discussed in the current conversation so that you can remember it. If the tool doesn't relevant memories, you should ask the user to remind you about it.";

  @override
  String get usageExample =>
      'User: That day when we talked about my issues with my girlfriend, it helped me a lot.\n'
      'Assistant: \n```tool_call\nsearch_memory(query="last vacation")\n```\n'
      'ToolResponse: The user mentioned trust issues with their girlfriend during their last vacation. It...\n'
      'Assistant: Ah, yes, I remember. The trust issues during your vacation, right?';

  @override
  Future<String> call(Map<String, dynamic> arguments) async {
    try {
      if (!arguments.containsKey("query")) {
        return 'Error: Missing required parameter "query" for searching memory.';
      }

      final String query = arguments["query"];
      final List<double> queryVector = await _embeddingModel.getEmbeddings(query);

      final memories = await _conversationMemoryRepository.searchMemories(queryVector: queryVector);

      if (memories.isEmpty) {
        return 'No relevant memories found for the query: $query';
      }

      return memories.first.content; // The memories are sorted by most relevant, so we return the first one
    } catch (e, s) {
      log('Error while handling SearchMemoryTool.call: $e', error: e, stackTrace: s);
      return 'Error: $e';
    }
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
  String get name => 'get_health_data';

  @override
  String get definition =>
      'get_health_data(required String health_data_type, required String period):\nRetrieve health-related data for a specified category and time period.\nThe health_data_type parameter must be one of the following: SLEEP, WATER, STEPS_COUNT, ACTIVE_ENERGY_BURNED, or WEIGHT.\nThe period parameter must be one of: TODAY (from midnight to now) or LAST_24_HOURS.';

  @override
  String get usageExample =>
      'User: How many steps did I take today?\n'
      'Assistant: Let me check your steps count for today.\n'
      '```tool_call\nget_health_data(health_data_type="STEPS_COUNT", period="TODAY")\n```\n\n'
      'User: How much water did I drink in the last 24 hours?\n'
      'Assistant: Please wait while I check that for you.\n'
      '```tool_call\nget_health_data(health_data_type="WATER", period="LAST_24_HOURS")\n```\n';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    try {
      // Validate required parameters and return an error message if any are missing
      if (!arguments.containsKey("health_data_type") || !arguments.containsKey("period")) {
        return 'Error: Missing required parameters for retrieving health data.';
      }

      final String healthDataType = arguments["health_data_type"].toUpperCase();
      final String period = arguments["period"].toUpperCase();

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
      HealthDataType.ACTIVE_ENERGY_BURNED => 'Active energy burned: ${total / 1000} kcal', // Convert to kcal
      HealthDataType.WEIGHT => 'Weight: $total kg',
      _ => 'Total: $total', // Fallback for any other type, though currently not expected
    };
  }
}

class DisplayUserProgressTool extends Tool {
  final HealthService healthService;
  final void Function(List<ChartDataPoint>) displayHealthData;
  DisplayUserProgressTool({required this.healthService, required this.displayHealthData});

  @override
  String get name => 'display_user_progress';

  @override
  String get definition =>
      'display_user_progress(required String period):\nDisplay a Line Chart of the user\'s daily data for a given time period, along with the total for that period.\nThe period parameter must be one of: LAST_7_DAYS or LAST_30_DAYS.';

  @override
  String get usageExample =>
      'User: How is my progress in the last 7 days?\n'
      'Assistant: Let me show you your progress chart for the last 7 days.\n'
      '```tool_call\ndisplay_user_progress(period="LAST_7_DAYS")\n```\n\n';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    try {
      // Validate required parameters and return an error message if any are missing
      if (!arguments.containsKey("period")) {
        return 'Error: Missing required parameters for displaying user progress.';
      }

      final String period = arguments["period"].toUpperCase();

      // Validate period for progress display (different from get_health_data)
      if (period != 'LAST_7_DAYS' && period != 'LAST_30_DAYS') {
        return 'Error: Invalid period. Must be either LAST_7_DAYS or LAST_30_DAYS.';
      }

      final endTime = DateTime.now();
      final days = period == 'LAST_7_DAYS' ? 7 : 30;
      final startTime = endTime.subtract(Duration(days: days));

      // Get health data for the specified range
      final healthData = await healthService.getHealthDataForRange(
        startTime: startTime,
        endTime: endTime,
        types: [
          HealthDataType.STEPS,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.WATER,
          HealthDataType.WEIGHT,
        ],
      );

      // Process data into daily aggregates for chart display
      final chartData = _processHealthDataToChartPoints(healthData, days, endTime);

      // Calculate totals for the period for all health data types
      final totals = _calculateTotalsForPeriod(healthData);

      // Call the display function with the processed data
      displayHealthData(chartData);

      // Return success message with summary
      final totalsSummary = _formatTotalsSummary(totals, period);
      return 'Successfully displayed progress chart. $totalsSummary';
    } catch (e, s) {
      log('Error while handling DisplayUserProgressTool.call: $e', error: e, stackTrace: s);
      return 'Error: $e';
    }
  }

  /// Process health data into daily chart data points
  List<ChartDataPoint> _processHealthDataToChartPoints(List<HealthDataPoint> healthData, int days, DateTime endTime) {
    // Create maps to store daily aggregates for each health type
    final Map<String, Map<HealthDataType, double>> dailyData = {};

    // Initialize all days with 0 values for each health type
    for (int i = days - 1; i >= 0; i--) {
      final date = endTime.subtract(Duration(days: i));
      final dateKey = DateFormat('MM-dd').format(date);
      dailyData[dateKey] = {
        HealthDataType.STEPS: 0.0,
        HealthDataType.ACTIVE_ENERGY_BURNED: 0.0,
        HealthDataType.SLEEP_ASLEEP: 0.0,
        HealthDataType.WATER: 0.0,
        HealthDataType.WEIGHT: 0.0,
      };
    }

    // Aggregate health data by day and type
    for (var point in healthData) {
      final dateKey = DateFormat('MM-dd').format(point.dateFrom);

      if (dailyData.containsKey(dateKey)) {
        if (point.value is NumericHealthValue) {
          final value = (point.value as NumericHealthValue).numericValue;

          var adjustedValue = value;
          if (point.type == HealthDataType.SLEEP_ASLEEP) {
            // Convert sleep from minutes to hours for better display
            adjustedValue = value / 60;
          } else if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
            // Convert calories to kcal for better display
            adjustedValue = value / 1000;
          }

          if (point.type == HealthDataType.STEPS) {
            // For steps, we want the total for the day, so we take the max value
            // as the health data might contain cumulative values
            dailyData[dateKey]![point.type] = dailyData[dateKey]![point.type]! > adjustedValue
                ? dailyData[dateKey]![point.type]!
                : adjustedValue.toDouble();
          } else if (point.type == HealthDataType.WEIGHT) {
            // For weight, we want the latest value for the day
            if (dailyData[dateKey]![point.type] == 0.0 || adjustedValue > 0) {
              dailyData[dateKey]![point.type] = adjustedValue.toDouble();
            }
          } else {
            // For other metrics, sum up the values
            dailyData[dateKey]![point.type] = dailyData[dateKey]![point.type]! + adjustedValue;
          }
        }
      }
    }

    // Convert to ChartDataPoint list - combine all metrics into a single value per day
    // For demonstration, we'll use steps as the primary metric
    final List<ChartDataPoint> chartPoints = [];
    int dayIndex = 0;

    for (int i = days - 1; i >= 0; i--) {
      final date = endTime.subtract(Duration(days: i));
      final dateKey = DateFormat('MM-dd').format(date);

      // Use steps as the primary metric for the chart display
      final metricValue = dailyData[dateKey]![HealthDataType.STEPS] ?? 0.0;

      chartPoints.add(
        ChartDataPoint(
          x: dayIndex.toDouble(),
          y: metricValue,
          label: dateKey,
          color: _getColorForHealthType(HealthDataType.STEPS),
        ),
      );

      dayIndex++;
    }

    return chartPoints;
  }

  /// Calculate totals for all health data types for the given period
  Map<HealthDataType, double> _calculateTotalsForPeriod(List<HealthDataPoint> healthData) {
    final Map<HealthDataType, double> totals = {
      HealthDataType.STEPS: 0.0,
      HealthDataType.ACTIVE_ENERGY_BURNED: 0.0,
      HealthDataType.SLEEP_ASLEEP: 0.0,
      HealthDataType.WATER: 0.0,
      HealthDataType.WEIGHT: 0.0,
    };

    // Track the latest weight value
    HealthDataPoint? latestWeight;

    for (var point in healthData) {
      if (point.value is NumericHealthValue) {
        final value = (point.value as NumericHealthValue).numericValue;

        switch (point.type) {
          case HealthDataType.STEPS:
            // For steps, we want the maximum value (assuming cumulative daily steps)
            if (totals[point.type]! < value) {
              totals[point.type] = value.toDouble();
            }
            break;
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            totals[point.type] = totals[point.type]! + value.toDouble();
            break;
          case HealthDataType.SLEEP_ASLEEP:
            totals[point.type] = totals[point.type]! + value.toDouble();
            break;
          case HealthDataType.WATER:
            totals[point.type] = totals[point.type]! + value.toDouble();
            break;
          case HealthDataType.WEIGHT:
            // For weight, keep the latest value
            if (latestWeight == null || point.dateFrom.isAfter(latestWeight.dateFrom)) {
              latestWeight = point;
              totals[point.type] = value.toDouble();
            }
            break;
          default:
            break;
        }
      }
    }

    return totals;
  }

  /// Format the totals summary for all health data types
  String _formatTotalsSummary(Map<HealthDataType, double> totals, String period) {
    final List<String> formattedTotals = [];

    if (totals[HealthDataType.STEPS]! > 0) {
      formattedTotals.add('Steps: ${totals[HealthDataType.STEPS]!.toInt()}');
    }
    if (totals[HealthDataType.ACTIVE_ENERGY_BURNED]! > 0) {
      formattedTotals.add('Calories: ${(totals[HealthDataType.ACTIVE_ENERGY_BURNED]! / 1000).toInt()} kcal');
    }
    if (totals[HealthDataType.SLEEP_ASLEEP]! > 0) {
      formattedTotals.add('Sleep: ${(totals[HealthDataType.SLEEP_ASLEEP]! / 60).toStringAsFixed(1)} hours');
    }
    if (totals[HealthDataType.WATER]! > 0) {
      formattedTotals.add('Water: ${totals[HealthDataType.WATER]!.toStringAsFixed(1)} L');
    }
    if (totals[HealthDataType.WEIGHT]! > 0) {
      formattedTotals.add('Weight: ${totals[HealthDataType.WEIGHT]!.toStringAsFixed(1)} kg');
    }

    if (formattedTotals.isEmpty) {
      return 'No data available for this period.';
    }

    // E.g: LAST_7_DAYS => the last 7 days
    period = "the ${period.toLowerCase().replaceAll('_', ' ')}";
    return 'Totals for $period:\n${formattedTotals.join('\n')}.';
  }

  /// Get appropriate color for different health data types
  Color _getColorForHealthType(HealthDataType type) {
    return switch (type) {
      HealthDataType.STEPS => Colors.green,
      HealthDataType.SLEEP_ASLEEP => Colors.purple,
      HealthDataType.WATER => Colors.blue,
      HealthDataType.ACTIVE_ENERGY_BURNED => Colors.orange,
      HealthDataType.WEIGHT => Colors.red,
      _ => Colors.grey,
    };
  }
}

class CreateCalendarSingleEventTool extends Tool {
  final CalendarService _calendarService;

  CreateCalendarSingleEventTool({CalendarService? calendarService})
    : _calendarService = calendarService ?? CalendarService();

  @override
  String get name => 'create_calendar_single_event';

  @override
  String get definition =>
      'create_calendar_single_event(required String event_name, required String starts_at, required String ends_at):\nCreate a single (non-recurring) calendar event.\nThe starts_at and ends_at parameters should be in ISO 8601 format (e.g. 2024-08-01T10:00:00Z).';
  // 'create_calendar_single_event(required String event_name, required String starts_at, required String ends_at, optional String description, optional String location):\nCreate a single (non-recurring) calendar event.\nThe starts_at and ends_at parameters should be in ISO 8601 format (e.g. 2024-08-01T10:00:00Z).';

  @override
  String get usageExample =>
      'System: Current date and time is Monday, 01 January 2024 – 10:00 AM\n'
      'User: Can you create a calendar event for my doctor appointment?\n'
      'Assistant: Sure thing, please tell me the date, time and duration of the appointment.\n'
      'User: Its tomorrow at 4 PM for 1 hour.\n'
      'Assistant: Okay, I will create a calendar event named Doctor Appointment for tomorrow January 2nd, 2024 from 4 PM to 5 PM.\n'
      '```tool_call\ncreate_calendar_single_event(event_name="Doctor Appointment", starts_at="2024-01-02T16:00:00Z", ends_at="2024-01-02T17:00:00Z")\n```\n';

  @override
  FutureOr<String> call(Map<String, dynamic> arguments) async {
    await _calendarService.initialize(); // Ensure the calendar service is initialized
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
  String get name => 'schedule_recurring_calendar_event';

  @override
  String get definition =>
      'schedule_recurring_calendar_event(required String event_name, required String starts_at, required String ends_at, required String frequency, optional String recurrence_ends_at, optional String description, optional String location):\nSchedule a recurring calendar event.\nThe starts_at and ends_at parameters should be in ISO 8601 format (e.g. 2024-08-01T10:00:00Z).\nThe frequency parameter must be one of the following: DAILY, WEEKLY, MONTHLY, or YEARLY.\nThe recurrence_ends_at parameter is optional and specifies the end date of the recurrence in ISO 8601 format (e.g. 2024-08-01T10:00:00Z). If not provided, the event will recur indefinitely.';

  @override
  String get usageExample => throw UnimplementedError('ScheduleRecurringCalendarEventTool is not used for now');

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
