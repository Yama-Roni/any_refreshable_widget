import 'dart:async';
import 'package:flutter/material.dart';

/// A type-safe callback that can handle both synchronous and asynchronous operations.
///
/// This typedef uses FutureOr<void> which is the proper way to represent a function
/// that can return either void (synchronous) or Future<void> (asynchronous).
/// FutureOr is part of Dart's type system and provides better type safety than dynamic.
typedef FlexibleCallback = FutureOr<void> Function();

/// Defines how multiple futures should be executed during refresh.
enum RefreshConcurrency {
  /// Execute all futures concurrently (in parallel).
  /// This is the default and fastest option as all operations run simultaneously.
  concurrent,

  /// Execute futures sequentially (one after another).
  /// This is useful when futures depend on each other or when you want to limit resource usage.
  sequential,
}

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
          minHeight: mediaQuery.size.height -
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
/// The handler executes all futures according to the specified concurrency mode.
/// By default, futures run sequentially, but can be configured
/// to run concurrently. If any future throws an error, the error is captured and
/// made available through the [error] getter.
class _MultiFutureRefreshHandler<T> extends ChangeNotifier {
  /// List of future functions to execute when refreshing.
  final List<Future<void> Function()> _futureFunctions;

  /// Callback function called before starting the refresh operation.
  /// Can be either synchronous (void) or asynchronous (Future<void>).
  final FlexibleCallback? _onBeforeRefresh;

  /// Callback function called after completing the refresh operation.
  final VoidCallback? _onAfterRefresh;

  /// How the futures should be executed (concurrent or sequential).
  final RefreshConcurrency _concurrency;

  /// Whether the futures are currently being executed.
  bool _isLoading = false;

  /// The first error encountered during execution, if any.
  Object? _error;

  /// Whether this handler has been disposed.
  bool _disposed = false;

  /// Creates a [_MultiFutureRefreshHandler] with the given future functions.
  ///
  /// [futureFunctions] is a list of functions that return futures to be
  /// executed when [initialize] or [refresh] is called.
  /// [onBeforeRefresh] is called before starting the refresh operation.
  /// Can be either synchronous or asynchronous.
  /// [onAfterRefresh] is called after completing the refresh operation.
  /// [concurrency] determines whether futures are executed concurrently or sequentially.
  _MultiFutureRefreshHandler(
    List<Future<void> Function()> futureFunctions, {
    FlexibleCallback? onBeforeRefresh,
    VoidCallback? onAfterRefresh,
    RefreshConcurrency concurrency = RefreshConcurrency.concurrent,
  })  : _futureFunctions = futureFunctions,
        _onBeforeRefresh = onBeforeRefresh,
        _onAfterRefresh = onAfterRefresh,
        _concurrency = concurrency;

  /// Refresh all futures by re-executing them.
  ///
  /// This method executes all futures according to the specified concurrency mode.
  /// It executes all futures and updates the loading and error states.
  Future<void> refresh() async {
    // Call onBeforeRefresh callback before starting the refresh
    if (_onBeforeRefresh != null) {
      await _onBeforeRefresh!.call();
    }

    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      if (_concurrency == RefreshConcurrency.concurrent) {
        // Execute all futures concurrently using Future.wait
        final futures = _futureFunctions.map((fn) => fn()).toList();
        await Future.wait(futures);
      } else {
        // Execute futures sequentially one by one
        for (int i = 0; i < _futureFunctions.length; i++) {
          if (_disposed) return;
          await _futureFunctions[i]();
        }
      }
    } catch (e) {
      if (!_disposed) {
        _error = e;
      }
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _safeNotifyListeners();

        // Call onAfterRefresh callback after completing the refresh
        _onAfterRefresh?.call();
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
/// AnyRefreshableWidget(
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
class AnyRefreshableWidget<T> extends StatefulWidget {
  /// List of future functions to execute when refreshing.
  ///
  /// All functions in this list will be executed concurrently using
  /// [Future.wait] when a refresh is triggered. Each function should
  /// return a [Future<void>] that completes when its operation is done.
  final List<Future<void> Function()> onRefresh;

  /// Callback function called before starting the refresh operation.
  /// Can be either synchronous (void) or asynchronous (Future<void>).
  final FlexibleCallback? onBeforeRefresh;

  /// Callback function called after completing the refresh operation.
  final VoidCallback? onAfterRefresh;

  /// How the futures should be executed during refresh.
  ///
  /// - [RefreshConcurrency.concurrent]: All futures execute simultaneously
  /// - [RefreshConcurrency.sequential] (default): Futures execute one after another
  final RefreshConcurrency concurrency;

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

  /// Creates a [AnyRefreshableWidget] that handles multiple futures.
  ///
  /// The [onRefresh] list contains all the future functions that will be
  /// executed concurrently when the user pulls to refresh.
  ///
  /// The [builder] function is called to build the widget content based on
  /// the current loading state and any errors that occurred.

  /// The [triggerMode] is used to determine when the refresh indicator should
  /// appear. If null, uses the default trigger mode.
  final RefreshIndicatorTriggerMode? triggerMode;

  const AnyRefreshableWidget({
    super.key,
    required this.onRefresh,
    this.onBeforeRefresh,
    this.onAfterRefresh,
    required this.builder,
    this.concurrency = RefreshConcurrency.sequential,
    this.notificationPredicate,
    this.refreshColor,
    this.backgroundColor,
    this.displacement = 40.0,
    this.strokeWidth = 2.0,
    this.customIndicator,
    this.triggerMode,
  });

  /// Creates a [AnyRefreshableWidget] that handles a single future.
  ///
  /// This is a convenience constructor for cases where you only need to
  /// execute one asynchronous operation on refresh. It's equivalent to
  /// creating a [AnyRefreshableWidget] with a single-item [onRefresh] list.
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
  /// AnyRefreshableWidget.single(
  ///   onRefresh: () => fetchUserData(),
  ///   builder: (context, isLoading, error) {
  ///     if (error != null) return ErrorWidget(error);
  ///     if (isLoading) return LoadingWidget();
  ///     return UserDataWidget();
  ///   },
  /// )
  /// ```
  AnyRefreshableWidget.single({
    super.key,
    required Future<void> Function() onRefresh,
    FlexibleCallback? onBeforeRefresh,
    VoidCallback? onAfterRefresh,
    required Widget Function(BuildContext, bool, Object?) builder,
    this.notificationPredicate,
    this.refreshColor,
    this.backgroundColor,
    this.displacement = 40.0,
    this.strokeWidth = 2.0,
    this.customIndicator,
    this.triggerMode,
  })  : onRefresh = [
          () async {
            await onRefresh();
          },
        ],
        onBeforeRefresh = onBeforeRefresh,
        onAfterRefresh = onAfterRefresh,
        concurrency = RefreshConcurrency
            .sequential, // Single future doesn't need concurrency option
        builder =
            ((context, isLoading, error) => builder(context, isLoading, error));

  @override
  State<AnyRefreshableWidget<T>> createState() =>
      _AnyRefreshableWidgetState<T>();
}

class _AnyRefreshableWidgetState<T> extends State<AnyRefreshableWidget<T>> {
  late _MultiFutureRefreshHandler<T> _handler;

  @override
  void initState() {
    super.initState();
    _handler = _MultiFutureRefreshHandler<T>(
      widget.onRefresh,
      onBeforeRefresh: widget.onBeforeRefresh,
      onAfterRefresh: widget.onAfterRefresh,
      concurrency: widget.concurrency,
    );
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
