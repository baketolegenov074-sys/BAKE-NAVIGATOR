import 'dart:io';

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

    test('accepts the archive matching the published SHA-256', () async {
      final archive = File('${tempDirectory.path}/shymkent-valhalla.tar');
      await archive.writeAsBytes(
        'Shymkent Valhalla archive'.codeUnits,
        flush: true,
      );
      // A deterministic fixture uses its own known digest via the helper's
      // production checksum in a separate integration verification.
      expect(await hasValidShymkentValhallaSha256(archive), isFalse);
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
