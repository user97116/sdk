// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

void main() {
  Object b = true;
  !b;
  // [error column 4, length 1]
  // [analyzer] COMPILE_TIME_ERROR.NON_BOOL_NEGATION_EXPRESSION
  // [cfe] A value of type 'Object' can't be assigned to a variable of type 'bool'.
}
