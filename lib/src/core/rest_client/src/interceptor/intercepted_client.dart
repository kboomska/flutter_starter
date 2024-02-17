// ignore_for_file: body_might_complete_normally_catch_error, avoid-unnecessary-reassignment, argument_type_not_assignable_to_error_handler

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart';

/// BaseHandler
abstract base class Handler {
  final _completer = Completer<_InterceptorState>();

  void Function()? _processNextInQueue;
}

/// Handler that is used for requests
final class RequestHandler extends Handler {
  /// Creates a new [RequestHandler].
  RequestHandler();

  /// Rejects the request.
  void reject(Object error, {bool next = false}) {
    _completer.completeError(
      _InterceptorState(
        value: error,
        action: next ? _InterceptorAction.next : _InterceptorAction.reject,
      ),
    );
    _processNextInQueue?.call();
  }

  /// Goes to the next interceptor.
  void next(BaseRequest request) {
    _completer.complete(_InterceptorState(value: request));
    _processNextInQueue?.call();
  }

  /// Resolves the request.
  void resolve(Response response, {bool next = false}) {
    _completer.complete(
      _InterceptorState(
        value: response,
        action:
            next ? _InterceptorAction.resolveNext : _InterceptorAction.resolve,
      ),
    );
    _processNextInQueue?.call();
  }
}

/// Handler that is used for responses.
final class ResponseHandler extends Handler {
  /// Creates a new [ResponseHandler].
  ResponseHandler();

  /// Rejects the response.
  void reject(Object error, {bool next = false}) {
    _completer.completeError(
      _InterceptorState(
        value: error,
        action:
            next ? _InterceptorAction.rejectNext : _InterceptorAction.reject,
      ),
    );
    _processNextInQueue?.call();
  }

  /// Resolves the response.
  void resolve(Response response, {bool next = false}) {
    _completer.complete(
      _InterceptorState(
        value: response,
        action:
            next ? _InterceptorAction.resolveNext : _InterceptorAction.resolve,
      ),
    );
    _processNextInQueue?.call();
  }

  /// Goes to the next interceptor.
  void next(Response response) {
    _completer.complete(_InterceptorState(value: response));
    _processNextInQueue?.call();
  }
}

/// Handler that is used for errors.
final class ErrorHandler extends Handler {
  /// Creates a new [ErrorHandler].
  ErrorHandler();

  /// Rejects other interceptors.
  void reject(Object error, {bool next = false}) {
    _completer.completeError(
      _InterceptorState(
        value: error,
        action:
            next ? _InterceptorAction.rejectNext : _InterceptorAction.reject,
      ),
    );
    _processNextInQueue?.call();
  }

  /// Resolves with response.
  void resolve(Response response) {
    _completer.complete(
      _InterceptorState(value: response, action: _InterceptorAction.resolve),
    );
    _processNextInQueue?.call();
  }

  /// Goes to the next interceptor.
  void next(Object error, [StackTrace? stackTrace]) {
    _completer.completeError(_InterceptorState(value: error), stackTrace);
    _processNextInQueue?.call();
  }
}

typedef _Interceptor<T extends Object, H extends Handler> = void Function(
  T value,
  H handler,
);

enum _InterceptorAction {
  next,
  reject,
  rejectNext,
  resolve,
  resolveNext,
}

/// State of interceptor.
final class _InterceptorState {
  const _InterceptorState({
    required this.value,
    this.action = _InterceptorAction.next,
  });

  final _InterceptorAction action;
  final Object value;
}

