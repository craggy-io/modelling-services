// agent_dialog.dart: how to connect an AI agent to the modelling MCP
// server, each setup line with a copy button.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The hosted MCP server's address.
const mcpUrl = 'https://models.craggy.io/mcp';

/// The agent guide served beside the app.
const agentGuideUrl = 'https://models.craggy.io/llms.txt';

/// The ways to connect, in the order shown: a title and the text to copy.
const agentSetups = [
  ('MCP server URL', mcpUrl),
  ('Claude Code', 'claude mcp add --transport http craggy-models $mcpUrl'),
  ('Any MCP client (JSON config)', '{"mcpServers": {"craggy-models": {"type": "http", "url": "$mcpUrl"}}}'),
  ('Run it locally (stdio)', 'go install github.com/craggy-io/modelling-services/cmd/modelling-mcp@latest'),
  ('Guide for agents', agentGuideUrl),
];

Future<void> showAgentDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const AgentDialog());

class AgentDialog extends StatelessWidget {
  const AgentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('agent-dialog'),
      icon: const Icon(Icons.smart_toy_outlined),
      title: const Text('Connect an AI agent'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Point your agent at the Craggy Models MCP server. It can sketch, edit, check and export '
                'models, then give you a link that opens the result here. Nothing is stored and there '
                'are no accounts.',
                style: theme.textTheme.bodyMedium,
              ),
              for (final (title, text) in agentSetups) _CopyLine(title: title, text: text),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

/// One setup line: its title, the text in a monospace box, and a copy button.
class _CopyLine extends StatelessWidget {
  const _CopyLine({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(text, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Copied $title')));
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
