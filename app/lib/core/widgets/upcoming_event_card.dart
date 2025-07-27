import 'dart:developer';

import 'package:device_calendar/device_calendar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:waico/core/services/calendar_service.dart';
import 'package:waico/generated/locale_keys.g.dart';

class UpcomingEventCard extends StatefulWidget {
  const UpcomingEventCard({super.key});

  @override
  State<UpcomingEventCard> createState() => _UpcomingEventCardState();
}

class _UpcomingEventCardState extends State<UpcomingEventCard> {
  final CalendarService _calendarService = CalendarService();
  Event? _upcomingEvent;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUpcomingEvent();
  }

  Future<void> _loadUpcomingEvent() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Initialize calendar service if not already initialized
      if (!_calendarService.isInitialized) {
        final initialized = await _calendarService.initialize();
        if (!initialized) {
          throw Exception('Failed to initialize calendar service');
        }
      }

      // Get the upcoming event
      final event = await _calendarService.getUpcomingEvent();

      setState(() {
        _upcomingEvent = event;
        _isLoading = false;
      });
    } catch (e) {
      log(e.toString());
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Container(
        height: 100,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error, size: 32),
              const SizedBox(height: 8),
              Text(
                LocaleKeys.calendar_failed_load_events.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }

    if (_upcomingEvent == null) {
      return Container(
        height: 90,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_available, color: theme.colorScheme.primary, size: 28),
              const SizedBox(height: 8),
              Text(
                LocaleKeys.calendar_no_upcoming_events.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return _buildEventCard(theme, _upcomingEvent!);
  }

  Widget _buildEventCard(ThemeData theme, Event event) {
    final eventTitle = event.title?.replaceFirst('[Waico] ', '') ?? LocaleKeys.calendar_no_title.tr();
    final eventDateTime = event.start;
    final eventLocation = event.location;
    final primaryColor = theme.colorScheme.primary;

    // Format the date and time
    String dateTimeText = '';
    String relativeTime = '';
    if (eventDateTime != null) {
      final now = DateTime.now();
      final eventDate = eventDateTime.toLocal();
      final duration = eventDate.difference(now);

      // Always prepare the original date/time format
      final isToday = eventDate.year == now.year && eventDate.month == now.month && eventDate.day == now.day;
      final isTomorrow = eventDate.year == now.year && eventDate.month == now.month && eventDate.day == now.day + 1;

      final timeFormatter = DateFormat('h:mm a'); // e.g., "2:30 PM"
      final dateFormatter = DateFormat('MMM d'); // e.g., "Jul 18"

      if (isToday) {
        dateTimeText = LocaleKeys.calendar_at.tr(
          namedArgs: {'day': LocaleKeys.common_today.tr(), 'time': timeFormatter.format(eventDate)},
        );
      } else if (isTomorrow) {
        dateTimeText = LocaleKeys.calendar_at.tr(
          namedArgs: {'day': LocaleKeys.common_tomorrow.tr(), 'time': timeFormatter.format(eventDate)},
        );
      } else {
        dateTimeText = LocaleKeys.calendar_at.tr(
          namedArgs: {'day': dateFormatter.format(eventDate), 'time': timeFormatter.format(eventDate)},
        );
      }

      // Check if event is less than 10 hours away
      if (duration.inHours < 10 && duration.inMinutes > 0) {
        // Show "in x time" format with original format below
        if (duration.inMinutes < 60) {
          relativeTime = LocaleKeys.calendar_in_minutes.plural(
            duration.inMinutes,
            namedArgs: {'count': duration.inMinutes.toString()},
          );
        } else {
          final hours = duration.inHours;
          final minutes = duration.inMinutes % 60;
          if (minutes == 0) {
            relativeTime = LocaleKeys.calendar_in_hours.plural(hours, namedArgs: {'count': hours.toString()});
          } else {
            relativeTime = LocaleKeys.calendar_in_hours_minutes.tr(
              namedArgs: {'hours': hours.toString(), 'minutes': minutes.toString()},
            );
          }
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withOpacity(0.2), primaryColor.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.2), width: 1),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.event, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          eventTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          LocaleKeys.calendar_upcoming.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(color: primaryColor, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (dateTimeText.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.access_time, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateTimeText,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),

                            if (relativeTime.isNotEmpty)
                              Text(
                                relativeTime,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  if (eventLocation != null && eventLocation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            eventLocation,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
