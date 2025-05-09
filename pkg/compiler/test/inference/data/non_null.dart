// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*member: main:[null|powerset=1]*/
main() {
  nonNullStaticField();
  nonNullInstanceField1();
  nonNullInstanceField2();
  nonNullLocal();
}

/*member: staticField:[null|exact=JSUInt31|powerset=1]*/
var staticField;

/*member: nonNullStaticField:[exact=JSUInt31|powerset=0]*/
nonNullStaticField() => staticField ??= 42;

/*member: Class1.:[exact=Class1|powerset=0]*/
class Class1 {
  /*member: Class1.field:[null|exact=JSUInt31|powerset=1]*/
  var field;
}

/*member: nonNullInstanceField1:[exact=JSUInt31|powerset=0]*/
nonNullInstanceField1() {
  return Class1()
      . /*[exact=Class1|powerset=0]*/ /*update: [exact=Class1|powerset=0]*/ field ??= 42;
}

/*member: Class2.:[exact=Class2|powerset=0]*/
class Class2 {
  /*member: Class2.field:[null|exact=JSUInt31|powerset=1]*/
  var field;

  /*member: Class2.method:[exact=JSUInt31|powerset=0]*/
  method() {
    return /*[exact=Class2|powerset=0]*/ /*update: [exact=Class2|powerset=0]*/ field ??=
        42;
  }
}

/*member: nonNullInstanceField2:[exact=JSUInt31|powerset=0]*/
nonNullInstanceField2() {
  return Class2(). /*invoke: [exact=Class2|powerset=0]*/ method();
}

/*member: nonNullLocal:[exact=JSUInt31|powerset=0]*/
nonNullLocal() {
  var local = null;
  return local ??= 42;
}
