// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_js_interop_checks/src/transformations/js_util_optimizer.dart'
    show ExtensionIndex;
import 'package:kernel/ast.dart';
import 'package:kernel/core_types.dart';

enum AnnotationType { import, export, weakExport }

/// A utility wrapper for [CoreTypes].
class CoreTypesUtil {
  final ExtensionIndex _extensionIndex;
  final CoreTypes coreTypes;
  final Procedure allowInteropTarget;
  final Procedure dartifyRawTarget;
  final Procedure functionToJSTarget;
  final Procedure functionToJSCaptureThisTarget;
  final Procedure greaterThanOrEqualToTarget;
  final Procedure inlineJSTarget;
  final Procedure isDartFunctionWrappedTarget;
  final Procedure jsifyRawTarget;
  final Procedure jsObjectFromDartObjectTarget;
  final Class jsValueClass;
  final Procedure jsValueBoxTarget;
  final Procedure jsValueUnboxTarget;
  final Procedure numToIntTarget;
  final Class wasmExternRefClass;
  final Class wasmArrayClass;
  final Class wasmArrayRefClass;
  final Procedure wrapDartFunctionTarget;
  final Procedure exportWasmFunctionTarget;

  CoreTypesUtil(this.coreTypes, this._extensionIndex)
      : allowInteropTarget = coreTypes.index
            .getTopLevelProcedure('dart:js_util', 'allowInterop'),
        dartifyRawTarget = coreTypes.index
            .getTopLevelProcedure('dart:_js_helper', 'dartifyRaw'),
        functionToJSTarget = coreTypes.index.getTopLevelProcedure(
            'dart:js_interop', 'FunctionToJSExportedDartFunction|get#toJS'),
        functionToJSCaptureThisTarget = coreTypes.index.getTopLevelProcedure(
            'dart:js_interop',
            'FunctionToJSExportedDartFunction|get#toJSCaptureThis'),
        greaterThanOrEqualToTarget =
            coreTypes.index.getProcedure('dart:core', 'num', '>='),
        inlineJSTarget =
            coreTypes.index.getTopLevelProcedure('dart:_js_helper', 'JS'),
        isDartFunctionWrappedTarget = coreTypes.index
            .getTopLevelProcedure('dart:_js_helper', '_isDartFunctionWrapped'),
        numToIntTarget =
            coreTypes.index.getProcedure('dart:core', 'num', 'toInt'),
        jsifyRawTarget =
            coreTypes.index.getTopLevelProcedure('dart:_js_helper', 'jsifyRaw'),
        jsObjectFromDartObjectTarget = coreTypes.index
            .getTopLevelProcedure('dart:_js_helper', 'jsObjectFromDartObject'),
        jsValueBoxTarget =
            coreTypes.index.getProcedure('dart:_js_helper', 'JSValue', 'box'),
        jsValueClass = coreTypes.index.getClass('dart:_js_helper', 'JSValue'),
        jsValueUnboxTarget =
            coreTypes.index.getProcedure('dart:_js_helper', 'JSValue', 'unbox'),
        wasmExternRefClass =
            coreTypes.index.getClass('dart:_wasm', 'WasmExternRef'),
        wasmArrayClass = coreTypes.index.getClass('dart:_wasm', 'WasmArray'),
        wasmArrayRefClass =
            coreTypes.index.getClass('dart:_wasm', 'WasmArrayRef'),
        wrapDartFunctionTarget = coreTypes.index
            .getTopLevelProcedure('dart:_js_helper', '_wrapDartFunction'),
        exportWasmFunctionTarget = coreTypes.index
            .getTopLevelProcedure('dart:_internal', 'exportWasmFunction');

  DartType get nonNullableObjectType =>
      coreTypes.objectRawType(Nullability.nonNullable);

  DartType get nonNullableWasmExternRefType =>
      wasmExternRefClass.getThisType(coreTypes, Nullability.nonNullable);

  DartType get nullableJSValueType =>
      InterfaceType(jsValueClass, Nullability.nullable);

  DartType get nullableWasmExternRefType =>
      wasmExternRefClass.getThisType(coreTypes, Nullability.nullable);

  Procedure jsifyTarget(DartType type) =>
      isJSValueType(type) ? jsValueUnboxTarget : jsifyRawTarget;

  /// Whether [type] erases to a `JSValue` or `JSValue?`.
  bool isJSValueType(DartType type) =>
      _extensionIndex.isStaticInteropType(type) ||
      _extensionIndex.isExternalDartReferenceType(type);

