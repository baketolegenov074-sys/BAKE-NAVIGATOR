import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class KazakhstanMapAsset {
  const KazakhstanMapAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String name;
  final String url;
  final int size;
  final String sha256;
}

class KazakhstanMapRelease {
  const KazakhstanMapRelease({
    required this.id,
    required this.assets,
    required this.totalBytes,
  });

  final int id;
  final List<KazakhstanMapAsset> assets;
  final int totalBytes;
}

class KazakhstanMapDownloader {
  static const _releaseApi =
      'https://api.github.com/repos/baketolegenov074-sys/BAKE-NAVIGATOR/releases/tags/kazakhstan-map-latest';

  Future<KazakhstanMapRelease> fetchLatestRelease() async {
    final response = await http.get(
      Uri.parse(_releaseApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'BAKE-Navigator-Android',
      },
    ).timeout(const Duration(seconds: 40));

    if (response.statusCode != 200) {
      throw HttpException(
        'Не удалось получить сведения о карте (HTTP ${response.statusCode}).',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rawAssets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final assets = rawAssets
        .where((item) =>
            (item['name'] as String? ?? '')
                .startsWith('kazakhstan.mbtiles.part-'))
        .map((item) {
          final digest = (item['digest'] as String? ?? '');
          if (!digest.startsWith('sha256:')) {
            throw const FormatException('У части карты отсутствует SHA-256.');
          }
          return KazakhstanMapAsset(
            name: item['name'] as String,
            url: item['browser_download_url'] as String,
            size: item['size'] as int,
            sha256: digest.substring(7).toLowerCase(),
          );
        })
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (assets.isEmpty) {
      throw const FormatException('В публикации не найдены части карты Казахстана.');
    }
    for (var i = 0; i < assets.length; i++) {
      final expected = 'kazakhstan.mbtiles.part-${i.toString().padLeft(2, '0')}';
      if (assets[i].name != expected || assets[i].size <= 0) {
        throw const FormatException('Неполный или неверно упорядоченный пакет карты.');
      }
    }

    return KazakhstanMapRelease(
      id: json['id'] as int,
      assets: assets,
      totalBytes: assets.fold<int>(0, (sum, asset) => sum + asset.size),
    );
  }

  Future<String> download({
    required KazakhstanMapRelease release,
    required Directory directory,
    required void Function(int receivedBytes, int totalBytes, String status)
        onProgress,
  }) async {
    await directory.create(recursive: true);
    final assembling = File('${directory.path}/kazakhstan-map.assembling');
    final destination = File('${directory.path}/bake_offline_map.mbtiles');

    var completedBytes = 0;
    if (await assembling.exists()) {
      completedBytes = await assembling.length();
    }

    var boundary = 0;
    var completedParts = 0;
    for (final asset in release.assets) {
      boundary += asset.size;
      if (completedBytes >= boundary) {
        completedParts++;
      } else {
        break;
      }
    }
    final validBoundary = release.assets.take(completedParts).fold<int>(
      0,
      (sum, asset) => sum + asset.size,
    );
    if (completedBytes != validBoundary) {
      if (await assembling.exists()) {
        await assembling.truncate(validBoundary);
      }
      completedBytes = validBoundary;
    }

    for (var index = completedParts; index < release.assets.length; index++) {
      final asset = release.assets[index];
      final chunk = File('${directory.path}/${asset.name}.download');
      if (await chunk.exists()) await chunk.delete();

      onProgress(
        completedBytes,
        release.totalBytes,
        'Загрузка части ${index + 1} из ${release.assets.length}',
      );

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(asset.url))
          ..followRedirects = true
          ..headers['User-Agent'] = 'BAKE-Navigator-Android';
        final response = await client.send(request).timeout(
          const Duration(minutes: 3),
        );
        if (response.statusCode != 200) {
          throw HttpException(
            'Ошибка загрузки части ${index + 1}: HTTP ${response.statusCode}.',
          );
        }

        final sink = chunk.openWrite();
        var partBytes = 0;
        var lastReported = 0;
        try {
          await for (final data in response.stream.timeout(const Duration(minutes: 5))) {
            sink.add(data);
            partBytes += data.length;
            if (partBytes - lastReported >= 16 * 1024 * 1024) {
              lastReported = partBytes;
              onProgress(
                completedBytes + partBytes,
                release.totalBytes,
                'Загрузка части ${index + 1} из ${release.assets.length}',
              );
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        if (partBytes != asset.size || await chunk.length() != asset.size) {
          throw HttpException('Размер части ${index + 1} не совпадает с ожидаемым.');
        }
        final digest = await sha256.bind(chunk.openRead()).first;
        if (digest.toString().toLowerCase() != asset.sha256) {
          throw const FormatException('SHA-256 части карты не совпал.');
        }
      } finally {
        client.close();
      }

      final output = assembling.openWrite(mode: FileMode.writeOnlyAppend);
      try {
        await for (final data in chunk.openRead()) {
          output.add(data);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      completedBytes += asset.size;
      await chunk.delete();
      onProgress(
        completedBytes,
        release.totalBytes,
        'Часть ${index + 1} из ${release.assets.length} проверена',
      );
    }

    if (!await assembling.exists() ||
        await assembling.length() != release.totalBytes) {
      throw const FormatException('Собранный файл карты имеет неверный размер.');
    }

    final backup = File('${directory.path}/bake_offline_map.previous');
    if (await backup.exists()) await backup.delete();
    final hadPrevious = await destination.exists();
    if (hadPrevious) await destination.rename(backup.path);
    try {
      await assembling.rename(destination.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (hadPrevious && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }

    onProgress(
      release.totalBytes,
      release.totalBytes,
      'Файл карты загружен и собран',
    );
    return destination.path;
  }
}
