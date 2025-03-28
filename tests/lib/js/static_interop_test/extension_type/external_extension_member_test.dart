// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:js_interop';
import 'package:expect/expect.dart';

@JS()
external void eval(String code);

extension type ExtensionType._(JSObject _) {
  external ExtensionType();
}

extension E on ExtensionType {
  external String field;
  @JS('field')
  external String renamedField;
  external final String finalField;

  external String get getSet;
  external set getSet(String val);
  @JS('getSet')
  external String get renamedGetSet;
  @JS('getSet')
  external set renamedGetSet(String val);

  external String method();
  external String differentArgsMethod(String a, [String b = '']);
  @JS('method')
  external String renamedMethod();
}

void main() {
  eval('''
    globalThis.ExtensionType = function ExtensionType() {
      this.field = 'field';
      this.finalField = 'finalField';
      this.getSet = 'getSet';
      this.method = function() {
        return 'method';
      }
      this.differentArgsMethod = function(a, b) {
        return a + b;
      }
    }
  ''');
  var extension = ExtensionType();

  // Fields.
  Expect.equals('field', extension.field);
  extension.field = 'modified';
  Expect.equals('modified', extension.field);
  Expect.equals('modified', extension.renamedField);
  extension.renamedField = 'renamedField';
  Expect.equals('renamedField', extension.renamedField);
  Expect.equals('finalField', extension.finalField);

  // Getters and setters.
  Expect.equals('getSet', extension.getSet);
  extension.getSet = 'modified';
  Expect.equals('modified', extension.getSet);
  Expect.equals('modified', extension.renamedGetSet);
  extension.renamedGetSet = 'renamedGetSet';
  Expect.equals('renamedGetSet', extension.renamedGetSet);

  // Methods.
  Expect.equals('method', extension.method());
  Expect.equals('methodundefined', extension.differentArgsMethod('method'));
  Expect.equals('method', extension.renamedMethod());
}
