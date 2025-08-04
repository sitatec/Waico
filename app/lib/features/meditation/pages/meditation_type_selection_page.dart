import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:waico/features/meditation/background_sound_manager.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';
import 'package:waico/features/meditation/widgets/meditation_type_card.dart';
import 'package:waico/features/meditation/widgets/background_sound_selector.dart';
import 'package:waico/generated/locale_keys.g.dart';

class MeditationTypeSelectionPage extends StatelessWidget {
  final Function(MeditationType, int, String?, String?) onTypeSelected;

  const MeditationTypeSelectionPage({super.key, required this.onTypeSelected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(LocaleKeys.meditation_type_selection_choose_meditation_type.tr()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.self_improvement, color: Colors.white, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    LocaleKeys.meditation_type_selection_create_your_guide.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    LocaleKeys.meditation_type_selection_guide_description.tr(),
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Beginner recommendation
            Text(
              LocaleKeys.meditation_perfect_for_beginners.tr(),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),

            MeditationTypeCard(
              type: MeditationType.beginner,
              onTap: () => _showDurationSelection(context, MeditationType.beginner),
            ),

            const SizedBox(height: 24),

            // All meditation types
            Text(
              LocaleKeys.meditation_all_meditation_types.tr(),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),

            ...MeditationType.values
                .where((type) => type != MeditationType.beginner)
                .map((type) => MeditationTypeCard(type: type, onTap: () => _showDurationSelection(context, type))),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showDurationSelection(BuildContext context, MeditationType type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DurationSelectionModal(
        type: type,
        onDurationSelected: (duration, customTitle, backgroundSound) {
          Navigator.of(context).pop(); // Close duration modal
          onTypeSelected(type, duration, customTitle, backgroundSound);
        },
      ),
    );
  }
}

class DurationSelectionModal extends StatefulWidget {
  final MeditationType type;
  final Function(int, String?, String?) onDurationSelected;

  const DurationSelectionModal({super.key, required this.type, required this.onDurationSelected});

  @override
  State<DurationSelectionModal> createState() => _DurationSelectionModalState();
}

class _DurationSelectionModalState extends State<DurationSelectionModal> {
  final TextEditingController _titleController = TextEditingController();
  String? _selectedBackgroundSound = BackgroundSoundManager.availableSounds.first;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const durations = [5, 10, 15, 20, 25, 30];

    return SingleChildScrollView(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                LocaleKeys.meditation_type_selection_personalize_meditation.tr(),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
              ),
            ),
            const SizedBox(height: 8),

            // Custom title section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleKeys.meditation_type_selection_meditation_title_optional.tr(),
                    style: TextStyle(fontSize: 15, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: LocaleKeys.meditation_type_selection_enter_meditation_title.tr(),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Background sound selection
            ExpansionTile(
              title: Row(
                children: [
                  Icon(Icons.music_note_outlined, color: theme.colorScheme.primary, size: 21),
                  const SizedBox(width: 8),
                  Text(
                    LocaleKeys.meditation_type_selection_background_sound.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              maintainState: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              children: [
                BackgroundSoundSelector(
                  onSoundSelected: (sound) {
                    setState(() {
                      _selectedBackgroundSound = sound;
                    });
                  },
                  selectedSound: _selectedBackgroundSound,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Duration options
            ExpansionTile(
              initiallyExpanded: true,
              title: Row(
                children: [
                  Icon(Icons.access_time, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    LocaleKeys.meditation_type_selection_select_duration.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              maintainState: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: durations.map((duration) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DurationCard(
                          duration: duration,
                          onTap: () {
                            final customTitle = _titleController.text.trim().isNotEmpty
                                ? _titleController.text.trim()
                                : null;
                            widget.onDurationSelected(duration, customTitle, _selectedBackgroundSound);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class DurationCard extends StatelessWidget {
  final int duration;
  final VoidCallback onTap;

  const DurationCard({super.key, required this.duration, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.access_time, color: Theme.of(context).colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocaleKeys.common_in_minutes.plural(duration, namedArgs: {'count': duration.toString()}),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                      Text(
                        _getDurationDescription(duration),
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: Colors.grey.shade400, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDurationDescription(int duration) {
    if (duration <= 5) {
      return LocaleKeys.meditation_duration_descriptions_quick_focused.tr();
    } else if (duration <= 10) {
      return LocaleKeys.meditation_duration_descriptions_perfect_beginners.tr();
    } else if (duration <= 15) {
      return LocaleKeys.meditation_duration_descriptions_balanced_relaxing.tr();
    } else if (duration <= 20) {
      return LocaleKeys.meditation_duration_descriptions_deep_restorative.tr();
    } else {
      return LocaleKeys.meditation_duration_descriptions_extended_practice.tr();
    }
  }
}