/// Base class for all clients that intercept requests and responses.
base class InterceptedClient extends BaseClient {
  /// Creates a new [InterceptedClient].
  InterceptedClient({
    required Client inner,
    List<HttpInterceptor>? interceptors,
  })  : _inner = inner,
        _interceptors = interceptors ?? const [];

  final Client _inner;
  final List<HttpInterceptor> _interceptors;

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    var future = Future(() => _InterceptorState(value: request));

    for (final interceptor in _interceptors) {
      future = future.then(
        _requestInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptRequest
              : interceptor.interceptRequest,
        ),
      );
    }

    future = future.then(
      _requestInterceptorWrapper((request, handler) {
        _inner
            .send(request)
            .then(Response.fromStream)
            .then((response) => handler.resolve(response, next: true));
      }),
    );

    for (final interceptor in _interceptors) {
      future = future.then(
        _responseInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptResponse
              : interceptor.interceptResponse,
        ),
      );
    }

    for (final interceptor in _interceptors) {
      future = future.catchError(
        _errorInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptError
              : interceptor.interceptError,
        ),
      );
    }

    return future.then((res) {
      final response = res.value as Response;
      return _convertToStreamed(response);
    }).catchError((Object e, StackTrace stackTrace) {
      final err = e is _InterceptorState ? e.value : e;

      if (e is _InterceptorState) {
        if (e.action == _InterceptorAction.resolve) {
          return _convertToStreamed(e.value as Response);
        }
      }

      Error.throwWithStackTrace(err, stackTrace);
    });
  }

  StreamedResponse _convertToStreamed(Response response) => StreamedResponse(
        ByteStream.fromBytes(response.bodyBytes),
        response.statusCode,
        contentLength: response.contentLength,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        request: response.request,
      );

  // Wrapper for request interceptors to return future.
  FutureOr<_InterceptorState> Function(_InterceptorState)
      _requestInterceptorWrapper(
    _Interceptor<BaseRequest, RequestHandler> interceptor,
  ) =>
          (_InterceptorState state) {
            if (state.action == _InterceptorAction.next) {
              final handler = RequestHandler();
              interceptor(state.value as BaseRequest, handler);
              return handler._completer.future;
            }

            return state;
          };

  // Wrapper for response interceptors to return future.
  FutureOr<_InterceptorState> Function(_InterceptorState)
      _responseInterceptorWrapper(
    _Interceptor<Response, ResponseHandler> interceptor,
  ) =>
          (_InterceptorState state) {
            if (state.action == _InterceptorAction.next ||
                state.action == _InterceptorAction.resolveNext) {
              final handler = ResponseHandler();
              interceptor(state.value as Response, handler);
              return handler._completer.future;
            }

            return state;
          };

  // Wrapper for error interceptors to return future.
  FutureOr<_InterceptorState> Function(_InterceptorState)
      _errorInterceptorWrapper(
    _Interceptor<Object, ErrorHandler> interceptor,
  ) =>
          (Object error) {
            final state = error is _InterceptorState
                ? error
                : _InterceptorState(value: error);

            if (state.action == _InterceptorAction.next ||
                state.action == _InterceptorAction.rejectNext) {
              final handler = ErrorHandler();
              interceptor(state.value, handler);
              return handler._completer.future;
            }

            throw state;
          };
}

/// Interceptor that is used for both requests and responses.
class HttpInterceptor {
  /// Creates a new [HttpInterceptor].
  const HttpInterceptor();

  /// Creates a new [HttpInterceptor] from the given handlers.
  factory HttpInterceptor.fromHandlers({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
    _Interceptor<Object, ErrorHandler>? interceptError,
  }) =>
      _HttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
        interceptError: interceptError,
      );

  /// Intercepts the request and returns a new request.
  void interceptRequest(BaseRequest request, RequestHandler handler) =>
      handler.next(request);

  /// Intercepts the response and returns a new response.
  void interceptResponse(Response response, ResponseHandler handler) =>
      handler.next(response);

  /// Intercepts the error and returns a new error or response.
  void interceptError(Object error, ErrorHandler handler) =>
      handler.next(error);
}

final class _HttpInterceptorWrapper extends HttpInterceptor {
  _HttpInterceptorWrapper({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
    _Interceptor<Object, ErrorHandler>? interceptError,
  })  : _interceptRequest = interceptRequest,
        _interceptResponse = interceptResponse,
        _interceptError = interceptError;

