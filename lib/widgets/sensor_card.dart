import "package:flutter/material.dart";

/// A collapsible card showing one sensor's live readings, collapsed by
/// default.
class SensorCard extends StatefulWidget {
  const SensorCard({
    super.key,
    required this.title,
    required this.buildReadings,
    this.tick,
    this.throttle = const Duration(milliseconds: 100),
  });

  final String title;
  final List<String> Function() buildReadings;
  final Listenable? tick;
  final Duration throttle;

  @override
  State<SensorCard> createState() => _SensorCardState();
}

class _SensorCardState extends State<SensorCard> {
  bool _expanded = false;
  DateTime _lastRebuild = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    widget.tick?.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant SensorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) {
      oldWidget.tick?.removeListener(_onTick);
      widget.tick?.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.tick?.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!mounted || !_expanded) {
      return;
    }
    DateTime now = DateTime.now();
    // Throttle rebuilds to avoid excessive redraws for high-frequency sensors.
    if (now.difference(_lastRebuild) < widget.throttle) {
      return;
    }
    _lastRebuild = now;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      onExpansionChanged: (bool expanded) =>
          setState(() => _expanded = expanded),
      children: widget
          .buildReadings()
          .map(
            (String reading) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(reading),
              ),
            ),
          )
          .toList(),
    ),
  );
}
