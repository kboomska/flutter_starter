import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:sizzle_starter/src/core/rest_client/rest_client.dart';

final class RestClientHttp extends RestClientBase {
  RestClientHttp({required super.baseUrl, required this.client});

  /// Http client
  final http.Client client;

  /// Send  request
  @protected
  @visibleForTesting
  Future<Map<String, Object?>?> sendRequest({
    required String path,
    required String method,
    Map<String, Object?>? body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) async {
    try {
      final uri = buildUri(path: path, queryParams: queryParams);

      final request = http.Request(method, uri);

      if (headers != null) {
        request.headers.addAll(headers);
      }

      if (body != null) {
        request.body = encodeBody(body);
      }

      final response = await client.send(request);

      final result = await response.stream.bytesToString();

      return decodeResponse(result, statusCode: response.statusCode);
    } on RestClientException {
      rethrow;
    } on Object catch (e, stack) {
      Error.throwWithStackTrace(
        ClientException(message: e.toString(), cause: e),
        stack,
      );
    }
    // on DioException catch (e) {
    //   if (e.type == DioExceptionType.connectionError ||
    //       e.type == DioExceptionType.sendTimeout ||
    //       e.type == DioExceptionType.receiveTimeout) {
    //     Error.throwWithStackTrace(
    //       ConnectionException(
    //         message: 'ConnectionException',
    //         statusCode: e.response?.statusCode,
    //         cause: e,
    //       ),
    //       e.stackTrace,
    //     );
    //   }
    //   if (e.response != null) {
    //     final result = await decodeResponse(
    //       e.response?.data,
    //       statusCode: e.response?.statusCode,
    //     );

    //     return result;
    //   }
    //   Error.throwWithStackTrace(
    //     ClientException(
    //       message: e.toString(),
    //       statusCode: e.response?.statusCode,
    //       cause: e,
    //     ),
    //     e.stackTrace,
    //   );
    // }
  }

  @override
  Future<Map<String, Object?>?> delete(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) =>
      sendRequest(
        path: path,
        method: 'DELETE',
        headers: headers,
        queryParams: queryParams,
      );

  @override
  Future<Map<String, Object?>?> get(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) =>
      sendRequest(
        path: path,
        method: 'GET',
        headers: headers,
        queryParams: queryParams,
      );

  @override
  Future<Map<String, Object?>?> patch(
    String path, {
    required Map<String, Object?> body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) =>
      sendRequest(
        path: path,
        method: 'PATCH',
        body: body,
        headers: headers,
        queryParams: queryParams,
      );

  @override
  Future<Map<String, Object?>?> post(
    String path, {
    required Map<String, Object?> body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) =>
      sendRequest(
        path: path,
        method: 'POST',
        body: body,
        headers: headers,
        queryParams: queryParams,
      );

  @override
  Future<Map<String, Object?>?> put(
    String path, {
    required Map<String, Object?> body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
  }) =>
      sendRequest(
        path: path,
        method: 'PUT',
        body: body,
        headers: headers,
        queryParams: queryParams,
      );
}
