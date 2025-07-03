import 'package:flutter/material.dart';

extension NavigationUtilsExt on BuildContext {
  Future<T?> navigateTo<T>(Widget page) => Navigator.of(this).push(MaterialPageRoute(builder: (_) => page));

  void navBack<T>(T? result) => Navigator.of(this).pop(result);
}
