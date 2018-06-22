// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library frontend_server;

import 'dart:async';
import 'dart:convert';
import 'dart:io' hide FileSystemEntity;

import 'package:args/args.dart';
import 'package:build_integration/file_system/multi_root.dart';
// front_end/src imports below that require lint `ignore_for_file`
// are a temporary state of things until frontend team builds better api
// that would replace api used below. This api was made private in
// an effort to discourage further use.
// ignore_for_file: implementation_imports
import 'package:front_end/src/api_prototype/compiler_options.dart';
import 'package:front_end/src/api_prototype/file_system.dart'
    show FileSystemEntity;
import 'package:front_end/src/api_prototype/front_end.dart';
import 'package:front_end/src/fasta/kernel/utils.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/binary/ast_to_binary.dart';
import 'package:kernel/binary/limited_ast_to_binary.dart';
import 'package:kernel/kernel.dart'
    show Component, loadComponentSourceFromBytes;
import 'package:kernel/target/targets.dart';
import 'package:path/path.dart' as path;
import 'package:usage/uuid/uuid.dart';
import 'package:vm/incremental_compiler.dart' show IncrementalCompiler;
import 'package:vm/kernel_front_end.dart'
    show compileToKernel, parseCommandLineDefines;

ArgParser argParser = new ArgParser(allowTrailingOptions: true)
  ..addFlag('train',
      help: 'Run through sample command line to produce snapshot',
      negatable: false)
  ..addFlag('incremental',
      help: 'Run compiler in incremental mode', defaultsTo: false)
  ..addOption('sdk-root',
      help: 'Path to sdk root',
      defaultsTo: '../../out/android_debug/flutter_patched_sdk')
  ..addOption('platform', help: 'Platform kernel filename')
  ..addFlag('aot',
      help: 'Run compiler in AOT mode (enables whole-program transformations)',
      defaultsTo: false)
  ..addFlag('strong',
      help: 'Run compiler in strong mode (uses strong mode semantics)',
      defaultsTo: false)
  ..addFlag('sync-async',
      help: 'Start `async` functions synchronously.', defaultsTo: true)
  ..addFlag('tfa',
      help:
          'Enable global type flow analysis and related transformations in AOT mode.',
      defaultsTo: false)
  ..addMultiOption('entry-points',
      help: 'Path to JSON file with the list of entry points')
  ..addFlag('link-platform',
      help:
          'When in batch mode, link platform kernel file into result kernel file.'
          ' Intended use is to satisfy different loading strategies implemented'
          ' by gen_snapshot(which needs platform embedded) vs'
          ' Flutter engine(which does not)',
      defaultsTo: true)
  ..addOption('import-dill',
      help: 'Import libraries from existing dill file', defaultsTo: null)
  ..addOption('output-dill',
      help: 'Output path for the generated dill', defaultsTo: null)
  ..addOption('output-incremental-dill',
      help: 'Output path for the generated incremental dill', defaultsTo: null)
  ..addOption('depfile',
      help: 'Path to output Ninja depfile. Only used in batch mode.')
  ..addOption('packages',
      help: '.packages file to use for compilation', defaultsTo: null)
  ..addOption('target',
      help: 'Target model that determines what core libraries are available',
      allowed: <String>['vm', 'flutter'],
      defaultsTo: 'vm')
  ..addMultiOption('filesystem-root',
      help: 'File path that is used as a root in virtual filesystem used in'
          ' compiled kernel files. When used --output-dill should be provided'
          ' as well.',
      hide: true)
  ..addOption('filesystem-scheme',
      help:
          'Scheme that is used in virtual filesystem set up via --filesystem-root'
          ' option',
      defaultsTo: 'org-dartlang-root',
      hide: true)
  ..addFlag('verbose', help: 'Enables verbose output from the compiler.')
  ..addOption('initialize-from-dill',
      help: 'Normally the output dill is used to specify which dill to '
          'initialize from, but it can be overwritten here.',
      defaultsTo: null,
      hide: true)
  ..addMultiOption('define',
      abbr: 'D',
      help: 'The values for the environment constants (e.g. -Dkey=value).');

