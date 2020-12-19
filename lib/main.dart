import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
  static const REPLAYER_MESSAGE = "Replayer is listening...";
  static const GROUPED_CHANNEL_ID = 'grouped_channel_id';
  static const RELOAD_ONGOING_PAYLOAD = 'RELOAD_ONGOING';

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
        print(payload);
        if (payload == RELOAD_ONGOING_PAYLOAD) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            _showOngoingNotification();
          });
        }
      },
    );

    _refreshNotificationDisplayList();
    _showOngoingNotification();
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
        ?.whenComplete(() {
      print("Done refresh list");
      _showOngoingNotification();
      return {
        if (_refreshController.isRefresh)
          _refreshController.refreshCompleted()
        else if (_refreshController.isLoading)
          _refreshController.loadComplete()
      };
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
        GROUPED_CHANNEL_ID, 'Grouped Channel', 'Channel for WhatsApp messages',
        playSound: false,
        importance: Importance.max,
        priority: Priority.high,
        ongoing: false,
        category: "msg",
        styleInformation: BigTextStyleInformation(''));
    var platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: IOSNotificationDetails(),
        macOS: MacOSNotificationDetails());
    final DateFormat dateFormatter = DateFormat('MMM dd, K:mm:ss a');

    await flutterLocalNotificationsPlugin.show(
      hashValues(
        timestamp.year.hashCode,
        timestamp.month.hashCode,
        timestamp.day.hashCode,
        timestamp.hour.hashCode,
        timestamp.minute.hashCode,
        timestamp.second.hashCode,
        title.hashCode,
        content.hashCode,
      ),
      title,
      "[" + dateFormatter.format(timestamp) + "] " + content,
      platformChannelSpecifics,
      payload: "Pressed regular notif",
    );
    _showOngoingNotification();
  }

  void _showOngoingNotification() {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'channel_id_ongoing',
        'Ongoing Grouped Channel',
        'Channel for ongoing alert',
        playSound: false,
        importance: Importance.min,
//        priority: Priority.high,
//        ongoing: true,
        onlyAlertOnce: true,
        styleInformation: BigTextStyleInformation(''),
//        category: "service",
        additionalFlags: Int32List.fromList([0x00000020]) //FLAG_NO_CLEAR
        );
    var platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: IOSNotificationDetails(),
        macOS: MacOSNotificationDetails());
    final DateFormat dateFormatter = DateFormat('MMM dd, K:mm:ss a');

    flutterLocalNotificationsPlugin.show(
      0,
      REPLAYER_MESSAGE,
      "Last updated " + dateFormatter.format(DateTime.now()),
      platformChannelSpecifics,
      payload: RELOAD_ONGOING_PAYLOAD,
    );
  }

  @override
  Widget build(BuildContext context) {
    List<ActiveNotification> filteredNotifs = _notifs
        .where((x) =>
            x.body != null &&
            x.title != null &&
            x.channelId == GROUPED_CHANNEL_ID)
        .toList();
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
                            title: Text(titleString),
                            subtitle: Text(contentString.toString()),
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