  void annotateProcedure(
      Procedure procedure, String pragmaOptionString, AnnotationType type) {
    String pragmaNameType = switch (type) {
      AnnotationType.import => 'import',
      AnnotationType.export => 'export',
      AnnotationType.weakExport => 'weak-export',
    };
    procedure.addAnnotation(ConstantExpression(
        InstanceConstant(coreTypes.pragmaClass.reference, [], {
      coreTypes.pragmaName.fieldReference:
          StringConstant('wasm:$pragmaNameType'),
      coreTypes.pragmaOptions.fieldReference: StringConstant(pragmaOptionString)
    })));
  }

  Expression variableCheckConstant(
          VariableDeclaration variable, Constant constant) =>
      StaticInvocation(coreTypes.identicalProcedure,
          Arguments([VariableGet(variable), ConstantExpression(constant)]));

  Expression variableGreaterThanOrEqualToConstant(
          VariableDeclaration variable, Constant constant) =>
      InstanceInvocation(
        InstanceAccessKind.Instance,
        VariableGet(variable),
        greaterThanOrEqualToTarget.name,
        Arguments([ConstantExpression(constant)]),
        interfaceTarget: greaterThanOrEqualToTarget,
        functionType: greaterThanOrEqualToTarget.getterType as FunctionType,
      );

  /// Cast the [invocation] if needed to conform to the expected [returnType].
  Expression castInvocationForReturn(
      Expression invocation, DartType returnType) {
    if (returnType is VoidType) {
      // `undefined` may be returned for `void` external members. It, however,
      // is an extern ref, and therefore needs to be made a Dart type before
      // we can finish the invocation.
      return invokeOneArg(dartifyRawTarget, invocation);
    } else {
      Expression expression;
      if (isJSValueType(returnType)) {
        // TODO(joshualitt): Expose boxed `JSNull` and `JSUndefined` to Dart
        // code after migrating existing users of js interop on Dart2Wasm.
        // expression = _createJSValue(invocation);
        // Casts are expensive, so we stick to a null-assertion if needed. If
        // the nullability can't be determined, cast.
        expression = invokeOneArg(jsValueBoxTarget, invocation);
        final nullability = returnType.extensionTypeErasure.nullability;
        if (nullability == Nullability.nonNullable) {
          expression = NullCheck(expression);
        } else if (nullability == Nullability.undetermined) {
          expression = AsExpression(expression, returnType);
        }
      } else {
        // Because we simply don't have enough information, we leave all JS
        // numbers as doubles. However, in cases where we know the user expects
        // an `int` we check that the double is an integer, and then insert a
        // cast. We also let static interop types flow through without
        // conversion, both as arguments, and as the return type.
        expression = convertAndCast(
            returnType, invokeOneArg(dartifyRawTarget, invocation));
      }
      return expression;
    }
  }

  // Handles any necessary type conversions. Today this is just for handling the
  // case where a user wants us to coerce a JS number to an int instead of a
  // double. This is okay as long as the value is an integer value.
  Expression convertAndCast(DartType staticType, Expression expression) {
    final erasedType = staticType.extensionTypeErasure;
    if (erasedType == coreTypes.intNullableRawType ||
        erasedType == coreTypes.intNonNullableRawType) {
      // let v = [expression] as double? in
      //  if (v == null) {
      //    return null;
      //  } else {
      //    let v2 = v.toInt() in
      //      if (v == v2) {
      //        return v2;
      //      } else {
      //        throw;
      //      }
      VariableDeclaration v = VariableDeclaration('#vardouble',
          initializer:
              AsExpression(expression, coreTypes.doubleNullableRawType),
          type: coreTypes.doubleNullableRawType,
          isSynthesized: true);
      VariableDeclaration v2 = VariableDeclaration('#varint',
          initializer: invokeMethod(v, numToIntTarget),
          type: coreTypes.intNonNullableRawType,
          isSynthesized: true);
      expression = Let(
          v,
          ConditionalExpression(
              variableCheckConstant(v, NullConstant()),
              ConstantExpression(NullConstant()),
              Let(
                  v2,
                  ConditionalExpression(
                      invokeMethod(v, coreTypes.objectEquals,
                          Arguments([VariableGet(v2)])),
                      VariableGet(v2),
                      Throw(StringLiteral(
                          'Expected integer value, but was not integer.')),
                      coreTypes.intNonNullableRawType)),
              coreTypes.intNullableRawType));
    }
    return AsExpression(expression, staticType);
  }
}

StaticInvocation invokeOneArg(Procedure target, Expression arg) =>
    StaticInvocation(target, Arguments([arg]));

InstanceInvocation invokeMethod(VariableDeclaration receiver, Procedure target,
        [Arguments? arguments]) =>
    InstanceInvocation(InstanceAccessKind.Instance, VariableGet(receiver),
        target.name, arguments ?? Arguments([]),
        interfaceTarget: target,
        functionType:
            target.function.computeFunctionType(Nullability.nonNullable));

bool parametersNeedParens(List<String> parameters) =>
    parameters.isEmpty || parameters.length > 1;
