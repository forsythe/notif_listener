import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:android_notification_listener2/android_notification_listener2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

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
  RefreshController _refreshController =
      RefreshController(initialRefresh: true);

  final max32BitInt = pow(2, 31) - 1;

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

    _refreshNotificationDisplayList();
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
    final List<RegExp> ignoreWhatsappMsgs = [
      RegExp(r"^\d+ messages from \d+ chats$"),
      RegExp(r"^\d+ new messages$"),
      RegExp(r"^Checking for new messages$")
    ];

    if (event.packageName != "com.whatsapp" ||
        ignoreWhatsappMsgs.any((re) => re.hasMatch(event.packageMessage))) {
      return;
    }
    _showNotificationWithoutSound(
        event.timeStamp, event.packageText, event.packageMessage);

    _refreshNotificationDisplayList();
  }

  void _refreshNotificationDisplayList() {
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.getActiveNotifications()
        ?.then((value) => setState(() {
              _notifs = value;
            }))
        ?.whenComplete(() => {
              if (_refreshController.isRefresh)
                _refreshController.refreshCompleted()
              else if (_refreshController.isLoading)
                _refreshController.loadComplete()
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
    final DateFormat dateFormatter = DateFormat('MMM dd, K:mm:ss a');

    await flutterLocalNotificationsPlugin.show(
      hashValues((timestamp.millisecondsSinceEpoch / 1000).hashCode,
          title.hashCode, content.hashCode),
      title,
      "[" + dateFormatter.format(timestamp) + "] " + content,
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
      darkTheme: ThemeData.dark(),
      home: Scaffold(
          appBar: AppBar(
            title: const Text('WhatsApp Notification Replayer'),
          ),
          body: Scrollbar(
            child: SmartRefresher(
              enablePullDown: true,
              enablePullUp: false,
              controller: _refreshController,
              onRefresh: () => _refreshNotificationDisplayList(),
              child: filteredNotifs.isEmpty
                  ? (Center(
                      child: Text("No displayed notifications"),
                    ))
                  : ListView.builder(
                      itemCount: filteredNotifs.length,
                      itemBuilder: (context, index) {
                        var titleString = filteredNotifs[index].title;
                        var bodyString = filteredNotifs[index].body;
                        final RegExp parseBodyRegex =
                            RegExp(r"^\[(.*), (\d+:\d+)(:.*)(AM|PM)\] (.*)");
                        var parsedBody = parseBodyRegex.allMatches(bodyString);
                        var hmTime = parsedBody.first.group(2);
                        var amPm = parsedBody.first.group(4);
                        var contentString = parsedBody.first.group(5);

                        return Card(
                          child: ListTile(
                            visualDensity: VisualDensity.comfortable,
                            leading: Text(titleString),
                            title: Text(contentString.toString()),
                            trailing: Tooltip(
                              child: Text(
                                  hmTime.toString() + " " + amPm.toString()),
                              message: "Received " +
                                  RegExp(r"^\[(.*)\](.*)")
                                      .allMatches(bodyString)
                                      .first
                                      .group(1),
                            ),
                            dense: false,
                          ),
                        );
                      }),
            ),
          )),
    );
  }
}
