import 'dart:convert';

class Request {
  static int _lastID = 0;

  final int id;
  final String module;
  final String function;
  final List<Object?> params;

  Request(this.module, this.function, {int? id})
    : id = _nextId(id),
      params = <Object?>[];

  static int _nextId(int? id) {
    if (id == null) {
      if (++_lastID >= 0x100000000) {
        _lastID = 1;
      }
      return _lastID;
    } else {
      _lastID = id;
      return id;
    }
  }

  String toJson() => jsonEncode(<String, Object?>{
    'id': id,
    'module': module,
    'function': function,
    'params': params,
  });

  void addParam(Object? param) {
    params.add(param);
  }
}

class Response {
  final String json;
  final int id;
  final List<Object?> errors;
  final List<Object?> data;

  Response.fromJson(this.json)
    : assert(json.isNotEmpty),
      id = (jsonDecode(json) as Map<String, dynamic>)['id'] as int,
      errors = List<Object?>.from(
        ((jsonDecode(json) as Map<String, dynamic>)['errors'] as List?) ??
            const <Object?>[],
      ),
      data = List<Object?>.from(
        ((jsonDecode(json) as Map<String, dynamic>)['data'] as List?) ??
            const <Object?>[],
      );

  void validate() {
    if (errors.isNotEmpty) {
      throw APIError(errors.first.toString());
    }
  }

  List<Object?> getData() => data;

  String toJson() => json;
}

class APIError implements Exception {
  final String cause;

  APIError(this.cause);

  @override
  String toString() => cause;
}

class RC4 {
  int _a = 0;
  int _b = 0;
  final List<int> _sBox = List<int>.generate(256, (index) => index);

  RC4(List<int> key) {
    int j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + _sBox[i] + key[i % key.length]) % 256;
      final tmp = _sBox[i];
      _sBox[i] = _sBox[j];
      _sBox[j] = tmp;
    }
  }

  void crypt(List<int> inData) {
    for (int i = 0; i < inData.length; i++) {
      _a = (_a + 1) % 256;
      _b = (_b + _sBox[_a]) % 256;
      final tmp = _sBox[_a];
      _sBox[_a] = _sBox[_b];
      _sBox[_b] = tmp;
      inData[i] ^= _sBox[(_sBox[_a] + _sBox[_b]) % 256];
    }
  }
}
