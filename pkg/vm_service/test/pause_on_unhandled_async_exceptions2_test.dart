// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// VMOptions=
// VMOptions=--optimization-counter-threshold=90

import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart pkg/vm_service/test/pause_on_unhandled_async_exceptions2_test.dart
//
const LINE_A = 43;
// AUTOGENERATED END

class Foo {}

Never doThrow() {
  throw 'TheException';
}

Future<Never> asyncThrower() async {
  // ignore: await_only_futures
  await 0; // force async gap
  doThrow();
}

Future<void> testeeMain() async {
  // Trigger optimization via OSR.
  int s = 0;
  for (int i = 0; i < 100; i++) {
    s += i;
  }
  print(s);
  // No try ... catch.
  await asyncThrower(); // LINE_A
}

final tests = <IsolateTest>[
  hasStoppedWithUnhandledException,
  (VmService service, IsolateRef isolateRef) async {
    final isolateId = isolateRef.id!;
    final stack = await service.getStack(isolateId);
    expect(stack.asyncCausalFrames, isNotNull);
    final asyncStack = stack.asyncCausalFrames!;
    expect(asyncStack.length, greaterThanOrEqualTo(4));
    expect(asyncStack[0].function!.name, 'doThrow');
    expect(asyncStack[1].function!.name, 'asyncThrower');
    expect(asyncStack[2].kind, FrameKind.kAsyncSuspensionMarker);
    expect(asyncStack[3].kind, FrameKind.kAsyncCausal);
    expect(asyncStack[3].function!.name, 'testeeMain');
    expect(asyncStack[3].location!.line, LINE_A);
  }
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'pause_on_unhandled_async_exceptions2_test.dart',
      pauseOnUnhandledExceptions: true,
      testeeConcurrent: testeeMain,
      extraArgs: extraDebuggingArgs,
    );
