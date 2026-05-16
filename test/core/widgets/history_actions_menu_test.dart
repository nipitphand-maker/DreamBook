import 'package:dreambook/core/models/caregiver.dart';
import 'package:dreambook/core/widgets/history_actions_menu.dart';
import 'package:dreambook/features/caregivers/data/current_caregiver_provider.dart';
import 'package:dreambook/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test caregiver fixture — pinned to a known id so test rows can author
/// against it (the editor "own-row" case) or against a different id (the
/// editor "other-author" case).
Caregiver _fakeSelf({
  required CaregiverRole role,
  String id = 'self-caregiver-id',
}) {
  final now = DateTime.utc(2026, 5, 16);
  return Caregiver(
    id: id,
    displayName: 'Me',
    deviceId: 'test-device-fp',
    role: role,
    joinedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

/// Wraps the actions menu inside a MaterialApp + ProviderScope with the
/// `currentCaregiverProvider` overridden to a synchronous value — the
/// underlying FutureProvider is honoured by Riverpod 3 via `.value` once a
/// `Future.value(...)` resolves on the first pump.
Widget _wrap({
  required Caregiver? caregiver,
  required String? rowLoggedBy,
}) {
  return ProviderScope(
    overrides: [
      currentCaregiverProvider.overrideWith((_) async => caregiver),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: HistoryActionsMenu(
            rowLoggedBy: rowLoggedBy,
            onEdit: () {},
            onDelete: () async {},
            confirmTitle: 'Confirm?',
            confirmBody: 'Are you sure?',
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('HistoryActionsMenu role gating', () {
    testWidgets('admin sees the actions trigger on EVERY row (own + other)',
        (tester) async {
      // Own row.
      await tester.pumpWidget(_wrap(
        caregiver: _fakeSelf(role: CaregiverRole.admin),
        rowLoggedBy: 'self-caregiver-id',
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_menu')), findsOneWidget);

      // Other-author row.
      await tester.pumpWidget(_wrap(
        caregiver: _fakeSelf(role: CaregiverRole.admin),
        rowLoggedBy: 'someone-else',
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_menu')), findsOneWidget);
    });

    testWidgets('editor sees the actions trigger ONLY on rows they authored',
        (tester) async {
      // Own row → menu shows.
      await tester.pumpWidget(_wrap(
        caregiver: _fakeSelf(role: CaregiverRole.editor),
        rowLoggedBy: 'self-caregiver-id',
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_menu')), findsOneWidget);

      // Other-author row → menu hidden.
      await tester.pumpWidget(_wrap(
        caregiver: _fakeSelf(role: CaregiverRole.editor),
        rowLoggedBy: 'someone-else',
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_menu')), findsNothing);
    });

    testWidgets(
        'editor sees actions on legacy rows with null logged_by '
        '(pre-attribution data is not permanently locked)', (tester) async {
      await tester.pumpWidget(_wrap(
        caregiver: _fakeSelf(role: CaregiverRole.editor),
        rowLoggedBy: null,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_menu')), findsOneWidget);
    });

    testWidgets('read-only user never sees the actions trigger',
        (tester) async {
      // Own row → still hidden.
      await tester.pumpWidget(_wrap(
        caregiver: _fakeSelf(role: CaregiverRole.readOnly),
        rowLoggedBy: 'self-caregiver-id',
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_menu')), findsNothing);

      // Other-author row → also hidden.
      await tester.pumpWidget(_wrap(
        caregiver: _fakeSelf(role: CaregiverRole.readOnly),
        rowLoggedBy: 'someone-else',
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_menu')), findsNothing);
    });

    testWidgets(
        'menu surfaces Edit + Delete items, and tapping Delete pops a '
        'localized confirmation dialog', (tester) async {
      var deleteCalled = false;
      var editCalled = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentCaregiverProvider
              .overrideWith((_) async => _fakeSelf(role: CaregiverRole.admin)),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: HistoryActionsMenu(
                rowLoggedBy: 'self-caregiver-id',
                onEdit: () => editCalled = true,
                onDelete: () async => deleteCalled = true,
                confirmTitle: 'Delete this feed?',
                confirmBody: 'This feed entry will be removed.',
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open the popup menu.
      await tester.tap(find.byKey(const Key('history_actions_menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_actions_edit')), findsOneWidget);
      expect(find.byKey(const Key('history_actions_delete')), findsOneWidget);

      // Pick Edit.
      await tester.tap(find.byKey(const Key('history_actions_edit')));
      await tester.pumpAndSettle();
      expect(editCalled, isTrue);

      // Reopen and pick Delete → confirm dialog appears.
      await tester.tap(find.byKey(const Key('history_actions_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history_actions_delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this feed?'), findsOneWidget);

      // Cancel does not invoke onDelete.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleteCalled, isFalse);

      // Reopen & confirm Delete → onDelete fires.
      await tester.tap(find.byKey(const Key('history_actions_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history_actions_delete')));
      await tester.pumpAndSettle();
      // Two "Delete" labels now: the popup item (gone with the popup) and the
      // confirm dialog's destructive button. Tap the dialog one via its
      // FilledButton type to disambiguate.
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleteCalled, isTrue);
    });
  });

  group('canEditRow rules', () {
    test('admin can edit anything', () {
      expect(
        canEditRow(
          role: CaregiverRole.admin,
          rowLoggedBy: 'anyone',
          selfCaregiverId: 'self',
        ),
        isTrue,
      );
      expect(
        canEditRow(
          role: CaregiverRole.admin,
          rowLoggedBy: null,
          selfCaregiverId: null,
        ),
        isTrue,
      );
    });

    test('editor can only edit own rows + legacy null rows', () {
      expect(
        canEditRow(
          role: CaregiverRole.editor,
          rowLoggedBy: 'self',
          selfCaregiverId: 'self',
        ),
        isTrue,
      );
      expect(
        canEditRow(
          role: CaregiverRole.editor,
          rowLoggedBy: null,
          selfCaregiverId: 'self',
        ),
        isTrue,
      );
      expect(
        canEditRow(
          role: CaregiverRole.editor,
          rowLoggedBy: 'someone-else',
          selfCaregiverId: 'self',
        ),
        isFalse,
      );
    });

    test('read-only can never edit', () {
      expect(
        canEditRow(
          role: CaregiverRole.readOnly,
          rowLoggedBy: 'self',
          selfCaregiverId: 'self',
        ),
        isFalse,
      );
    });
  });
}