String usage = '''
Usage: server [options] [input.dart]

If input dart source code is provided on the command line, then the server
compiles it, generates dill file and exits.
If no input dart source is provided on the command line, server waits for
instructions from stdin.

Instructions:
- compile <input.dart>
- recompile [<input.dart>] <boundary-key>
<path/to/updated/file1.dart>
<path/to/updated/file2.dart>
...
<boundary-key>
- accept
- quit

Output:
- result <boundary-key>
<compiler output>
<boundary-key> [<output.dill>]

Options:
${argParser.usage}
''';

enum _State {
  READY_FOR_INSTRUCTION,
  RECOMPILE_LIST,
  COMPILE_EXPRESSION_EXPRESSION,
  COMPILE_EXPRESSION_DEFS,
  COMPILE_EXPRESSION_TYPEDEFS,
  COMPILE_EXPRESSION_LIBRARY_URI,
  COMPILE_EXPRESSION_KLASS,
  COMPILE_EXPRESSION_IS_STATIC
}

/// Actions that every compiler should implement.
abstract class CompilerInterface {
  /// Compile given Dart program identified by `filename` with given list of
  /// `options`. When `generator` parameter is omitted, new instance of
  /// `IncrementalKernelGenerator` is created by this method. Main use for this
  /// parameter is for mocking in tests.
  /// Returns [true] if compilation was successful and produced no errors.
  Future<bool> compile(
    String filename,
    ArgResults options, {
    IncrementalCompiler generator,
  });

  /// Assuming some Dart program was previously compiled, recompile it again
  /// taking into account some changed(invalidated) sources.
  Future<Null> recompileDelta({String filename});

  /// Accept results of previous compilation so that next recompilation cycle
  /// won't recompile sources that were previously reported as changed.
  void acceptLastDelta();

  /// This let's compiler know that source file identifed by `uri` was changed.
  void invalidate(Uri uri);

  /// Resets incremental compiler accept/reject status so that next time
  /// recompile is requested, complete kernel file is produced.
  void resetIncrementalCompiler();

  /// Compiles [expression] with free variables listed in [definitions],
  /// free type variables listed in [typedDefinitions]. "Free" means their
  /// values are through evaluation API call, rather than coming from running
  /// application.
  /// If [klass] is not [null], expression is compiled in context of [klass]
  /// class.
  /// If [klass] is [null],expression is compiled at top-level of
  /// [libraryUrl] library. If [klass] is not [null], [isStatic] determines
  /// whether expression can refer to [this] or not.
  Future<Null> compileExpression(
      String expression,
      List<String> definitions,
      List<String> typeDefinitions,
      String libraryUri,
      String klass,
      bool isStatic);

  /// Communicates an error [msg] to the client.
  void reportError(String msg);
}

abstract class ProgramTransformer {
  void transform(Component component);
}

/// Class that for test mocking purposes encapsulates creation of [BinaryPrinter].
class BinaryPrinterFactory {
  /// Creates new [BinaryPrinter] to write to [targetSink].
  BinaryPrinter newBinaryPrinter(IOSink targetSink) {
    return new LimitedBinaryPrinter(targetSink, (_) => true /* predicate */,
        false /* excludeUriToSource */);
  }
}

class FrontendCompiler implements CompilerInterface {
  FrontendCompiler(this._outputStream,
      {this.printerFactory, this.transformer}) {
    _outputStream ??= stdout;
    printerFactory ??= new BinaryPrinterFactory();
  }

  StringSink _outputStream;
  BinaryPrinterFactory printerFactory;

  CompilerOptions _compilerOptions;
  Uri _mainSource;
  ArgResults _options;

  IncrementalCompiler _generator;
  String _kernelBinaryFilename;
  String _kernelBinaryFilenameIncremental;
  String _kernelBinaryFilenameFull;
  String _initializeFromDill;

  final ProgramTransformer transformer;

  final List<String> errors = new List<String>();

  void setMainSourceFilename(String filename) {
    final Uri filenameUri = _getFileOrUri(filename);
    _mainSource = filenameUri;
  }

