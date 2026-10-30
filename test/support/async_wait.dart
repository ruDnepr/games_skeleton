import 'dart:async';

import 'package:flutter/foundation.dart';

/// Waits until [condition] becomes true, driven by notifications of [listenable].
///
/// Used by the plain (non-widget) tests that wait for a message from the other
/// side of a network game.
Future<void> waitUntil(
  Listenable listenable,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (condition()) return;
  final completer = Completer<void>();
  void listener() {
    if (condition() && !completer.isCompleted) completer.complete();
  }

  listenable.addListener(listener);
  try {
    await completer.future.timeout(timeout);
  } finally {
    listenable.removeListener(listener);
  }
}
