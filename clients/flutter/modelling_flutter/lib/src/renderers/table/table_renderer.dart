// table_renderer.dart: areas or relationships as rows (design §7.2) with
// the profile's properties as columns; sort by any column, filter rows,
// and edit inline (unless read-only) through undoable operations.

import 'package:flutter/material.dart';

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_types.dart';
import '../../inspector/inspector.dart';
import '../../shared/markers.dart';
import '../../shared/shown_elements.dart';
import '../../theme/model_theme.dart';
import '../model_renderer.dart';
import 'table_columns.dart';

/// The table renderer.
class TableRenderer extends ModelRenderer {
  const TableRenderer();

  @override
  String get id => 'table';

  @override
  String get label => 'Table';

  @override
  IconData get icon => Icons.table_rows_outlined;

  @override
  Widget build(BuildContext context, ModelController controller) => TableView(controller: controller);

  @override
  int shownAreas(ModelController controller, ModelTheme theme) => shownNodes(controller).where((n) => !n.ghost).length;
}

/// The table for [controller]: "Areas" or "Relationships", a row filter,
/// column headers that sort (ascending, descending, model order), and
/// inline editors for label, kind, tags and properties.
class TableView extends StatefulWidget {
  const TableView({super.key, required this.controller});

  final ModelController controller;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  final _filter = TextEditingController();
  final _horizontal = ScrollController();
  var _edges = false;
  String? _sort;
  var _ascending = true;

  ModelController get _c => widget.controller;

  @override
  void dispose() {
    _filter.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _sortBy(String column) => setState(() {
    if (_sort != column) {
      _sort = column;
      _ascending = true;
    } else if (_ascending) {
      _ascending = false;
    } else {
      _sort = null;
    }
  });

  List<ModelElementRef> _rows(List<TableColumn> columns) {
    final c = _c;
    final nodes = shownNodes(c);
    var rows = _edges
        ? [
            for (final id in shownEdges(c, {for (final n in nodes) n.id})) ModelElementRef.edge(id),
          ]
        : [for (final n in nodes) ModelElementRef.node(n.id)];
    final q = _filter.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = [
        for (final r in rows)
          if (columns.any((col) => cellText(c, r, col).toLowerCase().contains(q))) r,
      ];
    }
    final sort = _sort == null ? null : columns.where((col) => col.id == _sort).firstOrNull;
    if (sort != null) {
      final text = {for (final r in rows) r: cellText(c, r, sort)};
      final order = {for (var i = 0; i < rows.length; i++) rows[i]: i};
      rows.sort((a, b) {
        final k = compareCells(text[a]!, text[b]!);
        return k != 0 ? (_ascending ? k : -k) : order[a]!.compareTo(order[b]!);
      });
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _c, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = _c;
    final columns = tableColumns(c, edges: _edges);
    if (_sort != null && !columns.any((col) => col.id == _sort)) _sort = null;
    final rows = _rows(columns);
    const lead = 40.0;
    final width = lead + columns.fold(0.0, (w, col) => w + col.width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            chrome.filterChip(
              key: const ValueKey('table-areas'),
              label: 'Areas',
              selected: !_edges,
              onPressed: () => setState(() => _edges = false),
            ),
            SizedBox(width: t.spacing.xs),
            chrome.filterChip(
              key: const ValueKey('table-relationships'),
              label: 'Relationships',
              selected: _edges,
              onPressed: () => setState(() => _edges = true),
            ),
            SizedBox(width: t.spacing.sm),
            Expanded(
              child: chrome.searchField(
                key: const ValueKey('table-filter'),
                controller: _filter,
                hint: 'Filter rows',
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        SizedBox(height: t.spacing.xs),
        Expanded(
          child: Scrollbar(
            controller: _horizontal,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, columns, lead),
                    Expanded(
                      child: rows.isEmpty
                          ? Center(child: Text('No matching rows.', style: t.small))
                          : ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, i) => _row(context, rows[i], columns, lead),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, List<TableColumn> columns, double lead) {
    final t = ModelTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.border, width: t.borderWidth),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: lead),
          for (final col in columns)
            SizedBox(
              width: col.width,
              child: GestureDetector(
                key: ValueKey('table-sort-${col.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _sortBy(col.id),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.spacing.xs, vertical: t.spacing.xs),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(col.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.overline),
                      ),
                      if (_sort == col.id)
                        Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: t.muted),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ModelElementRef ref, List<TableColumn> columns, double lead) {
    final t = ModelTheme.of(context);
    final chrome = ModelChrome.of(context);
    final c = _c;
    final ghost = !(ref.isNode ? c.index.node(ref.id) != null : c.index.edge(ref.id) != null);
    final editable = !c.readOnly && !ghost;
    final selected = c.selection == ref;
    final label = cellText(c, ref, columns[1]);
    return Semantics(
      selected: selected,
      label: '${ref.isNode ? 'Area' : 'Relationship'} $label${ghost ? ', removed since the base' : ''}',
      child: GestureDetector(
        key: ValueKey('table-row-${ref.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          c.select(ref);
          if (ref.isNode) c.focus(ref.id);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          decoration: BoxDecoration(
            color: selected ? t.raised : null,
            border: Border(
              bottom: BorderSide(color: t.border.withValues(alpha: 0.3), width: t.borderWidth),
            ),
          ),
          child: Opacity(
            opacity: ghost ? 0.55 : 1,
            child: Row(
              children: [
                SizedBox(
                  width: lead,
                  child: chrome.iconButton(
                    icon: Icons.info_outline,
                    tooltip: 'Inspect $label',
                    onPressed: () => inspectElement(context, c, ref),
                  ),
                ),
                for (final col in columns)
                  SizedBox(
                    width: col.width,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: t.spacing.xxs, vertical: t.spacing.xxs),
                      child: _cell(context, ref, col, editable: editable, ghost: ghost),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    ModelElementRef ref,
    TableColumn col, {
    required bool editable,
    required bool ghost,
  }) {
    final t = ModelTheme.of(context);
    final c = _c;
    final editor = editable ? cellEditor(context, c, ref, col) : null;
    final content =
        editor ??
        Text(
          cellText(c, ref, col),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.standard.copyWith(decoration: ghost && col.id == 'label' ? TextDecoration.lineThrough : null),
        );
    if (col.id != 'label') return content;
    return Row(
      children: [
        Expanded(child: content),
        ...elementMarks(context, c, ref.id, edge: !ref.isNode),
      ],
    );
  }
}
