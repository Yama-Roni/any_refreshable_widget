import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:any_refreshable_widget/any_refreshable_widget.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final pages = [
      _singleRefreshableWidget(),
      _multiRefreshableWidget(),
      _refreshWithCustomIndicator(),
      _refreshWithCustomWidget(),
      _refreshWithErrorCallback(),
      _refreshWithBeforeAfterCallback(),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text('Refreshable Widget'),
        ),
        body: PageView.builder(
          itemCount: pages.length,
          itemBuilder: (context, index) {
            return pages[index];
          },
        ),
      ),
    );
  }
}

/// Single Refreshable Widget
Widget _singleRefreshableWidget() {
  return AnyRefreshableWidget.single(
    onRefresh: () async {
      await Future.delayed(const Duration(seconds: 2));
    },
    builder: (context, isLoading, error) {
      return Center(child: Text('Single Refreshable Widget'));
    },
  );
}

/// Multi Refreshable Widget
Widget _multiRefreshableWidget() {
  return AnyRefreshableWidget(
    onRefresh: [
      () => Future.delayed(const Duration(seconds: 1)),
      () => Future.delayed(const Duration(seconds: 1)),
    ],
    builder: (context, isLoading, error) {
      return Center(child: Text('Multi Refreshable Widget'));
    },
  );
}

/// Refresh with Custom Indicator
Widget _refreshWithCustomIndicator() {
  return AnyRefreshableWidget.single(
    onRefresh: () async {
      await Future.delayed(const Duration(seconds: 2));
    },
    customIndicator: const Center(child: CircularProgressIndicator()),
    builder: (context, isLoading, error) {
      return Center(child: Text('Refresh with Custom Indicator'));
    },
  );
}

/// Refresh with Custom Widget
Widget _refreshWithCustomWidget() {
  return AnyRefreshableWidget.single(
    onRefresh: () async {
      await Future.delayed(const Duration(seconds: 2));
    },
    builder: (context, isLoading, error) {
      return isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(child: Text('Refresh with Custom Widget'));
    },
  );
}

/// Refresh with Error Callback
Widget _refreshWithErrorCallback() {
  return AnyRefreshableWidget.single(
    onRefresh: () async {
      await Future.delayed(const Duration(seconds: 2));
      throw Exception('Error');
    },
    builder: (context, isLoading, error) {
      return error != null
          ? const Center(child: Text('Error Widget!!!'))
          : Center(child: Text('Refresh with Error Callback'));
    },
  );
}

/// Refresh with Before After Callback
Widget _refreshWithBeforeAfterCallback() {
  return AnyRefreshableWidget.single(
    onBeforeRefresh: () {
      log('onBeforeRefresh');
    },
    onRefresh: () async {
      await Future.delayed(const Duration(seconds: 2));
    },
    onAfterRefresh: () {
      log('onAfterRefresh');
    },
    builder: (context, isLoading, error) {
      return Center(child: Text('Refresh with Before After Callback'));
    },
  );
}
