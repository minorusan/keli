import 'package:flutter_test/flutter_test.dart';
import 'package:keli_client/services/update_service.dart';

void main() {
  test('parseUpdate flags a newer build as available', () {
    final info = parseUpdate(
      {'version': '1.0.1', 'build': 2, 'apkUrl': '/keli.apk', 'hasApk': true},
      currentBuild: 1,
      baseUrl: 'http://host:9120',
    );
    expect(info.available, isTrue);
    expect(info.apkUrl, 'http://host:9120/keli.apk');
  });

  test('parseUpdate: same build is not an update', () {
    final info = parseUpdate(
      {'version': '1.0.0', 'build': 1, 'hasApk': true},
      currentBuild: 1,
      baseUrl: 'http://host:9120',
    );
    expect(info.available, isFalse);
  });

  test('parseUpdate: no APK means no update even if build is higher', () {
    final info = parseUpdate(
      {'version': '2.0.0', 'build': 9, 'hasApk': false},
      currentBuild: 1,
      baseUrl: 'http://host:9120',
    );
    expect(info.available, isFalse);
  });
}
