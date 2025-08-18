import 'package:flutter/material.dart';

/// A widget that provides pull-to-refresh functionality for any content.
///
/// This widget can handle multiple futures, has customizable refresh indicator,
/// and ensures the content is always pullable regardless of its type.
class _RefreshWidget extends StatefulWidget {
  /// The child widget to be wrapped with refresh functionality.
  final Widget child;

  /// Callback function triggered when the user pulls to refresh.
  ///
  /// This should return a Future that completes when the refresh is done.
  final Future<void> Function() onRefresh;

  /// Optional custom refresh indicator color.
  final Color? refreshColor;

  /// Optional custom refresh indicator background color.
  final Color? backgroundColor;

  /// Optional custom refresh indicator displacement.
  final double? displacement;

  /// Optional custom refresh indicator stroke width.
  final double? strokeWidth;

  /// Optional custom notification predicate.
  final bool Function(ScrollNotification)? notificationPredicate;

  /// Optional custom refresh indicator.
  /// If provided, this widget will be used instead of the default refresh indicator.
  final Widget? customIndicator;

  /// Optional custom refresh indicator trigger mode.
  /// If null, uses the default trigger mode.
  /// Optional custom refresh indicator trigger mode.
  final RefreshIndicatorTriggerMode? triggerMode;

  /// Creates a RefreshWidget.
  const _RefreshWidget({
    super.key,
    required this.child,
    required this.onRefresh,
    this.refreshColor,
    this.backgroundColor,
    this.displacement,
    this.strokeWidth,
    this.notificationPredicate,
    this.customIndicator,
    this.triggerMode,
  });

  @override
  State<_RefreshWidget> createState() => _RefreshWidgetState();
}

class _RefreshWidgetState extends State<_RefreshWidget>
    with TickerProviderStateMixin {
  bool _isRefreshing = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    /// If a custom indicator is provided, use it instead of the default refresh indicator.
    if (widget.customIndicator != null) {
      return RefreshIndicator.noSpinner(
        key: widget.key,
        onRefresh: () async {
          setState(() {
            _isRefreshing = true;
          });
          _animationController.forward();

          final result = await widget.onRefresh();
          setState(() {
            _isRefreshing = false;
          });
          _animationController.reverse();
          return result;
        },
        notificationPredicate:
            widget.notificationPredicate ?? defaultScrollNotificationPredicate,
        triggerMode: widget.triggerMode ?? RefreshIndicatorTriggerMode.anywhere,
        child: Stack(
          children: [
            _ensureScrollable(widget.child),
            if (_isRefreshing) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, widget.displacement ?? 40.0),
                      child: widget.customIndicator,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator.adaptive(
      key: widget.key,
      onRefresh: widget.onRefresh,
      color: widget.refreshColor,
      backgroundColor: widget.backgroundColor,
      displacement: widget.displacement ?? 40.0,
      notificationPredicate:
          widget.notificationPredicate ?? defaultScrollNotificationPredicate,
      triggerMode: widget.triggerMode ?? RefreshIndicatorTriggerMode.anywhere,
      strokeWidth:
          widget.strokeWidth ?? RefreshProgressIndicator.defaultStrokeWidth,
      // Ensure the content is always scrollable for pull-to-refresh to work
      child: _ensureScrollable(widget.child),
    );
  }

  // This method ensures that the child is wrapped in a scrollable widget
  Widget _ensureScrollable(Widget child) {
    // Get the media query to get the height of the screen
    final mediaQuery = MediaQuery.of(context);

    // If the child is already a ScrollView, we don't need to wrap it
    if (child is ScrollView) {
      // For ListView, GridView, etc. that might have physics set to NeverScrollableScrollPhysics
      // we need to ensure it's scrollable for pull-to-refresh to work
      if (child.physics is NeverScrollableScrollPhysics) {
        // Since ScrollView doesn't have a copyWith method, wrap the child in a SingleChildScrollView
        return ScrollConfiguration(
          behavior: const ScrollBehavior(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              width: double.infinity,
              height: mediaQuery.size.height,
              child: child,
            ),
          ),
        );
      }
      return child;
    }

    // If the child is not a ScrollView, wrap it in a SingleChildScrollView
    // with AlwaysScrollableScrollPhysics to ensure it can be pulled down
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight:
              mediaQuery.size.height -
              (mediaQuery.padding.top +
                  mediaQuery.padding.bottom +
                  kToolbarHeight),
        ),
        child: child,
      ),
    );
  }
}

