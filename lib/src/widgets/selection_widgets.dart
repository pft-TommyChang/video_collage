part of '../video_collage_app.dart';

class _SelectionDropdown<T> extends StatelessWidget {
  const _SelectionDropdown({
    required this.label,
    required this.selected,
    required this.options,
    required this.itemLabel,
    this.itemBuilder,
    required this.onSelected,
  });

  final String label;
  final T selected;
  final List<T> options;
  final String Function(T option) itemLabel;
  final Widget Function(T option)? itemBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        DropdownButtonFormField<T>(
          key: ValueKey<String>(itemLabel(selected)),
          initialValue: selected,
          isExpanded: true,
          selectedItemBuilder: itemBuilder == null
              ? null
              : (context) => options
                    .map((option) => itemBuilder!(option))
                    .toList(growable: false),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFD7CEC2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFD7CEC2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF171A21), width: 2),
            ),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: options
              .map(
                (option) => DropdownMenuItem<T>(
                  value: option,
                  child: itemBuilder?.call(option) ?? Text(itemLabel(option)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onSelected(value);
            }
          },
        ),
      ],
    );
  }
}

class _ClipFitModeDropdownItem extends StatelessWidget {
  const _ClipFitModeDropdownItem({required this.mode});

  final ClipFitMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ClipFitModeIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ClipFitModeIcon extends StatelessWidget {
  const _ClipFitModeIcon({required this.mode});

  final ClipFitMode mode;

  @override
  Widget build(BuildContext context) {
    final isCropCenter = mode == ClipFitMode.cropCenter;

    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFB8B1A8)),
            ),
          ),
          Center(
            child: Container(
              width: isCropCenter ? 14 : 10,
              height: isCropCenter ? 10 : 7,
              decoration: BoxDecoration(
                color: const Color(0xFFFF7A59),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (isCropCenter)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF171A21),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClipLabelAlignmentDropdownItem extends StatelessWidget {
  const _ClipLabelAlignmentDropdownItem({required this.alignment});

  final ClipLabelAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ClipLabelAlignmentIcon(alignment: alignment),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            alignment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ClipLabelStyleDropdownItem extends StatelessWidget {
  const _ClipLabelStyleDropdownItem({required this.style});

  final ClipLabelVisualStyle style;

  @override
  Widget build(BuildContext context) {
    final previewStyle = clipLabelStyleForOverlayScale(
      1,
      baseFontSize: 12,
      baseEdgePadding: 4,
      alignment: ClipLabelAlignment.topLeft,
      visualStyle: style,
    );

    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFF7F2EA),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFD7CEC2)),
          ),
          alignment: Alignment.center,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: previewStyle.horizontalPadding,
              vertical: previewStyle.verticalPadding,
            ),
            decoration: BoxDecoration(
              color: previewStyle.backgroundColor,
              borderRadius: BorderRadius.circular(previewStyle.cornerRadius),
            ),
            child: _ClipLabelText(
              text: 'Aa',
              color: previewStyle.textColor,
              labelStyle: previewStyle,
              fontSizeOverride: 10,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            style.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ClipLabelText extends StatelessWidget {
  const _ClipLabelText({
    required this.text,
    required this.color,
    required this.labelStyle,
    this.fontSizeOverride,
  });

  final String text;
  final Color color;
  final ClipLabelStyle labelStyle;
  final double? fontSizeOverride;

  TextStyle _fillStyle() {
    return TextStyle(
      color: color,
      fontSize: fontSizeOverride ?? labelStyle.fontSize,
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
    );
  }

  TextStyle _outlineStyle() {
    return TextStyle(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = labelStyle.textOutlineWidth
        ..color = labelStyle.textOutlineColor!,
      fontSize: fontSizeOverride ?? labelStyle.fontSize,
      fontWeight: FontWeight.w600,
    );
  }

  Widget _buildText(TextStyle style) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (labelStyle.textOutlineColor == null ||
        labelStyle.textOutlineWidth <= 0) {
      return _buildText(_fillStyle());
    }

    return Stack(
      children: <Widget>[_buildText(_outlineStyle()), _buildText(_fillStyle())],
    );
  }
}

class _ClipLabelAlignmentIcon extends StatelessWidget {
  const _ClipLabelAlignmentIcon({required this.alignment});

  final ClipLabelAlignment alignment;

