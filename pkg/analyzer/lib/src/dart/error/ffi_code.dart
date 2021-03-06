// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/error/error.dart';
import 'package:analyzer/src/error/analyzer_error_code.dart';
import 'package:meta/meta.dart';

/// The diagnostic codes associated with `dart:ffi`.
class FfiCode extends AnalyzerErrorCode {
  /**
   * No parameters.
   */
  static const FfiCode ANNOTATION_ON_POINTER_FIELD = const FfiCode(
      name: 'ANNOTATION_ON_POINTER_FIELD',
      message:
          "Fields in a struct class whose type is 'Pointer' should not have "
          "any annotations.",
      correction: "Try removing the annotation.");

  /**
   * No parameters.
   */
  static const FfiCode EXTRA_ANNOTATION_ON_STRUCT_FIELD = const FfiCode(
      name: 'EXTRA_ANNOTATION_ON_STRUCT_FIELD',
      message: "Fields in a struct class must have exactly one annotation "
          "indicating the native type.",
      correction: "Try removing the extra annotation.");

  /**
   * No parameters.
   */
  static const FfiCode FIELD_IN_STRUCT_WITH_INITIALIZER = const FfiCode(
      name: 'FIELD_IN_STRUCT_WITH_INITIALIZER',
      message: "Fields in subclasses of 'Struct' can't have initializers.",
      correction: "Try removing the initializer.");

  /**
   * No parameters.
   */
  static const FfiCode FIELD_INITIALIZER_IN_STRUCT = const FfiCode(
      name: 'FIELD_INITIALIZER_IN_STRUCT',
      message: "Constructors in subclasses of 'Struct' can't have field "
          "initializers.",
      correction: "Try removing the field initializer.");

  /**
   * Parameters:
   * 0: the name of the struct class
   */
  static const FfiCode GENERIC_STRUCT_SUBCLASS = const FfiCode(
      name: 'GENERIC_STRUCT_SUBCLASS',
      message: "The class '{0}' can't extend 'Struct' because it is generic.",
      correction: "Try removing the type parameters from '{0}'.");

  /**
   * Parameters:
   * 0: the type of the field
   */
  static const FfiCode INVALID_FIELD_TYPE_IN_STRUCT = const FfiCode(
      name: 'INVALID_FIELD_TYPE_IN_STRUCT',
      message:
          "Fields in struct classes can't have the type '{0}'. They can only "
          "be declared as 'int', 'double' or 'Pointer'.",
      correction: "Try using 'int', 'double' or 'Pointer'.");

  /**
   * Parameters:
   * 0: the name of the subclass
   */
  static const FfiCode INVALID_TYPE_ARGUMENT_FOR_STRUCT = const FfiCode(
      name: 'INVALID_TYPE_ARGUMENT_FOR_STRUCT',
      message: "The type argument to 'Struct' must be the subclass ('{0}').",
      correction: "Try using '{0}' for the type argument.");

  /**
   * No parameters.
   */
  static const FfiCode MISMATCHED_ANNOTATION_ON_STRUCT_FIELD = const FfiCode(
      name: 'MISMATCHED_ANNOTATION_ON_STRUCT_FIELD',
      message: "The annotation does not match the declared type of the field.",
      correction: "Try using a different annotation or changing the declared "
          "type to match.");

  /**
   * No parameters.
   */
  static const FfiCode MISSING_ANNOTATION_ON_STRUCT_FIELD = const FfiCode(
      name: 'MISSING_ANNOTATION_ON_STRUCT_FIELD',
      message:
          "Fields in a struct class must either have the type 'Pointer' or an "
          "annotation indicating the native type.",
      correction: "Try adding an annotation.");

  /**
   * Parameters:
   * 0: the type of the field
   */
  static const FfiCode MISSING_FIELD_TYPE_IN_STRUCT = const FfiCode(
      name: 'MISSING_FIELD_TYPE_IN_STRUCT',
      message:
          "Fields in struct classes must have an explicitly declared type of "
          "'int', 'double' or 'Pointer'.",
      correction: "Try using 'int', 'double' or 'Pointer'.");

  /**
   * Parameters:
   * 0: the name of the subclass
   */
  static const FfiCode MISSING_TYPE_ARGUMENT_FOR_STRUCT = const FfiCode(
      name: 'MISSING_TYPE_ARGUMENT_FOR_STRUCT',
      message:
          "The type 'Struct' must have a type argument matching the subclass "
          "('{0}').",
      correction: "Try adding a type argument of '{0}'.");

