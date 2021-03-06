// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.severity;

enum Severity {
  context,
  error,
  ignored,
  internalProblem,
  warning,
}

const Map<String, String> severityEnumNames = const <String, String>{
  'CONTEXT': 'context',
  'ERROR': 'error',
  'IGNORED': 'ignored',
  'INTERNAL_PROBLEM': 'internalProblem',
  'WARNING': 'warning',
};

const Map<String, Severity> severityEnumValues = const <String, Severity>{
  'CONTEXT': Severity.context,
  'ERROR': Severity.error,
  'IGNORED': Severity.ignored,
  'INTERNAL_PROBLEM': Severity.internalProblem,
  'WARNING': Severity.warning,
};

const Map<Severity, String> severityPrefixes = const <Severity, String>{
  Severity.error: "Error",
  Severity.internalProblem: "Internal problem",
  Severity.warning: "Warning",
  Severity.context: "Context",
};

const Map<Severity, String> severityTexts = const <Severity, String>{
  Severity.error: "error",
  Severity.internalProblem: "internal problem",
  Severity.warning: "warning",
  Severity.context: "context",
};
