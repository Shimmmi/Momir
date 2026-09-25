import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps image downloads running with the screen off.
class ArtDownloadGuard {
  static var _ready = false;

  static void init() {
    if (kIsWeb || !Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'momir_art',
        channelName: 'Скачивание изображений',
        channelDescription: 'Докачка картинок карт',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
      ),
    );
    _ready = true;
  }

  static Future<void> start(String text) async {
    if (!_ready) return;
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) {
      await update(text);
      return;
    }
    await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Скачивание изображений Momir',
      notificationText: text,
      callback: artDownloadCallback,
    );
  }

  static Future<void> update(String text) async {
    if (!_ready) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Скачивание изображений Momir',
      notificationText: text,
    );
  }

  static Future<void> stop() async {
    if (!_ready) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> askBatteryExemption() {
    return FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}

@pragma('vm:entry-point')
void artDownloadCallback() {
  FlutterForegroundTask.setTaskHandler(_ArtHoldHandler());
}

class _ArtHoldHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
