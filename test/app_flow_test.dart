import 'dart:ui';

import 'package:candy_shooter/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home, map, and level one gameplay are reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CandyShooterApp());
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('PLAY'), findsOneWidget);
    await tester.tap(find.text('PLAY'));
    await tester.pump();
    expect(find.text('CANDY LAND'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.text('LEVEL 1'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));

    if (find.text('GOT IT').evaluate().isNotEmpty) {
      await tester.tap(find.text('GOT IT'));
      await tester.pumpAndSettle();
    }

    await tester.dragFrom(const Offset(180, 650), const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('29'), findsOneWidget);
  });
}
