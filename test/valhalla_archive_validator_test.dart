import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bake_navigator/services/valhalla_archive_validator.dart';

void main() {
  group('Shymkent Valhalla archive integrity', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('bake-valhalla-');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('accepts bytes matching their SHA-256 digest', () async {
      final bytes = 'Shymkent Valhalla archive'.codeUnits;
      final archive = File('${tempDirectory.path}/shymkent-valhalla.tar');
      await archive.writeAsBytes(bytes, flush: true);
      final expected = sha256.convert(bytes).toString();

      expect(
        await hasValidShymkentValhallaSha256(
          archive,
          expectedSha256: expected,
        ),
        isTrue,
      );
    });

    test('rejects modified archive bytes', () async {
      final archive = File('${tempDirectory.path}/modified.tar');
      await archive.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      expect(await hasValidShymkentValhallaSha256(archive), isFalse);
    });

    test('rejects a missing archive', () async {
      final archive = File('${tempDirectory.path}/missing.tar');
      expect(await hasValidShymkentValhallaSha256(archive), isFalse);
    });
  });
}
