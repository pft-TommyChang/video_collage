import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models.dart';

class PickedMediaFile {
  const PickedMediaFile({required this.path, this.clipInfo});

  final String path;
  final VideoClipInfo? clipInfo;
}

class SystemDialogService {
  const SystemDialogService();

  static const MethodChannel _mediaDialogChannel = MethodChannel(
    'video_collage/media_dialogs',
  );

  static const XTypeGroup _videoTypeGroup = XTypeGroup(
    label: 'Videos',
    extensions: <String>['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'],
  );
  static const XTypeGroup _photoTypeGroup = XTypeGroup(
    label: 'Photos',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
  );

  Future<List<PickedMediaFile>> pickMedia() async {
    if (Platform.isMacOS) {
      try {
        final result = await _mediaDialogChannel.invokeListMethod<Object?>(
          'pickMediaWithMetadata',
        );
        if (result != null) {
          return result
              .whereType<Map<Object?, Object?>>()
              .map(_pickedMediaFromMap)
              .toList(growable: false);
        }
      } on MissingPluginException {
        // Fall back to file_selector below.
      } on PlatformException {
        // Fall back to file_selector below.
      }
    }

    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[_videoTypeGroup, _photoTypeGroup],
      confirmButtonText: 'Add Media',
    );
    return files
        .map((file) => PickedMediaFile(path: file.path))
        .toList(growable: false);
  }

  Future<List<String>> pickVideos() async {
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[_videoTypeGroup],
      confirmButtonText: 'Add Videos',
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

  Future<String?> pickPhoto() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_photoTypeGroup],
      confirmButtonText: 'Choose Image',
    );
    return file?.path;
  }

  Future<String?> pickSavePath({
    required ExportFormat format,
    required String suggestedName,
    String? initialDirectory,
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
      initialDirectory: initialDirectory,
      suggestedName: suggestedName,
      confirmButtonText: 'Export',
    );
    return location?.path;
  }

  PickedMediaFile _pickedMediaFromMap(Map<Object?, Object?> map) {
    final path = map['path'] as String;
    final width = map['width'];
    final height = map['height'];
    final durationMilliseconds = map['durationMilliseconds'];
    final hasAudio = map['hasAudio'];
    final mediaKindName = map['mediaKind'];

    if (width is! int ||
        height is! int ||
        durationMilliseconds is! int ||
        hasAudio is! bool ||
        mediaKindName is! String) {
      return PickedMediaFile(path: path);
    }

    final mediaKind = switch (mediaKindName) {
      'photo' => MediaKind.photo,
      _ => MediaKind.video,
    };

    return PickedMediaFile(
      path: path,
      clipInfo: VideoClipInfo(
        path: path,
        name: p.basenameWithoutExtension(path),
        duration: Duration(milliseconds: durationMilliseconds),
        width: width,
        height: height,
        hasAudio: hasAudio,
        mediaKind: mediaKind,
      ),
    );
  }
}
