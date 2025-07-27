extension MapUtils on Map<String, dynamic> {
  Map<String, dynamic> deepCopy() {
    return map((key, value) {
      if (value is Map) {
        return MapEntry(key, value.cast<String, dynamic>().deepCopy());
      } else if (value is List) {
        return MapEntry(key, _deepCopyList(value));
      } else {
        return MapEntry(key, value); // primitives
      }
    });
  }
}

List _deepCopyList(List input) {
  return input.map((item) {
    if (item is Map) {
      return item.cast<String, dynamic>().deepCopy();
    } else if (item is List) {
      return _deepCopyList(item);
    } else {
      return item;
    }
  }).toList();
}
