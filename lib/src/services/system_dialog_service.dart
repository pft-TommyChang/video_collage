import 'package:file_selector/file_selector.dart';

class SystemDialogService {
  const SystemDialogService();

  static const XTypeGroup _videoTypeGroup = XTypeGroup(
    label: 'Videos',
    extensions: <String>['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'],
  );

  Future<List<String>> pickVideos() async {
    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[_videoTypeGroup],
      confirmButtonText: 'Add Videos',
    );
    return files.map((file) => file.path).toList(growable: false);
  }

  Future<String?> pickSingleVideo() async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[_videoTypeGroup],
      confirmButtonText: 'Choose Video',
    );
    return file?.path;
  }

  Future<String?> pickSavePath({
    String suggestedName = 'video_collage_export.mp4',
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'MP4 Video', extensions: <String>['mp4']),
      ],
      suggestedName: suggestedName,
      confirmButtonText: 'Export',
    );
    return location?.path;
  }
}
