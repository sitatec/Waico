import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:just_audio/just_audio.dart';
import 'package:waico/features/meditation/background_sound_manager.dart';
import 'package:waico/generated/locale_keys.g.dart';

/// Widget for selecting background sounds during meditation creation
class BackgroundSoundSelector extends StatefulWidget {
  final String? selectedSound;
  final ValueChanged<String?> onSoundSelected;
  final bool allowNoSound;

  const BackgroundSoundSelector({
    super.key,
    this.selectedSound,
    required this.onSoundSelected,
    this.allowNoSound = true,
  });

  @override
  State<BackgroundSoundSelector> createState() => _BackgroundSoundSelectorState();
}

class _BackgroundSoundSelectorState extends State<BackgroundSoundSelector> {
  String? _selectedSound;
  bool _isPlaying = false;
  String? _currentlyPlayingSound;
  AudioPlayer? _previewPlayer;

  @override
  void initState() {
    super.initState();
    _selectedSound = widget.selectedSound;
  }

  @override
  void dispose() {
    _stopPreview(updateState: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sounds = BackgroundSoundManager.getAllSounds();

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.meditation_type_selection_choose_background_sound.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // No sound option
            if (widget.allowNoSound) ...[
              _buildSoundOption(
                title: LocaleKeys.meditation_type_selection_no_background_sound.tr(),
                subtitle: LocaleKeys.meditation_type_selection_voice_only.tr(),
                filename: null,
                icon: Icons.volume_off,
                theme: theme,
              ),
              const SizedBox(height: 8),
            ],

            // Available sounds
            ...sounds.map(
              (sound) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildSoundOption(
                  title: sound.displayName,
                  subtitle: LocaleKeys.meditation_type_selection_tap_to_preview.tr(),
                  filename: sound.filename,
                  icon: Icons.music_note_outlined,
                  theme: theme,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoundOption({
    required String title,
    required String subtitle,
    required String? filename,
    required IconData icon,
    required ThemeData theme,
  }) {
    final isSelected = _selectedSound == filename;
    final isCurrentlyPlaying = _currentlyPlayingSound == filename && _isPlaying;

    return InkWell(
      onTap: () => _selectSound(filename),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.05) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (filename != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => isCurrentlyPlaying ? _stopPreview() : _previewSound(filename),
                icon: Icon(
                  isCurrentlyPlaying ? Icons.stop : Icons.play_arrow,
                  color: isCurrentlyPlaying ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
                tooltip: isCurrentlyPlaying ? LocaleKeys.common_stop_preview.tr() : LocaleKeys.common_play_preview.tr(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _selectSound(String? filename) {
    // Stop any currently playing preview when selecting a new sound
    if (_isPlaying) {
      _stopPreview();
    }

    setState(() {
      _selectedSound = filename;
    });
    widget.onSoundSelected(filename);
  }

  Future<void> _previewSound(String filename) async {
    // Stop any currently playing preview first
    if (_isPlaying) {
      await _stopPreview();
    }

    try {
      _previewPlayer = AudioPlayer();
      await _previewPlayer!.setAsset('assets/audio/$filename');
      await _previewPlayer!.setVolume(0.5);
      setState(() {
        _isPlaying = true;
        _currentlyPlayingSound = filename;
      });
      await _previewPlayer!.play();

      // Listen for the audio completing naturally
      _previewPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _stopPreview();
        }
      });
    } catch (e) {
      // Show error snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing sound: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
      _stopPreview();
    }
  }

  Future<void> _stopPreview({bool updateState = true}) async {
    if (_previewPlayer != null) {
      try {
        await _previewPlayer!.stop();
        await _previewPlayer!.dispose();
      } catch (e) {
        // Ignore errors when stopping/disposing
      }
      _previewPlayer = null;
    }

    if (mounted && updateState) {
      setState(() {
        _isPlaying = false;
        _currentlyPlayingSound = null;
      });
    }
  }
}
