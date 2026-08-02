import 'dart:io';

class DesktopFileService {
  const DesktopFileService._();

  static Future<bool> openFile(String path) async {
    if (Platform.isMacOS) {
      return _run('open', <String>[path]);
    }
    if (Platform.isWindows) {
      return _run('explorer.exe', <String>[path]);
    }
    return _run('xdg-open', <String>[path]);
  }

  static Future<bool> revealFile(String path) async {
    if (Platform.isMacOS) {
      return _run('open', <String>['-R', path]);
    }
    if (Platform.isWindows) {
      return _run('explorer.exe', <String>['/select,', path]);
    }
    return _run('xdg-open', <String>[File(path).parent.path]);
  }

  static Future<bool> _run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
