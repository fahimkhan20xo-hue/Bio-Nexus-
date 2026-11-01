import 'package:flutter_test/flutter_test.dart';
import 'package:bionexus/main.dart';

void main() {
  testWidgets('BioNexus home screen renders', (tester) async {
    await tester.pumpWidget(const BioNexusApp());
    expect(find.text('BioNexus'), findsOneWidget);
  });
}
