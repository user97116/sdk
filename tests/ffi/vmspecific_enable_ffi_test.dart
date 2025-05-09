// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// Dart test program for testing the --enable-ffi=false flag.
//
// VMOptions=--enable-ffi=false

// Formatting can break multitests, so don't format them.
// dart format off

import 'dart:ffi'; //# 01: compile-time error

import 'package:ffi/ffi.dart'; //# 01: compile-time error

void main() {
  Pointer<Int8> p = //# 01: compile-time error
      calloc(); //# 01: compile-time error
  print(p.address); //# 01: compile-time error
  calloc.free(p); //# 01: compile-time error
}
