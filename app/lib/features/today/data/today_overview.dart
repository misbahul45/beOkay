class TodayOverview {
  const TodayOverview({
    required this.date,
    required this.greeting,
    required this.timezone,
    required this.glucoseUnit,
    required this.generatedAt,
  });

  final String date;
  final String greeting;
  final String timezone;
  final String glucoseUnit;
  final DateTime generatedAt;

  factory TodayOverview.fromJson(Map<String, dynamic> json) => TodayOverview(
    date: json['date'] as String,
    greeting: json['greeting'] as String,
    timezone: json['timezone'] as String,
    glucoseUnit: json['glucoseUnit'] as String,
    generatedAt: DateTime.parse(json['generatedAt'] as String),
  );
}
