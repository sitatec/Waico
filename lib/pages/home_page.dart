import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final features = <Map<String, dynamic>>[
      {
        'title': 'Meditation',
        'color': const Color.fromARGB(109, 254, 148, 102),
        'image': {'url': 'assets/images/meditation.png', 'size': 105.0},
      },
      {
        'title': 'Sleep',
        'color': const Color.fromARGB(109, 93, 175, 247),
        'image': {'url': 'assets/images/sleep.png', 'size': 120.0},
      },
      {
        'title': 'Nutrition',
        'color': const Color.fromARGB(108, 38, 204, 146),
        'image': {'url': 'assets/images/nutrition.png', 'size': 85.0},
      },
      {
        'title': 'Workout',
        'color': const Color.fromARGB(110, 250, 211, 100),
        'image': {'url': 'assets/images/workout.png', 'size': 110.0},
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text(
          'Welcome Back',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.black),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: GridView.builder(
          itemCount: features.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: 0.9,
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
