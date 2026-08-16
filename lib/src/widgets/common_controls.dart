part of '../video_collage_app.dart';

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.isCollapsed,
    required this.onToggle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2D8CA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!isCollapsed && action != null) ...<Widget>[
                  const SizedBox(width: 12),
                  action!,
                ],
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: onToggle,
                  tooltip: isCollapsed ? 'Expand section' : 'Collapse section',
                  style: _sectionHeaderIconButtonStyle(),
                  icon: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    tween: Tween<double>(
                      begin: 0,
                      end: isCollapsed ? -math.pi / 2 : 0,
                    ),
                    builder: (context, angle, child) {
                      return Transform.rotate(angle: angle, child: child);
                    },
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                heightFactor: isCollapsed ? 0 : 1,
                child: IgnorePointer(
                  ignoring: isCollapsed,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: isCollapsed ? 0 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF697180)),
                        ),
                        const SizedBox(height: 16),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSelector extends StatelessWidget {
  const _ColorSelector({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.allowTransparent = false,
    this.imagePath,
    this.onPickImage,
    this.onClearImage,
  });

  final String label;
  final ColorChoice selected;
  final ValueChanged<ColorChoice> onSelected;
  final bool allowTransparent;
  final String? imagePath;
  final VoidCallback? onPickImage;
  final VoidCallback? onClearImage;

  Future<void> _openPalette(BuildContext context) async {
    var hsv = HSVColor.fromColor(
      selected.isTransparent ? Colors.white : selected.color,
    );
    final color = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final previewColor = hsv.toColor();
          final hex = (previewColor.toARGB32() & 0xFFFFFF)
              .toRadixString(16)
              .padLeft(6, '0')
              .toUpperCase();
          return AlertDialog(
            title: Text('Choose $label color'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _SaturationValuePicker(
                    hsvColor: hsv,
                    onChanged: (color) => setDialogState(() => hsv = color),
                  ),
                  const SizedBox(height: 16),
                  _HuePicker(
                    hue: hsv.hue,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withHue(value)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: previewColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFD7CEC2)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '#$hex',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, previewColor),
                child: const Text('Use color'),
              ),
            ],
          );
        },
      ),
    );
    if (color != null) {
      onSelected(_colorChoiceFromColor(color));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null;
    final hasTransparentBackground = allowTransparent && selected.isTransparent;
    const imageChoice = ColorChoice(
      label: 'Image',
      color: Colors.transparent,
      ffmpegHex: 'black',
    );
    final overrideChoice = hasImage
        ? imageChoice
        : hasTransparentBackground
        ? _transparentColor
        : null;
    final hasOverride = overrideChoice != null;
    const dropdownBackground = Color(0xFFFFFFFF);
    const dropdownSelectedColor = Color(0xFFF3EFE7);
    final dropdownBorderRadius = BorderRadius.circular(18);
    final choices = <ColorChoice>[..._colorChoices, ?overrideChoice];
    final selectedChoice =
        overrideChoice ??
        choices.firstWhere(
          (choice) => choice.color.toARGB32() == selected.color.toARGB32(),
          orElse: () => selected,
        );
    if (!choices.contains(selectedChoice)) {
      choices.add(selectedChoice);
    }
    Widget actionButton({
      required String tooltip,
      required VoidCallback? onPressed,
      required IconData icon,
    }) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(32),
          padding: EdgeInsets.zero,
        ),
        iconSize: 18,
        icon: Icon(icon),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Stack(
                alignment: Alignment.centerRight,
                children: <Widget>[
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(focusColor: dropdownSelectedColor),
                    child: ButtonTheme.fromButtonThemeData(
                      data: ButtonTheme.of(
                        context,
                      ).copyWith(alignedDropdown: true),
                      child: DropdownButtonFormField<ColorChoice>(
                        key: ValueKey(
                          '$label-${selected.color.toARGB32()}-$hasOverride',
                        ),
                        initialValue: selectedChoice,
                        isExpanded: true,
                        elevation: 4,
                        dropdownColor: dropdownBackground,
                        borderRadius: dropdownBorderRadius,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: hasOverride
                              ? const Color(0xFFF1EEE9)
                              : dropdownBackground,
                          contentPadding: const EdgeInsets.fromLTRB(
                            14,
                            12,
                            44,
                            12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: dropdownBorderRadius,
                            borderSide: const BorderSide(
                              color: Color(0xFFD7CEC2),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: dropdownBorderRadius,
                            borderSide: const BorderSide(
                              color: Color(0xFFD7CEC2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: dropdownBorderRadius,
                            borderSide: const BorderSide(
                              color: Color(0xFF171A21),
                              width: 2,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: choices.map((choice) {
                          final isImageChoice = identical(choice, imageChoice);
                          return DropdownMenuItem<ColorChoice>(
                            value: choice,
                            child: Row(
                              children: <Widget>[
                                if (isImageChoice)
                                  const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Icon(Icons.image, size: 19),
                                  )
                                else if (choice.isTransparent)
                                  const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Icon(
                                      Icons.layers_clear_outlined,
                                      size: 19,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: choice.color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFD7CEC2),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    choice.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: hasOverride
                            ? null
                            : (choice) {
                                if (choice != null) {
                                  onSelected(choice);
                                }
                              },
                      ),
                    ),
                  ),
                  Positioned(
                    right: 40,
                    child: IconButton(
                      tooltip: 'Open color palette',
                      onPressed: hasOverride
                          ? null
                          : () => _openPalette(context),
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.palette_outlined),
                    ),
                  ),
                ],
              ),
            ),
            if (onPickImage != null)
              actionButton(
                tooltip: hasImage ? 'Remove border image' : 'Use border image',
                onPressed: hasImage ? onClearImage : onPickImage,
                icon: hasImage
                    ? Icons.image_not_supported_outlined
                    : Icons.image_outlined,
              ),
            if (allowTransparent)
              actionButton(
                tooltip: hasTransparentBackground
                    ? 'Use solid background'
                    : 'Use transparent background',
                onPressed: () => onSelected(
                  hasTransparentBackground
                      ? _defaultBackgroundColor
                      : _transparentColor,
                ),
                icon: hasTransparentBackground
                    ? Icons.layers_outlined
                    : Icons.layers_clear_outlined,
              ),
          ],
        ),
      ],
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({
    required this.hsvColor,
    required this.onChanged,
  });

  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const height = 220.0;
        void update(Offset position) {
          final saturation = (position.dx / constraints.maxWidth).clamp(
            0.0,
            1.0,
          );
          final value = (1 - position.dy / height).clamp(0.0, 1.0);
          onChanged(hsvColor.withSaturation(saturation).withValue(value));
        }

        return GestureDetector(
          onPanDown: (details) => update(details.localPosition),
          onPanUpdate: (details) => update(details.localPosition),
          child: CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _SaturationValuePainter(hsvColor),
          ),
        );
      },
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hsvColor);

  final HSVColor hsvColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(12);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, radius));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.white,
            HSVColor.fromAHSV(1, hsvColor.hue, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.restore();

    final marker = Offset(
      hsvColor.saturation * size.width,
      (1 - hsvColor.value) * size.height,
    );
    canvas.drawCircle(marker, 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      marker,
      8,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.hsvColor != hsvColor;
}

class _HuePicker extends StatelessWidget {
  const _HuePicker({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: Colors.transparent,
          inactiveTrackColor: Colors.transparent,
          trackHeight: 32,
          thumbColor: Colors.white,
          overlayColor: Colors.white24,
        ),
        child: Slider(value: hue, min: 0, max: 360, onChanged: onChanged),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(
          onPressed: value < _maxGridDimension
              ? () => onChanged(value + 1)
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _EmptyListState extends StatelessWidget {
  const _EmptyListState({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: isLoading ? 'Opening media picker' : 'Browse for media',
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6F1),
            borderRadius: borderRadius,
            border: Border.all(color: const Color(0xFFE7DED1)),
          ),
          child: InkWell(
            key: const ValueKey<String>('empty-media-add-target'),
            onTap: onTap,
            borderRadius: borderRadius,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE7DE),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: isLoading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(
                            Icons.file_upload_outlined,
                            color: Color(0xFFC94F32),
                            size: 23,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          isLoading
                              ? 'Opening media picker…'
                              : 'Drop videos or photos',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: const Color(0xFF171A21),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isLoading
                              ? 'Select one or more files to continue.'
                              : 'here or into a grid cell, or click to browse.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF697180)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSidePanel extends StatelessWidget {
  const _AnimatedSidePanel({
    super.key,
    required this.isCollapsed,
    required this.animate,
    required this.width,
    required this.child,
  });

  final bool isCollapsed;
  final bool animate;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: animate ? const Duration(milliseconds: 240) : Duration.zero,
      curve: Curves.easeInOutCubic,
      width: isCollapsed ? 0 : width,
      height: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: ExcludeFocus(
        excluding: isCollapsed,
        child: ExcludeSemantics(
          excluding: isCollapsed,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: width,
            maxWidth: width,
            child: child,
          ),
        ),
      ),
    );
  }
}
