part of '../spiceapi.dart';

class Connection {
  static const _timeout = Duration(seconds: 3);
  static const _bufferSize = 1024 * 1024 * 8;

  final String host;
  final int port;
  String pass;
  dynamic resource;
  final List<int> _dataBuffer = <int>[];
  final StreamController<Response> _responses =
      StreamController<Response>.broadcast();
  final StreamController<Connection> _connections =
      StreamController<Connection>.broadcast();
  final Completer<Connection> _connectCompleter = Completer<Connection>();
  WebSocket? _socket;
  RC4? _cipher;
  bool _disposed = false;

  Connection(
    this.host,
    this.port,
    this.pass, {
    this.resource,
    bool refreshSession = true,
  }) {
    if (pass.isNotEmpty) {
      _cipher = RC4(utf8.encode(pass));
    }
    _connect(refreshSession);
  }

  Future<void> _connect(bool refreshSession) async {
    try {
      final socket = await WebSocket.connect(
        'ws://$host:$port',
      ).timeout(_timeout);
      _socket = socket;

      socket.listen(
        (data) {
          List<int> buffer = [];
          if (data is String) {
            buffer = utf8.encode(data);
          } else if (data is List<int>) {
            buffer = data;
          }

          _cipher?.crypt(buffer);
          _dataBuffer.addAll(buffer);

          if (_dataBuffer.length > _bufferSize) {
            dispose();
            return;
          }

          for (int i = 0; i < _dataBuffer.length; i++) {
            if (_dataBuffer[i] != 0) {
              continue;
            }

            final msgData = List<int>.from(_dataBuffer.getRange(0, i));
            _dataBuffer.removeRange(0, i + 1);

            if (msgData.isEmpty) {
              i = -1;
              continue;
            }

            final msgStr = utf8.decode(msgData, allowMalformed: false);
            _responses.add(Response.fromJson(msgStr));
            i = -1;
          }
        },
        onError: (_) => dispose(),
        onDone: dispose,
        cancelOnError: true,
      );

      if (refreshSession) {
        await controlRefreshSession(this);
      }

      if (!_connections.isClosed) {
        _connections.add(this);
      }
      if (!_connectCompleter.isCompleted) {
        _connectCompleter.complete(this);
      }
    } catch (error, stackTrace) {
      if (!_connectCompleter.isCompleted) {
        _connectCompleter.completeError(error, stackTrace);
      }
      dispose();
    }
  }

  void changePass(String pass) {
    this.pass = pass;
    if (pass.isNotEmpty) {
      _cipher = RC4(utf8.encode(pass));
    } else {
      _cipher = null;
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _socket?.close();
    _responses.close();
    _connections.close();
    free();
  }

  bool isDisposed() => _disposed;

  void free() {
    if (resource != null) {
      resource.release();
      resource = null;
    }
  }

  bool isFree() => resource == null;

  Future<Connection> onConnect() => _connectCompleter.future;

  bool isValid() => _socket != null && !_disposed;

  Future<Response> request(Request req) async {
    if (_socket == null) {
      await onConnect();
    }
    final response = _awaitResponse(req.id);
    _writeRequest(req);
    final res = await response;
    res.validate();
    return res;
  }

  void _writeRequest(Request req) {
    final socket = _socket;
    if (socket == null) {
      throw const SocketException('SpiceAPI websocket is not connected.');
    }

    final jsonEncoded = utf8.encode('${req.toJson()}\x00');
    _cipher?.crypt(jsonEncoded);
    socket.add(jsonEncoded);
  }

  Future<Response> _awaitResponse(int id) {
    return _responses.stream
        .where((res) => res.id == id)
        .first
        .timeout(_timeout);
  }
}
