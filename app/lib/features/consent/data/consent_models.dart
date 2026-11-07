class PolicyPurpose {
  const PolicyPurpose({
    required this.purpose,
    required this.required,
    required this.title,
    required this.description,
    required this.dataCategories,
    required this.withdrawalEffect,
  });

  final String purpose;
  final bool required;
  final String title;
  final String description;
  final List<String> dataCategories;
  final String withdrawalEffect;

  factory PolicyPurpose.fromJson(Map<String, dynamic> json) => PolicyPurpose(
        purpose: json['purpose'] as String,
        required: json['required'] as bool,
        title: json['title'] as String,
        description: json['description'] as String,
        dataCategories: (json['dataCategories'] as List<dynamic>).cast<String>(),
        withdrawalEffect: json['withdrawalEffect'] as String,
      );
}

class ConsentPolicy {
  const ConsentPolicy({required this.version, required this.summary, required this.purposes});

  final String version;
  final String summary;
  final List<PolicyPurpose> purposes;

  factory ConsentPolicy.fromJson(Map<String, dynamic> json) => ConsentPolicy(
        version: json['version'] as String,
        summary: json['summary'] as String,
        purposes: (json['purposes'] as List<dynamic>).map((item) => PolicyPurpose.fromJson(item as Map<String, dynamic>)).toList(),
      );
}

enum ConsentStatus { granted, withdrawn, notGiven, reconsentRequired }

ConsentStatus _parseStatus(String value) => switch (value) {
      'granted' => ConsentStatus.granted,
      'withdrawn' => ConsentStatus.withdrawn,
      'reconsent_required' => ConsentStatus.reconsentRequired,
      _ => ConsentStatus.notGiven,
    };

class PurposeConsent {
  const PurposeConsent({required this.purpose, required this.required, required this.status, required this.policyVersion, required this.grantedAt, required this.withdrawnAt});

  final String purpose;
  final bool required;
  final ConsentStatus status;
  final String? policyVersion;
  final DateTime? grantedAt;
  final DateTime? withdrawnAt;

  bool get isActive => status == ConsentStatus.granted;

  factory PurposeConsent.fromJson(Map<String, dynamic> json) => PurposeConsent(
        purpose: json['purpose'] as String,
        required: json['required'] as bool,
        status: _parseStatus(json['status'] as String),
        policyVersion: json['policyVersion'] as String?,
        grantedAt: DateTime.tryParse(json['grantedAt'] as String? ?? ''),
        withdrawnAt: DateTime.tryParse(json['withdrawnAt'] as String? ?? ''),
      );
}

class ConsentHistoryItem {
  const ConsentHistoryItem({required this.purpose, required this.policyVersion, required this.grantedAt, required this.withdrawnAt});

  final String purpose;
  final String policyVersion;
  final DateTime grantedAt;
  final DateTime? withdrawnAt;

  factory ConsentHistoryItem.fromJson(Map<String, dynamic> json) => ConsentHistoryItem(
        purpose: json['purpose'] as String,
        policyVersion: json['policyVersion'] as String,
        grantedAt: DateTime.parse(json['grantedAt'] as String),
        withdrawnAt: DateTime.tryParse(json['withdrawnAt'] as String? ?? ''),
      );
}

class ConsentOverview {
  const ConsentOverview({required this.policyVersion, required this.purposes, required this.history});

  final String policyVersion;
  final List<PurposeConsent> purposes;
  final List<ConsentHistoryItem> history;

  PurposeConsent? of(String purpose) {
    for (final item in purposes) {
      if (item.purpose == purpose) return item;
    }
    return null;
  }

  factory ConsentOverview.fromJson(Map<String, dynamic> json) => ConsentOverview(
        policyVersion: json['policyVersion'] as String,
        purposes: (json['purposes'] as List<dynamic>).map((item) => PurposeConsent.fromJson(item as Map<String, dynamic>)).toList(),
        history: (json['history'] as List<dynamic>).map((item) => ConsentHistoryItem.fromJson(item as Map<String, dynamic>)).toList(),
      );
}
