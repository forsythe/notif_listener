import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:android_notification_listener2/android_notification_listener2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AndroidNotificationListener _notifications;
  StreamSubscription<NotificationEventV2> _subscription;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  List<ActiveNotification> _notifs = [];

  final max32BitInt = pow(2, 31) - 1;
  final List<RegExp> ignoreWhatsappMsgs = [
    RegExp(r"^\d+ messages from \d+ chats$"),
    RegExp(r"^\d+ new messages$"),
    RegExp(r"^Checking for new messages$")
  ];

  @override
  void initState() {
    super.initState();
    initPlatformState();

    var initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    var initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: IOSInitializationSettings(),
        macOS: MacOSInitializationSettings());
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      // ignore: missing_return
      onSelectNotification: (payload) {
        showDialog(
          context: context,
          builder: (_) {
            return AlertDialog(
              title: Text("PayLoad"),
              content: Text("Payload : $payload"),
            );
          },
        );
      },
    );
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    startListening();
  }

  void onData(NotificationEventV2 event) {
    print(event);
    print('converting package extra to json');
    var jsonDatax = json.decode(event.packageExtra);

    print(jsonDatax);
    if (event.packageName != "com.whatsapp" ||
        ignoreWhatsappMsgs.any((re) => re.hasMatch(event.packageMessage))) {
      return;
    }
    _showNotificationWithoutSound(
        event.timeStamp, event.packageText, event.packageMessage);

    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.getActiveNotifications()
        ?.then((value) => {
              setState(() {
                _notifs = value;
              })
            });
  }

  void startListening() {
    _notifications = AndroidNotificationListener();
    try {
      _subscription = _notifications.notificationStream.listen(onData);
    } on NotificationExceptionV2 catch (exception) {
      print(exception);
    }
  }

  void stopListening() {
    _subscription.cancel();
  }

  Future _showNotificationWithoutSound(
      DateTime timestamp, String title, String content) async {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'channel_id', 'Grouped Channel', 'Channel for WhatsApp messages',
        playSound: false,
        importance: Importance.max,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''));
    var platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: IOSNotificationDetails(),
        macOS: MacOSNotificationDetails());
    await flutterLocalNotificationsPlugin.show(
      hashValues(timestamp.hashCode, title.hashCode, content.hashCode),
      title,
      "[" + timestamp.toLocal().toString() + "] " + content,
      platformChannelSpecifics,
      payload: 'No_Sound',
    );
  }

  @override
  Widget build(BuildContext context) {
    List<ActiveNotification> filteredNotifs =
        _notifs.where((x) => x.body != null && x.title != null).toList();
    filteredNotifs.sort((x, y) => x.body.compareTo(y.body));
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Notification Replayer'),
          ),
          body: ListView.builder(
              itemCount: filteredNotifs.length,
              itemBuilder: (context, index) => ListTile(
                    title: Text(filteredNotifs[index].title),
                    subtitle: Text(filteredNotifs[index].body),
                  ))),
    );
  }
}
