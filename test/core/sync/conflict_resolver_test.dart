import 'package:dreambook/core/sync/conflict_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

ResolverRow row({
  int version = 1,
  required DateTime updatedAt,
  String device = 'A',
  bool deleted = false,
}) =>
    ResolverRow(
      version: version,
      updatedAt: updatedAt,
      writtenByDevice: device,
      deleted: deleted,
    );

void main() {
  final t1 = DateTime.utc(2026, 5, 14, 10);
  final t2 = DateTime.utc(2026, 5, 14, 11);

  group('ConflictResolver.decide', () {
    test('higher version wins', () {
      final local = row(version: 3, updatedAt: t1);
      final remote = row(version: 4, updatedAt: t1);
      expect(ConflictResolver.decide(local, remote), ResolveOutcome.applyRemote);
    });

    test('lower version remote is ignored', () {
      final local = row(version: 5, updatedAt: t2);
      final remote = row(version: 3, updatedAt: t2);
      expect(ConflictResolver.decide(local, remote), ResolveOutcome.keepLocal);
    });

    test('same version → higher updated_at wins', () {
      final local = row(version: 3, updatedAt: t1, device: 'A');
      final remote = row(version: 3, updatedAt: t2, device: 'B');
      expect(ConflictResolver.decide(local, remote), ResolveOutcome.applyRemote);
    });

    test('same version + same updated_at → tie-break by lexically larger device', () {
      final local = row(version: 3, updatedAt: t1, device: 'A');
      final remote = row(version: 3, updatedAt: t1, device: 'B');
      expect(ConflictResolver.decide(local, remote), ResolveOutcome.applyRemote);
      final local2 = row(version: 3, updatedAt: t1, device: 'Z');
      final remote2 = row(version: 3, updatedAt: t1, device: 'B');
      expect(ConflictResolver.decide(local2, remote2), ResolveOutcome.keepLocal);
    });

    test('tombstone with higher version overrides live local', () {
      final local = row(version: 3, updatedAt: t1, deleted: false);
      final remote = row(version: 4, updatedAt: t2, deleted: true);
      expect(ConflictResolver.decide(local, remote), ResolveOutcome.applyRemote);
    });
  });
}
