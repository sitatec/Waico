import 'package:flutter/material.dart';
import '../widgets/health_dashboard.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final features = <Map<String, dynamic>>[
      {
        'title': 'Meditation',
        'color': const Color.fromARGB(108, 234, 136, 93),
        'image': {'url': 'assets/images/meditation.png', 'size': 105.0},
      },
      {
        'title': 'Sleep',
        'color': const Color.fromARGB(108, 79, 152, 216),
        'image': {'url': 'assets/images/sleep.png', 'size': 120.0},
      },
      {
        'title': 'Nutrition',
        'color': const Color.fromARGB(108, 32, 179, 128),
        'image': {'url': 'assets/images/nutrition.png', 'size': 85.0},
      },
      {
        'title': 'Workout',
        'color': const Color.fromARGB(118, 232, 194, 89),
        'image': {'url': 'assets/images/workout.png', 'size': 110.0},
      },
    ];
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            surfaceTintColor: theme.colorScheme.primary,
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
                childAspectRatio: 1.1,
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
            sizeConstraints: BoxConstraints(minWidth: 160, minHeight: 60),
          ),
        ),
        child: FloatingActionButton(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onPressed: () {},
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.voice_chat, color: theme.colorScheme.onPrimary),
              const SizedBox(width: 8),
              Text(
                "Counselor",
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onPrimary,
                ),
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
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
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
