// ignore_for_file: lines_longer_than_80_chars, leading_newlines_in_multiline_strings, cascade_invocations, avoid_positional_boolean_parameters

import 'dart:async';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import 'either_adapter.dart';
import 'models/dispatched_triple.dart';
import 'models/triple_model.dart';

///The typedef [Disposer] receive Future<void> Function()
typedef Disposer = Future<void> Function();

///The typedef [TripleCallback] receive void Function(DispatchedTriple triple)
typedef TripleCallback = void Function(DispatchedTriple triple);

final _tripleCallbackList = <TripleCallback>{};

void _execTripleObserver(Triple triple, Type storeType) {
  for (final callback in _tripleCallbackList) {
    callback(
      DispatchedTriple(
        triple,
        storeType,
      ),
    );
  }
}

///[TripleObserver] class
class TripleObserver {
  ///The method [addListener] it's the type void and receive the param callback [TripleCallback]
  static void addListener(TripleCallback callback) {
    _tripleCallbackList.add(callback);
  }

  ///The method [removeListener] it's the type void and receive the param callback [TripleCallback]
  static void removeListener(TripleCallback callback) {
    _tripleCallbackList.remove(callback);
  }

  TripleObserver._();
}

// Triple Inject

///The typedef [TripleResolverCallback] receive TStore Function<TStore extends Object>()
typedef TripleResolverCallback = TStore Function<TStore extends Object>();

TripleResolverCallback? _tripleResolver;

///The function [setTripleResolver] it's the type void and receive the
///param [tripleResolver] it's the type [TripleResolverCallback]
void setTripleResolver(
  TripleResolverCallback tripleResolver,
) =>
    _tripleResolver = tripleResolver;

///The function [getTripleResolver] it's the type [TStore]
TStore getTripleResolver<TStore extends Store>() {
  try {
    if (_tripleResolver != null) {
      final store = _tripleResolver?.call<TStore>();
      if (store is! Store) {
        throw TripleException(
          ''' 
      TRIPLE ERROR!
      Please, add a resolver or set a store.
      exemple:
        ...
        setTripleResolver(<T>() {
          return Modular.get<T>();
        });
    ''',
        );
      }
      return store;
    } else {
      throw TripleException(
        ''' 
      TRIPLE ERROR!
      Please, add a resolver or set a store.
      exemple:
        ...
        setTripleResolver(<T>() {
          return Modular.get<T>();
        });
    ''',
      );
    }
  } on TripleException {
    rethrow;
  }
}

class _MutableObjects<Error extends Object, State extends Object> {
  late Triple<Error, State> triple;
  late Triple<Error, State> lastState;
  CancelableOperation? completerExecution;
  DateTime lastExecution = DateTime.now();

  _MutableObjects(State state) {
    triple = Triple(state: state);
    lastState = Triple(state: state);
  }
}

///[Store] abstract class
@immutable
abstract class Store<Error extends Object, State extends Object> {
  late final _MutableObjects<Error, State> _mutableObjects;

  ///Get the complete triple value;
  Triple<Error, State> get triple => _mutableObjects.triple;

  ///[lastState] it's a get
  Triple<Error, State> get lastState => _mutableObjects.lastState;

  ///Get the [state] value;
  State get state => _mutableObjects.triple.state;

  ///Get loading value;
  bool get isLoading => _mutableObjects.triple.isLoading;

  ///Get [error] value;
  Error? get error => _mutableObjects.triple.error;

  ///[initialState] Start this store with a value defalt.
  Store(State initialState) {
    _mutableObjects = _MutableObjects<Error, State>(initialState);
    initStore();
  }

  ///
  void initStore() {}

  ///IMPORTANT!!!
  ///THIS METHOD TO BE VISIBLE FOR OVERRIDING ONLY!!!
  @visibleForOverriding
  void propagate(Triple<Error, State> triple) {
    _mutableObjects.triple = triple;
    _execTripleObserver(triple, runtimeType);
  }

  ///Change the State value.
  ///
  ///This also stores the state value to be retrieved using the [undo()]
  ///method when using MementoMixin
  @protected
  void update(State newState, {bool force = false}) {
    var candidate = _mutableObjects.triple.copyWith(
      state: newState,
      event: TripleEvent.state,
    );
    candidate = candidate.clearError();
    candidate = middleware(candidate);
    if (force || (candidate.state != _mutableObjects.triple.state)) {
      _mutableObjects.lastState = candidate.copyWith(isLoading: false);
      _mutableObjects.triple = candidate;
      propagate(_mutableObjects.triple);
    }
  }

  ///Change the loading value.
  @protected
  void setLoading(bool newloading, {bool force = false}) {
    var candidate = _mutableObjects.triple.copyWith(
      isLoading: newloading,
      event: TripleEvent.loading,
    );
    candidate = middleware(candidate);
    if (force || (candidate.isLoading != _mutableObjects.triple.isLoading)) {
      _mutableObjects.triple = candidate;
      propagate(_mutableObjects.triple);
    }
  }

