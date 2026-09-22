import 'package:agentkhata/features/update/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final good = {'versionName': '1.0.1', 'versionCode': 2, 'apkUrl': 'https://corebari.net/downloads/agentkhata/agentkhata-1.0.1.apk'};

  test('a complete https release is accepted', () {
    final r = AppRelease.fromJson({...good, 'notes': {'en': 'Faster sync', 'bn': 'দ্রুত সিংক'}})!;
    expect(r.versionCode, 2);
    expect(r.notes!['bn'], 'দ্রুত সিংক');
  });

  test('a download over plain http, or a missing field, is refused', () {
    expect(AppRelease.fromJson({...good, 'apkUrl': 'http://example.com/x.apk'}), isNull);
    expect(AppRelease.fromJson({...good}..remove('versionCode')), isNull);
  });

  test('only a higher version code counts as an update', () {
    final r = AppRelease.fromJson(good)!;
    expect(UpdateState(currentName: '1.0.0', currentCode: 1, latest: r).available, isTrue);
    expect(UpdateState(currentName: '1.0.1', currentCode: 2, latest: r).available, isFalse);
    expect(const UpdateState(currentName: '1.0.0', currentCode: 1).available, isFalse);
  });
}
