import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:important_memories_host/core/widgets/coach_tour.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('экскурсия проходит все шаги и закрывается', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('google_fonts')) errors.add(d);
    };
    addTearDown(() => FlutterError.onError = oldHandler);

    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const SizedBox(height: 60),
            Container(key: TourKeys.header, height: 48, color: Colors.amber),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Container(key: TourKeys.framesTab, width: 60, height: 40, color: Colors.blue),
              Container(key: TourKeys.profileTab, width: 60, height: 40, color: Colors.green),
            ]),
            ElevatedButton(
              onPressed: () async {
                result = await showCoachTour(context, [
                  const CoachStep(kind: CoachKind.welcome, title: 'Привет', text: 'Текст'),
                  CoachStep(target: TourKeys.header, title: 'Шапка', text: 'Описание'),
                  CoachStep(target: TourKeys.framesTab, title: 'Кадры', text: 'Описание'),
                  CoachStep(target: TourKeys.eventQr, title: 'Нет такого элемента', text: 'Пропускается'),
                  CoachStep(target: TourKeys.profileTab, title: 'Профиль', text: 'Описание'),
                  const CoachStep(kind: CoachKind.finish, title: 'Готово', points: ['Раз', 'Два'], ctaLabel: 'Поехали'),
                ]);
              },
              child: const Text('go'),
            ),
          ]),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Привет'), findsOneWidget);

    await tester.tap(find.text('Показать'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Шапка'), findsOneWidget);
    expect(find.textContaining('ШАГ 2 ИЗ 5'), findsOneWidget);

    await tester.tap(find.text('Далее'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Кадры'), findsOneWidget);

    await tester.tap(find.text('Далее'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Профиль'), findsOneWidget);

    await tester.tap(find.text('Далее'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Готово'), findsOneWidget);

    await tester.tap(find.text('Поехали'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Готово'), findsNothing);
    expect(result, true);
    expect(errors, isEmpty);
  });

  testWidgets('кнопка «Пропустить» закрывает экскурсию', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCoachTour(context, [
                  const CoachStep(kind: CoachKind.welcome, title: 'Привет', text: 'Текст'),
                  const CoachStep(kind: CoachKind.finish, title: 'Конец'),
                ]);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.text('Пропустить'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(result, false);
  });
}
