class ContextualInsight {
  ContextualInsight.fromJson(Map<String, dynamic> j)
    : code = j['code'] as String,
      domain = j['domain'] as String,
      title = j['title'] as String,
      body = j['body'] as String;
  final String code, domain, title, body;
}

/// Pengamatan deterministik dari catatan sendiri (maks 3). Bukan penilaian nilai kesehatan.
class ContextualInsights {
  ContextualInsights.fromJson(Map<String, dynamic> j)
    : items = [
        for (final v in (j['items'] as List))
          ContextualInsight.fromJson(v as Map<String, dynamic>),
      ],
      suppressed = (j['suppressed'] as num?)?.toInt() ?? 0;
  final List<ContextualInsight> items;
  final int suppressed;
}
