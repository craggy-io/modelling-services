// account_dialogs.dart: Open while signed in (the account's models first,
// each with delete, then opening a file), and the choice after a save
// conflict.

import 'package:flutter/material.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'host.dart';
import 'host_model_source.dart';

/// What the user picked in the Open dialog.
sealed class OpenChoice {
  const OpenChoice();
}

/// A model in the account.
class OpenAccountModel extends OpenChoice {
  const OpenAccountModel(this.id);
  final String id;
}

/// A local file instead.
class OpenFile extends OpenChoice {
  const OpenFile();
}

/// Lists [source]'s models to open or delete; null when cancelled.
Future<OpenChoice?> showAccountOpenDialog(BuildContext context, HostModelSource source) => showDialog<OpenChoice>(
  context: context,
  builder: (_) => _OpenDialog(source: source),
);

class _OpenDialog extends StatefulWidget {
  const _OpenDialog({required this.source});

  final HostModelSource source;

  @override
  State<_OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends State<_OpenDialog> {
  late Future<List<HostEntry>> _entries = widget.source.entries();
  String? _error;

  Future<void> _remove(HostEntry e) async {
    final title = e.title.isEmpty ? 'this model' : '"${e.title}"';
    final sure = await ModelChrome.of(context).confirm(
      context,
      title: 'Delete $title?',
      message: 'This removes $title from ${widget.source.label}. It cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    try {
      await widget.source.remove(e.id);
      setState(() {
        _error = null;
        _entries = widget.source.entries();
      });
    } on HostError catch (err) {
      setState(() => _error = 'Could not delete: ${describeHostError(err, widget.source.label)}');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('account-open-dialog'),
    title: Text('Open from ${widget.source.label}'),
    content: SizedBox(
      width: 520,
      height: 360,
      child: FutureBuilder<List<HostEntry>>(
        future: _entries,
        builder: (context, snap) {
          final error = snap.error;
          if (error != null) {
            final words = error is HostError ? describeHostError(error, widget.source.label) : '$error';
            return Center(child: Text('Could not list models: $words', key: const ValueKey('account-open-error')));
          }
          final entries = snap.data;
          if (entries == null) return const Center(child: CircularProgressIndicator());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              Expanded(
                child: entries.isEmpty
                    ? Center(child: Text('No models in ${widget.source.label} yet. Save one to see it here.'))
                    : ListView(children: [for (final e in entries) _row(e)]),
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      OutlinedButton.icon(
        key: const ValueKey('open-file'),
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Open a file…'),
        onPressed: () => Navigator.of(context).pop(const OpenFile()),
      ),
    ],
  );

  Widget _row(HostEntry e) => ListTile(
    key: ValueKey('account-model-${e.id}'),
    title: Text(e.title.isEmpty ? 'Untitled' : e.title),
    subtitle: Text(
      [e.subject, if (e.updatedAt != null) 'Saved ${_when(e.updatedAt!)}'].where((s) => s.isNotEmpty).join(' · '),
    ),
    onTap: () => Navigator.of(context).pop(OpenAccountModel(e.id)),
    trailing: IconButton(
      key: ValueKey('account-delete-${e.id}'),
      icon: const Icon(Icons.delete_outline),
      tooltip: 'Delete',
      onPressed: () => _remove(e),
    ),
  );

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// What to do when a save found the model changed elsewhere.
enum ConflictChoice { saveCopy, reload }

/// Asks whether to keep these edits as a copy or reload the saved model;
/// null when cancelled.
Future<ConflictChoice?> showConflictDialog(BuildContext context, String title) => showDialog<ConflictChoice>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('conflict-dialog'),
    title: const Text('Changed somewhere else'),
    content: Text(
      '"$title" was changed in another tab or on another device since you opened it. '
      'Save your version as a copy, or reload the saved version and drop your edits.',
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.of(context).pop(ConflictChoice.reload), child: const Text('Reload')),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(ConflictChoice.saveCopy),
        child: const Text('Save as a copy'),
      ),
    ],
  ),
);
