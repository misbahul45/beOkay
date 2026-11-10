enum GlucoseUnit {
  mgDl('mg/dL'),
  mmolL('mmol/L');

  const GlucoseUnit(this.wire);
  final String wire;
  String get label => wire;

  static GlucoseUnit parse(String value) => GlucoseUnit.values.firstWhere(
    (unit) => unit.wire == value,
    orElse: () => GlucoseUnit.mgDl,
  );
}

enum TextSizePreference {
  system('system', 'Ikuti sistem', 1.0),
  large('large', 'Besar', 1.15),
  extraLarge('extra_large', 'Sangat besar', 1.3);

  const TextSizePreference(this.wire, this.label, this.scale);
  final String wire;
  final String label;
  final double scale;

  static TextSizePreference parse(String value) =>
      TextSizePreference.values.firstWhere(
        (item) => item.wire == value,
        orElse: () => TextSizePreference.system,
      );
}

class Preferences {
  const Preferences({
    required this.locale,
    required this.timezone,
    required this.glucoseUnit,
    required this.textSize,
    required this.reduceMotion,
    required this.isDefault,
  });

  static const defaults = Preferences(
    locale: 'id-ID',
    timezone: 'Asia/Jakarta',
    glucoseUnit: GlucoseUnit.mgDl,
    textSize: TextSizePreference.system,
    reduceMotion: false,
    isDefault: true,
  );

  final String locale;
  final String timezone;
  final GlucoseUnit glucoseUnit;
  final TextSizePreference textSize;
  final bool reduceMotion;
  final bool isDefault;

  factory Preferences.fromJson(Map<String, dynamic> json) => Preferences(
    locale: json['locale'] as String,
    timezone: json['timezone'] as String,
    glucoseUnit: GlucoseUnit.parse(json['glucoseUnit'] as String),
    textSize: TextSizePreference.parse(json['textSize'] as String),
    reduceMotion: json['reduceMotion'] as bool,
    isDefault: json['isDefault'] as bool,
  );
}

class TimezoneOption {
  const TimezoneOption(this.id, this.label);
  final String id;
  final String label;
}

const supportedTimezones = <TimezoneOption>[
  TimezoneOption('Asia/Jakarta', 'WIB · Jakarta'),
  TimezoneOption('Asia/Makassar', 'WITA · Makassar'),
  TimezoneOption('Asia/Jayapura', 'WIT · Jayapura'),
  TimezoneOption('Asia/Singapore', 'Singapura'),
  TimezoneOption('Asia/Kuala_Lumpur', 'Kuala Lumpur'),
  TimezoneOption('Asia/Bangkok', 'Bangkok'),
  TimezoneOption('Australia/Perth', 'Perth'),
  TimezoneOption('UTC', 'UTC'),
];
