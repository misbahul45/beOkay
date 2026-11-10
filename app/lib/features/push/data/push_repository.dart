import 'dart:io';

import '../../../core/network/account_scoped_repository.dart';

class PushDevice {
  PushDevice.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      tokenHint = j['tokenHint'] as String;
  final String id, tokenHint;
}

class PushRepository extends AccountScopedRepository {
  PushRepository(super.api, {required super.isCurrentAccount});

  Future<PushDevice> register(String token, {String? appVersion}) async =>
      PushDevice.fromJson(
        (await write('POST', '/api/me/push-devices', {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'appVersion': ?appVersion,
        })).object,
      );

  Future<void> unregister(String id) async {
    await api.send('DELETE', '/api/me/push-devices/$id');
  }
}
