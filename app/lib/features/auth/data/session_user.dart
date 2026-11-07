class SessionUser {
  const SessionUser({required this.id, required this.email, required this.name, required this.emailVerified});

  final String id;
  final String email;
  final String name;
  final bool emailVerified;

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String? ?? '',
        emailVerified: json['emailVerified'] as bool? ?? false,
      );
}

class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.token,
    required this.userAgent,
    required this.ipAddress,
    required this.createdAt,
    required this.isCurrent,
  });

  final String id;
  final String token;
  final String userAgent;
  final String ipAddress;
  final DateTime createdAt;
  final bool isCurrent;
}
