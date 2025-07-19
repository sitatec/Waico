import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/widgets/setup_card.dart';
import 'package:waico/features/workout/widgets/custom_text_field.dart';
import 'package:waico/features/workout/widgets/selection_chips.dart';

class PhysicalStatsStep extends StatefulWidget {
  final WorkoutSetupData data;
  final ValueChanged<WorkoutSetupData> onDataChanged;

  const PhysicalStatsStep({super.key, required this.data, required this.onDataChanged});

  @override
  State<PhysicalStatsStep> createState() => _PhysicalStatsStepState();
}

class _PhysicalStatsStepState extends State<PhysicalStatsStep> {
  late TextEditingController _weightController;
  late TextEditingController _heightController;
  late TextEditingController _ageController;

  final List<String> _genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(text: widget.data.weight?.toString() ?? '');
    _heightController = TextEditingController(text: widget.data.height?.toString() ?? '');
    _ageController = TextEditingController(text: widget.data.age?.toString() ?? '');
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PhysicalStatsStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _weightController.text = widget.data.weight?.toString() ?? '';
      _heightController.text = widget.data.height?.toString() ?? '';
      _ageController.text = widget.data.age?.toString() ?? '';
    }
  }

  void _updateWeight(String value) {
    final weight = double.tryParse(value);
    widget.onDataChanged(widget.data.copyWith(weight: weight));
  }

  void _updateHeight(String value) {
    final height = double.tryParse(value);
    widget.onDataChanged(widget.data.copyWith(height: height));
  }

  void _updateAge(String value) {
    final age = int.tryParse(value);
    widget.onDataChanged(widget.data.copyWith(age: age));
  }

  void _updateGender(dynamic gender) {
    widget.onDataChanged(widget.data.copyWith(gender: gender as String?));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Let\'s start with your basic info',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'This information helps us create a personalized workout plan for you.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 24),

          // Weight and Height
          SetupCard(
            title: 'Physical Measurements',
            icon: Icons.straighten,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _weightController,
                        label: 'Weight',
                        suffix: 'kg',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        onChanged: _updateWeight,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CustomTextField(
                        controller: _heightController,
                        label: 'Height',
                        suffix: 'cm',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        onChanged: _updateHeight,
                      ),
                    ),
                  ],
                ),

                if (widget.data.weight != null && widget.data.height != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calculate, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'BMI: ${widget.data.bmi?.toStringAsFixed(1) ?? 'N/A'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Age
          SetupCard(
            title: 'Age',
            icon: Icons.cake,
            child: CustomTextField(
              controller: _ageController,
              label: 'Age',
              suffix: 'years',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              onChanged: _updateAge,
            ),
          ),

          const SizedBox(height: 16),

          // Gender
          SetupCard(
            title: 'Gender',
            icon: Icons.person,
            child: SelectionChips(
              options: _genderOptions,
              selectedOption: widget.data.gender,
              onSelectionChanged: _updateGender,
              multiSelect: false,
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
