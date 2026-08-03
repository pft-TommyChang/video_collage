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
  });

  final String label;
  final ColorChoice selected;
  final ValueChanged<ColorChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label color', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        DropdownButtonFormField<ColorChoice>(
          initialValue: selected,
          isExpanded: true,
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
          items: _colorChoices.map((choice) {
            return DropdownMenuItem<ColorChoice>(
              value: choice,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: choice.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD7CEC2)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(choice.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (choice) {
            if (choice != null) {
              onSelected(choice);
            }
          },
        ),
      ],
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
  const _EmptyListState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DED1)),
      ),
      child: Text(
        'Import videos or photos to start your collage.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF697180)),
      ),
    );
  }
}

class _AnimatedSidePanel extends StatelessWidget {
  const _AnimatedSidePanel({
    super.key,
    required this.isCollapsed,
    required this.width,
    required this.child,
  });

  final bool isCollapsed;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
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
