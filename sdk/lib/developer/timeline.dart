// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of dart.developer;

const bool _hasTimeline =
    const bool.fromEnvironment("dart.developer.timeline", defaultValue: true);

/// A typedef for the function argument to [Timeline.timeSync].
typedef TimelineSyncFunction<T> = T Function();

// TODO: This typedef is not used.
typedef Future TimelineAsyncFunction();

/// A class to represent Flow events.
///
/// [Flow] objects are used to thread flow events between timeline slices,
/// for example, those created with the [Timeline] class below. Adding
/// [Flow] objects cause arrows to be drawn between slices in Chrome's trace
/// viewer. The arrows start at e.g [Timeline] events that are passed a
/// [Flow.begin] object, go through [Timeline] events that are passed a
/// [Flow.step] object, and end at [Timeline] events that are passed a
/// [Flow.end] object, all having the same [Flow.id]. For example:
///
/// ```dart
/// var flow = Flow.begin();
/// Timeline.timeSync('flow_test', () {
///   doSomething();
/// }, flow: flow);
///
/// Timeline.timeSync('flow_test', () {
///   doSomething();
/// }, flow: Flow.step(flow.id));
///
/// Timeline.timeSync('flow_test', () {
///   doSomething();
/// }, flow: Flow.end(flow.id));
/// ```
class Flow {
  // These values must be kept in sync with the enum "EventType" in
  // runtime/vm/timeline.h.
  static const int _begin = 9;
  static const int _step = 10;
  static const int _end = 11;

  final int _type;

  /// The flow id of the flow event.
  final int id;

  Flow._(this._type, this.id);

  /// A "begin" Flow event.
  ///
  /// When passed to a [Timeline] method, generates a "begin" Flow event.
  /// If [id] is not provided, an id that conflicts with no other Dart-generated
  /// flow id's will be generated.
  static Flow begin({int id}) {
    return new Flow._(_begin, id ?? _getNextAsyncId());
  }

  /// A "step" Flow event.
  ///
  /// When passed to a [Timeline] method, generates a "step" Flow event.
  /// The [id] argument is required. It can come either from another [Flow]
  /// event, or some id that comes from the environment.
  static Flow step(int id) => new Flow._(_step, id);

  /// An "end" Flow event.
  ///
  /// When passed to a [Timeline] method, generates a "end" Flow event.
  /// The [id] argument is required. It can come either from another [Flow]
  /// event, or some id that comes from the environment.
  static Flow end(int id) => new Flow._(_end, id);
}

/// Add to the timeline.
///
/// [Timeline]'s methods add synchronous events to the timeline. When
/// generating a timeline in Chrome's tracing format, using [Timeline] generates
/// "Complete" events. [Timeline]'s [startSync] and [finishSync] can be used
/// explicitly, or implicitly by wrapping a closure in [timeSync]. For example:
///
/// ```dart
/// Timeline.startSync("Doing Something");
/// doSomething();
/// Timeline.finishSync();
/// ```
///
/// Or:
///
/// ```dart
/// Timeline.timeSync("Doing Something", () {
///   doSomething();
/// });
/// ```
class Timeline {
  /// Start a synchronous operation labeled [name]. Optionally takes
  /// a [Map] of [arguments]. This slice may also optionally be associated with
  /// a [Flow] event. This operation must be finished before
  /// returning to the event queue.
  static void startSync(String name, {Map arguments, Flow flow}) {
    if (!_hasTimeline) return;
    ArgumentError.checkNotNull(name, 'name');
    if (!_isDartStreamEnabled()) {
      // Push a null onto the stack and return.
      _stack.add(null);
      return;
    }
    var block = new _SyncBlock._(name, _getTraceClock(), _getThreadCpuClock());
    if (arguments != null) {
      block._arguments = arguments;
    }
    if (flow != null) {
      block.flow = flow;
    }
    _stack.add(block);
  }

  /// Finish the last synchronous operation that was started.
  static void finishSync() {
    if (!_hasTimeline) {
      return;
    }
    if (_stack.length == 0) {
      throw new StateError('Uneven calls to startSync and finishSync');
    }
    // Pop top item off of stack.
    var block = _stack.removeLast();
    if (block == null) {
      // Dart stream was disabled when startSync was called.
      return;
    }
    // Finish it.
    block.finish();
  }

  /// Emit an instant event.
  static void instantSync(String name, {Map arguments}) {
    if (!_hasTimeline) return;
    ArgumentError.checkNotNull(name, 'name');
    if (!_isDartStreamEnabled()) {
      // Stream is disabled.
      return;
    }
    Map instantArguments;
    if (arguments != null) {
      instantArguments = new Map.from(arguments);
    }
    _reportInstantEvent(
        _getTraceClock(), 'Dart', name, _argumentsAsJson(instantArguments));
  }

  /// A utility method to time a synchronous [function]. Internally calls
  /// [function] bracketed by calls to [startSync] and [finishSync].
  static T timeSync<T>(String name, TimelineSyncFunction<T> function,
      {Map arguments, Flow flow}) {
    startSync(name, arguments: arguments, flow: flow);
    try {
      return function();
    } finally {
      finishSync();
    }
  }

  /// The current time stamp from the clock used by the timeline. Units are
  /// microseconds.
  ///
  /// When run on the Dart VM, uses the same monotonic clock as the embedding
  /// API's `Dart_TimelineGetMicros`.
  static int get now => _getTraceClock();
  static final List<_SyncBlock> _stack = new List<_SyncBlock>();
}