  final _Interceptor<BaseRequest, RequestHandler>? _interceptRequest;
  final _Interceptor<Response, ResponseHandler>? _interceptResponse;
  final _Interceptor<Object, ErrorHandler>? _interceptError;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_interceptRequest != null) {
      _interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    if (_interceptResponse != null) {
      _interceptResponse!(response, handler);
    } else {
      handler.next(response);
    }
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    if (_interceptError != null) {
      _interceptError!(error, handler);
    } else {
      handler.next(error);
    }
  }
}

final class _TaskQueue<T> extends QueueList<T> {
  bool _isRunning = false;
}

/// Pair of value and handler.
typedef _ValueHandler<T extends Object, H extends Handler> = ({
  T value,
  H handler,
});

/// Sequential interceptor is type of [HttpInterceptor] that maintains
/// queues of requests and responses. It is used to intercept requests and
/// responses in the order they were added.
class SequentialHttpInterceptor extends HttpInterceptor {
  /// Creates a new [SequentialHttpInterceptor].
  SequentialHttpInterceptor();

  /// Creates a new [SequentialHttpInterceptor] from the given handlers.
  factory SequentialHttpInterceptor.fromHandlers({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
    _Interceptor<Object, ErrorHandler>? interceptError,
  }) =>
      _SequentialHttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
        interceptError: interceptError,
      );

  final _requestQueue =
      _TaskQueue<_ValueHandler<BaseRequest, RequestHandler>>();
  final _responseQueue = _TaskQueue<_ValueHandler<Response, ResponseHandler>>();
  final _errorQueue = _TaskQueue<_ValueHandler<Object, ErrorHandler>>();

  /// Method that enqueues the request.
  void _interceptRequest(BaseRequest request, RequestHandler handler) =>
      _queuedHandler(_requestQueue, request, handler, interceptRequest);

  /// Method that enqueues the response.
  void _interceptResponse(Response response, ResponseHandler handler) =>
      _queuedHandler(_responseQueue, response, handler, interceptResponse);

  /// Method that enqueues the error.
  void _interceptError(Object error, ErrorHandler handler) => _queuedHandler(
        _errorQueue,
        error,
        handler,
        interceptError,
      );

  void _queuedHandler<T extends Object, H extends Handler>(
    _TaskQueue<_ValueHandler<T, H>> taskQueue,
    T value,
    H handler,
    void Function(T value, H handler) intercept,
  ) {
    final task = (value: value, handler: handler);
    task.handler._processNextInQueue = () {
      if (taskQueue.isNotEmpty) {
        final nextTask = taskQueue.removeFirst();
        intercept(nextTask.value, nextTask.handler);
      } else {
        taskQueue._isRunning = false;
      }
    };

    taskQueue.add(task);

    if (!taskQueue._isRunning) {
      taskQueue._isRunning = true;
      final task = taskQueue.removeFirst();
      intercept(task.value, task.handler);
    }
  }
}

final class _SequentialHttpInterceptorWrapper
    extends SequentialHttpInterceptor {
  _SequentialHttpInterceptorWrapper({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
    _Interceptor<Object, ErrorHandler>? interceptError,
  })  : _$interceptRequest = interceptRequest,
        _$interceptResponse = interceptResponse,
        _$interceptError = interceptError;

  final _Interceptor<BaseRequest, RequestHandler>? _$interceptRequest;
  final _Interceptor<Response, ResponseHandler>? _$interceptResponse;
  final _Interceptor<Object, ErrorHandler>? _$interceptError;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_$interceptRequest != null) {
      _$interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    if (_$interceptResponse != null) {
      _$interceptResponse!(response, handler);
    } else {
      handler.next(response);
    }
  }

  @override
  void interceptError(Object error, ErrorHandler handler) {
    if (_$interceptError != null) {
      _$interceptError!(error, handler);
    } else {
      handler.next(error);
    }
  }
}
