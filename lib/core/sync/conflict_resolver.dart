/// Minimal projection of a syncable row that the resolver needs.
class ResolverRow {
  const ResolverRow({
    required this.version,
    required this.updatedAt,
    required this.writtenByDevice,
    required this.deleted,
  });

  final int version;
  final DateTime updatedAt;
  final String writtenByDevice;
  final bool deleted;
}

enum ResolveOutcome { keepLocal, applyRemote }

/// Pure LWW conflict resolution per spec §5.1.
///
/// Rules:
/// 1. Higher `version` wins.
/// 2. Same version → higher `updatedAt` wins.
/// 3. Same version + same updatedAt → lexically larger `writtenByDevice` wins
///    (deterministic across all replicas).
class ConflictResolver {
  ConflictResolver._();

  static ResolveOutcome decide(ResolverRow local, ResolverRow remote) {
    if (remote.version > local.version) return ResolveOutcome.applyRemote;
    if (remote.version < local.version) return ResolveOutcome.keepLocal;
    if (remote.updatedAt.isAfter(local.updatedAt)) return ResolveOutcome.applyRemote;
    if (remote.updatedAt.isBefore(local.updatedAt)) return ResolveOutcome.keepLocal;
    return remote.writtenByDevice.compareTo(local.writtenByDevice) > 0
        ? ResolveOutcome.applyRemote
        : ResolveOutcome.keepLocal;
  }
}
