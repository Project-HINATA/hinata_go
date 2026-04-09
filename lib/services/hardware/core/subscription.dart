import 'dart:async';
import 'dart:collection';

enum PolicyType { count, never, specificIsOn, specificNotOn }

class UnSubscribePolicy {
  final PolicyType type;
  final int count;
  final int index;
  final int byte;

  const UnSubscribePolicy._(
    this.type, {
    this.count = 0,
    this.index = 0,
    this.byte = 0,
  });

  factory UnSubscribePolicy.count(int count) =>
      UnSubscribePolicy._(PolicyType.count, count: count);
  factory UnSubscribePolicy.never() => UnSubscribePolicy._(PolicyType.never);
  factory UnSubscribePolicy.specificIsOn(int index, int byte) =>
      UnSubscribePolicy._(PolicyType.specificIsOn, index: index, byte: byte);
  factory UnSubscribePolicy.specificNotOn(int index, int byte) =>
      UnSubscribePolicy._(PolicyType.specificNotOn, index: index, byte: byte);

  bool needDispose(List<int> msg, int currentCount) {
    switch (type) {
      case PolicyType.count:
        return currentCount >= count;
      case PolicyType.never:
        return false;
      case PolicyType.specificIsOn:
        if (index < msg.length) {
          return msg[index] == byte;
        }
        return true;
      case PolicyType.specificNotOn:
        if (index < msg.length) {
          return msg[index] != byte;
        }
        return true;
    }
  }
}

class Subscription {
  final UnSubscribePolicy policy;
  final Queue<List<int>> _buffer = Queue();
  final Queue<Completer<List<int>>> _completers = Queue();
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  int _count = 0;
  bool _isClosed = false;

  Subscription(this.policy);

  Stream<List<int>> get stream => _controller.stream;

  Future<List<int>> receive() {
    if (_buffer.isNotEmpty) {
      return Future.value(_buffer.removeFirst());
    } else if (_isClosed) {
      return Future.error(StateError('Subscription channel disconnected'));
    } else {
      var completer = Completer<List<int>>();
      _completers.add(completer);
      return completer.future;
    }
  }

  bool send(List<int> msg) {
    _count++;
    bool needDispose = policy.needDispose(msg, _count);

    if (!_isClosed) {
      _controller.add(msg);
      if (_completers.isNotEmpty) {
        _completers.removeFirst().complete(msg);
      } else {
        _buffer.add(msg);
      }

      if (needDispose) {
        _closeInternal();
      }
    } else {
      needDispose = true;
    }

    return needDispose;
  }

  void _closeInternal() {
    _isClosed = true;
    _controller.close();
    while (_completers.isNotEmpty) {
      _completers.removeFirst().completeError(
        StateError('Subscription channel disconnected'),
      );
    }
  }

  void close() {
    if (!_isClosed) {
      _closeInternal();
    }
  }
}
