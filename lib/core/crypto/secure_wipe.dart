import 'dart:typed_data';

/// Overwrites every byte of [buffer] with zero.
///
/// IMPORTANT — defense in depth only. The Dart VM may have copied this
/// buffer during GC compaction; those copies cannot be reached from here.
/// Treat this as a best-effort hygiene helper, not a guarantee. Per spec
/// §6.2 ("Uint8List zero-fill as a guarantee — SKIP / theater").
void secureWipe(Uint8List buffer) {
  for (var i = 0; i < buffer.length; i++) {
    buffer[i] = 0;
  }
}
