import 'package:flutter/material.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/pages/counselor_page.dart';
import 'package:waico/core/widgets/health_dashboard.dart';

class HomePage extends StatelessWidget {
  static const features = <Map<String, dynamic>>[
    {
      'title': 'Meditation',
      'color': const Color.fromARGB(98, 201, 94, 0),
      'image': {'url': 'assets/images/meditation.png', 'size': 80.0},
    },
    {
      'title': 'Sleep',
      'color': const Color.fromARGB(97, 0, 58, 192),
      'image': {'url': 'assets/images/sleep.png', 'size': 90.0},
    },
    {
      'title': 'Nutrition',
      'color': const Color.fromARGB(106, 0, 113, 73),
      'image': {'url': 'assets/images/nutrition.png', 'size': 70.0},
    },
    {
      'title': 'Workout',
      'color': const Color.fromARGB(92, 210, 154, 1),
      'image': {'url': 'assets/images/workout.png', 'size': 90.0},
    },
  ];

  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            expandedHeight: MediaQuery.sizeOf(context).height * 0.34,
            flexibleSpace: FlexibleSpaceBar(
              expandedTitleScale: 1.2,
              background: ClipRRect(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                child: const HealthDashboard(),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            sliver: SliverGrid.builder(
              itemCount: features.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.3,
              ),
              itemBuilder: (context, index) {
                final feature = features[index];
                return FeatureCard(
                  title: feature['title'] as String,
                  color: feature['color'] as Color,
                  image: feature['image']['url'] as String,
                  imageSize: feature['image']['size'],
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 1400)),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Theme(
        data: theme.copyWith(
          floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
            backgroundColor: theme.colorScheme.primary,
            sizeConstraints: BoxConstraints(minWidth: 160, minHeight: 52),
          ),
        ),
        child: FloatingActionButton(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onPressed: () {
            context.navigateTo(CounselorPage());
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.voice_chat, color: theme.colorScheme.onPrimary),
              const SizedBox(width: 10),
              Text(
                "Counselor",
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onPrimary,
                ),
                textHeightBehavior: TextHeightBehavior(applyHeightToFirstAscent: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final String title;
  final Color color;
  final String image;
  final double imageSize;

  const FeatureCard({super.key, required this.title, required this.color, required this.image, this.imageSize = 90});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            child: Text(
              title,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Image.asset(
              image,
              width: imageSize,
              height: imageSize,
              fit: BoxFit.contain,
              alignment: AlignmentDirectional.bottomEnd,
            ),
          ),
        ],
      ),
    );
  }
}
