import '../../../core/network/api_client.dart';

class NextAction {
  NextAction.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      step = (j['step'] as String?) ?? 'TODAY',
      spark = (j['spark'] as String?) ?? 'NEUTRAL',
      title = j['title'] as String,
      body = (j['body'] as String?) ?? '',
      target = (j['target'] as String?) ?? 'LOG',
      ref = j['ref'] as String?;
  final String kind, step, spark, title, body, target;
  final String? ref;
}

class WeekProgress {
  WeekProgress.fromJson(Map<String, dynamic> j)
    : activeDays = (j['activeDays'] as num?)?.toInt() ?? 0,
      deviceDays = (j['deviceDays'] as num?)?.toInt() ?? 0,
      total = (j['total'] as num?)?.toDouble() ?? 0;
  final int activeDays, deviceDays;
  final double total;
}

class NextActionView {
  NextActionView.fromJson(Map<String, dynamic> j)
    : journey = (j['journey'] as String?) ?? 'UNDETERMINED',
      flow = [for (final f in (j['flow'] as List? ?? const [])) f as String],
      action = NextAction.fromJson(j['action'] as Map<String, dynamic>),
      energy = j['energy'] as String?,
      week = WeekProgress.fromJson(
        ((j['progress'] as Map?)?['week'] as Map<String, dynamic>?) ?? const {},
      ),
      best7 =
          (((j['progress'] as Map?)?['personalBest'] as Map?)?['best7DayActive']
                  as num?)
              ?.toInt() ??
          0,
      returned =
          ((j['progress'] as Map?)?['returnAfterBreak'] as Map?)?['returned'] ==
          true;
  final String journey;
  final List<String> flow;
  final NextAction action;
  final String? energy;
  final WeekProgress week;
  final int best7;
  final bool returned;
}

class NextActionRepository {
  NextActionRepository(this._api);
  final ApiClient _api;

  Future<NextActionView> get() async => NextActionView.fromJson(
    (await _api.get('/api/me/today/next-action')).object,
  );

  Future<void> setEnergy(String energy) async =>
      _api.put('/api/me/checkins/energy', body: {'energy': energy});
}
