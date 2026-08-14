import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef C2paTrustListDownloader = Future<List<int>> Function(Uri uri);
typedef C2paSupportDirectoryProvider = Future<Directory> Function();

class C2paTrustListService {
  const C2paTrustListService({
    this.updateInterval = const Duration(hours: 24),
    C2paTrustListDownloader? downloader,
    C2paSupportDirectoryProvider? supportDirectoryProvider,
    DateTime Function()? now,
  }) : _downloader = downloader,
       _supportDirectoryProvider = supportDirectoryProvider,
       _now = now;

  static final Uri officialTrustListUri = Uri.parse(
    'https://raw.githubusercontent.com/c2pa-org/conformance-public/'
    'refs/heads/main/trust-list/C2PA-TRUST-LIST.pem',
  );
  static const String _trustListFileName = 'c2pa-trust-list.pem';
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _responseTimeout = Duration(seconds: 15);
  static const int _maximumDownloadBytes = 2 * 1024 * 1024;

  final Duration updateInterval;
  final C2paTrustListDownloader? _downloader;
  final C2paSupportDirectoryProvider? _supportDirectoryProvider;
  final DateTime Function()? _now;

  Future<bool> refreshIfNeeded() async {
    final trustList = await _cachedTrustListFile();
    if (await _isFreshValidTrustList(trustList)) {
      return false;
    }

    try {
      final bytes = await (_downloader ?? _download)(officialTrustListUri);
      if (!_isValidPem(bytes)) {
        throw const FormatException('The C2PA trust list is not valid PEM.');
      }
      await _replaceFile(trustList, bytes);
      return true;
    } catch (_) {
      // Keep the last valid cached list, or let the caller use the bundled one.
      return false;
    }
  }

  Future<String?> settingsPathFor(String c2paToolPath) async {
    final cachedTrustList = await _cachedTrustListFile();
    if (await _isValidTrustListFile(cachedTrustList)) {
      return p.join(cachedTrustList.parent.path, 'c2pa.toml');
    }

    final bundledTrustList = File(
      p.join(p.dirname(c2paToolPath), _trustListFileName),
    );
    if (await _isValidTrustListFile(bundledTrustList)) {
      return p.join(bundledTrustList.parent.path, 'c2pa.toml');
    }
    return null;
  }

  Future<File> _cachedTrustListFile() async {
    final directory = await (_supportDirectoryProvider ?? _supportDirectory)();
    return File(p.join(directory.path, 'c2pa', _trustListFileName));
  }

  Future<bool> _isFreshValidTrustList(File file) async {
    if (!await _isValidTrustListFile(file)) {
      return false;
    }
    final modified = await file.lastModified();
    final age = (_now ?? DateTime.now)().difference(modified);
    return !age.isNegative && age < updateInterval;
  }

  Future<bool> _isValidTrustListFile(File file) async {
    try {
      if (!await file.exists() || await file.length() > _maximumDownloadBytes) {
        return false;
      }
      return _isValidPem(await file.readAsBytes());
    } catch (_) {
      return false;
    }
  }

  bool _isValidPem(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > _maximumDownloadBytes) {
      return false;
    }
    final source = utf8.decode(bytes, allowMalformed: true);
    return source.contains('-----BEGIN CERTIFICATE-----') &&
        source.contains('-----END CERTIFICATE-----');
  }

  Future<List<int>> _download(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Perfect-Collage-C2PA-Trust-Updater',
      );
      final response = await request.close().timeout(_responseTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'C2PA trust list returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }

      final bytes = <int>[];
      await for (final chunk in response.timeout(_responseTimeout)) {
        if (bytes.length + chunk.length > _maximumDownloadBytes) {
          throw const FormatException('The C2PA trust list is too large.');
        }
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _replaceFile(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final suffix = '${pid}_${(_now ?? DateTime.now)().microsecondsSinceEpoch}';
    final temporary = File('${target.path}.$suffix.tmp');
    final backup = File('${target.path}.$suffix.backup');
    await temporary.writeAsBytes(bytes, flush: true);

    try {
      if (await target.exists()) {
        await target.rename(backup.path);
      }
      try {
        await temporary.rename(target.path);
        if (await backup.exists()) {
          await backup.delete();
        }
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<Directory> _supportDirectory() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw const FileSystemException('APPDATA is not available.');
      }
      return Directory(p.join(appData, 'video_collage_mac'));
    }

    final homeDirectory = Platform.environment['HOME'];
    if (homeDirectory == null || homeDirectory.isEmpty) {
      throw const FileSystemException('HOME is not available.');
    }
    if (Platform.isMacOS) {
      return Directory(
        p.join(
          homeDirectory,
          'Library',
          'Application Support',
          'video_collage_mac',
        ),
      );
    }
    final dataHome = Platform.environment['XDG_DATA_HOME'];
    return Directory(
      dataHome == null || dataHome.isEmpty
          ? p.join(homeDirectory, '.local', 'share', 'video_collage_mac')
          : p.join(dataHome, 'video_collage_mac'),
    );
  }
}