  @override
  Future<bool> compile(
    String filename,
    ArgResults options, {
    IncrementalCompiler generator,
  }) async {
    _options = options;
    setMainSourceFilename(filename);
    _kernelBinaryFilenameFull = _options['output-dill'] ?? '$filename.dill';
    _kernelBinaryFilenameIncremental = _options['output-incremental-dill'] ??
        (_options['output-dill'] != null
            ? '${_options['output-dill']}.incremental.dill'
            : '$filename.incremental.dill');
    _kernelBinaryFilename = _kernelBinaryFilenameFull;
    _initializeFromDill =
        _options['initialize-from-dill'] ?? _kernelBinaryFilenameFull;
    final String boundaryKey = new Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    final Uri sdkRoot = _ensureFolderPath(options['sdk-root']);
    final String platformKernelDill = options['platform'] ??
        (options['strong'] ? 'platform_strong.dill' : 'platform.dill');
    final CompilerOptions compilerOptions = new CompilerOptions()
      ..sdkRoot = sdkRoot
      ..packagesFileUri = _getFileOrUri(_options['packages'])
      ..strongMode = options['strong']
      ..sdkSummary = sdkRoot.resolve(platformKernelDill)
      ..verbose = options['verbose']
      ..onProblem =
          (message, Severity severity, List<FormattedMessage> context) {
        bool printMessage;
        switch (severity) {
          case Severity.error:
          case Severity.internalProblem:
            printMessage = true;
            errors.add(message.formatted);
            break;
          case Severity.warning:
            printMessage = true;
            break;
          case Severity.errorLegacyWarning:
          case Severity.context:
          case Severity.ignored:
            throw 'Unexpected severity: $severity';
        }
        if (printMessage) {
          _outputStream.writeln(message.formatted);
          for (FormattedMessage message in context) {
            _outputStream.writeln(message.formatted);
          }
        }
      };
    if (options.wasParsed('filesystem-root')) {
      List<Uri> rootUris = <Uri>[];
      for (String root in options['filesystem-root']) {
        rootUris.add(Uri.base.resolveUri(new Uri.file(root)));
      }
      compilerOptions.fileSystem = new MultiRootFileSystem(
          options['filesystem-scheme'], rootUris, compilerOptions.fileSystem);

      if (_options['output-dill'] == null) {
        print('When --filesystem-root is specified it is required to specify'
            ' --output-dill option that points to physical file system location'
            ' of a target dill file.');
        return false;
      }
    }

    final Map<String, String> environmentDefines = {};
    if (!parseCommandLineDefines(
        options['define'], environmentDefines, usage)) {
      return false;
    }

    final TargetFlags targetFlags = new TargetFlags(
        strongMode: options['strong'], syncAsync: options['sync-async']);
    compilerOptions.target = getTarget(options['target'], targetFlags);

    final String importDill = options['import-dill'];
    if (importDill != null) {
      compilerOptions.inputSummaries = <Uri>[
        Uri.base.resolveUri(new Uri.file(importDill))
      ];
    }

    Component component;
    if (options['incremental']) {
      _compilerOptions = compilerOptions;
      _generator =
          generator ?? _createGenerator(new Uri.file(_initializeFromDill));
      await invalidateIfInitializingFromDill();
      component = await _runWithPrintRedirection(() => _generator.compile());
    } else {
      if (options['link-platform']) {
        // TODO(aam): Remove linkedDependencies once platform is directly embedded
        // into VM snapshot and http://dartbug.com/30111 is fixed.
        compilerOptions.linkedDependencies = <Uri>[
          sdkRoot.resolve(platformKernelDill)
        ];
      }
      component = await _runWithPrintRedirection(() => compileToKernel(
          _mainSource, compilerOptions,
          aot: options['aot'],
          useGlobalTypeFlowAnalysis: options['tfa'],
          entryPoints: options['entry-points'],
          environmentDefines: environmentDefines));
    }
    if (component != null) {
      if (transformer != null) {
        transformer.transform(component);
      }

      await writeDillFile(component, _kernelBinaryFilename,
          filterExternal: importDill != null);

      _outputStream
          .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
      final String depfile = options['depfile'];
      if (depfile != null) {
        await _writeDepfile(component, _kernelBinaryFilename, depfile);
      }

      _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
    } else
      _outputStream.writeln(boundaryKey);
    return errors.isEmpty;
  }

