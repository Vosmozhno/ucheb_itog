import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:tour_rental/repositories/session_store.dart';

class FakeResponse {
  const FakeResponse(this.body, {this.status = 200, this.headers = const {}});
  final Object? body;
  final int status;
  final Map<String, List<String>> headers;
}

class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.respond);
  final FutureOr<FakeResponse> Function(RequestOptions request) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = await respond(options);
    return ResponseBody.fromString(
      jsonEncode(result.body),
      result.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...result.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.value, this.demoRole]);
  Map<String, dynamic>? value;
  String? demoRole;
  @override
  Future<Map<String, dynamic>?> read() async => value == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
  @override
  Future<void> write(Map<String, dynamic> data) async {
    value = Map<String, dynamic>.from(jsonDecode(jsonEncode(data)));
  }

  @override
  Future<void> clear() async {
    value = null;
    demoRole = null;
  }

  @override
  Future<String?> readDemoRole() async => demoRole;
}
