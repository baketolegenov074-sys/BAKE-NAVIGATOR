import 'package:flutter_test/flutter_test.dart';
import 'package:bake_navigator/services/offline_address_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline Shymkent address search', () {
    late OfflineAddressSearch search;

    setUp(() {
      search = OfflineAddressSearch();
    });

    test('finds a shopping centre by its brand name', () async {
      final results = await search.search('mega planet');
      expect(
        results.any((feature) =>
            (feature['properties'] as Map)['name'] == 'Mega Planet'),
        isTrue,
      );
    });

    test('tolerates a one-character typo in an organization name', () async {
      final results = await search.search('мега планетт');
      expect(
        results.any((feature) =>
            (feature['properties'] as Map)['name'] == 'Mega Planet'),
        isTrue,
      );
    });

    test('finds a POI by an alternate local spelling', () async {
      final results = await search.search('шимкент плаза');
      expect(
        results.any((feature) =>
            (feature['properties'] as Map)['name'] == 'Shymkent Plaza'),
        isTrue,
      );
    });

    test('keeps the numbered school separate from ordinary POIs', () async {
      final results = await search.search('школа 88');
      expect(
        results.any((feature) =>
            (feature['properties'] as Map)['name'] == 'Школа №88'),
        isTrue,
      );
    });
  });
}