  writeDillFile(Component component, String filename,
      {bool filterExternal: false}) async {
    final IOSink sink = new File(filename).openWrite();
    final BinaryPrinter printer = filterExternal
        ? new LimitedBinaryPrinter(
            sink, (lib) => !lib.isExternal, true /* excludeUriToSource */)
        : printerFactory.newBinaryPrinter(sink);

    printer.writeComponentFile(component);
    await sink.close();
  }

  Future<Null> invalidateIfInitializingFromDill() async {
    if (_kernelBinaryFilename != _kernelBinaryFilenameFull) return null;
    // If the generator is initialized, it's not going to initialize from dill
    // again anyway, so there's no reason to spend time invalidating what should
    // be invalidated by the normal approach anyway.
    if (_generator.initialized) return null;

    final File f = new File(_initializeFromDill);
    if (!f.existsSync()) return null;

    Component component;
    try {
      component = loadComponentSourceFromBytes(f.readAsBytesSync());
    } catch (e) {
      // If we cannot load the dill file we shouldn't initialize from it.
      _generator = _createGenerator(null);
      return null;
    }

    nextUri:
    for (Uri uri in component.uriToSource.keys) {
      if (uri == null || '$uri' == '') continue nextUri;

      final List<int> oldBytes = component.uriToSource[uri].source;
      final FileSystemEntity entity =
          _compilerOptions.fileSystem.entityForUri(uri);
      if (!await entity.exists()) {
        _generator.invalidate(uri);
        continue nextUri;
      }
      final List<int> newBytes = await entity.readAsBytes();
      if (oldBytes.length != newBytes.length) {
        _generator.invalidate(uri);
        continue nextUri;
      }
      for (int i = 0; i < oldBytes.length; ++i) {
        if (oldBytes[i] != newBytes[i]) {
          _generator.invalidate(uri);
          continue nextUri;
        }
      }
    }
  }

  @override
  Future<Null> recompileDelta({String filename}) async {
    final String boundaryKey = new Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    await invalidateIfInitializingFromDill();
    if (filename != null) {
      setMainSourceFilename(filename);
    }
    errors.clear();
    final Component deltaProgram =
        await _generator.compile(entryPoint: _mainSource);

    if (deltaProgram != null && transformer != null) {
      transformer.transform(deltaProgram);
    }

    final IOSink sink = new File(_kernelBinaryFilename).openWrite();
    final BinaryPrinter printer = printerFactory.newBinaryPrinter(sink);
    printer.writeComponentFile(deltaProgram);
    await sink.close();
    _outputStream
        .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
    _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
  }

  @override
  Future<Null> compileExpression(
      String expression,
      List<String> definitions,
      List<String> typeDefinitions,
      String libraryUri,
      String klass,
      bool isStatic) async {
    final String boundaryKey = new Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    Procedure procedure = await _generator.compileExpression(
        expression, definitions, typeDefinitions, libraryUri, klass, isStatic);
    if (procedure != null) {
      final IOSink sink = new File(_kernelBinaryFilename).openWrite();
      sink.add(serializeProcedure(procedure));
      await sink.close();
      _outputStream
          .writeln('$boundaryKey $_kernelBinaryFilename ${errors.length}');
      _kernelBinaryFilename = _kernelBinaryFilenameIncremental;
    } else {
      _outputStream.writeln(boundaryKey);
    }
  }

  @override
  void reportError(String msg) {
    final String boundaryKey = new Uuid().generateV4();
    _outputStream.writeln('result $boundaryKey');
    _outputStream.writeln(msg);
    _outputStream.writeln(boundaryKey);
  }

  @override
  void acceptLastDelta() {
    _generator.accept();
  }

  @override
  void invalidate(Uri uri) {
    _generator.invalidate(uri);
  }

  @override
  void resetIncrementalCompiler() {
    _generator.resetDeltaState();
    _kernelBinaryFilename = _kernelBinaryFilenameFull;
  }

  Uri _getFileOrUri(String fileOrUri) {
    if (fileOrUri == null) {
      return null;
    }
    if (_options.wasParsed('filesystem-root')) {
      // This is a hack.
      // Only expect uri when filesystem-root option is specified. It has to
      // be uri for filesystem-root use case because mapping is done on
      // scheme-basis.
      // This is so that we don't deal with Windows files paths that can not
      // be processed as uris.
      return Uri.base.resolve(fileOrUri);
    }
    return Uri.base.resolveUri(new Uri.file(fileOrUri));
  }

