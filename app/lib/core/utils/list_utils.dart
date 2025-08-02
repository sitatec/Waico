import 'dart:typed_data';

Float32List mergeFloat32Lists(Iterable<Float32List> lists) {
  // Compute total length
  final totalLength = lists.fold(0, (sum, currentList) => sum + currentList.length);

  // Allocate one big buffer
  final merged = Float32List(totalLength);

  // Copy each list into the merged buffer
  int offset = 0;
  for (final list in lists) {
    merged.setRange(offset, offset + list.length, list);
    offset += list.length;
  }

  return merged;
}
