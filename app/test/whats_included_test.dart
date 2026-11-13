import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owen_tours/features/trips/models.dart';
import 'package:owen_tours/features/trips/widgets.dart';

WhatsIncluded included({bool transport = true, bool breakfast = false, bool accommodation = false}) => WhatsIncluded.fromJson({
      'transportIncluded': transport,
      'transportType': transport ? 'coach' : null,
      'breakfast': breakfast,
      'lunch': false,
      'dinner': false,
      'snacks': false,
      'mealsSummary': breakfast ? 'Breakfast' : 'No meals included',
      'accommodationIncluded': accommodation,
      'accommodationType': accommodation ? 'lodge' : null,
      'otherIncludes': ['Entrance fee to Afriski'],
      'excludes': ['Spending money'],
    });

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('shows what is and is not included', (tester) async {
    await tester.pumpWidget(wrap(WhatsIncludedSection(included: included(breakfast: true, accommodation: true))));
    expect(find.text('Transport included – Coach'), findsOneWidget);
    expect(find.text('Meals: Breakfast'), findsOneWidget);
    expect(find.text('Accommodation – Lodge'), findsOneWidget);
    expect(find.text('Entrance fee to Afriski'), findsOneWidget);
    expect(find.text('Not included'), findsOneWidget);
    expect(find.text('Spending money'), findsOneWidget);
  });

  testWidgets('clearly says when transport and meals are not included', (tester) async {
    await tester.pumpWidget(wrap(WhatsIncludedSection(included: included(transport: false))));
    expect(find.text('Transport not included'), findsOneWidget);
    expect(find.text('Meals: No meals included'), findsOneWidget);
    expect(find.text('Accommodation not included'), findsOneWidget);
  });
}