  IncrementalCompiler _createGenerator(Uri initializeFromDillUri) {
    return new IncrementalCompiler(_compilerOptions, _mainSource,
        initializeFromDillUri: initializeFromDillUri);
  }

  Uri _ensureFolderPath(String path) {
    String uriPath = new Uri.file(path).toString();
    if (!uriPath.endsWith('/')) {
      uriPath = '$uriPath/';
    }
    return Uri.base.resolve(uriPath);
  }

  /// Runs the given function [f] in a Zone that redirects all prints into
  /// [_outputStream].
  Future<T> _runWithPrintRedirection<T>(Future<T> f()) {
    return runZoned(() => new Future<T>(f),
        zoneSpecification: new ZoneSpecification(
            print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
                _outputStream.writeln(line)));
  }
}

String _escapePath(String path) {
  return path.replaceAll(r'\', r'\\').replaceAll(r' ', r'\ ');
}

// https://ninja-build.org/manual.html#_depfile
void _writeDepfile(Component component, String output, String depfile) async {
  final IOSink file = new File(depfile).openWrite();
  file.write(_escapePath(output));
  file.write(':');
  for (Uri dep in component.uriToSource.keys) {
    if (dep == null) continue;
    file.write(' ');
    file.write(_escapePath(dep.toFilePath()));
  }
  file.write('\n');
  await file.close();
}

class _CompileExpressionRequest {
  String expression;
  // Note that FE will reject a compileExpression command by returning a null
  // procedure when defs or typeDefs include an illegal identifier.
  List<String> defs = <String>[];
  List<String> typeDefs = <String>[];
  String library;
  String klass;
  bool isStatic;
}

/// Listens for the compilation commands on [input] stream.
/// This supports "interactive" recompilation mode of execution.
void listenAndCompile(CompilerInterface compiler, Stream<List<int>> input,
    ArgResults options, void quit(),
    {IncrementalCompiler generator}) {
  _State state = _State.READY_FOR_INSTRUCTION;
  _CompileExpressionRequest compileExpressionRequest;
  String boundaryKey;
  String recompileFilename;
  input
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((String string) async {
    switch (state) {
      case _State.READY_FOR_INSTRUCTION:
        const String COMPILE_INSTRUCTION_SPACE = 'compile ';
        const String RECOMPILE_INSTRUCTION_SPACE = 'recompile ';
        const String COMPILE_EXPRESSION_INSTRUCTION_SPACE =
            'compile-expression ';
        if (string.startsWith(COMPILE_INSTRUCTION_SPACE)) {
          final String filename =
              string.substring(COMPILE_INSTRUCTION_SPACE.length);
          await compiler.compile(filename, options, generator: generator);
        } else if (string.startsWith(RECOMPILE_INSTRUCTION_SPACE)) {
          // 'recompile [<filename>] <boundarykey>'
          //   where <boundarykey> can't have spaces
          final String remainder =
              string.substring(RECOMPILE_INSTRUCTION_SPACE.length);
          final int spaceDelim = remainder.lastIndexOf(' ');
          if (spaceDelim > -1) {
            recompileFilename = remainder.substring(0, spaceDelim);
            boundaryKey = remainder.substring(spaceDelim + 1);
          } else {
            boundaryKey = remainder;
          }
          state = _State.RECOMPILE_LIST;
        } else if (string.startsWith(COMPILE_EXPRESSION_INSTRUCTION_SPACE)) {
          // 'compile-expression <boundarykey>
          // expression
          // definitions (one per line)
          // ...
          // <boundarykey>
          // type-defintions (one per line)
          // ...
          // <boundarykey>
          // <libraryUri: String>
          // <klass: String>
          // <isStatic: true|false>
          compileExpressionRequest = new _CompileExpressionRequest();
          boundaryKey =
              string.substring(COMPILE_EXPRESSION_INSTRUCTION_SPACE.length);
          state = _State.COMPILE_EXPRESSION_EXPRESSION;
        } else if (string == 'accept') {
          compiler.acceptLastDelta();
        } else if (string == 'reset') {
          compiler.resetIncrementalCompiler();
        } else if (string == 'quit') {
          quit();
        }
        break;
      case _State.RECOMPILE_LIST:
        if (string == boundaryKey) {
          compiler.recompileDelta(filename: recompileFilename);
          state = _State.READY_FOR_INSTRUCTION;
        } else
          compiler.invalidate(Uri.base.resolve(string));
        break;
      case _State.COMPILE_EXPRESSION_EXPRESSION:
        compileExpressionRequest.expression = string;
        state = _State.COMPILE_EXPRESSION_DEFS;
        break;
      case _State.COMPILE_EXPRESSION_DEFS:
        if (string == boundaryKey) {
          state = _State.COMPILE_EXPRESSION_TYPEDEFS;
        } else {
          compileExpressionRequest.defs.add(string);
        }
        break;
      case _State.COMPILE_EXPRESSION_TYPEDEFS:
        if (string == boundaryKey) {
          state = _State.COMPILE_EXPRESSION_LIBRARY_URI;
        } else {
          compileExpressionRequest.typeDefs.add(string);
        }
        break;
      case _State.COMPILE_EXPRESSION_LIBRARY_URI:
        compileExpressionRequest.library = string;
        state = _State.COMPILE_EXPRESSION_KLASS;
        break;
      case _State.COMPILE_EXPRESSION_KLASS:
        compileExpressionRequest.klass = string.isEmpty ? null : string;
        state = _State.COMPILE_EXPRESSION_IS_STATIC;
        break;
      case _State.COMPILE_EXPRESSION_IS_STATIC:
        if (string == 'true' || string == 'false') {
          compileExpressionRequest.isStatic = string == 'true';
          compiler.compileExpression(
              compileExpressionRequest.expression,
              compileExpressionRequest.defs,
              compileExpressionRequest.typeDefs,
              compileExpressionRequest.library,
              compileExpressionRequest.klass,
              compileExpressionRequest.isStatic);
        } else {
          compiler
              .reportError('Got $string. Expected either "true" or "false"');
        }
        state = _State.READY_FOR_INSTRUCTION;
        break;
    }
  });
}

/// Entry point for this module, that creates `_FrontendCompiler` instance and
/// processes user input.
/// `compiler` is an optional parameter so it can be replaced with mocked
/// version for testing.
Future<void> starter(
  List<String> args, {
  CompilerInterface compiler,
  Stream<List<int>> input,
  StringSink output,
  IncrementalCompiler generator,
  BinaryPrinterFactory binaryPrinterFactory,
}) async {
  ArgResults options;
  try {
    options = argParser.parse(args);
  } catch (error) {
    print('ERROR: $error\n');
    print(usage);
    exit(1);
  }

  if (options['train']) {
    final String sdkRoot = options['sdk-root'];
    final String platform = options['platform'];
    final Directory temp =
        Directory.systemTemp.createTempSync('train_frontend_server');
    try {
      final String outputTrainingDill = path.join(temp.path, 'app.dill');
      final List<String> args = <String>[
        '--incremental',
        '--sdk-root=$sdkRoot',
        '--output-dill=$outputTrainingDill',
      ];
      if (platform != null) {
        args.add('--platform=${new Uri.file(platform)}');
      }
      options = argParser.parse(args);
      compiler ??=
          new FrontendCompiler(output, printerFactory: binaryPrinterFactory);

      await compiler.compile(Platform.script.toFilePath(), options,
          generator: generator);
      compiler.acceptLastDelta();
      await compiler.recompileDelta();
      compiler.acceptLastDelta();
      compiler.resetIncrementalCompiler();
      await compiler.recompileDelta();
      compiler.acceptLastDelta();
      await compiler.recompileDelta();
      compiler.acceptLastDelta();
      return 0;
    } finally {
      temp.deleteSync(recursive: true);
    }
  }

  compiler ??= new FrontendCompiler(
    output,
    printerFactory: binaryPrinterFactory,
  );

  if (options.rest.isNotEmpty) {
    exit(await compiler.compile(options.rest[0], options, generator: generator)
        ? 0
        : 254);
  }

  listenAndCompile(compiler, input ?? stdin, options, () {
    exit(0);
  }, generator: generator);
}
