## 0.0.1

* **Initial release** - A comprehensive Flutter widget that provides pull-to-refresh functionality for any content
* **Multi-future support** - Handle multiple asynchronous operations concurrently with a single refresh action
* **Universal compatibility** - Works with any widget type (ScrollView, non-scrollable content, custom widgets)
* **Smart scrollable detection** - Automatically wraps non-scrollable content to enable pull-to-refresh
* **Customizable refresh indicator** - Support for custom colors, background, displacement, and stroke width
* **Custom indicator widget** - Option to provide completely custom refresh indicator instead of default
* **Adaptive design** - Uses platform-appropriate refresh indicators (iOS/Android)
* **Loading state management** - Built-in loading and error state handling with reactive notifications
* **Flexible notification handling** - Customizable scroll notification predicates for refresh triggering
* **Two widget variants** - Main `AnyRefreshableWidget` for multiple futures and `AnyRefreshableWidget.single` for single operations
* **Error handling** - Captures and exposes the first error encountered during refresh operations
* **Animation support** - Smooth animations for custom indicators with built-in animation controller