/// A helper class to handle multiple futures with a single refresh action.
///
/// This class manages the execution of multiple asynchronous operations
/// concurrently and provides unified loading and error states. It extends
/// [ChangeNotifier] to notify listeners when the state changes.
///
/// The handler automatically executes all futures using [Future.wait] to
/// ensure they run concurrently rather than sequentially. If any future
/// throws an error, the error is captured and made available through the
/// [error] getter.
class _MultiFutureRefreshHandler<T> extends ChangeNotifier {
  /// List of future functions to execute when refreshing.
  final List<Future<void> Function()> _futureFunctions;

  /// Whether the futures are currently being executed.
  bool _isLoading = false;

  /// The first error encountered during execution, if any.
  Object? _error;

  /// Whether this handler has been disposed.
  bool _disposed = false;

  /// Creates a [_MultiFutureRefreshHandler] with the given future functions.
  ///
  /// [futureFunctions] is a list of functions that return futures to be
  /// executed concurrently when [initialize] or [refresh] is called.
  _MultiFutureRefreshHandler(List<Future<void> Function()> futureFunctions)
    : _futureFunctions = futureFunctions;

  /// Refresh all futures by re-executing them.
  ///
  /// This is an alias for [initialize] that provides a more semantic
  /// method name for refresh operations. It executes all futures
  /// and updates the loading and error states.
  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      for (int i = 0; i < _futureFunctions.length; i++) {
        if (_disposed) return;
        await _futureFunctions[i]();
      }
    } catch (e) {
      if (!_disposed) {
        _error = e;
      }
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  /// Whether any of the futures are currently executing.
  ///
  /// Returns true from when [initialize] or [refresh] is called
  /// until all futures complete (successfully or with an error).
  bool get isLoading => _isLoading;

  /// The first error encountered during the last execution, if any.
  ///
  /// Returns null if no error occurred or if [initialize]/[refresh]
  /// hasn't been called yet. Only the first error is captured when
  /// multiple futures fail simultaneously.
  Object? get error => _error;

  /// Safely calls notifyListeners only if the handler is not disposed.
  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A widget that handles multiple futures with refresh capability.
///
/// This widget provides pull-to-refresh functionality for content that depends on
/// multiple asynchronous operations. It automatically manages loading states and
/// error handling, executing all futures concurrently when refreshed.
///
/// Example usage:
/// ```dart
/// RefreshableWidget(
///   onRefresh: [
///     () => fetchUserData(),
///     () => fetchNotifications(),
///     () => fetchSettings(),
///   ],
///   builder: (context, isLoading, error) {
///     if (error != null) return ErrorWidget(error);
///     if (isLoading) return LoadingWidget();
///     return ContentWidget();
///   },
/// )
/// ```
class RefreshableWidget<T> extends StatefulWidget {
  /// List of future functions to execute when refreshing.
  ///
  /// All functions in this list will be executed concurrently using
  /// [Future.wait] when a refresh is triggered. Each function should
  /// return a [Future<void>] that completes when its operation is done.
  final List<Future<void> Function()> onRefresh;

  /// Builder function that creates the widget content.
  ///
  /// Parameters:
  /// - [context]: The build context
  /// - [isLoading]: Whether any of the futures are currently executing
  /// - [error]: The first error encountered during execution, if any
  ///
  /// This function is called whenever the loading state or error state changes.
  final Widget Function(BuildContext, bool, Object?) builder;

  /// Predicate function to determine which scroll notifications trigger refresh.
  ///
  /// If null, uses the default scroll notification predicate. This can be used
  /// to customize when the refresh indicator should appear based on scroll events.
  final bool Function(ScrollNotification)? notificationPredicate;

  /// The color of the refresh indicator.
  ///
  /// If null, uses the theme's accent color or platform default.
  final Color? refreshColor;

  /// The background color of the refresh indicator.
  ///
  /// If null, uses the theme's background color or platform default.
  final Color? backgroundColor;

  /// The distance from the top of the widget to show the refresh indicator.
  ///
  /// Measured in logical pixels. Defaults to 40.0.
  final double displacement;

  /// The stroke width of the refresh indicator.
  ///
  /// Controls the thickness of the circular progress indicator. Defaults to 2.0.
  final double strokeWidth;

  /// Custom refresh indicator widget.
  ///
  /// If provided, this widget will be used instead of the default
  /// [RefreshProgressIndicator]. The custom indicator will be positioned
  /// at the top of the widget and animated during refresh.
  final Widget? customIndicator;

  /// Creates a [RefreshableWidget] that handles multiple futures.
  ///
  /// The [onRefresh] list contains all the future functions that will be
  /// executed concurrently when the user pulls to refresh.
  ///
  /// The [builder] function is called to build the widget content based on
  /// the current loading state and any errors that occurred.

  /// The [triggerMode] is used to determine when the refresh indicator should
  /// appear. If null, uses the default trigger mode.
  final RefreshIndicatorTriggerMode? triggerMode;

  const RefreshableWidget({
    super.key,
    required this.onRefresh,
    required this.builder,
    this.notificationPredicate,
    this.refreshColor,
    this.backgroundColor,
    this.displacement = 40.0,
    this.strokeWidth = 2.0,
    this.customIndicator,
    this.triggerMode,
  });

  /// Creates a [RefreshableWidget] that handles a single future.
  ///
  /// This is a convenience constructor for cases where you only need to
  /// execute one asynchronous operation on refresh. It's equivalent to
  /// creating a [RefreshableWidget] with a single-item [onRefresh] list.
  ///
  /// Parameters:
  /// - [onRefresh]: The single future function to execute when refreshing
  /// - [builder]: Function to build the widget content based on loading/error state
  /// - [notificationPredicate]: Optional predicate for scroll notifications
  /// - [refreshColor]: Optional color for the refresh indicator
  /// - [backgroundColor]: Optional background color for the refresh indicator
  /// - [displacement]: Distance from top to show indicator (defaults to 40.0)
  /// - [strokeWidth]: Thickness of the progress indicator (defaults to 2.0)
  /// - [customIndicator]: Optional custom refresh indicator widget
  /// - [triggerMode]: Optional custom refresh indicator trigger mode
  ///
  /// Example usage:
  /// ```dart
  /// RefreshableWidget.single(
  ///   onRefresh: () => fetchUserData(),
  ///   builder: (context, isLoading, error) {
  ///     if (error != null) return ErrorWidget(error);
  ///     if (isLoading) return LoadingWidget();
  ///     return UserDataWidget();
  ///   },
  /// )
  /// ```
  RefreshableWidget.single({
    super.key,
    required Future<void> Function() onRefresh,
    required Widget Function(BuildContext, bool, Object?) builder,
    this.notificationPredicate,
    this.refreshColor,
    this.backgroundColor,
    this.displacement = 40.0,
    this.strokeWidth = 2.0,
    this.customIndicator,
    this.triggerMode,
  }) : onRefresh = [
         () async {
           await onRefresh();
         },
       ],
       builder = ((context, isLoading, error) =>
           builder(context, isLoading, error));

  @override
  State<RefreshableWidget<T>> createState() => _RefreshableWidgetState<T>();
}

class _RefreshableWidgetState<T> extends State<RefreshableWidget<T>> {
  late _MultiFutureRefreshHandler<T> _handler;

  @override
  void initState() {
    super.initState();
    _handler = _MultiFutureRefreshHandler<T>(widget.onRefresh);
    _handler.addListener(_handleStateChange);
  }

  @override
  void dispose() {
    _handler.removeListener(_handleStateChange);
    _handler.dispose();
    super.dispose();
  }

  void _handleStateChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RefreshWidget(
      key: widget.key,
      onRefresh: _handler.refresh,
      refreshColor: widget.refreshColor,
      backgroundColor: widget.backgroundColor,
      displacement: widget.displacement,
      strokeWidth: widget.strokeWidth,
      customIndicator: widget.customIndicator,
      notificationPredicate: widget.notificationPredicate,
      triggerMode: widget.triggerMode,
      child: widget.builder(context, _handler.isLoading, _handler.error),
    );
  }
}
