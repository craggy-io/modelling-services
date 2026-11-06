import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modelling_flutter_example/main.dart';

void main() {
  testWidgets('boots in diff mode and switches between every renderer', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Changed only'), findsOneWidget);
    for (final id in ['outline', 'graph', 'matrix', 'table', 'blocks']) {
      await tester.tap(find.byKey(ValueKey('renderer-$id')).first);
      await tester.pumpAndSettle();
      // The chip and the shown renderer.
      expect(find.byKey(ValueKey('renderer-$id')), findsNWidgets(2));
    }
    expect(find.byKey(const ValueKey('graph-node-net')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('renderer-graph')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-node-net')), findsOneWidget);
  });
}
