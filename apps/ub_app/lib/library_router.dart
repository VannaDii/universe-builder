import 'package:flutter/material.dart';

import 'navigation_location.dart';

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
  LibraryLocation? _pending;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  LibraryLocation get currentConfiguration => _location;
  void setLocation(LibraryLocation location) {
    if (_disposed || _location.uri == location.uri) return;
    _location = location;
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(LibraryLocation configuration) async {
    if (_disposed) return;
    if (navigatorKey.currentState?.canPop() == true) {
      _pending = configuration;
      await navigatorKey.currentState!.maybePop();
      return;
    }
    _location = await navigate(configuration);
    if (!_disposed) notifyListeners();
  }

  void childLeft() {
    if (_disposed) return;
    if (navigatorKey.currentState?.canPop() == true || _pending == null) {
      return;
    }
    final target = _pending!;
    _pending = null;
    setNewRoutePath(target);
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
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    WidgetsBinding.instance.addPostFrameCallback((_) => router.childLeft());
  }
}
