// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/resolution/driver_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AssignmentToFinalNoSetterTest);
    defineReflectiveTests(AssignmentToFinalNoSetterWithExtensionMethodsTest);
  });
}

@reflectiveTest
class AssignmentToFinalNoSetterTest extends DriverResolutionTest {
  test_prefixedIdentifier() async {
    await assertErrorsInCode('''
class A {
  int get x => 0;
}
main() {
  A a = new A();
  a.x = 0;
}''', [
      error(StaticWarningCode.ASSIGNMENT_TO_FINAL_NO_SETTER, 60, 1),
    ]);
  }

  test_propertyAccess() async {
    await assertErrorsInCode('''
class A {
  int get x => 0;
}
class B {
  static A a;
}
main() {
  B.a.x = 0;
}''', [
      error(StaticWarningCode.ASSIGNMENT_TO_FINAL_NO_SETTER, 71, 1),
    ]);
  }
}

@reflectiveTest
class AssignmentToFinalNoSetterWithExtensionMethodsTest
    extends AssignmentToFinalNoSetterTest {
  @override
  AnalysisOptionsImpl get analysisOptions => AnalysisOptionsImpl()
    ..contextFeatures = new FeatureSet.forTesting(
        sdkVersion: '2.3.0', additionalFeatures: [Feature.extension_methods]);

  test_instance_undefined_hasGetter() async {
    await assertErrorsInCode('''
extension E on int {
  int get foo => 0;
}
f() {
  0.foo = 1;
}
''', [
      error(StaticWarningCode.ASSIGNMENT_TO_FINAL_NO_SETTER, 53, 3),
    ]);
  }
}