/// An asynchronous task on the timeline. An asynchronous task can have many
/// (nested) synchronous operations. Synchronous operations can live longer than
/// the current isolate event. To pass a [TimelineTask] to another isolate,
/// you must first call [pass] to get the task id and then construct a new
/// [TimelineTask] in the other isolate.
class TimelineTask {
  /// Create a task. The task ID will be set by the system.
  ///
  /// If [parent] is provided, the parent's task ID is provided as argument
  /// 'parentId' when [start] is called. In DevTools, this argument will result
  /// in this [TimelineTask] being linked to the [parent] [TimelineTask].
  TimelineTask({TimelineTask parent})
      : _parent = parent,
        _taskId = _getNextAsyncId() {}

  /// Create a task with an explicit [taskId]. This is useful if you are
  /// passing a task from one isolate to another.
  ///
  /// If [parent] is provided, the parent's task ID is provided as argument
  /// 'parentId' when [start] is called. In DevTools, this argument will result
  /// in this [TimelineTask] being linked to the [parent] [TimelineTask].
  TimelineTask.withTaskId(int taskId, {TimelineTask parent})
      : _parent = parent,
        _taskId = taskId {
    ArgumentError.checkNotNull(taskId, 'taskId');
  }

  /// Start a synchronous operation within this task named [name].
  /// Optionally takes a [Map] of [arguments].
  void start(String name, {Map arguments}) {
    if (!_hasTimeline) return;
    ArgumentError.checkNotNull(name, 'name');
    var block = new _AsyncBlock._(name, _taskId);
    _stack.add(block);
    block._start({
      if (arguments != null) ...arguments,
      if (_parent != null) 'parentId': _parent._taskId.toRadixString(16),
    });
  }

  /// Emit an instant event for this task.
  /// Optionally takes a [Map] of [arguments].
  void instant(String name, {Map arguments}) {
    if (!_hasTimeline) return;
    ArgumentError.checkNotNull(name, 'name');
    Map instantArguments;
    if (arguments != null) {
      instantArguments = new Map.from(arguments);
    }
    _reportTaskEvent(_getTraceClock(), _taskId, 'n', 'Dart', name,
        _argumentsAsJson(instantArguments));
  }

  /// Finish the last synchronous operation that was started.
  /// Optionally takes a [Map] of [arguments].
  void finish({Map arguments}) {
    if (!_hasTimeline) {
      return;
    }
    if (_stack.length == 0) {
      throw new StateError('Uneven calls to start and finish');
    }
    // Pop top item off of stack.
    var block = _stack.removeLast();
    block._finish(arguments);
  }

  /// Retrieve the [TimelineTask]'s task id. Will throw an exception if the
  /// stack is not empty.
  int pass() {
    if (_stack.length > 0) {
      throw new StateError(
          'You cannot pass a TimelineTask without finishing all started '
          'operations');
    }
    int r = _taskId;
    return r;
  }

  final TimelineTask _parent;
  final int _taskId;
  final List<_AsyncBlock> _stack = [];
}

/// An asynchronous block of time on the timeline. This block can be kept
/// open across isolate messages.
class _AsyncBlock {
  /// The category this block belongs to.
  final String category = 'Dart';

  /// The name of this block.
  final String name;

  /// The asynchronous task id.
  final int _taskId;

  _AsyncBlock._(this.name, this._taskId);

  // Emit the start event.
  void _start(Map arguments) {
    _reportTaskEvent(_getTraceClock(), _taskId, 'b', category, name,
        _argumentsAsJson(arguments));
  }

  // Emit the finish event.
  void _finish(Map arguments) {
    _reportTaskEvent(_getTraceClock(), _taskId, 'e', category, name,
        _argumentsAsJson(arguments));
  }
}

/// A synchronous block of time on the timeline. This block should not be
/// kept open across isolate messages.
class _SyncBlock {
  /// The category this block belongs to.
  final String category = 'Dart';

  /// The name of this block.
  final String name;

  /// An (optional) set of arguments which will be serialized to JSON and
  /// associated with this block.
  Map _arguments;
  // The start time stamp.
  final int _start;
  // The start time stamp of the thread cpu clock.
  final int _startCpu;

  /// An (optional) flow event associated with this block.
  Flow _flow;

  _SyncBlock._(this.name, this._start, this._startCpu);

  /// Finish this block of time. At this point, this block can no longer be
  /// used.
  void finish() {
    // Report event to runtime.
    _reportCompleteEvent(
        _start, _startCpu, category, name, _argumentsAsJson(_arguments));
    if (_flow != null) {
      _reportFlowEvent(_start, _startCpu, category, "${_flow.id}", _flow._type,
          _flow.id, _argumentsAsJson(null));
    }
  }

  void set flow(Flow f) {
    _flow = f;
  }
}

String _argumentsAsJson(Map arguments) {
  if ((arguments == null) || (arguments.length == 0)) {
    // Fast path no arguments. Avoid calling jsonEncode.
    return '{}';
  }
  return json.encode(arguments);
}

/// Returns true if the Dart Timeline stream is enabled.
external bool _isDartStreamEnabled();

/// Returns the next async task id.
external int _getNextAsyncId();

/// Returns the current value from the trace clock.
external int _getTraceClock();

/// Returns the current value from the thread CPU usage clock.
external int _getThreadCpuClock();

/// Reports an event for a task.
external void _reportTaskEvent(int start, int taskId, String phase,
    String category, String name, String argumentsAsJson);

/// Reports a complete synchronous event.
external void _reportCompleteEvent(int start, int startCpu, String category,
    String name, String argumentsAsJson);

/// Reports a flow event.
external void _reportFlowEvent(int start, int startCpu, String category,
    String name, int type, int id, String argumentsAsJson);

/// Reports an instant event.
external void _reportInstantEvent(
    int start, String category, String name, String argumentsAsJson);
