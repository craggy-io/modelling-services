// table_columns.dart: the table renderer's columns: what each shows for an
// area or relationship (also what it sorts and filters by), and the inline
// editor each offers, editing through ModelEditing so every edit is one
// undoable step.

import 'package:flutter/material.dart';
import 'package:modelling/modelling.dart' hide View;

import '../../chrome/model_chrome.dart';
import '../../controller/model_controller.dart';
import '../../controller/model_editing.dart';
import '../../controller/model_types.dart';
import '../../inspector/field_editors.dart';

/// One table column. [property] is set for property columns.
class TableColumn {
  const TableColumn(this.id, this.title, this.width, {this.property});

  final String id;
  final String title;
  final double width;
  final String? property;
}

/// The columns for areas ([edges] false) or relationships: the fixed ones,
/// then the profile's declared properties and any others in use.
List<TableColumn> tableColumns(ModelController c, {required bool edges}) {
  final p = c.profile;
  final Iterable<Map<String, PropertySpec>> specs = p == null
      ? const []
      : edges
      ? p.edgeKinds.values.map((k) => k.properties)
      : p.nodeKinds.values.map((k) => k.properties);
  final declared = <String>{for (final s in specs) ...s.keys};
  final Iterable<Properties> all = edges
      ? c.model.edges.map((e) => e.properties)
      : c.model.nodes.map((n) => n.properties);
  final used = <String>{for (final props in all) ...props.keys};
  final props = [...declared.toList()..sort(), ...(used.difference(declared).toList()..sort())];
  return [
    const TableColumn('id', 'Id', 120),
    const TableColumn('label', 'Label', 220),
    const TableColumn('kind', 'Kind', 150),
    if (edges) ...const [TableColumn('from', 'From', 160), TableColumn('to', 'To', 160)],
    if (!edges) const TableColumn('parent', 'Parent', 160),
    const TableColumn('tags', 'Tags', 170),
    for (final k in props) TableColumn('prop:$k', k, 150, property: k),
  ];
}

/// The element a row shows (current or removed).
({String id, String label, String kind, List<String> tags, Properties properties})? tableElement(
  ModelController c,
  ModelElementRef ref,
) {
  if (ref.isNode) {
    final n = c.nodeOrGhost(ref.id);
    return n == null ? null : (id: n.id, label: n.label, kind: n.kind, tags: n.tags, properties: n.properties);
  }
  final e = c.edgeOrGhost(ref.id);
  return e == null ? null : (id: e.id, label: e.label, kind: e.kind, tags: e.tags, properties: e.properties);
}

/// What [col] shows for [ref] as text.
String cellText(ModelController c, ModelElementRef ref, TableColumn col) {
  final x = tableElement(c, ref);
  if (x == null) return '';
  final p = c.profile;
  return switch (col.id) {
    'id' => x.id,
    'label' => x.label,
    'kind' =>
      x.kind.isEmpty ? '' : ((ref.isNode ? p?.nodeKinds[x.kind]?.label : p?.edgeKinds[x.kind]?.label) ?? x.kind),
    'parent' => c.parentOf(ref.id) == '' ? '' : c.labelOf(c.parentOf(ref.id)),
    'from' => c.labelOf(c.edgeOrGhost(ref.id)!.from),
    'to' => c.labelOf(c.edgeOrGhost(ref.id)!.to),
    'tags' => x.tags.join(', '),
    _ => propertyText(x.properties[col.property]),
  };
}

/// Orders two cell texts: numerically when both are numbers, else
/// alphabetically ignoring case.
int compareCells(String a, String b) {
  final x = num.tryParse(a), y = num.tryParse(b);
  if (x != null && y != null) return x.compareTo(y);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// The inline editor for [col] on a current element, or null when the
/// column is not editable (id, parent, ends).
Widget? cellEditor(BuildContext context, ModelController c, ModelElementRef ref, TableColumn col) {
  final x = tableElement(c, ref)!;
  final chrome = ModelChrome.of(context);
  final key = ValueKey('table-edit-${ref.id}-${col.id}');
  String? done(bool ok) => ok ? null : c.notice.value;
  switch (col.id) {
    case 'label':
      return CommitField(key: key, value: x.label, onCommit: (v) => done(c.rename(ref, v)));
    case 'kind':
      final p = c.profile;
      final kinds = p == null
          ? const <String, String>{}
          : ref.isNode
          ? {for (final e in p.nodeKinds.entries) e.key: e.value.label}
          : {for (final e in p.edgeKinds.entries) e.key: e.value.label};
      if (kinds.isEmpty) {
        return CommitField(key: key, value: x.kind, onCommit: (v) => done(c.setFields(ref, {'kind': v.trim()})));
      }
      return chrome.select<String>(
        key: key,
        value: x.kind,
        options: [
          const ModelOption('', '(none)'),
          for (final e in kinds.entries) ModelOption(e.key, e.value),
          if (x.kind.isNotEmpty && !kinds.containsKey(x.kind)) ModelOption(x.kind, x.kind),
        ],
        onChanged: (v) => c.setFields(ref, {'kind': v}),
      );
    case 'tags':
      return CommitField(
        key: key,
        value: x.tags.join(', '),
        onCommit: (v) => done(c.setFields(ref, {'tags': parseTags(v)})),
      );
    case _ when col.property != null:
      final spec = propertySpecs(c, ref, x.kind)[col.property!];
      return KeyedSubtree(
        key: key,
        child: propertyEditor(chrome, c, ref, col.property!, spec, x.properties[col.property]),
      );
  }
  return null;
}
