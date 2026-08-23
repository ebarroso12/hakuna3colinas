class TopStats {
  final double distanceMeters;
  final double avgSpeedKmh;
  final double calories;
  final Duration duration;
  final bool caloriesIsEstimate;

  TopStats({
    required this.distanceMeters,
    required this.avgSpeedKmh,
    required this.calories,
    required this.duration,
    required this.caloriesIsEstimate,
  });

  double get distanceKm => distanceMeters / 1000;

  static final zero = TopStats(
    distanceMeters: 0,
    avgSpeedKmh: 0,
    calories: 0,
    duration: Duration.zero,
    caloriesIsEstimate: true,
  );
}
