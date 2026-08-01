part of '../video_collage_app.dart';

class _ClipLabelEditResult {
  const _ClipLabelEditResult({
    required this.displayMode,
    this.name,
    this.preset,
  });

  final String? name;
  final _TwoClipLabelPreset? preset;
  final ClipLabelDisplayMode displayMode;
}

class _ClipLabelEditDialog extends StatefulWidget {
  const _ClipLabelEditDialog({
    required this.initialLabel,
    required this.initialDisplayMode,
    required this.showTwoClipPresets,
  });

  final String initialLabel;
  final ClipLabelDisplayMode initialDisplayMode;
  final bool showTwoClipPresets;

  @override
  State<_ClipLabelEditDialog> createState() => _ClipLabelEditDialogState();
}

class _ClipLabelEditDialogState extends State<_ClipLabelEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _textController;
  late String _draftName;
  late ClipLabelDisplayMode _selectedDisplayMode;

  @override
  void initState() {
    super.initState();
    _draftName = widget.initialLabel;
    _selectedDisplayMode = widget.initialDisplayMode;
    _textController = TextEditingController(text: widget.initialLabel)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialLabel.length,
      );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _applySingleClipPreset(String preset) {
    Navigator.of(context).pop(
      _ClipLabelEditResult(name: preset, displayMode: _selectedDisplayMode),
    );
  }

  void _applyTwoClipPreset(_TwoClipLabelPreset preset) {
    Navigator.of(context).pop(
      _ClipLabelEditResult(preset: preset, displayMode: _selectedDisplayMode),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      _ClipLabelEditResult(
        name: _draftName.trim(),
        displayMode: _selectedDisplayMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactPresetButtonStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: Theme.of(context).textTheme.bodyMedium,
    );

    return AlertDialog(
      title: const Text('Edit clip label'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Global label display',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Affects every clip in preview and export.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<ClipLabelDisplayMode>(
                  showSelectedIcon: false,
                  segments: ClipLabelDisplayMode.values
                      .map(
                        (mode) => ButtonSegment<ClipLabelDisplayMode>(
                          value: mode,
                          label: Text(mode.label),
                        ),
                      )
                      .toList(growable: false),
                  selected: <ClipLabelDisplayMode>{_selectedDisplayMode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _selectedDisplayMode = selection.first;
                    });
                  },
                ),
                if (_selectedDisplayMode ==
                    ClipLabelDisplayMode.indexOnly) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    'Index only mode hides custom labels, so clip label editing is unavailable.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'This clip',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only updates the selected clip label. Label cannot be blank.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _textController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Clip label',
                      border: OutlineInputBorder(),
                      helperText: 'Required',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Clip label cannot be blank.';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setState(() {
                        _draftName = value;
                      });
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Single-clip presets',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _singleClipLabelPresetRows
                        .map((presetRow) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: presetRow
                                  .map((preset) {
                                    return OutlinedButton(
                                      style: compactPresetButtonStyle,
                                      onPressed: () =>
                                          _applySingleClipPreset(preset),
                                      child: Text(preset),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                  if (widget.showTwoClipPresets) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Two-clip presets',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Global action for the two visible clips in the collage.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _twoClipLabelPresets
                          .map((preset) {
                            return OutlinedButton(
                              style: compactPresetButtonStyle,
                              onPressed: () => _applyTwoClipPreset(preset),
                              child: Text(
                                '${preset.firstLabel} / ${preset.secondLabel}',
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _TwoClipLabelPreset {
  const _TwoClipLabelPreset(this.firstLabel, this.secondLabel);

  final String firstLabel;
  final String secondLabel;
}

const List<_TwoClipLabelPreset> _twoClipLabelPresets = <_TwoClipLabelPreset>[
  _TwoClipLabelPreset('Before', 'After'),
  _TwoClipLabelPreset('Source', 'Target'),
  _TwoClipLabelPreset('Current', 'New'),
  _TwoClipLabelPreset('Input', 'Output'),
];

const List<List<String>> _singleClipLabelPresetRows = <List<String>>[
  <String>['Source', 'Before', 'Current', 'Input'],
  <String>['Target', 'After', 'New', 'Output', 'Result'],
];

String _formatHistoryTimestamp(int timestampMillis) {
  if (timestampMillis <= 0) {
    return 'Unknown time';
  }
  final dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
  final year = dateTime.year.toString().padLeft(4, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}
