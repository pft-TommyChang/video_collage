import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models.dart';

class VideoExportException implements Exception {
  const VideoExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VideoThumbnailStrip {
  const VideoThumbnailStrip({required this.directoryPath, required this.paths});

  final String directoryPath;
  final List<String> paths;

  Future<void> dispose() async {
    final directory = Directory(directoryPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

enum VideoMergeFrameRateMode { firstVideo, highest }

class _VideoMergeProfile {
  const _VideoMergeProfile({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.sampleRate,
  });

  final int width;
  final int height;
  final String frameRate;
  final int sampleRate;
}

class VideoExportService {
  VideoExportService();

  static const String _decoderThreadCount = '1';
  static const String _complexFilterThreadCount = '4';
  static const String _encoderThreadCount = '4';
  static const MethodChannel _metadataChannel = MethodChannel(
    'video_collage/media_probe',
  );
  static const String _firstFrameSelectFilter = "select='eq(n\\,0)'";

  Future<void> cancelActiveExport() {
    return FFmpegKit.cancel();
  }

  Future<VideoThumbnailStrip> generateVideoThumbnails({
    required String filePath,
    required Duration duration,
    int count = 12,
    void Function(List<String> paths)? onProgress,
  }) async {
    final safeCount = count.clamp(4, 24);
    final directory = await Directory.systemTemp.createTemp(
      'video_collage_thumbnails_',
    );
    final paths = <String>[];
    final durationMilliseconds = math.max(0, duration.inMilliseconds);

    try {
      for (var index = 0; index < safeCount; index += 1) {
        final timestampMilliseconds = (durationMilliseconds * index / safeCount)
            .round();
        final outputPath = p.join(
          directory.path,
          'thumb_${index.toString().padLeft(3, '0')}.jpg',
        );
        final session = await FFmpegKit.executeWithArguments(<String>[
          '-y',
          if (timestampMilliseconds > 0) ...<String>[
            '-ss',
            (timestampMilliseconds / 1000).toStringAsFixed(3),
          ],
          '-threads',
          _decoderThreadCount,
          '-i',
          filePath,
          '-frames:v',
          '1',
          '-vf',
          'scale=180:-2:flags=lanczos',
          '-q:v',
          '4',
          outputPath,
        ]);
        final returnCode = await session.getReturnCode();
        if (!ReturnCode.isSuccess(returnCode) ||
            !File(outputPath).existsSync()) {
          if (index == 0) {
            final output = await session.getOutput();
            throw VideoExportException(
              'Thumbnail extraction failed: ${output ?? 'Unknown FFmpeg error'}',
            );
          }
          continue;
        }
        paths.add(outputPath);
        onProgress?.call(List<String>.unmodifiable(paths));
      }

      if (paths.isEmpty) {
        throw const VideoExportException(
          'Thumbnail extraction produced no frames.',
        );
      }
      return VideoThumbnailStrip(directoryPath: directory.path, paths: paths);
    } catch (_) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> exportTrimmedVideo({
    required String filePath,
    required Duration start,
    required Duration duration,
    required String outputPath,
    required bool hasAudio,
    ({int width, int height})? outputSize,
    int? frameRate,
    void Function(VideoExportProgress progress)? onProgress,
  }) async {
    final totalMilliseconds = math.max(1, duration.inMilliseconds);
    var lastProgress = 0.0;

    void reportProgress({
      required double progress,
      required int processedMilliseconds,
      double? speed,
    }) {
      if (onProgress == null) {
        return;
      }
      final normalized = progress.clamp(0.0, 1.0);
      if (normalized < lastProgress) {
        return;
      }
      lastProgress = normalized;
      onProgress(
        VideoExportProgress(
          progress: normalized,
          processed: Duration(milliseconds: processedMilliseconds),
          total: duration,
          speed: speed,
        ),
      );
    }

    final videoFilters = <String>[
      'setpts=PTS-STARTPTS',
      if (outputSize != null)
        'scale=${outputSize.width}:${outputSize.height}:flags=lanczos',
    ];
    final arguments = <String>[
      '-y',
      '-threads',
      _decoderThreadCount,
      '-i',
      filePath,
      '-ss',
      _durationSeconds(start),
      '-t',
      _durationSeconds(duration),
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      // Reset the trimmed streams to t=0 so video players can display the
      // opening frame immediately instead of waiting for a positive timestamp.
      '-vf',
      videoFilters.join(','),
      if (hasAudio) ...<String>['-af', 'asetpts=PTS-STARTPTS'],
      ..._h264VideoEncodingArguments(frameRate: frameRate),
      ..._aacAudioEncodingArguments(),
      '-movflags',
      '+faststart',
      outputPath,
    ];
    reportProgress(progress: 0, processedMilliseconds: 0);
    await _runFfmpegCommand(
      arguments: arguments,
      onStatistics: (statistics) {
        final processedMilliseconds = statistics.getTime().round().clamp(
          0,
          totalMilliseconds,
        );
        reportProgress(
          progress: processedMilliseconds / totalMilliseconds,
          processedMilliseconds: processedMilliseconds,
          speed: statistics.getSpeed(),
        );
      },
    );
    reportProgress(progress: 1, processedMilliseconds: totalMilliseconds);
  }

  Future<VideoClipInfo> probeMedia(String filePath) async {
    if (_isPhotoPath(filePath)) {
      return _probePhoto(filePath);
    }
    return _probeVideo(filePath);
  }

  Future<double> probeVideoFrameRate(String path) async {
    return _frameRateValue(await _probeMergeFrameRate(path));
  }

  Future<void> mergeVideos({
    required List<VideoClipInfo> videos,
    required String outputPath,
    ClipFitMode fitMode = ClipFitMode.cropCenter,
    VideoMergeFrameRateMode frameRateMode = VideoMergeFrameRateMode.firstVideo,
    void Function(VideoExportProgress progress)? onProgress,
  }) async {
    if (videos.length < 2) {
      throw const VideoExportException('Choose at least two videos to merge.');
    }
    if (videos.any((video) => !video.isVideo)) {
      throw const VideoExportException('Only video files can be merged.');
    }

    final profile = await _probeMergeProfile(videos.first);
    final outputFrameRate = frameRateMode == VideoMergeFrameRateMode.firstVideo
        ? profile.frameRate
        : await _highestMergeFrameRate(videos, profile.frameRate);
    final outputWidth = profile.width.isEven
        ? profile.width
        : profile.width - 1;
    final outputHeight = profile.height.isEven
        ? profile.height
        : profile.height - 1;
    if (outputWidth < 2 || outputHeight < 2) {
      throw const VideoExportException(
        'The first video has an invalid resolution.',
      );
    }

    final total = videos.fold<Duration>(
      Duration.zero,
      (duration, video) => duration + video.duration,
    );
    final totalMilliseconds = math.max(1, total.inMilliseconds);
    final hasAudio = videos.any((video) => video.hasAudio);
    final filters = <String>[];
    final videoFitFilter = switch (fitMode) {
      ClipFitMode.cropCenter =>
        'scale=$outputWidth:$outputHeight:force_original_aspect_ratio=increase:flags=lanczos,'
            'crop=$outputWidth:$outputHeight:(iw-ow)/2:(ih-oh)/2',
      ClipFitMode.centerInside =>
        'scale=$outputWidth:$outputHeight:force_original_aspect_ratio=decrease:flags=lanczos,'
            'pad=$outputWidth:$outputHeight:(ow-iw)/2:(oh-ih)/2:color=black',
    };

    for (var index = 0; index < videos.length; index += 1) {
      final video = videos[index];
      final durationSeconds = _durationSeconds(video.duration);
      filters.add(
        '[$index:v]'
        'trim=duration=$durationSeconds,setpts=PTS-STARTPTS,'
        '$videoFitFilter,'
        'setsar=1,fps=$outputFrameRate,format=yuv420p'
        '[mergev$index]',
      );
      if (hasAudio) {
        if (video.hasAudio) {
          filters.add(
            '[$index:a]'
            'asetpts=PTS-STARTPTS,'
            'aresample=${profile.sampleRate}:async=1:first_pts=0,'
            'aformat=sample_rates=${profile.sampleRate}:channel_layouts=stereo,'
            'apad,atrim=duration=$durationSeconds'
            '[mergea$index]',
          );
        } else {
          filters.add(
            'anullsrc=r=${profile.sampleRate}:cl=stereo,'
            'atrim=duration=$durationSeconds,asetpts=PTS-STARTPTS'
            '[mergea$index]',
          );
        }
      }
    }

    final concatInputs = <String>[
      for (var index = 0; index < videos.length; index += 1) ...<String>[
        '[mergev$index]',
        if (hasAudio) '[mergea$index]',
      ],
    ].join();
    filters.add(
      '$concatInputs'
      'concat=n=${videos.length}:v=1:a=${hasAudio ? 1 : 0}'
      '[mergedv]${hasAudio ? '[mergeda]' : ''}',
    );

    final arguments = <String>[
      '-y',
      for (final video in videos) ..._videoInputArguments(video),
      '-filter_complex_threads',
      _complexFilterThreadCount,
      '-filter_complex',
      filters.join(';'),
      '-map',
      '[mergedv]',
      if (hasAudio) ...<String>['-map', '[mergeda]'],
      '-map_metadata',
      '0',
      '-metadata:s:v:0',
      'rotate=0',
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '18',
      '-threads',
      _encoderThreadCount,
      '-pix_fmt',
      'yuv420p',
      '-r',
      outputFrameRate,
      if (hasAudio) ..._aacAudioEncodingArguments(),
      '-movflags',
      '+faststart',
      outputPath,
    ];

    onProgress?.call(
      VideoExportProgress(progress: 0, processed: Duration.zero, total: total),
    );
    await _runFfmpegCommand(
      arguments: arguments,
      onStatistics: (statistics) {
        final processedMilliseconds = statistics.getTime().round().clamp(
          0,
          totalMilliseconds,
        );
        onProgress?.call(
          VideoExportProgress(
            progress: processedMilliseconds / totalMilliseconds,
            processed: Duration(milliseconds: processedMilliseconds),
            total: total,
            speed: statistics.getSpeed(),
          ),
        );
      },
    );
    onProgress?.call(
      VideoExportProgress(progress: 1, processed: total, total: total),
    );
  }

  Future<_VideoMergeProfile> _probeMergeProfile(
    VideoClipInfo firstVideo,
  ) async {
    final session = await FFprobeKit.getMediaInformation(firstVideo.path);
    final returnCode = await session.getReturnCode();
    final information = session.getMediaInformation();
    if (!ReturnCode.isSuccess(returnCode) || information == null) {
      throw const VideoExportException(
        'Could not read the first video format.',
      );
    }
    final videoStream = _findPrimaryVideoStream(information);
    if (videoStream == null) {
      throw const VideoExportException(
        'The first file does not contain a video stream.',
      );
    }
    final averageFrameRate = videoStream.getAverageFrameRate();
    final frameRate = _isValidFrameRate(averageFrameRate)
        ? averageFrameRate!
        : _validFrameRate(videoStream.getRealFrameRate());
    var sampleRate = 48000;
    for (final stream in information.getStreams()) {
      if (stream.getType() == 'audio') {
        sampleRate = int.tryParse(stream.getSampleRate() ?? '') ?? sampleRate;
        break;
      }
    }
    return _VideoMergeProfile(
      width: firstVideo.width,
      height: firstVideo.height,
      frameRate: frameRate,
      sampleRate: sampleRate,
    );
  }

  Future<String> _highestMergeFrameRate(
    List<VideoClipInfo> videos,
    String firstFrameRate,
  ) async {
    var highest = firstFrameRate;
    var highestValue = _frameRateValue(firstFrameRate);
    for (final video in videos.skip(1)) {
      final candidate = await _probeMergeFrameRate(video.path);
      final candidateValue = _frameRateValue(candidate);
      if (candidateValue > highestValue) {
        highest = candidate;
        highestValue = candidateValue;
      }
    }
    return highest;
  }

  Future<String> _probeMergeFrameRate(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final returnCode = await session.getReturnCode();
    final information = session.getMediaInformation();
    if (!ReturnCode.isSuccess(returnCode) || information == null) {
      throw VideoExportException('Could not read video frame rate: $path');
    }
    final videoStream = _findPrimaryVideoStream(information);
    if (videoStream == null) {
      throw VideoExportException('No video stream found: $path');
    }
    final averageFrameRate = videoStream.getAverageFrameRate();
    return _isValidFrameRate(averageFrameRate)
        ? averageFrameRate!
        : _validFrameRate(videoStream.getRealFrameRate());
  }

  double _frameRateValue(String value) {
    final parts = value.split('/');
    final numerator = double.tryParse(parts.first) ?? 0;
    final denominator = parts.length > 1 ? (double.tryParse(parts[1]) ?? 0) : 1;
    return denominator <= 0 ? 0 : numerator / denominator;
  }

  String _validFrameRate(String? value) {
    return _isValidFrameRate(value) ? value! : '30';
  }

  bool _isValidFrameRate(String? value) {
    if (value == null || value.isEmpty || value == '0/0') {
      return false;
    }
    final parts = value.split('/');
    final numerator = double.tryParse(parts.first) ?? 0;
    final denominator = parts.length > 1 ? (double.tryParse(parts[1]) ?? 0) : 1;
    if (numerator <= 0 || denominator <= 0) {
      return false;
    }
    return true;
  }

  Future<VideoClipInfo> _probeVideo(String filePath) async {
    final nativeProbe = await _probeVideoWithNativeMetadata(filePath);
    if (nativeProbe != null) {
      return VideoClipInfo(
        path: filePath,
        name: p.basenameWithoutExtension(filePath),
        duration: Duration(
          milliseconds: (nativeProbe.durationSeconds * 1000).round(),
        ),
        width: nativeProbe.width,
        height: nativeProbe.height,
        hasAudio: nativeProbe.hasAudio,
        mediaKind: MediaKind.video,
        frameRate: nativeProbe.frameRate,
      );
    }

    final session = await FFprobeKit.getMediaInformation(filePath);
    final returnCode = await session.getReturnCode();
    final information = session.getMediaInformation();

    if (!ReturnCode.isSuccess(returnCode) || information == null) {
      final output = await session.getOutput();
      throw VideoExportException(
        'ffprobe failed for ${p.basename(filePath)}:\n${output ?? 'Unknown FFprobe error'}',
      );
    }

    final stream = _findPrimaryVideoStream(information);
    final durationSeconds =
        double.tryParse(information.getDuration() ?? '0') ?? 0;
    final fallbackWidth = stream?.getWidth() ?? 0;
    final fallbackHeight = stream?.getHeight() ?? 0;
    final averageFrameRate = stream?.getAverageFrameRate();
    final frameRate = _frameRateValue(
      _isValidFrameRate(averageFrameRate)
          ? averageFrameRate!
          : _validFrameRate(stream?.getRealFrameRate()),
    );

    return VideoClipInfo(
      path: filePath,
      name: p.basenameWithoutExtension(filePath),
      duration: Duration(milliseconds: (durationSeconds * 1000).round()),
      width: fallbackWidth,
      height: fallbackHeight,
      hasAudio: _hasAudioStream(information),
      mediaKind: MediaKind.video,
      frameRate: frameRate,
    );
  }

  Future<_VideoDisplayMetadata?> _probeVideoWithNativeMetadata(
    String filePath,
  ) async {
    try {
      final result = await _metadataChannel.invokeMapMethod<String, Object?>(
        'probeVideoMetadata',
        <String, Object?>{'path': filePath},
      );
      if (result == null) {
        return null;
      }

      final width = result['width'];
      final height = result['height'];
      final durationSeconds = result['durationSeconds'];
      final hasAudio = result['hasAudio'];
      final frameRate = result['frameRate'];

      if (width is! int || height is! int || durationSeconds is! num) {
        return null;
      }

      return _VideoDisplayMetadata(
        width: width,
        height: height,
        durationSeconds: durationSeconds.toDouble(),
        hasAudio: hasAudio == true,
        frameRate: frameRate is num ? frameRate.toDouble() : 0,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<VideoClipInfo> _probePhoto(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    try {
      return VideoClipInfo(
        path: filePath,
        name: p.basenameWithoutExtension(filePath),
        duration: Duration.zero,
        width: image.width,
        height: image.height,
        hasAudio: false,
        mediaKind: MediaKind.photo,
      );
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  Future<void> exportCollage({
    required List<CollageSlotClip> slotClips,
    required ExportOptions options,
    required String outputPath,
    void Function(VideoExportProgress progress)? onProgress,
  }) async {
    if (slotClips.isEmpty) {
      throw const VideoExportException('Please add at least one media item.');
    }

    final border = options.borderPx;
    final cellWidth =
        ((options.outputWidth - ((options.columns + 1) * border)) /
                options.columns)
            .floor();
    final cellHeight =
        ((options.outputHeight - ((options.rows + 1) * border)) / options.rows)
            .floor();

    if (cellWidth <= 0 || cellHeight <= 0) {
      throw const VideoExportException(
        'Border is too large for the current rows, columns, and output resolution.',
      );
    }

    final exportFormat = exportFormatForClips(slotClips);
    final targetDurationMs = math.max(
      1000,
      exportDurationForClips(
        slotClips,
        options.durationMode,
        options.playMode,
      ).inMilliseconds,
    );
    final targetDurationSeconds = (targetDurationMs / 1000).toStringAsFixed(3);
    Directory? labelTempDirectory;
    var lastProgress = 0.0;

    void reportProgress({
      required double progress,
      required int processedMs,
      double? speed,
    }) {
      if (onProgress == null) {
        return;
      }
      final normalized = progress.clamp(0.0, 1.0);
      if (normalized < lastProgress) {
        return;
      }
      lastProgress = normalized;
      onProgress(
        VideoExportProgress(
          progress: normalized,
          processed: Duration(milliseconds: processedMs),
          total: Duration(milliseconds: targetDurationMs),
          speed: speed,
        ),
      );
    }

    try {
      reportProgress(progress: 0, processedMs: 0);
      if (exportFormat == ExportFormat.jpg) {
        await _exportPhotoCollage(
          slotClips: slotClips,
          options: options,
          outputPath: outputPath,
        );
        reportProgress(progress: 1, processedMs: targetDurationMs);
        return;
      }

      if (options.playMode == PlayMode.sequential) {
        await _exportSequentialVideoCollage(
          slotClips: slotClips,
          options: options,
          outputPath: outputPath,
          targetDurationMs: targetDurationMs,
          cellWidth: cellWidth,
          cellHeight: cellHeight,
          reportProgress: reportProgress,
        );
        return;
      }

      final labelOverlays = options.includeClipLabelsInOutput
          ? await _createClipLabelOverlays(
              slotClips: slotClips,
              scaleFactor: options.scaleFactor,
              baseFontSize: options.clipLabelFontSize,
              clipLabelDisplayMode: options.clipLabelDisplayMode,
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              clipLabelAlignment: options.clipLabelAlignment,
              clipLabelVisualStyle: options.clipLabelVisualStyle,
              clipLabelPadding: options.clipLabelPadding,
              tempDirectory: labelTempDirectory = await Directory.systemTemp
                  .createTemp('video_collage_labels_'),
            )
          : const <_ClipLabelOverlay>[];

      final borderImageInputIndex = slotClips.length + labelOverlays.length;
      final filters = <String>[
        _borderBaseFilter(
          options: options,
          durationSeconds: targetDurationSeconds,
          borderImageInputIndex: borderImageInputIndex,
        ),
      ];
      final hasRoundedCornerMask = _addRoundedCornerMaskFilters(
        filters: filters,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        radius: options.tileCornerRadiusPx,
        outputCount: slotClips.length,
      );

      for (var inputIndex = 0; inputIndex < slotClips.length; inputIndex++) {
        final clip = slotClips[inputIndex].clip;

        if (clip.isPhoto) {
          filters.addAll(
            _scaledPhotoFilters(
              fitMode: options.fitMode,
              viewport: slotClips[inputIndex].viewport,
              backgroundColor: options.backgroundColor,
              inputIndex: inputIndex,
              backgroundDurationSeconds: targetDurationSeconds,
              trimDurationSeconds: targetDurationSeconds,
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              outputLabel: 'clip$inputIndex',
            ),
          );
        } else {
          filters.add(
            _simultaneousVideoFilter(
              inputIndex: inputIndex,
              fitMode: options.fitMode,
              viewport: slotClips[inputIndex].viewport,
              backgroundColor: options.backgroundColor,
              durationSeconds: targetDurationSeconds,
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              outputLabel: 'clip$inputIndex',
            ),
          );
        }

        var decoratedClipName = 'clip$inputIndex';
        if (options.includeClipLabelsInOutput) {
          final labelInputIndex = slotClips.length + inputIndex;
          final labelOverlay = labelOverlays[inputIndex];
          final labeledClipName = 'labeled$inputIndex';
          filters.add(
            '[$decoratedClipName][$labelInputIndex:v]overlay='
            'x=${labelOverlay.x}:y=${labelOverlay.y}:format=auto'
            '[$labeledClipName]',
          );
          decoratedClipName = labeledClipName;
        }

        _addRoundedCornerApplicationFilters(
          filters: filters,
          inputLabel: decoratedClipName,
          outputLabel: 'v$inputIndex',
          maskIndex: inputIndex,
          hasMask: hasRoundedCornerMask,
        );
      }

      for (var inputIndex = 0; inputIndex < slotClips.length; inputIndex++) {
        final slotIndex = slotClips[inputIndex].slotIndex;
        final row = slotIndex ~/ options.columns;
        final col = slotIndex % options.columns;
        final x = border + col * (cellWidth + border);
        final y = border + row * (cellHeight + border);
        final source = inputIndex == 0 ? 'base' : 'stage${inputIndex - 1}';
        final destination = inputIndex == slotClips.length - 1
            ? 'merged'
            : 'stage$inputIndex';
        filters.add(
          // Keep the last tile frame visible if an unusual input still ends
          // early instead of exposing the solid-color base.
          '[$source][v$inputIndex]overlay='
          'x=$x:y=$y:eof_action=repeat:repeatlast=1[$destination]',
        );
      }
      filters.add('[merged]format=yuv420p[outv]');

      final audioOutputLabel = _buildAudioFilterGraph(
        filters: filters,
        slotClips: slotClips,
        audioMode: options.audioMode,
        targetDurationSeconds: targetDurationSeconds,
      );

      final arguments = <String>[
        '-y',
        for (final entry in slotClips)
          ...entry.clip.isPhoto
              ? <String>[
                  '-loop',
                  '1',
                  '-framerate',
                  '30',
                  '-t',
                  targetDurationSeconds,
                  '-threads',
                  _decoderThreadCount,
                  '-i',
                  entry.clip.path,
                ]
              : _videoInputArguments(entry.clip),
        for (final overlay in labelOverlays) ...<String>[
          '-loop',
          '1',
          '-threads',
          _decoderThreadCount,
          '-i',
          overlay.filePath,
        ],
        if (options.borderImagePath != null)
          ..._borderImageInputArguments(
            path: options.borderImagePath!,
            durationSeconds: targetDurationSeconds,
          ),
        '-filter_complex_threads',
        _complexFilterThreadCount,
        '-filter_complex',
        filters.join(';'),
        '-map',
        '[outv]',
        '-t',
        targetDurationSeconds,
        '-r',
        '30',
        '-c:v',
        'libx264',
        '-preset',
        'medium',
        '-crf',
        '18',
        '-threads',
        _encoderThreadCount,
        '-pix_fmt',
        'yuv420p',
        if (audioOutputLabel != null) ...<String>[
          '-map',
          '[$audioOutputLabel]',
          '-c:a',
          'aac',
          '-b:a',
          '192k',
        ] else
          '-an',
        '-movflags',
        '+faststart',
        outputPath,
      ];

      await FFmpegKitConfig.enableStatistics();
      final sessionCompleter = Completer<FFmpegSession>();
      await FFmpegKit.executeWithArgumentsAsync(
        arguments,
        (session) {
          if (!sessionCompleter.isCompleted) {
            sessionCompleter.complete(session);
          }
        },
        null,
        (statistics) {
          reportProgress(
            progress: statistics.getTime() / targetDurationMs,
            processedMs: statistics.getTime(),
            speed: statistics.getSpeed(),
          );
        },
      );
      final session = await sessionCompleter.future;
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isCancel(returnCode)) {
        throw const VideoExportException('Export cancelled.');
      }

      if (!ReturnCode.isSuccess(returnCode)) {
        final output = await session.getOutput();
        throw VideoExportException(
          'ffmpeg export failed:\n${output ?? 'Unknown FFmpeg error'}',
        );
      }
      reportProgress(progress: 1, processedMs: targetDurationMs);
    } finally {
      if (labelTempDirectory case final directory?) {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    }
  }

  Future<void> _exportPhotoCollage({
    required List<CollageSlotClip> slotClips,
    required ExportOptions options,
    required String outputPath,
  }) async {
    final border = options.borderPx;
    final cellWidth =
        ((options.outputWidth - ((options.columns + 1) * border)) /
                options.columns)
            .floor();
    final cellHeight =
        ((options.outputHeight - ((options.rows + 1) * border)) / options.rows)
            .floor();
    Directory? labelTempDirectory;

    try {
      final labelOverlays = options.includeClipLabelsInOutput
          ? await _createClipLabelOverlays(
              slotClips: slotClips,
              scaleFactor: options.scaleFactor,
              baseFontSize: options.clipLabelFontSize,
              clipLabelDisplayMode: options.clipLabelDisplayMode,
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              clipLabelAlignment: options.clipLabelAlignment,
              clipLabelVisualStyle: options.clipLabelVisualStyle,
              clipLabelPadding: options.clipLabelPadding,
              tempDirectory: labelTempDirectory = await Directory.systemTemp
                  .createTemp('photo_collage_labels_'),
            )
          : const <_ClipLabelOverlay>[];

      final borderImageInputIndex = slotClips.length + labelOverlays.length;
      final filters = <String>[
        _borderBaseFilter(
          options: options,
          durationSeconds: '1',
          borderImageInputIndex: borderImageInputIndex,
        ),
      ];
      final hasRoundedCornerMask = _addRoundedCornerMaskFilters(
        filters: filters,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        radius: options.tileCornerRadiusPx,
        outputCount: slotClips.length,
      );

      for (var inputIndex = 0; inputIndex < slotClips.length; inputIndex++) {
        final clip = slotClips[inputIndex].clip;

        if (clip.isPhoto) {
          filters.addAll(
            _scaledPhotoFilters(
              fitMode: options.fitMode,
              viewport: slotClips[inputIndex].viewport,
              backgroundColor: options.backgroundColor,
              inputIndex: inputIndex,
              backgroundDurationSeconds: '1',
              cellWidth: cellWidth,
              cellHeight: cellHeight,
              outputLabel: 'clip$inputIndex',
            ),
          );
        } else {
          filters.add(
            '[$inputIndex:v]'
            '${_videoTileScaleFilterChain(fitMode: options.fitMode, viewport: slotClips[inputIndex].viewport, backgroundColor: options.backgroundColor, cellWidth: cellWidth, cellHeight: cellHeight)}'
            '[clip$inputIndex]',
          );
        }

        var decoratedClipName = 'clip$inputIndex';
        if (options.includeClipLabelsInOutput) {
          final labelInputIndex = slotClips.length + inputIndex;
          final labelOverlay = labelOverlays[inputIndex];
          final labeledClipName = 'labeled$inputIndex';
          filters.add(
            '[$decoratedClipName][$labelInputIndex:v]overlay='
            'x=${labelOverlay.x}:y=${labelOverlay.y}:format=auto'
            '[$labeledClipName]',
          );
          decoratedClipName = labeledClipName;
        }

        _addRoundedCornerApplicationFilters(
          filters: filters,
          inputLabel: decoratedClipName,
          outputLabel: 'v$inputIndex',
          maskIndex: inputIndex,
          hasMask: hasRoundedCornerMask,
        );
      }

      for (var inputIndex = 0; inputIndex < slotClips.length; inputIndex++) {
        final slotIndex = slotClips[inputIndex].slotIndex;
        final row = slotIndex ~/ options.columns;
        final col = slotIndex % options.columns;
        final x = border + col * (cellWidth + border);
        final y = border + row * (cellHeight + border);
        final source = inputIndex == 0 ? 'base' : 'stage${inputIndex - 1}';
        final destination = inputIndex == slotClips.length - 1
            ? 'merged'
            : 'stage$inputIndex';
        filters.add(
          '[$source][v$inputIndex]overlay=x=$x:y=$y:eof_action=pass[$destination]',
        );
      }
      filters.add('[merged]format=yuvj420p[outv]');

      final arguments = <String>[
        '-y',
        for (final entry in slotClips)
          ..._singleThreadedInputArguments(entry.clip.path),
        for (final overlay in labelOverlays) ...<String>[
          '-loop',
          '1',
          '-threads',
          _decoderThreadCount,
          '-i',
          overlay.filePath,
        ],
        if (options.borderImagePath != null)
          ..._borderImageInputArguments(
            path: options.borderImagePath!,
            durationSeconds: '1',
          ),
        '-filter_complex_threads',
        _complexFilterThreadCount,
        '-filter_complex',
        filters.join(';'),
        '-map',
        '[outv]',
        '-frames:v',
        '1',
        '-c:v',
        'mjpeg',
        '-q:v',
        '2',
        outputPath,
      ];

      final session = await FFmpegKit.executeWithArguments(arguments);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isCancel(returnCode)) {
        throw const VideoExportException('Export cancelled.');
      }
      if (!ReturnCode.isSuccess(returnCode)) {
        final output = await session.getOutput();
        throw VideoExportException(
          'ffmpeg export failed:\n${output ?? 'Unknown FFmpeg error'}',
        );
      }
    } finally {
      if (labelTempDirectory case final directory?) {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    }
  }

  Future<void> _exportSequentialVideoCollage({
    required List<CollageSlotClip> slotClips,
    required ExportOptions options,
    required String outputPath,
    required int targetDurationMs,
    required int cellWidth,
    required int cellHeight,
    required void Function({
      required double progress,
      required int processedMs,
      double? speed,
    })
    reportProgress,
  }) async {
    final sequentialEntries = slotClips
        .where(
          (entry) => entry.clip.isVideo && entry.clip.duration > Duration.zero,
        )
        .toList(growable: false);
    if (sequentialEntries.isEmpty) {
      throw const VideoExportException(
        'Sequential mode requires at least one video clip with duration.',
      );
    }

    final segmentDirectory = await Directory.systemTemp.createTemp(
      'video_collage_sequential_segments_',
    );
    try {
      final border = options.borderPx;
      final tilePositions = <(int x, int y)>[
        for (final slotClip in slotClips)
          (
            border +
                (slotClip.slotIndex % options.columns) * (cellWidth + border),
            border +
                (slotClip.slotIndex ~/ options.columns) * (cellHeight + border),
          ),
      ];
      final videoOrderById = <String, int>{
        for (var index = 0; index < sequentialEntries.length; index += 1)
          sequentialEntries[index].clip.id: index,
      };
      final segmentPaths = <String>[];
      var processedMsBeforeSegment = 0;

      for (
        var segmentIndex = 0;
        segmentIndex < sequentialEntries.length;
        segmentIndex += 1
      ) {
        final activeEntry = sequentialEntries[segmentIndex];
        final activeInputIndex = slotClips.indexOf(activeEntry);
        final segmentDuration = activeEntry.clip.duration;
        final segmentDurationMs = segmentDuration.inMilliseconds;
        final segmentDurationSeconds = _durationSeconds(segmentDuration);
        final segmentLabelOverlays = options.includeClipLabelsInOutput
            ? await _createClipLabelOverlays(
                slotClips: slotClips,
                scaleFactor: options.scaleFactor,
                baseFontSize: options.clipLabelFontSize,
                clipLabelDisplayMode: options.clipLabelDisplayMode,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                clipLabelAlignment: options.clipLabelAlignment,
                clipLabelVisualStyle: options.clipLabelVisualStyle,
                clipLabelPadding: options.clipLabelPadding,
                tempDirectory: await Directory(
                  p.join(
                    segmentDirectory.path,
                    'labels_${segmentIndex.toString().padLeft(2, '0')}',
                  ),
                ).create(recursive: true),
                highlightedInputIndex: activeInputIndex,
                highlightedTextColor: clipLabelHighlightedTextColor(
                  options.clipLabelVisualStyle,
                ),
              )
            : const <_ClipLabelOverlay>[];
        final borderImageInputIndex =
            slotClips.length + segmentLabelOverlays.length;
        final filters = <String>[
          _borderBaseFilter(
            options: options,
            durationSeconds: segmentDurationSeconds,
            borderImageInputIndex: borderImageInputIndex,
          ),
        ];
        final hasRoundedCornerMask = _addRoundedCornerMaskFilters(
          filters: filters,
          cellWidth: cellWidth,
          cellHeight: cellHeight,
          radius: options.tileCornerRadiusPx,
          outputCount: slotClips.length,
        );

        for (
          var inputIndex = 0;
          inputIndex < slotClips.length;
          inputIndex += 1
        ) {
          final slotClip = slotClips[inputIndex];
          final videoOrder = videoOrderById[slotClip.clip.id];
          final tileLabel = 'tile$inputIndex';
          final preparedTileLabel = 'prepared_$tileLabel';
          switch (slotClip.clip.mediaKind) {
            case MediaKind.photo:
              filters.addAll(
                _scaledPhotoFilters(
                  fitMode: options.fitMode,
                  viewport: slotClip.viewport,
                  backgroundColor: options.backgroundColor,
                  inputIndex: inputIndex,
                  backgroundDurationSeconds: segmentDurationSeconds,
                  trimDurationSeconds: segmentDurationSeconds,
                  cellWidth: cellWidth,
                  cellHeight: cellHeight,
                  outputLabel: preparedTileLabel,
                ),
              );
            case MediaKind.video when inputIndex == activeInputIndex:
              filters.add(
                _sequentialActiveVideoFilter(
                  inputIndex: inputIndex,
                  fitMode: options.fitMode,
                  viewport: slotClip.viewport,
                  backgroundColor: options.backgroundColor,
                  durationSeconds: segmentDurationSeconds,
                  cellWidth: cellWidth,
                  cellHeight: cellHeight,
                  outputLabel: preparedTileLabel,
                ),
              );
            case MediaKind.video
                when videoOrder != null && videoOrder < segmentIndex:
              filters.add(
                _sequentialFrozenVideoFilter(
                  inputIndex: inputIndex,
                  fitMode: options.fitMode,
                  viewport: slotClip.viewport,
                  backgroundColor: options.backgroundColor,
                  freezeAtEnd: true,
                  clipDuration: slotClip.clip.duration,
                  durationSeconds: segmentDurationSeconds,
                  cellWidth: cellWidth,
                  cellHeight: cellHeight,
                  outputLabel: preparedTileLabel,
                ),
              );
            case MediaKind.video:
              filters.add(
                _sequentialFrozenVideoFilter(
                  inputIndex: inputIndex,
                  fitMode: options.fitMode,
                  viewport: slotClip.viewport,
                  backgroundColor: options.backgroundColor,
                  freezeAtEnd: false,
                  clipDuration: slotClip.clip.duration,
                  durationSeconds: segmentDurationSeconds,
                  cellWidth: cellWidth,
                  cellHeight: cellHeight,
                  outputLabel: preparedTileLabel,
                ),
              );
          }
          _addRoundedCornerApplicationFilters(
            filters: filters,
            inputLabel: preparedTileLabel,
            outputLabel: tileLabel,
            maskIndex: inputIndex,
            hasMask: hasRoundedCornerMask,
          );
        }

        var stageLabel = 'base';
        for (
          var inputIndex = 0;
          inputIndex < slotClips.length;
          inputIndex += 1
        ) {
          final position = tilePositions[inputIndex];
          final nextStageLabel = inputIndex == slotClips.length - 1
              ? 'merged'
              : 'stage$inputIndex';
          filters.add(
            '[$stageLabel][tile$inputIndex]overlay='
            'x=${position.$1}:y=${position.$2}:eof_action=pass'
            '[$nextStageLabel]',
          );
          stageLabel = nextStageLabel;
        }

        if (options.includeClipLabelsInOutput) {
          var labeledStageLabel = stageLabel;
          for (
            var inputIndex = 0;
            inputIndex < slotClips.length;
            inputIndex += 1
          ) {
            final labelOverlay = segmentLabelOverlays[inputIndex];
            final labelInputIndex = slotClips.length + inputIndex;
            final position = tilePositions[inputIndex];
            final nextStageLabel = inputIndex == slotClips.length - 1
                ? 'labeled_merged'
                : 'label_stage$inputIndex';
            filters.add(
              '[$labeledStageLabel][$labelInputIndex:v]overlay='
              'x=${position.$1 + labelOverlay.x}:y=${position.$2 + labelOverlay.y}:format=auto'
              '[$nextStageLabel]',
            );
            labeledStageLabel = nextStageLabel;
          }
          stageLabel = labeledStageLabel;
        }

        filters.add('[$stageLabel]format=yuv420p[outv]');

        if (activeEntry.clip.hasAudio) {
          filters.add(
            _normalizedAudioFilter(
              inputIndex: activeInputIndex,
              targetDurationSeconds: segmentDurationSeconds,
              outputLabel: 'outa',
            ),
          );
        } else {
          filters.add(
            'anullsrc=r=44100:cl=stereo,atrim=duration=$segmentDurationSeconds[outa]',
          );
        }

        final segmentPath = p.join(
          segmentDirectory.path,
          'segment_${segmentIndex.toString().padLeft(2, '0')}.ts',
        );
        final arguments = <String>[
          '-y',
          for (final entry in slotClips)
            ...entry.clip.isPhoto
                ? _loopedStillImageInputArguments(
                    path: entry.clip.path,
                    durationSeconds: segmentDurationSeconds,
                  )
                : _videoInputArguments(entry.clip),
          for (final overlay in segmentLabelOverlays) ...<String>[
            '-loop',
            '1',
            '-threads',
            _decoderThreadCount,
            '-i',
            overlay.filePath,
          ],
          if (options.borderImagePath != null)
            ..._borderImageInputArguments(
              path: options.borderImagePath!,
              durationSeconds: segmentDurationSeconds,
            ),
          '-filter_complex_threads',
          _complexFilterThreadCount,
          '-filter_complex',
          filters.join(';'),
          '-map',
          '[outv]',
          '-map',
          '[outa]',
          '-t',
          segmentDurationSeconds,
          ..._h264VideoEncodingArguments(),
          ..._aacAudioEncodingArguments(),
          // Keep each MPEG-TS segment starting close to t=0 so the first
          // visual frame survives the later concat/remux step.
          '-muxpreload',
          '0',
          '-muxdelay',
          '0',
          '-f',
          'mpegts',
          segmentPath,
        ];

        await _runFfmpegCommand(
          arguments: arguments,
          onStatistics: (statistics) {
            final processedMs =
                processedMsBeforeSegment + statistics.getTime().round();
            reportProgress(
              progress: processedMs / targetDurationMs,
              processedMs: processedMs,
              speed: statistics.getSpeed(),
            );
          },
        );
        segmentPaths.add(segmentPath);
        processedMsBeforeSegment += segmentDurationMs;
      }

      final concatListPath = p.join(segmentDirectory.path, 'segments.txt');
      final concatList = segmentPaths.map((path) => "file '$path'").join('\n');
      await File(concatListPath).writeAsString('$concatList\n');

      reportProgress(progress: 0.99, processedMs: targetDurationMs - 1);
      await _runFfmpegCommand(
        arguments: <String>[
          '-y',
          '-f',
          'concat',
          '-safe',
          '0',
          '-fflags',
          '+genpts',
          '-i',
          concatListPath,
          // Re-encode the final concat output and explicitly reset timestamps
          // so sequential exports begin with a visible frame at t=0.
          '-vf',
          'setpts=PTS-STARTPTS',
          '-af',
          'asetpts=PTS-STARTPTS',
          ..._h264VideoEncodingArguments(),
          ..._aacAudioEncodingArguments(),
          '-movflags',
          '+faststart',
          outputPath,
        ],
      );
      reportProgress(progress: 1, processedMs: targetDurationMs);
    } finally {
      if (await segmentDirectory.exists()) {
        await segmentDirectory.delete(recursive: true);
      }
    }
  }

  Future<List<_ClipLabelOverlay>> _createClipLabelOverlays({
    required List<CollageSlotClip> slotClips,
    required double scaleFactor,
    required double baseFontSize,
    required ClipLabelDisplayMode clipLabelDisplayMode,
    required int cellWidth,
    required int cellHeight,
    required ClipLabelAlignment clipLabelAlignment,
    required ClipLabelVisualStyle clipLabelVisualStyle,
    required double clipLabelPadding,
    required Directory tempDirectory,
    int? highlightedInputIndex,
    ui.Color? highlightedTextColor,
  }) async {
    final labelStyle = clipLabelStyleForOverlayScale(
      overlayLabelScaleForExportScale(scaleFactor),
      baseFontSize: baseFontSize,
      baseEdgePadding: clipLabelPadding,
      alignment: clipLabelAlignment,
      visualStyle: clipLabelVisualStyle,
    );
    final maxTextWidth = math.max(
      1.0,
      cellWidth -
          labelStyle.margin.left -
          labelStyle.margin.right -
          (labelStyle.horizontalPadding * 2),
    );

    final overlays = <_ClipLabelOverlay>[];
    for (var inputIndex = 0; inputIndex < slotClips.length; inputIndex++) {
      final filePath = p.join(tempDirectory.path, 'label_$inputIndex.png');
      final labelImage = await _renderClipLabelImage(
        filePath: filePath,
        text: buildClipLabelText(
          slotIndex: slotClips[inputIndex].slotIndex,
          clipName: slotClips[inputIndex].clip.name,
          mode: clipLabelDisplayMode,
        ),
        labelStyle: labelStyle,
        maxTextWidth: maxTextWidth,
        textColor: inputIndex == highlightedInputIndex
            ? highlightedTextColor ?? labelStyle.textColor
            : labelStyle.textColor,
      );
      final position = _resolveClipLabelOverlayPosition(
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        overlayWidth: labelImage.width,
        overlayHeight: labelImage.height,
        margin: labelStyle.margin,
        alignment: clipLabelAlignment,
      );
      overlays.add(
        _ClipLabelOverlay(filePath: filePath, x: position.$1, y: position.$2),
      );
    }
    return overlays;
  }

  (int, int) _resolveClipLabelOverlayPosition({
    required int cellWidth,
    required int cellHeight,
    required int overlayWidth,
    required int overlayHeight,
    required EdgeInsets margin,
    required ClipLabelAlignment alignment,
  }) {
    final leftInset = margin.left.round();
    final rightInset = margin.right.round();
    final topInset = margin.top.round();
    final bottomInset = margin.bottom.round();
    final minX = math.max(0, leftInset);
    final minY = math.max(0, topInset);
    final maxX = math.max(minX, cellWidth - overlayWidth - rightInset);
    final maxY = math.max(minY, cellHeight - overlayHeight - bottomInset);
    final centeredX = ((cellWidth - overlayWidth) / 2).round().clamp(
      minX,
      maxX,
    );
    final centeredY = ((cellHeight - overlayHeight) / 2).round().clamp(
      minY,
      maxY,
    );

    return switch (alignment) {
      ClipLabelAlignment.topLeft => (minX, minY),
      ClipLabelAlignment.topCenter => (centeredX, minY),
      ClipLabelAlignment.topRight => (maxX, minY),
      ClipLabelAlignment.center => (centeredX, centeredY),
      ClipLabelAlignment.bottomLeft => (minX, maxY),
      ClipLabelAlignment.bottomCenter => (centeredX, maxY),
      ClipLabelAlignment.bottomRight => (maxX, maxY),
    };
  }

  Future<void> _runFfmpegCommand({
    required List<String> arguments,
    void Function(Statistics statistics)? onStatistics,
  }) async {
    await FFmpegKitConfig.enableStatistics();
    final sessionCompleter = Completer<FFmpegSession>();
    await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) {
        if (!sessionCompleter.isCompleted) {
          sessionCompleter.complete(session);
        }
      },
      null,
      onStatistics == null
          ? null
          : (statistics) {
              onStatistics(statistics);
            },
    );
    final session = await sessionCompleter.future;
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isCancel(returnCode)) {
      throw const VideoExportException('Export cancelled.');
    }

    if (!ReturnCode.isSuccess(returnCode)) {
      final output = await session.getOutput();
      throw VideoExportException(
        'ffmpeg export failed:\n${output ?? 'Unknown FFmpeg error'}',
      );
    }
  }

  Future<_RenderedClipLabelImage> _renderClipLabelImage({
    required String filePath,
    required String text,
    required ClipLabelStyle labelStyle,
    required double maxTextWidth,
    required ui.Color textColor,
  }) async {
    final textEffectPadding = math.max(
      labelStyle.textOutlineWidth,
      labelStyle.textShadowColor == null ? 0.0 : 2.0,
    );
    final layoutTextWidth = math.max(
      1.0,
      maxTextWidth - (textEffectPadding * 2),
    );
    final fillTextPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: labelStyle.fontSize,
          fontWeight: FontWeight.w600,
          shadows: labelStyle.textShadowColor == null
              ? null
              : <Shadow>[
                  Shadow(
                    color: labelStyle.textShadowColor!,
                    blurRadius: 6,
                    offset: const Offset(0, 1.5),
                  ),
                ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: layoutTextWidth);
    final outlineTextPainter =
        labelStyle.textOutlineColor == null || labelStyle.textOutlineWidth <= 0
        ? null
        : (TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = labelStyle.textOutlineWidth
                  ..color = labelStyle.textOutlineColor!,
                fontSize: labelStyle.fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '...',
          )..layout(maxWidth: layoutTextWidth));

    final imageWidth = math.max(
      1,
      (fillTextPainter.width +
              (labelStyle.horizontalPadding * 2) +
              (textEffectPadding * 2))
          .ceil(),
    );
    final imageHeight = math.max(
      1,
      (fillTextPainter.height +
              (labelStyle.verticalPadding * 2) +
              (textEffectPadding * 2))
          .ceil(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (labelStyle.backgroundColor case final backgroundColor?) {
      final backgroundPaint = ui.Paint()..color = backgroundColor;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
          ui.Radius.circular(labelStyle.cornerRadius),
        ),
        backgroundPaint,
      );
    }
    final textOffset = Offset(
      labelStyle.horizontalPadding + textEffectPadding,
      labelStyle.verticalPadding + textEffectPadding,
    );
    outlineTextPainter?.paint(canvas, textOffset);
    fillTextPainter.paint(canvas, textOffset);

    final image = await recorder.endRecording().toImage(
      imageWidth,
      imageHeight,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData == null) {
      throw const VideoExportException('Failed to render export clip label.');
    }

    await File(filePath).writeAsBytes(_bytesFromByteData(byteData));
    return _RenderedClipLabelImage(width: imageWidth, height: imageHeight);
  }

  List<String> _scaledPhotoFilters({
    required ClipFitMode fitMode,
    required ClipViewport viewport,
    required ColorChoice backgroundColor,
    required int inputIndex,
    required String backgroundDurationSeconds,
    String? trimDurationSeconds,
    required int cellWidth,
    required int cellHeight,
    required String outputLabel,
  }) {
    final output = _photoForegroundOutputForFitMode(fitMode: fitMode);
    final trimFilter = trimDurationSeconds == null
        ? ''
        : ',trim=duration=$trimDurationSeconds,setpts=PTS-STARTPTS';
    final backgroundLabel = 'photo_bg_$inputIndex';
    final foregroundLabel = 'photo_fg_$inputIndex';
    return <String>[
      'color=c=${backgroundColor.ffmpegHex}:s=$cellWidth'
          'x$cellHeight:d=$backgroundDurationSeconds,format=rgba[$backgroundLabel]',
      '[$inputIndex:v]'
          'format=rgba,'
          '${_photoTileScaleFilterChain(fitMode: fitMode, viewport: viewport, cellWidth: cellWidth, cellHeight: cellHeight)}'
          '$trimFilter'
          '[$foregroundLabel]',
      '[$backgroundLabel][$foregroundLabel]overlay='
          'x=${output.$1}:y=${output.$2}:format=auto[$outputLabel]',
    ];
  }

  String _simultaneousVideoFilter({
    required int inputIndex,
    required ClipFitMode fitMode,
    required ClipViewport viewport,
    required ColorChoice backgroundColor,
    required String durationSeconds,
    required int cellWidth,
    required int cellHeight,
    required String outputLabel,
  }) {
    // Container duration metadata can extend beyond the final decodable frame.
    // Pad without relying on that metadata, then cap the tile exactly.
    return '[$inputIndex:v]'
        'setpts=PTS-STARTPTS,'
        '${_videoTileScaleFilterChain(fitMode: fitMode, viewport: viewport, backgroundColor: backgroundColor, cellWidth: cellWidth, cellHeight: cellHeight)},'
        'tpad=stop_mode=clone:stop_duration=$durationSeconds,'
        'trim=duration=$durationSeconds,'
        'setpts=PTS-STARTPTS'
        '[$outputLabel]';
  }

  String _sequentialActiveVideoFilter({
    required int inputIndex,
    required ClipFitMode fitMode,
    required ClipViewport viewport,
    required ColorChoice backgroundColor,
    required String durationSeconds,
    required int cellWidth,
    required int cellHeight,
    required String outputLabel,
  }) {
    return '[$inputIndex:v]'
        'setpts=PTS-STARTPTS,'
        '${_videoTileScaleFilterChain(fitMode: fitMode, viewport: viewport, backgroundColor: backgroundColor, cellWidth: cellWidth, cellHeight: cellHeight)},'
        'trim=duration=$durationSeconds,'
        'setpts=PTS-STARTPTS'
        '[$outputLabel]';
  }

  String _sequentialFrozenVideoFilter({
    required int inputIndex,
    required ClipFitMode fitMode,
    required ClipViewport viewport,
    required ColorChoice backgroundColor,
    required bool freezeAtEnd,
    required Duration clipDuration,
    required String durationSeconds,
    required int cellWidth,
    required int cellHeight,
    required String outputLabel,
  }) {
    final tailSampleSeconds = math.min(0.5, clipDuration.inMilliseconds / 1000);
    final freezeStartSeconds = freezeAtEnd
        ? math.max(0, clipDuration.inMilliseconds / 1000 - tailSampleSeconds)
        : 0.0;
    final freezeSelectionFilter = freezeAtEnd
        ? 'trim=start=${freezeStartSeconds.toStringAsFixed(3)},'
              'setpts=PTS-STARTPTS,'
              'reverse,'
              // Lock to a single decoded frame so inactive tiles do not
              // advance by one frame when sequential segments are stitched.
              '$_firstFrameSelectFilter,'
              'setpts=PTS-STARTPTS,'
        : '$_firstFrameSelectFilter,'
              'setpts=PTS-STARTPTS,';
    return '[$inputIndex:v]'
        'setpts=PTS-STARTPTS,'
        '${_videoTileScaleFilterChain(fitMode: fitMode, viewport: viewport, backgroundColor: backgroundColor, cellWidth: cellWidth, cellHeight: cellHeight)},'
        '$freezeSelectionFilter'
        'fps=30,'
        'tpad=stop_mode=clone:stop_duration=$durationSeconds,'
        'trim=duration=$durationSeconds,'
        'setpts=PTS-STARTPTS'
        '[$outputLabel]';
  }

  String _videoTileScaleFilterChain({
    required ClipFitMode fitMode,
    required ClipViewport viewport,
    required ColorChoice backgroundColor,
    required int cellWidth,
    required int cellHeight,
  }) {
    return switch (fitMode) {
      ClipFitMode.cropCenter =>
        '${_cropViewportFilterChain(viewport: viewport, cellWidth: cellWidth, cellHeight: cellHeight)},'
            'setsar=1',
      ClipFitMode.centerInside =>
        'format=rgba,'
            'scale=$cellWidth:$cellHeight:force_original_aspect_ratio=decrease,'
            'pad=$cellWidth:$cellHeight:(ow-iw)/2:(oh-ih)/2:color=${backgroundColor.ffmpegHex},'
            'setsar=1',
    };
  }

  String _borderBaseFilter({
    required ExportOptions options,
    required String durationSeconds,
    required int borderImageInputIndex,
  }) {
    if (options.borderImagePath == null) {
      return 'color=c=${options.borderColor.ffmpegHex}:'
          's=${options.outputWidth}x${options.outputHeight}:'
          'd=$durationSeconds[base]';
    }
    return '[$borderImageInputIndex:v]'
        'scale=${options.outputWidth}:${options.outputHeight}:'
        'force_original_aspect_ratio=increase,'
        'crop=${options.outputWidth}:${options.outputHeight},'
        'setsar=1,trim=duration=$durationSeconds,setpts=PTS-STARTPTS[base]';
  }

  List<String> _borderImageInputArguments({
    required String path,
    required String durationSeconds,
  }) => <String>[
    '-loop',
    '1',
    '-framerate',
    '30',
    '-t',
    durationSeconds,
    '-threads',
    _decoderThreadCount,
    '-i',
    path,
  ];

  String _photoTileScaleFilterChain({
    required ClipFitMode fitMode,
    required ClipViewport viewport,
    required int cellWidth,
    required int cellHeight,
  }) {
    return switch (fitMode) {
      ClipFitMode.cropCenter =>
        '${_cropViewportFilterChain(viewport: viewport, cellWidth: cellWidth, cellHeight: cellHeight)},'
            'setsar=1',
      ClipFitMode.centerInside =>
        'scale=$cellWidth:$cellHeight:force_original_aspect_ratio=decrease,'
            'setsar=1',
    };
  }

  String _cropViewportFilterChain({
    required ClipViewport viewport,
    required int cellWidth,
    required int cellHeight,
  }) {
    final zoomedWidth = math.max(
      cellWidth,
      (cellWidth * viewport.zoom).round(),
    );
    final zoomedHeight = math.max(
      cellHeight,
      (cellHeight * viewport.zoom).round(),
    );
    final focusX = viewport.focusX.toStringAsFixed(6);
    final focusY = viewport.focusY.toStringAsFixed(6);
    return 'scale=$zoomedWidth:$zoomedHeight:'
        'force_original_aspect_ratio=increase,'
        'crop=$cellWidth:$cellHeight:'
        '(iw-ow)*$focusX:(ih-oh)*$focusY';
  }

  (String, String) _photoForegroundOutputForFitMode({
    required ClipFitMode fitMode,
  }) {
    return switch (fitMode) {
      ClipFitMode.cropCenter => ('0', '0'),
      ClipFitMode.centerInside => ('(W-w)/2', '(H-h)/2'),
    };
  }

  StreamInformation? _findPrimaryVideoStream(MediaInformation information) {
    for (final stream in information.getStreams()) {
      if (stream.getType() == 'video') {
        return stream;
      }
    }
    return null;
  }

  bool _hasAudioStream(MediaInformation information) {
    for (final stream in information.getStreams()) {
      if (stream.getType() == 'audio') {
        return true;
      }
    }
    return false;
  }

  bool _isPhotoPath(String filePath) {
    return _photoExtensions.contains(p.extension(filePath).toLowerCase());
  }

  String? _buildAudioFilterGraph({
    required List<String> filters,
    required List<CollageSlotClip> slotClips,
    required AudioMode audioMode,
    required String targetDurationSeconds,
  }) {
    switch (audioMode) {
      case AudioMode.firstClip:
        if (!slotClips.first.clip.hasAudio) {
          return null;
        }
        filters.add(
          _normalizedAudioFilter(
            inputIndex: 0,
            targetDurationSeconds: targetDurationSeconds,
            outputLabel: 'outa',
          ),
        );
        return 'outa';
      case AudioMode.mixAll:
        final audioInputIndexes = <int>[
          for (var i = 0; i < slotClips.length; i++)
            if (slotClips[i].clip.hasAudio) i,
        ];
        if (audioInputIndexes.isEmpty) {
          return null;
        }

        final audioLabels = <String>[];
        for (final inputIndex in audioInputIndexes) {
          final label = 'a$inputIndex';
          filters.add(
            _normalizedAudioFilter(
              inputIndex: inputIndex,
              targetDurationSeconds: targetDurationSeconds,
              outputLabel: label,
            ),
          );
          audioLabels.add(label);
        }
        filters.add(
          '${audioLabels.map((label) => '[$label]').join()}'
          'amix=inputs=${audioLabels.length}:duration=longest:dropout_transition=0[outa]',
        );
        return 'outa';
      case AudioMode.longestClip:
        var longestInputIndex = 0;
        var longestDuration = Duration.zero;
        for (var i = 0; i < slotClips.length; i++) {
          final clip = slotClips[i].clip;
          if (clip.duration > longestDuration) {
            longestDuration = clip.duration;
            longestInputIndex = i;
          }
        }
        if (!slotClips[longestInputIndex].clip.hasAudio) {
          return null;
        }
        filters.add(
          _normalizedAudioFilter(
            inputIndex: longestInputIndex,
            targetDurationSeconds: targetDurationSeconds,
            outputLabel: 'outa',
          ),
        );
        return 'outa';
      case AudioMode.mute:
        return null;
    }
  }

  String _normalizedAudioFilter({
    required int inputIndex,
    required String targetDurationSeconds,
    required String outputLabel,
  }) {
    return '[$inputIndex:a]'
        'asetpts=PTS-STARTPTS,'
        'aresample=44100:async=1:first_pts=0,'
        'aformat=sample_rates=44100:channel_layouts=stereo,'
        'apad,'
        'atrim=duration=$targetDurationSeconds'
        '[$outputLabel]';
  }

  String _durationSeconds(Duration duration) {
    return (duration.inMilliseconds / 1000).toStringAsFixed(3);
  }

  List<String> _loopedStillImageInputArguments({
    required String path,
    required String durationSeconds,
  }) {
    return <String>[
      '-loop',
      '1',
      '-framerate',
      '30',
      '-t',
      durationSeconds,
      '-threads',
      _decoderThreadCount,
      '-i',
      path,
    ];
  }

  List<String> _singleThreadedInputArguments(String path) {
    return <String>['-threads', _decoderThreadCount, '-i', path];
  }

  List<String> _videoInputArguments(VideoClipInfo clip) {
    if (!clip.isTrimmed) {
      return _singleThreadedInputArguments(clip.path);
    }
    return <String>[
      '-ss',
      _durationSeconds(clip.trimStart),
      '-t',
      _durationSeconds(clip.duration),
      '-threads',
      _decoderThreadCount,
      '-i',
      clip.path,
    ];
  }

  List<String> _h264VideoEncodingArguments({int? frameRate = 30}) {
    return <String>[
      if (frameRate != null) ...<String>['-r', '$frameRate'],
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '18',
      '-threads',
      _encoderThreadCount,
      '-pix_fmt',
      'yuv420p',
    ];
  }

  List<String> _aacAudioEncodingArguments() {
    return <String>['-c:a', 'aac', '-b:a', '192k'];
  }

  bool _addRoundedCornerMaskFilters({
    required List<String> filters,
    required int cellWidth,
    required int cellHeight,
    required int radius,
    required int outputCount,
  }) {
    final safeRadius = math.min(radius, math.min(cellWidth, cellHeight) ~/ 2);
    if (safeRadius <= 0 || outputCount <= 0) {
      return false;
    }

    final right = cellWidth - safeRadius - 1;
    final bottom = cellHeight - safeRadius - 1;
    final radiusSquared = safeRadius * safeRadius;
    final alphaExpression =
        "if(lt(X,$safeRadius)*lt(Y,$safeRadius),if(lte((X-$safeRadius)^2+(Y-$safeRadius)^2,$radiusSquared),255,0),"
        "if(gt(X,$right)*lt(Y,$safeRadius),if(lte((X-$right)^2+(Y-$safeRadius)^2,$radiusSquared),255,0),"
        "if(lt(X,$safeRadius)*gt(Y,$bottom),if(lte((X-$safeRadius)^2+(Y-$bottom)^2,$radiusSquared),255,0),"
        "if(gt(X,$right)*gt(Y,$bottom),if(lte((X-$right)^2+(Y-$bottom)^2,$radiusSquared),255,0),255))))";

    final maskOutputs = <String>[
      for (var index = 0; index < outputCount; index += 1)
        '[corner_mask_$index]',
    ].join();
    final splitFilter = outputCount == 1 ? '' : 'split=$outputCount';
    filters.add(
      'nullsrc=s=${cellWidth}x$cellHeight,'
      'format=gray,'
      "geq=lum='$alphaExpression',"
      'trim=end_frame=1,'
      // Reuse the computed frame for the full export. mergeplanes ends when
      // its mask input ends, so a single unlooped mask freezes video tiles.
      'loop=loop=-1:size=1:start=0,'
      'setpts=N/(30*TB)'
      '${splitFilter.isEmpty ? '' : ',$splitFilter'}'
      '$maskOutputs',
    );
    return true;
  }

  void _addRoundedCornerApplicationFilters({
    required List<String> filters,
    required String inputLabel,
    required String outputLabel,
    required int maskIndex,
    required bool hasMask,
  }) {
    if (!hasMask) {
      filters.add('[$inputLabel]format=yuv420p[$outputLabel]');
      return;
    }

    final foregroundLabel = 'corner_foreground_$maskIndex';
    filters
      // Preserve the prior rounded-corner color conversion exactly while the
      // expensive alpha expression is evaluated only once in the shared mask.
      ..add('[$inputLabel]format=yuva420p,format=gbrap[$foregroundLabel]')
      ..add(
        '[$foregroundLabel][corner_mask_$maskIndex]'
        'mergeplanes='
        'map0s=0:map0p=0:'
        'map1s=0:map1p=1:'
        'map2s=0:map2p=2:'
        'map3s=1:map3p=0:'
        'format=gbrap[$outputLabel]',
      );
  }
}

const Set<String> _photoExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.heic',
  '.heif',
};

Uint8List _bytesFromByteData(ByteData byteData) {
  return byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
}

class _ClipLabelOverlay {
  const _ClipLabelOverlay({
    required this.filePath,
    required this.x,
    required this.y,
  });

  final String filePath;
  final int x;
  final int y;
}

class _RenderedClipLabelImage {
  const _RenderedClipLabelImage({required this.width, required this.height});

  final int width;
  final int height;
}

class _VideoDisplayMetadata {
  const _VideoDisplayMetadata({
    required this.width,
    required this.height,
    required this.durationSeconds,
    required this.hasAudio,
    required this.frameRate,
  });

  final int width;
  final int height;
  final double durationSeconds;
  final bool hasAudio;
  final double frameRate;
}

class VideoExportProgress {
  const VideoExportProgress({
    required this.progress,
    required this.processed,
    required this.total,
    this.speed,
  });

  final double progress;
  final Duration processed;
  final Duration total;
  final double? speed;
}
