// gallery_page.dart: every renderer on each bundled sample (the templates,
// a diff of the payment app against its revision, and a findings overlay),
// read-only, side by side. The manual test bed and screenshot source.

import 'package:flutter/material.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'samples.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.bundled});

  final Bundled bundled;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final Map<String, ModelController> _samples = _build(widget.bundled);
  late String _shown = _samples.keys.first;

  static Map<String, ModelController> _build(Bundled b) {
    final app = b.templates['app']!;
    final profile = b.profileFor(app);
    return {
      'Payment app': ModelController(app, profile: profile, readOnly: true),
      'System context': ModelController(b.templates['system-context']!, readOnly: true),
      'Diff: base vs revised': ModelController(revisedApp(app), base: app, profile: profile, readOnly: true),
      'Overlay: open findings': ModelController(app, profile: profile, readOnly: true)
        ..overlays = const [findingsOverlay]
        ..activeOverlay = findingsOverlay.id,
    };
  }

  @override
  void dispose() {
    for (final c in _samples.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = _samples[_shown]!;
    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
            child: Wrap(
              spacing: t.spacing.xs,
              runSpacing: t.spacing.xs,
              children: [
                for (final name in _samples.keys)
                  chrome.filterChip(
                    key: ValueKey('sample-$name'),
                    label: name,
                    selected: name == _shown,
                    onPressed: () => setState(() => _shown = name),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(t.spacing.md),
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => WorkspaceStatus(controller: c, shown: c.visibility.included.length),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final wide = bounds.maxWidth >= 1100;
                final panels = [for (final r in modellerRenderers) _panel(context, r, c)];
                return GridView.count(
                  key: ValueKey('gallery-$_shown'),
                  padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
                  crossAxisCount: wide ? 2 : 1,
                  childAspectRatio: wide ? 1.3 : 1.5,
                  mainAxisSpacing: t.spacing.md,
                  crossAxisSpacing: t.spacing.md,
                  children: panels,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, ModelRenderer r, ModelController c) {
    final t = ModelTheme.of(context);
    return Container(
      key: ValueKey('gallery-panel-${r.id}'),
      padding: EdgeInsets.all(t.spacing.sm),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border, width: t.borderWidth),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(r.icon, size: t.iconSize, color: t.muted),
              SizedBox(width: t.spacing.xs),
              Text(r.label, style: t.heading),
            ],
          ),
          SizedBox(height: t.spacing.xs),
          Expanded(child: r.build(context, c)),
        ],
      ),
    );
  }
}
