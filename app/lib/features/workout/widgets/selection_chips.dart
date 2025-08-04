import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:waico/generated/locale_keys.g.dart';

class SelectionChips extends StatelessWidget {
  final List<String> options;
  final dynamic selectedOption; // Can be String or List<String>
  final ValueChanged<dynamic> onSelectionChanged;
  final bool multiSelect;
  final String? emptyMessage;
  final bool scrollable;

  const SelectionChips({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.onSelectionChanged,
    this.multiSelect = false,
    this.emptyMessage,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (options.isEmpty) {
      return Text(
        emptyMessage ?? LocaleKeys.common_no_options_available.tr(),
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    final List<String> selectedList = multiSelect
        ? (selectedOption as List<String>? ?? [])
        : (selectedOption != null ? [selectedOption as String] : []);

    Widget chipsWidget = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selectedList.contains(option);

        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (selected) {
            if (multiSelect) {
              final newSelection = List<String>.from(selectedList);
              if (selected) {
                newSelection.add(option);
              } else {
                newSelection.remove(option);
              }
              onSelectionChanged(newSelection);
            } else {
              onSelectionChanged(selected ? option : null);
            }
          },
          color: WidgetStatePropertyAll(Colors.white),
          checkmarkColor: theme.colorScheme.primary,
          labelStyle: TextStyle(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );

    if (scrollable && options.length > 6) {
      return SizedBox(height: 150, child: SingleChildScrollView(child: chipsWidget));
    }

    return chipsWidget;
  }
}

class SuggestionChips extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSuggestionTapped;
  final String? title;

  const SuggestionChips({super.key, required this.suggestions, required this.onSuggestionTapped, this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 35,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(suggestion),
                color: WidgetStatePropertyAll(Colors.white),
                onPressed: () => onSuggestionTapped(suggestion),
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                labelStyle: TextStyle(color: theme.colorScheme.primary, fontSize: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              );
            },
          ),
        ),
      ],
    );
  }
}
