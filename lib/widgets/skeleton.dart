import 'package:flutter/material.dart';

/// A softly pulsing placeholder shape shown while data loads.
class Skeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const Skeleton({super.key, this.width = double.infinity, required this.height, this.radius = 8});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// Placeholder for a list of record cards.
class SkeletonCards extends StatelessWidget {
  final int count;

  const SkeletonCards({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: count,
      itemBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 40, height: 40, radius: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 180, height: 14),
                      SizedBox(height: 8),
                      Skeleton(width: 120, height: 12),
                      SizedBox(height: 12),
                      Skeleton(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder for the home screen's app grid.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisExtent: 112),
      itemCount: 12,
      itemBuilder: (_, _) => const Column(
        children: [
          SizedBox(height: 4),
          Skeleton(width: 60, height: 60, radius: 16),
          SizedBox(height: 10),
          Skeleton(width: 56, height: 10),
        ],
      ),
    );
  }
}
