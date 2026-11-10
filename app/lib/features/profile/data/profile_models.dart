class Profile {
  const Profile({
    required this.exists,
    required this.displayName,
    required this.birthYear,
    required this.missing,
  });

  final bool exists;
  final String displayName;
  final int? birthYear;
  final List<String> missing;

  bool get isComplete => missing.isEmpty;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    exists: json['exists'] as bool,
    displayName: json['displayName'] as String,
    birthYear: json['birthYear'] as int?,
    missing:
        ((json['completeness'] as Map<String, dynamic>)['missing']
                as List<dynamic>)
            .cast<String>(),
  );
}
