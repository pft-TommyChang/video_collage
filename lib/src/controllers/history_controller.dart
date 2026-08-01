part of '../video_collage_app.dart';

extension _HistoryController on _VideoCollageScreenState {
  Future<void> _recordExportHistory(String path, ExportFormat format) async {
    final normalizedPath = _resolveHistoryPath(path);
    final entry = ExportHistoryEntry(
      path: normalizedPath,
      format: format.label,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final history = await _settingsStore.addExportHistoryEntry(entry);
    if (!mounted) {
      return;
    }
    _updateState(() {
      _exportHistory = history;
      _sessionLastExportEntry = entry;
    });
  }

  Future<void> _openExportHistoryEntry(ExportHistoryEntry entry) async {
    final resolvedPath = _resolveHistoryPath(entry.path);
    final file = File(resolvedPath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'Export file no longer exists: $resolvedPath';
      });
      return;
    }

    try {
      final result = await Process.run('open', <String>[resolvedPath]);
      if (result.exitCode != 0 && mounted) {
        _updateState(() {
          _statusMessage = 'Unable to open export: $resolvedPath';
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'Unable to open export: $resolvedPath';
      });
    }
  }

  Future<void> _openLastExport() async {
    final lastExportEntry = _lastExportEntry;
    if (lastExportEntry == null) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'No export history yet.';
      });
      return;
    }
    await _openExportHistoryEntry(lastExportEntry);
  }

  Future<void> _showLastExportMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final lastExportEntry = _lastExportEntry;
    if (_isExporting || lastExportEntry == null) {
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = details.globalPosition;
    final action = await showMenu<_LastExportAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const <PopupMenuEntry<_LastExportAction>>[
        PopupMenuItem<_LastExportAction>(
          value: _LastExportAction.openFile,
          child: Text('Open File'),
        ),
        PopupMenuItem<_LastExportAction>(
          value: _LastExportAction.openFolder,
          child: Text('Open Folder'),
        ),
      ],
    );

    switch (action) {
      case _LastExportAction.openFile:
        await _openExportHistoryEntry(lastExportEntry);
      case _LastExportAction.openFolder:
        await _openExportHistoryFolder(lastExportEntry);
      case null:
        return;
    }
  }

  Future<void> _openExportHistoryFolder(ExportHistoryEntry entry) async {
    final resolvedPath = _resolveHistoryPath(entry.path);
    final file = File(resolvedPath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'Export file no longer exists: $resolvedPath';
      });
      return;
    }

    final directoryPath = p.dirname(resolvedPath);
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'Export folder no longer exists: $directoryPath';
      });
      return;
    }

    try {
      final result = await Process.run('open', <String>['-R', resolvedPath]);
      if (result.exitCode != 0 && mounted) {
        _updateState(() {
          _statusMessage = 'Unable to open folder: $directoryPath';
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _statusMessage = 'Unable to open folder: $directoryPath';
      });
    }
  }

  String _resolveHistoryPath(String path) {
    if (p.isAbsolute(path)) {
      return p.normalize(path);
    }
    return p.normalize(p.absolute(path));
  }

  Future<void> _showExportHistory() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Recent Exports'),
          content: SizedBox(
            width: 520,
            child: _exportHistory.isEmpty
                ? const Text('No recent exports.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _exportHistory.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _exportHistory[index];
                      final exists = File(entry.path).existsSync();
                      return ListTile(
                        enabled: exists,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          p.basename(entry.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${entry.format} • ${_formatHistoryTimestamp(entry.timestampMillis)}\n${entry.path}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Open folder',
                              onPressed: !exists
                                  ? null
                                  : () {
                                      Navigator.of(dialogContext).pop();
                                      unawaited(
                                        _openExportHistoryFolder(entry),
                                      );
                                    },
                              icon: const Icon(Icons.folder_open_outlined),
                            ),
                            IconButton(
                              tooltip: 'Open file',
                              onPressed: !exists
                                  ? null
                                  : () {
                                      Navigator.of(dialogContext).pop();
                                      unawaited(_openExportHistoryEntry(entry));
                                    },
                              icon: const Icon(Icons.open_in_new_rounded),
                            ),
                          ],
                        ),
                        onTap: !exists
                            ? null
                            : () {
                                Navigator.of(dialogContext).pop();
                                unawaited(_openExportHistoryEntry(entry));
                              },
                      );
                    },
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    _toastOverlayEntry?.remove();

    final overlay = Overlay.of(context);

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
        bottom: 36,
        child: IgnorePointer(
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xE3171A21),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _toastOverlayEntry = entry;
    _toastTimer = Timer(const Duration(seconds: 1), () {
      _toastOverlayEntry?.remove();
      _toastOverlayEntry = null;
      _toastTimer = null;
    });
  }

  String _defaultClipNameForPath(String path) {
    return p.basenameWithoutExtension(path);
  }

  String _suggestedExportFileName(ExportFormat format) {
    if (!_appendDateTimeToExportName) {
      return format.suggestedFileName;
    }
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final extension = format == ExportFormat.jpg ? 'jpg' : 'mp4';
    return 'pfc_export_$timestamp.$extension';
  }
}
