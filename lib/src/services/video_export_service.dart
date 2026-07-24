import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';
import 'package:path/path.dart' as p;

import '../models.dart';

class VideoExportException implements Exception {
  const VideoExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VideoExportService {
  const VideoExportService();

  Future<VideoClipInfo> probeClip(String filePath) async {
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

    return VideoClipInfo(
      path: filePath,
      name: p.basename(filePath),
      duration: Duration(milliseconds: (durationSeconds * 1000).round()),
      width: stream?.getWidth() ?? 0,
      height: stream?.getHeight() ?? 0,
    );
  }

  Future<void> exportCollage({
    required List<CollageSlotClip> slotClips,
    required ExportOptions options,
    required String outputPath,
  }) async {
    if (slotClips.isEmpty) {
      throw const VideoExportException('Please add at least one video.');
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

    final targetDurationMs = math.max(
      1000,
      slotClips.fold<int>(
        0,
        (current, entry) =>
            math.max(current, entry.clip.duration.inMilliseconds),
      ),
    );
    final targetDurationSeconds = (targetDurationMs / 1000).toStringAsFixed(3);
    Directory? labelTempDirectory;

    try {
      final labelOverlays = options.includeClipLabelsInOutput
          ? await _createClipLabelOverlays(
              slotClips: slotClips,
              scaleFactor: options.scaleFactor,
              cellWidth: cellWidth,
              tempDirectory: labelTempDirectory = await Directory.systemTemp
                  .createTemp('video_collage_labels_'),
            )
          : const <_ClipLabelOverlay>[];

      final filters = <String>[
        'color=c=${options.borderColor.ffmpegHex}:s=${options.outputWidth}x${options.outputHeight}:d=$targetDurationSeconds[base]',
      ];

      for (var inputIndex = 0; inputIndex < slotClips.length; inputIndex++) {
        final clipDurationMs = slotClips[inputIndex]
            .clip
            .duration
            .inMilliseconds
            .clamp(0, targetDurationMs);
        final stopDurationMs = targetDurationMs - clipDurationMs;
        final stopDurationFilter = stopDurationMs > 0
            ? ',tpad=stop_mode=clone:stop_duration=${(stopDurationMs / 1000).toStringAsFixed(3)}'
            : '';
        final roundedCornerFilter = _roundedCornerFilter(
          cellWidth: cellWidth,
          cellHeight: cellHeight,
          radius: options.tileCornerRadiusPx,
        );

        filters.add(
          '[$inputIndex:v]setpts=PTS-STARTPTS,'
          'scale=$cellWidth:$cellHeight:force_original_aspect_ratio=increase,'
          'crop=$cellWidth:$cellHeight,'
          'setsar=1'
          '$stopDurationFilter'
          '[clip$inputIndex]',
        );

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

        filters.add(
          '[$decoratedClipName]${_filterChainFrom(roundedCornerFilter)}[v$inputIndex]',
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
      filters.add('[merged]format=yuv420p[outv]');

      final arguments = <String>[
        '-y',
        for (final entry in slotClips) ...<String>['-i', entry.clip.path],
        for (final overlay in labelOverlays) ...<String>[
          '-loop',
          '1',
          '-i',
          overlay.filePath,
        ],
        '-filter_complex',
        filters.join(';'),
        '-map',
        '[outv]',
        '-map',
        '0:a?',
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
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-movflags',
        '+faststart',
        outputPath,
      ];

      final session = await FFmpegKit.executeWithArguments(arguments);
      final returnCode = await session.getReturnCode();

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

  Future<List<_ClipLabelOverlay>> _createClipLabelOverlays({
    required List<CollageSlotClip> slotClips,
    required double scaleFactor,
    required int cellWidth,
    required Directory tempDirectory,
  }) async {
    final labelStyle = clipLabelStyleForOverlayScale(
      overlayLabelScaleForExportScale(scaleFactor),
    );
    final maxTextWidth = math.max(
      1.0,
      cellWidth - (labelStyle.margin * 2) - (labelStyle.horizontalPadding * 2),
    );

    final overlays = <_ClipLabelOverlay>[];
    for (var inputIndex = 0; inputIndex < slotClips.length; inputIndex++) {
      final filePath = p.join(tempDirectory.path, 'label_$inputIndex.png');
      await _renderClipLabelImage(
        filePath: filePath,
        text:
            '#${slotClips[inputIndex].slotIndex + 1} ${slotClips[inputIndex].clip.name}',
        labelStyle: labelStyle,
        maxTextWidth: maxTextWidth,
      );
      overlays.add(
        _ClipLabelOverlay(
          filePath: filePath,
          x: labelStyle.margin.round(),
          y: labelStyle.margin.round(),
        ),
      );
    }
    return overlays;
  }

  Future<void> _renderClipLabelImage({
    required String filePath,
    required String text,
    required ClipLabelStyle labelStyle,
    required double maxTextWidth,
  }) async {
    final paragraphBuilder =
        ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontSize: labelStyle.fontSize,
            fontWeight: ui.FontWeight.w600,
            maxLines: 1,
            ellipsis: '...',
          ),
        )..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFFFFFFFF),
            fontSize: labelStyle.fontSize,
            fontWeight: ui.FontWeight.w600,
          ),
        );

    paragraphBuilder.addText(text);
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: maxTextWidth));

    final imageWidth = math.max(
      1,
      (paragraph.longestLine + (labelStyle.horizontalPadding * 2)).ceil(),
    );
    final imageHeight = math.max(
      1,
      (paragraph.height + (labelStyle.verticalPadding * 2)).ceil(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final backgroundPaint = ui.Paint()..color = const ui.Color(0x7A000000);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
        ui.Radius.circular(imageHeight / 2),
      ),
      backgroundPaint,
    );
    canvas.drawParagraph(
      paragraph,
      ui.Offset(labelStyle.horizontalPadding, labelStyle.verticalPadding),
    );

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
  }

  StreamInformation? _findPrimaryVideoStream(MediaInformation information) {
    for (final stream in information.getStreams()) {
      if (stream.getType() == 'video') {
        return stream;
      }
    }
    return null;
  }

  String _roundedCornerFilter({
    required int cellWidth,
    required int cellHeight,
    required int radius,
  }) {
    final safeRadius = math.min(radius, math.min(cellWidth, cellHeight) ~/ 2);
    if (safeRadius <= 0) {
      return ',format=yuv420p';
    }

    final right = cellWidth - safeRadius - 1;
    final bottom = cellHeight - safeRadius - 1;
    final radiusSquared = safeRadius * safeRadius;
    final alphaExpression =
        "if(lt(X,$safeRadius)*lt(Y,$safeRadius),if(lte((X-$safeRadius)^2+(Y-$safeRadius)^2,$radiusSquared),255,0),"
        "if(gt(X,$right)*lt(Y,$safeRadius),if(lte((X-$right)^2+(Y-$safeRadius)^2,$radiusSquared),255,0),"
        "if(lt(X,$safeRadius)*gt(Y,$bottom),if(lte((X-$safeRadius)^2+(Y-$bottom)^2,$radiusSquared),255,0),"
        "if(gt(X,$right)*gt(Y,$bottom),if(lte((X-$right)^2+(Y-$bottom)^2,$radiusSquared),255,0),255))))";

    return ",format=yuva420p,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='$alphaExpression'";
  }
}

String _filterChainFrom(String filterChain) {
  return filterChain.startsWith(',') ? filterChain.substring(1) : filterChain;
}

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