  Alignment _indicatorAlignment() => switch (alignment) {
    ClipLabelAlignment.topLeft => Alignment.topLeft,
    ClipLabelAlignment.topCenter => Alignment.topCenter,
    ClipLabelAlignment.topRight => Alignment.topRight,
    ClipLabelAlignment.center => Alignment.center,
    ClipLabelAlignment.bottomLeft => Alignment.bottomLeft,
    ClipLabelAlignment.bottomCenter => Alignment.bottomCenter,
    ClipLabelAlignment.bottomRight => Alignment.bottomRight,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF171A21), width: 1),
        ),
        child: Align(
          alignment: _indicatorAlignment(),
          child: Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Color(0xFFFF7A59),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportDurationDropdownItem extends StatelessWidget {
  const _ExportDurationDropdownItem({required this.mode});

  final ExportDurationMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ExportDurationIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _AudioModeDropdownItem extends StatelessWidget {
  const _AudioModeDropdownItem({required this.mode});

  final AudioMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _AudioModeIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _PlayModeDropdownItem extends StatelessWidget {
  const _PlayModeDropdownItem({required this.mode});

  final PlayMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _PlayModeIcon(mode: mode),
        const SizedBox(width: 12),
        Flexible(
          child: Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _PlayModeIcon extends StatelessWidget {
  const _PlayModeIcon({required this.mode});

  final PlayMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: switch (mode) {
        PlayMode.parallel => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _PlayModeParallelRow(),
            SizedBox(height: 2),
            _PlayModeParallelRow(),
          ],
        ),
        PlayMode.sequential => const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _PlayModeTile(),
            SizedBox(width: 1),
            _PlayModeArrow(),
            SizedBox(width: 1),
            _PlayModeTile(isHighlighted: true),
          ],
        ),
      },
    );
  }
}

class _PlayModeParallelRow extends StatelessWidget {
  const _PlayModeParallelRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _PlayModeTile(isHighlighted: true),
        SizedBox(width: 1),
        _PlayModeArrow(),
      ],
    );
  }
}

class _PlayModeTile extends StatelessWidget {
  const _PlayModeTile({this.isHighlighted = false});

  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF7A59)
            : const Color(0xFFE5DED3),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFF7A59)
              : const Color(0xFFB8B1A8),
        ),
      ),
    );
  }
}

class _PlayModeArrow extends StatelessWidget {
  const _PlayModeArrow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 4,
      height: 6,
      child: CustomPaint(painter: _PlayModeArrowPainter()),
    );
  }
}

class _PlayModeArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF7A59)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width - 1.7, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 2.4, 1),
      Offset(size.width - 0.3, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 2.4, size.height - 1),
      Offset(size.width - 0.3, centerY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AudioModeIcon extends StatelessWidget {
  const _AudioModeIcon({required this.mode});

  final AudioMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: switch (mode) {
        AudioMode.firstClip => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AudioTrackBar(width: 16, isHighlighted: true),
            SizedBox(height: 2),
            _AudioTrackBar(width: 12),
            SizedBox(height: 2),
            _AudioTrackBar(width: 8),
          ],
        ),
        AudioMode.mixAll => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AudioTrackBar(width: 16, isHighlighted: true),
            SizedBox(height: 2),
            _AudioTrackBar(width: 13, isHighlighted: true),
            SizedBox(height: 2),
            _AudioTrackBar(width: 10, isHighlighted: true),
          ],
        ),
        AudioMode.longestClip => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AudioTrackBar(width: 8),
            SizedBox(height: 2),
            _AudioTrackBar(width: 11),
            SizedBox(height: 2),
            _AudioTrackBar(width: 16, isHighlighted: true),
          ],
        ),
        AudioMode.mute => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const Center(
              child: Icon(
                Icons.volume_up_rounded,
                size: 15,
                color: Color(0xFFB8B1A8),
              ),
            ),
            Center(
              child: Transform.rotate(
                angle: -0.78,
                child: Container(
                  width: 20,
                  height: 2.4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A59),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _AudioTrackBar extends StatelessWidget {
  const _AudioTrackBar({required this.width, this.isHighlighted = false});

  final double width;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF7A59)
            : const Color(0xFFB8B1A8),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ExportDurationIcon extends StatelessWidget {
  const _ExportDurationIcon({required this.mode});

  final ExportDurationMode mode;

  @override
  Widget build(BuildContext context) {
    final highlightLong = mode == ExportDurationMode.longest;
    final highlightShort = mode == ExportDurationMode.shortest;

    return Container(
      width: 28,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2EA),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD7CEC2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DurationBar(width: 16, isHighlighted: highlightLong),
          const SizedBox(height: 3),
          _DurationBar(width: 10, isHighlighted: highlightShort),
        ],
      ),
    );
  }
}

class _DurationBar extends StatelessWidget {
  const _DurationBar({required this.width, required this.isHighlighted});

  final double width;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF7A59)
            : const Color(0xFFB8B1A8),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _AspectRatioDropdownItem extends StatelessWidget {
  const _AspectRatioDropdownItem({required this.preset});

  final AspectRatioPreset preset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _AspectRatioSwatch(preset: preset),
        const SizedBox(width: 12),
        Text(preset.label, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _AspectRatioSwatch extends StatelessWidget {
  const _AspectRatioSwatch({required this.preset});

  final AspectRatioPreset preset;

  @override
  Widget build(BuildContext context) {
    const outerSize = 26.0;
    const maxInnerSize = 16.0;
    final ratio = preset.value;
    final innerWidth = ratio >= 1 ? maxInnerSize : maxInnerSize * ratio;
    final innerHeight = ratio >= 1 ? maxInnerSize / ratio : maxInnerSize;

    return Container(
      width: outerSize,
      height: outerSize,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCCFBC)),
      ),
      alignment: Alignment.center,
      child: Container(
        width: innerWidth,
        height: innerHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF171A21), width: 1.4),
        ),
      ),
    );
  }
}
