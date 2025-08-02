import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';
import 'package:waico/features/meditation/repositories/meditation_repository.dart';
import 'package:waico/features/meditation/pages/meditation_type_selection_page.dart';
import 'package:waico/features/meditation/widgets/meditation_guide_card.dart';
import 'package:waico/features/meditation/widgets/meditation_sound_player.dart';
import 'package:waico/features/meditation/meditation_guide_generator.dart';

/// Page that displays all user's meditation guides with option to create new ones
class MeditationPage extends StatefulWidget {
  const MeditationPage({super.key});

  @override
  State<MeditationPage> createState() => _MeditationPageState();
}

class _MeditationPageState extends State<MeditationPage> {
  final MeditationRepository _meditationRepository = MeditationRepository();
  List<MeditationGuide> _meditationGuides = [];
  bool _isLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadMeditationGuides();
  }

  Future<void> _loadMeditationGuides() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final guides = _meditationRepository.getAllMeditationGuides();
      setState(() {
        _meditationGuides = guides;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load meditation guides: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleCompletion(MeditationGuide guide) async {
    try {
      if (guide.isCompleted) {
        await _meditationRepository.markAsIncomplete(guide.id);
      } else {
        await _meditationRepository.markAsCompleted(guide.id);
      }
      await _loadMeditationGuides();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update meditation status: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteMeditation(MeditationGuide guide) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Meditation'),
        content: Text('Are you sure you want to delete "${guide.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _meditationRepository.deleteMeditationGuide(guide.id);
        await _loadMeditationGuides();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Meditation deleted successfully'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete meditation: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  void _showCreateMeditation() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => MeditationTypeSelectionPage(onTypeSelected: _generateMeditationGuide)),
    );
  }

  Future<void> _generateMeditationGuide(
    MeditationType type,
    int durationMinutes,
    String? customTitle,
    String? backgroundSound,
  ) async {
    Navigator.of(context).pop(); // Close type selection page

    setState(() {
      _isGenerating = true;
    });

    try {
      final guide = await MeditationGuideGenerator.generateGuide(
        type,
        durationMinutes,
        customTitle: customTitle,
        backgroundSound: backgroundSound,
      );
      _meditationRepository.save(guide);
      log("Generated meditation guide: ${guide.title} (${guide.type}) $guide");

      await _loadMeditationGuides();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${guide.title} created successfully!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate meditation: $e'), backgroundColor: Colors.red));
      }
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _viewMeditationGuide(MeditationGuide guide) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MeditationGuideViewer(guide: guide),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Meditation', style: TextStyle(fontSize: 20)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMeditationGuides,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats card
                    _buildStatsCard(),
                    const SizedBox(height: 24),

                    // Meditation guides section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Your Meditations',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                        ),
                        if (_meditationGuides.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              // TODO: Add filter/sort options
                            },
                            icon: const Icon(Icons.sort, size: 16),
                            label: const Text('Sort'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isGenerating)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200, width: 1.5),
                        ),
                        child: Text(
                          'Generation can take 30 seconds to a few minutes depending on the duration and your device performance. Please bear with us!',
                          style: TextStyle(color: Colors.blue.shade700, fontSize: 14, height: 1.4),
                        ),
                      ),
                    const SizedBox(height: 16),

                    if (_meditationGuides.isEmpty)
                      _buildEmptyState()
                    else
                      ..._meditationGuides
                          .map(
                            (guide) => MeditationGuideCard(
                              guide: guide,
                              onTap: () => _viewMeditationGuide(guide),
                              onToggleCompletion: () => _toggleCompletion(guide),
                              onDelete: () => _deleteMeditation(guide),
                            ),
                          )
                          .toList(),

                    const SizedBox(height: 100), // Space for FAB
                  ],
                ),
              ),
            ),
      floatingActionButton: _isGenerating
          ? FloatingActionButton(
              onPressed: null,
              backgroundColor: Colors.grey,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            )
          : FloatingActionButton.extended(
              onPressed: _showCreateMeditation,
              backgroundColor: Theme.of(context).colorScheme.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'New Meditation',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
    );
  }

  Widget _buildStatsCard() {
    final totalCount = _meditationGuides.length;
    final completedCount = _meditationGuides.where((g) => g.isCompleted).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.self_improvement, color: Colors.white, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Meditation Journey',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalCount',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text('Total Meditations', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$completedCount',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text('Completed', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Icon(Icons.self_improvement, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No Meditations Yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first personalized meditation guide to begin your mindfulness journey.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500, height: 1.4),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isGenerating ? null : _showCreateMeditation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create Meditation'),
          ),
        ],
      ),
    );
  }
}

class MeditationGuideViewer extends StatelessWidget {
  final MeditationGuide guide;

  const MeditationGuideViewer({super.key, required this.guide});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(guide.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        guide.type,
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      '${guide.durationMinutes} min',
                      style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                if (guide.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(guide.description, style: TextStyle(fontSize: 16, color: Colors.grey.shade700, height: 1.4)),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: MeditationSoundPlayer(guide: guide),
            ),
          ),
        ],
      ),
    );
  }
}
