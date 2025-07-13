import 'package:flutter/material.dart';

extension NavigationUtilsExt on BuildContext {
  /// Navigate to given [page]
  ///
  /// If [replaceCurrent] is true replace current page page [page] instead of pushing it on top of it.
  /// Uses NavigatorState.pushReplacement
  Future<T?> navigateTo<T>(Widget page, {bool replaceCurrent = false}) {
    return replaceCurrent
        ? Navigator.of(this).pushReplacement(MaterialPageRoute(builder: (_) => page))
        : Navigator.of(this).push(MaterialPageRoute(builder: (_) => page));
  }

  void navBack<T>([T? result]) => Navigator.of(this).pop(result);
}
