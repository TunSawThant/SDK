// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi' as ffi;

import 'dylib_utils.dart';

typedef NativeDoubleUnOp = ffi.Double Function(ffi.Double);

typedef DoubleUnOp = double Function(double);

main(List<String> arguments) {
  ffi.DynamicLibrary l = dlopenPlatformSpecific("ffi_test_dynamic_library");
  print(l);
  print(l.runtimeType);

  var timesFour = l.lookupFunction<NativeDoubleUnOp, DoubleUnOp>("timesFour");
  print(timesFour);
  print(timesFour.runtimeType);

  print(timesFour(3.0));
}
