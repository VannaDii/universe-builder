import 'package:flutter/material.dart';

import 'navigation_location.dart';
import 'guarded_pop_scope.dart';

final class LibraryRouteParser extends RouteInformationParser<LibraryLocation> {
  const LibraryRouteParser();
  @override
  Future<LibraryLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    try {
      return LibraryLocation.parse(routeInformation.uri);
    } on Object {
      return const LibraryLocation();
    }
  }

  @override
  RouteInformation restoreRouteInformation(LibraryLocation configuration) =>
      RouteInformation(uri: configuration.uri);
}

/// The existing editor Navigator remains responsible for its guarded Back action.
/// Root links are applied after a child screen has left, never by forcibly
/// removing an editor and bypassing its unfinished-input save.
final class LibraryRouter extends RouterDelegate<LibraryLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<LibraryLocation> {
  LibraryRouter({required this.home, required this.navigate}) {
    observer = _LibraryObserver(this);
  }
  final WidgetBuilder home;
  final Future<LibraryLocation> Function(LibraryLocation) navigate;
  late final NavigatorObserver observer;
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  LibraryLocation _location = const LibraryLocation();
  final _routes = <Route<dynamic>>[];
  LibraryLocation _base = const LibraryLocation();
  bool _external = false;
  Future<void> _navigation = Future<void>.value();
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  LibraryLocation get currentConfiguration => _location;
  void setLocation(LibraryLocation location) {
    if (_disposed || _external) return;
    if (location.editor == null && location.record == null) _base = location;
    if (_location.uri == location.uri) return;
    _location = location;
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(LibraryLocation configuration) {
    final result = _navigation.then((_) => _applyRoute(configuration));
    _navigation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _applyRoute(LibraryLocation configuration) async {
    if (_disposed) return;
    _external = true;
    try {
      final navigator = navigatorKey.currentState;
      while (navigator?.canPop() == true && _routes.isNotEmpty) {
        final top = _routes.last;
        if (top.settings.name == configuration.uri.toString()) {
          _location = configuration;
          return;
        }
        if (!await leaveRoute(navigator!, top)) return;
      }
      _location = await navigate(configuration);
      _base = LibraryLocation(
        section: _location.section,
        universe: _location.universe,
      );
    } finally {
      _external = false;
      if (!_disposed) notifyListeners();
    }
  }

  void pushed(Route<dynamic> route) {
    _routes.add(route);
    if (_external || route.settings.name == null) return;
    try {
      setLocation(LibraryLocation.parse(Uri.parse(route.settings.name!)));
    } on Object {
      /* Unmapped dialogs keep their parent location. */
    }
  }

  void popped(Route<dynamic> route) {
    _routes.remove(route);
    if (_external || _disposed) return;
    final names = _routes.reversed
        .map((route) => route.settings.name)
        .whereType<String>();
    LibraryLocation target = _base;
    if (names.isNotEmpty) {
      try {
        target = LibraryLocation.parse(Uri.parse(names.first));
      } on Object {
        /* Root. */
      }
    }
    setLocation(target);
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    observers: [observer],
    pages: [
      MaterialPage<void>(
        key: const ValueKey('library-root'),
        child: Builder(builder: home),
      ),
    ],
    onDidRemovePage: (_) {},
  );
}

final class _LibraryObserver extends NavigatorObserver {
  _LibraryObserver(this.router);
  final LibraryRouter router;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      router.pushed(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      router.popped(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      router.popped(route);
}
