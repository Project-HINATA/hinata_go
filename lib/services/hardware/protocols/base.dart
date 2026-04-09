import 'dart:async';

typedef WriteFunc = Future<void> Function(List<int> data);
typedef ReadFunc = Future<List<int>> Function({Duration? timeout});

class IoBase {
  final WriteFunc write;
  final ReadFunc read;
  IoBase(this.write, this.read);
}
