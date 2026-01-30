import 'package:flutter_test/flutter_test.dart';

import 'package:idex/main.dart';

void main() {
  testWidgets('Ideas app shows home screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IdeasApp());

    // Verify that the home screen is displayed.
    expect(find.text('My Ideas'), findsOneWidget);

    // Verify the FAB is present
    expect(find.text('New Idea'), findsOneWidget);
  });
}
