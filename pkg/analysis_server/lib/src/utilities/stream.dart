// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

class MoreTypedStreamController<T, ListenData, PauseData> {
  final StreamController<T> controller;

  /// A wrapper around [StreamController] that statically guarantees its
  /// clients that [onPause] and [onCancel] can only be invoked after
  /// [onListen], and [onResume] can only be invoked after [onPause].
  ///
  /// There is no static guarantee that [onPause] will not be invoked twice.
  ///
  /// Internally the wrapper is not safe, and uses explicit null checks.
  factory MoreTypedStreamController({
    required ListenData Function(StreamController<T>) onListen,
    PauseData Function(ListenData)? onPause,
    void Function(ListenData, PauseData)? onResume,
    FutureOr<void> Function(ListenData)? onCancel,
    bool sync = false,
  }) {
    ListenData? listenData;
    PauseData? pauseData;
    var controller = StreamController<T>(
      onPause: () {
        if (pauseData != null) {
          throw StateError('Already paused');
        }
        if (onPause != null) {
          pauseData = onPause(listenData as ListenData);
        }
      },
      onResume: () {
        if (onResume != null) {
          var currentPauseData = pauseData as PauseData;
          pauseData = null;
          onResume(listenData as ListenData, currentPauseData);
        }
      },
      onCancel: () {
        if (onCancel != null) {
          var currentListenData = listenData as ListenData;
          listenData = null;
          onCancel(currentListenData);
        }
      },
      sync: sync,
    );
    controller.onListen = () {
      listenData = onListen(controller);
    };
    return MoreTypedStreamController._(controller);
  }

  MoreTypedStreamController._(this.controller);
}
