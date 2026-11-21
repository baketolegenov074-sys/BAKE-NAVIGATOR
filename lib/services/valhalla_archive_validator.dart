import 'dart:io';

import 'package:crypto/crypto.dart';

const String expectedShymkentValhallaSha256 =
    'a5b4326bbe3991c4b0a40735b7c2713c89d3aa62323f347e514d95897eceee8e';

/// Streams the archive through SHA-256 without loading the full file in memory.
Future<bool> hasValidShymkentValhallaSha256(
  File archive, {
  String expectedSha256 = expectedShymkentValhallaSha256,
}) async {
  if (!await archive.exists()) return false;
  final digest = await sha256.bind(archive.openRead()).first;
  return digest.toString() == expectedSha256.toLowerCase();
}