  ///Change the error value.
  @protected
  void setError(Error newError, {bool force = false}) {
    var candidate = _mutableObjects.triple.copyWith(error: newError, event: TripleEvent.error);
    candidate = middleware(candidate);
    if (force || (candidate.error != _mutableObjects.triple.error)) {
      _mutableObjects.triple = candidate;
      propagate(_mutableObjects.triple);
    }
  }

  ///called when dispacher [update], [setLoading] or [setError]
  ///overriding to change triple before the propagation;
  Triple<Error, State> middleware(Triple<Error, State> newTriple) {
    return newTriple;
  }

  ///Execute a Future.
  ///
  ///This function is a sugar code used to run a Future in a simple way,
  ///executing [setLoading] and adding to [setError] if
  ///an error occurs in Future
  Future<void> execute(
    Future<State> Function() func, {
    Duration delay = const Duration(
      milliseconds: 50,
    ),
  }) async {
    final localTime = DateTime.now();
    _mutableObjects.lastExecution = localTime;
    await Future.delayed(delay);
    if (localTime != _mutableObjects.lastExecution) {
      return;
    }

    setLoading(true);

    await _mutableObjects.completerExecution?.cancel();

    _mutableObjects.completerExecution = CancelableOperation.fromFuture(
      func(),
    );

    await _mutableObjects.completerExecution!.then(
      (value) {
        if (value is State) {
          setLoading(false);
          update(value, force: true);
        }
      },
      onError: (error, __) {
        if (error is Error) {
          setLoading(false);
          setError(error, force: true);
        } else {
          throw Exception(
            '''is expected a ${Error.toString()} type, and receipt ${error.runtimeType}''',
          );
        }
      },
    ).valueOrCancellation();
  }

  ///Execute a Future Either dartz.
  ///
  ///This function is a sugar code used to run a Future in a simple way,
  ///executing [setLoading] and adding to [setError] if an error
  ///occurs in Either
  Future<void> executeEither(
    Future<EitherAdapter<Error, State>> Function() func, {
    Duration delay = const Duration(
      milliseconds: 50,
    ),
  }) async {
    final localTime = DateTime.now();
    _mutableObjects.lastExecution = localTime;
    await Future.delayed(delay);
    if (localTime != _mutableObjects.lastExecution) {
      return;
    }

    setLoading(true);

    await _mutableObjects.completerExecution?.cancel();

    _mutableObjects.completerExecution = CancelableOperation.fromFuture(
      func(),
    );

    await _mutableObjects.completerExecution!.then(
      (value) {
        if (value is EitherAdapter<Error, State>) {
          setLoading(false);
          value.fold(
            (e) => setError(e, force: true),
            (s) => update(s, force: true),
          );
        }
      },
    ).valueOrCancellation();
  }

  ///Execute a Stream.
  ///
  ///This function is a sugar code used to run a Stream in a simple way,
  ///executing [setLoading] and adding to [setError] if
  ///an error occurs in Stream
  StreamSubscription executeStream(Stream<State> stream) {
    final StreamSubscription sub = stream.listen(
      update,
      onError: (error) => setError(error, force: true),
      onDone: () => setLoading(false),
    );
    return sub;
  }

  ///Discard the store
  Future destroy();

  ///Observer the Segmented State.
  ///
  ///EXAMPLE:
  ///```dart
  ///Disposer disposer = counter.observer(
  ///   onState: (state) => print(state),
  ///   onLoading: (loading) => print(loading),
  ///   onError: (error) => print(error),
  ///);
  ///
  ///dispose();
  ///```
  Disposer observer({
    void Function(State state)? onState,
    void Function(bool isLoading)? onLoading,
    void Function(Error error)? onError,
  });

  ///Represents a value of one of three mapped possibilities.
  ///
  ///EXAMPLE:
  ///```dart
  ///int result = store.when<int>(
  ///                 onState: (state) => state,
  ///                 onLoading: () => 0,
  ///                 onError: (error) => -1,
  ///             );
  ///```
  TReturn when<TReturn>({
    required TReturn Function(State state) onState,
    TReturn Function(bool isLoading)? onLoading,
    TReturn Function(Error error)? onError,
  }) {
    if (triple.event == TripleEvent.loading && onLoading != null && triple.isLoading) {
      return onLoading(triple.isLoading);
    } else if (triple.event == TripleEvent.error && onError != null) {
      return onError(triple.error!);
    } else {
      return onState(triple.state);
    }
  }
}

///[TripleException] class implements [Exception]
class TripleException implements Exception {
  ///The variable [message] it's the type String
  final String message;

  ///[TripleException] constructor class
  TripleException(this.message);

  @override
  String toString() {
    return message;
  }
}