  /**
   * Parameters:
   * 0: the name of the subclass
   * 1: the name of the class being extended, implemented, or mixed in
   */
  static const FfiCode SUBTYPE_OF_FFI_CLASS_IN_EXTENDS = const FfiCode(
      name: 'SUBTYPE_OF_FFI_CLASS',
      uniqueName: 'SUBTYPE_OF_FFI_CLASS_IN_EXTENDS',
      message: "The class '{0}' can't extend '{1}'.",
      correction: "Try extending 'Struct'.");

  /**
   * Parameters:
   * 0: the name of the subclass
   * 1: the name of the class being extended, implemented, or mixed in
   */
  static const FfiCode SUBTYPE_OF_FFI_CLASS_IN_IMPLEMENTS = const FfiCode(
      name: 'SUBTYPE_OF_FFI_CLASS',
      uniqueName: 'SUBTYPE_OF_FFI_CLASS_IN_IMPLEMENTS',
      message: "The class '{0}' can't implement '{1}'.",
      correction: "Try extending 'Struct'.");

  /**
   * Parameters:
   * 0: the name of the subclass
   * 1: the name of the class being extended, implemented, or mixed in
   */
  static const FfiCode SUBTYPE_OF_FFI_CLASS_IN_WITH = const FfiCode(
      name: 'SUBTYPE_OF_FFI_CLASS',
      uniqueName: 'SUBTYPE_OF_FFI_CLASS_IN_WITH',
      message: "The class '{0}' can't mix in '{1}'.",
      correction: "Try extending 'Struct'.");

  /**
   * Parameters:
   * 0: the name of the subclass
   * 1: the name of the class being extended, implemented, or mixed in
   */
  static const FfiCode SUBTYPE_OF_STRUCT_CLASS_IN_EXTENDS = const FfiCode(
      name: 'SUBTYPE_OF_STRUCT_CLASS',
      uniqueName: 'SUBTYPE_OF_STRUCT_CLASS_IN_EXTENDS',
      message:
          "The class '{0}' can't extend '{1}' because '{1}' is a subtype of "
          "'Struct'.",
      correction: "Try extending 'Struct' directly.");

  /**
   * Parameters:
   * 0: the name of the subclass
   * 1: the name of the class being extended, implemented, or mixed in
   */
  static const FfiCode SUBTYPE_OF_STRUCT_CLASS_IN_IMPLEMENTS = const FfiCode(
      name: 'SUBTYPE_OF_STRUCT_CLASS',
      uniqueName: 'SUBTYPE_OF_STRUCT_CLASS_IN_IMPLEMENTS',
      message:
          "The class '{0}' can't implement '{1}' because '{1}' is a subtype of "
          "'Struct'.",
      correction: "Try extending 'Struct' directly.");

  /**
   * Parameters:
   * 0: the name of the subclass
   * 1: the name of the class being extended, implemented, or mixed in
   */
  static const FfiCode SUBTYPE_OF_STRUCT_CLASS_IN_WITH = const FfiCode(
      name: 'SUBTYPE_OF_STRUCT_CLASS',
      uniqueName: 'SUBTYPE_OF_STRUCT_CLASS_IN_WITH',
      message:
          "The class '{0}' can't mix in '{1}' because '{1}' is a subtype of "
          "'Struct'.",
      correction: "Try extending 'Struct' directly.");

  @override
  final String uniqueName;

  /// Initialize a newly created error code to have the given [name]. If
  /// [uniqueName] is provided, then it will be used to construct the unique
  /// name for the code, otherwise the name will be used to construct the unique
  /// name.
  ///
  /// The message associated with the error will be created from the given
  /// [message] template. The correction associated with the error will be
  /// created from the given [correction] template.
  ///
  /// If [hasPublishedDocs] is `true` then a URL for the docs will be generated.
  const FfiCode(
      {@required String message,
      @required String name,
      String correction,
      bool hasPublishedDocs,
      String uniqueName})
      : uniqueName =
            uniqueName == null ? 'FfiCode.$name' : 'FfiCode.$uniqueName',
        super.temporary(name, message,
            correction: correction, hasPublishedDocs: hasPublishedDocs);

  @override
  ErrorSeverity get errorSeverity => type.severity;

  @override
  ErrorType get type => ErrorType.COMPILE_TIME_ERROR;
}
