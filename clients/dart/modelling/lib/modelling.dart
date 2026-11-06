/// Block models: labelled nodes nested by containment, labelled edges,
/// typed properties, evidence references and saved views, as one versioned
/// JSON document (design §4, §6).
///
/// The pure-Dart twin of modelling-services' Go packages (model, diff, edit,
/// query and the Mermaid and outline parts of export). The shared vectors in
/// `conformance/` are the contract: both implementations must pass them.
library;

export 'src/apply.dart' show apply;
export 'src/canonical.dart' show canonicalJson, jsonEquals;
export 'src/diff.dart' show ChangeKind, FieldChange, Change, ChangeSet, compare;
export 'src/history.dart' show EditHistory, EditStep;
export 'src/index.dart' show ModelIndex;
export 'src/json_read.dart' show ModelFormatException, JsonValue;
export 'src/lint.dart' show Severity, Finding, lint;
export 'src/mermaid.dart' show toMermaid, parseMermaid;
export 'src/model.dart'
    show
        modelFormat,
        modelVersion,
        Properties,
        Position,
        Model,
        Node,
        Edge,
        Evidence,
        Ref,
        Link,
        View,
        NodeSize,
        Filter,
        isScalarValue,
        fillEvidenceIds;
export 'src/op.dart' show Ops, Op, EditException;
export 'src/outline.dart' show toOutline, parseOutline;
export 'src/profile.dart' show Profile, NodeKind, EdgeKind, PropertySpec;
export 'src/query.dart' show Direction, search, haystack, neighbours, paths, impact;
export 'src/export_ids.dart' show slug;
export 'src/validate.dart' show Limits, Issue, ModelValidationException, validId;
