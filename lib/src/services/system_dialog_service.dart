import 'package:file_selector/file_selector.dart';

import '../models.dart';

class SystemDialogService {
  const SystemDialogService();

  static const XTypeGroup _videoTypeGroup = XTypeGroup(
    label: 'Videos',
    extensions: <String>['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'],
  );
  static const XTypeGroup _photoTypeGroup = XTypeGroup(
    label: 'Photos',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
  );

  Future<List<String>> pickMedia() async {
    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[_videoTypeGroup, _photoTypeGroup],
      confirmButtonText: 'Add Media',
    );
    return files.map((file) => file.path).toList(growable: false);
  }

  Future<String?> pickSingleMedia() async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[_videoTypeGroup, _photoTypeGroup],
      confirmButtonText: 'Choose Media',
    );
    return file?.path;
  }

  Future<String?> pickSavePath({
    required ExportFormat format,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[
        switch (format) {
          ExportFormat.mp4 => const XTypeGroup(
            label: 'MP4 Video',
            extensions: <String>['mp4'],
          ),
          ExportFormat.jpg => const XTypeGroup(
            label: 'JPEG Image',
            extensions: <String>['jpg', 'jpeg'],
          ),
        },
      ],
      suggestedName: format.suggestedFileName,
      confirmButtonText: 'Export',
    );
    return location?.path;
  }
}
