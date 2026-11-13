import 'dart:typed_data';


import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../config.dart';

/// An error from the API, already turned into words the user can read.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}});

  final String message;
  final int? statusCode;

  /// e.g. {"travellers[0].passportNumber": ["Thandi needs a passport number..."]}
  final Map<String, List<String>> fieldErrors;

  bool get isConflict => statusCode == 409;

  /// All messages, field errors first, for showing in a list.
  List<String> get allMessages => [
        ...fieldErrors.values.expand((e) => e),
        if (fieldErrors.isEmpty) message,
      ];

  @override
  String toString() => message;

  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final res = error.response;
      if (res == null) {
        return ApiException(
          error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.receiveTimeout
              ? 'The connection is slow. Please try again.'
              : "We couldn't reach Owen Tours. Check your internet connection and try again.",
        );
      }
      final data = res.data;
      if (data is Map) {
        final detail = (data['detail'] ?? data['title'] ?? 'Something went wrong.').toString();
        final errors = <String, List<String>>{};
        final raw = data['errors'];
        if (raw is Map) {
          raw.forEach((key, value) {
            if (value is List) errors[key.toString()] = value.map((e) => e.toString()).toList();
          });
        }
        return ApiException(detail, statusCode: res.statusCode, fieldErrors: errors);
      }
      if (res.statusCode == 401) return ApiException('Please sign in again.', statusCode: 401);
      if (res.statusCode == 429) return ApiException('Too many tries. Please wait a few minutes.', statusCode: 429);
      return ApiException('Something went wrong (${res.statusCode}). Please try again.', statusCode: res.statusCode);
    }
    return ApiException('Something went wrong. Please try again.');
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'Accept': 'application/json'},
  ));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
    // Attach the Supabase access token (refreshed automatically by supabase_flutter).
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    handler.next(options);
  }));
  return dio;
});

final apiProvider = Provider<Api>((ref) => Api(ref.watch(dioProvider)));

/// Thin wrapper so every call turns errors into [ApiException].
class Api {
  Api(this._dio);
  final Dio _dio;

  Future<T> _run<T>(Future<Response<dynamic>> Function() call, T Function(dynamic data) map) async {
    try {
      final res = await call();
      return map(res.data);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<T> get<T>(String path, T Function(dynamic data) map, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get<dynamic>(path, queryParameters: _clean(query)), map);

  Future<T> post<T>(String path, T Function(dynamic data) map, {Object? body}) =>
      _run(() => _dio.post<dynamic>(path, data: body), map);

  Future<T> put<T>(String path, T Function(dynamic data) map, {Object? body}) =>
      _run(() => _dio.put<dynamic>(path, data: body), map);

  Future<void> delete(String path) => _run(() => _dio.delete<dynamic>(path), (_) {});

  Future<Uint8List> download(String path, {Map<String, dynamic>? query}) => _run(
        () => _dio.get<List<int>>(path, queryParameters: _clean(query), options: Options(responseType: ResponseType.bytes)),
        (data) => Uint8List.fromList(data as List<int>),
      );

  /// Multipart upload with progress (0.0–1.0).
  Future<T> upload<T>(
    String path,
    T Function(dynamic data) map, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const {},
    void Function(double progress)? onProgress,
  }) {
    final form = FormData.fromMap({
      ...fields,
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(contentType)),
    });
    return _run(
      () => _dio.post<dynamic>(path, data: form, onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      }),
      map,
    );
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null || (v is String && v.isEmpty)));
}

// ---------------- JSON helpers ----------------

typedef Json = Map<String, dynamic>;

Json asJson(dynamic v) => Map<String, dynamic>.from(v as Map);

List<T> asList<T>(dynamic v, T Function(Json) map) =>
    (v as List<dynamic>? ?? const []).map((e) => map(asJson(e))).toList();

List<String> asStrings(dynamic v) => (v as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

DateTime? asDate(dynamic v) => v == null ? null : DateTime.parse(v as String);

int asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

int? asIntOrNull(dynamic v) => (v as num?)?.toInt();

class Paged<T> {
  Paged(this.items, this.page, this.totalPages, this.totalCount);
  final List<T> items;
  final int page;
  final int totalPages;
  final int totalCount;

  static Paged<T> fromJson<T>(dynamic data, T Function(Json) map) {
    final j = asJson(data);
    return Paged(asList(j['items'], map), asInt(j['page']), asInt(j['totalPages']), asInt(j['totalCount']));
  }
}
