// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:developer';
import 'package:vm_service/vm_service.dart';

import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart pkg/vm_service/test/evaluate_class_type_parameters_test.dart
//
const LINE_A = 23;
const LINE_B = 29;
// AUTOGENERATED END

class A<T> {
  void foo() {
    debugger(); // LINE_A
  }
}

class B<S> extends A<int> {
  void bar() {
    debugger(); // LINE_B
  }
}

void testFunction() {
  final v = B<String>();
  v.bar();
  v.foo();
}

final tests = <IsolateTest>[
  hasStoppedAtBreakpoint,
  stoppedAtLine(LINE_B),
  (VmService service, IsolateRef isolateRef) async {
    final isolateId = isolateRef.id!;
    await evaluateInFrameAndExpect(service, isolateId, '"\$S"', 'String');
  },
  resumeIsolate,
  hasStoppedAtBreakpoint,
  stoppedAtLine(LINE_A),
  (VmService service, IsolateRef isolateRef) async {
    final isolateId = isolateRef.id!;
    await evaluateInFrameAndExpect(service, isolateId, '"\$T"', 'int');
  },
  resumeIsolate,
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'evaluate_class_type_parameters_test.dart',
      testeeConcurrent: testFunction,
    );
