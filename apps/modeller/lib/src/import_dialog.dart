// import_dialog.dart: paste Mermaid or outline text and read it as a model.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

enum _Format { mermaid, outline }

/// Asks for Mermaid or outline text; returns the model it reads as, or
/// null when cancelled.
Future<Model?> showImportDialog(BuildContext context) =>
    showDialog<Model>(context: context, builder: (_) => const _ImportDialog());

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _text = TextEditingController();
  var _format = _Format.mermaid;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _import() {
    try {
      final m = _format == _Format.mermaid ? parseMermaid(_text.text) : parseOutline(_text.text);
      Navigator.of(context).pop(m);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import text'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_Format>(
            segments: const [
              ButtonSegment(value: _Format.mermaid, label: Text('Mermaid')),
              ButtonSegment(value: _Format.outline, label: Text('Outline')),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('import-text'),
            controller: _text,
            autofocus: true,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'Consolas'),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: _format == _Format.mermaid
                  ? 'flowchart TD\n  app[Application] --> api[API]'
                  : '# Title\n\n- Application\n  - API',
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: _import, child: const Text('Import')),
    ],
  );
}
