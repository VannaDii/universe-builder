import 'package:flutter/material.dart';

final _leaveRequests = Expando<Future<void> Function()>(
  'editor leave requests',
);

/// Lets URL navigation await the same save-before-leave action used by Back.
/// Forms keep their existing validation, failure retention and pop behavior.
Future<bool> leaveRoute(NavigatorState navigator, Route<dynamic> route) async {
  final leave = _leaveRequests[route];
  if (leave == null) {
    await navigator.maybePop();
    return !route.isCurrent;
  }
  await leave();
  return !route.isCurrent;
}

class GuardedPopScope<T> extends StatefulWidget {
  const GuardedPopScope({
    super.key,
    required this.canPop,
    required this.onLeave,
    this.onBackground,
    this.onPopInvokedWithResult,
    required this.child,
  });
  final bool canPop;
  final Future<void> Function() onLeave;

  /// Request private input persistence before focus/suspension. This neither
  /// navigates nor admits canonical work; the editor retains save failures.
  final Future<void> Function()? onBackground;
  final PopInvokedWithResultCallback<T>? onPopInvokedWithResult;
  final Widget child;
  @override
  State<GuardedPopScope<T>> createState() => _GuardedPopScopeState<T>();
}

class _GuardedPopScopeState<T> extends State<GuardedPopScope<T>>
    with WidgetsBindingObserver {
  ModalRoute<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _route?.isActive == true) {
      widget.onBackground?.call().ignore();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route != null) _leaveRequests[_route!] = () => widget.onLeave();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) _leaveRequests[_route!] = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<T>(
    canPop: widget.canPop,
    onPopInvokedWithResult: widget.onPopInvokedWithResult,
    child: widget.child,
  );
}
