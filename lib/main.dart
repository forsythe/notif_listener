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
      RegExp(r"^Checking for new messages$"),
    ];

    if (event.packageName != "com.whatsapp" ||
        event.packageText == "Backup in progress" ||
        ignoreWhatsappMsgs.any((re) => re.hasMatch(event.packageMessage))) {
      return;
    }
    _showNotificationWithoutSound(
        event.timeStamp, event.packageText, event.packageMessage);

    _refreshNotificationDisplayList();
  }

  Future<void> _refreshNotificationDisplayList() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.getActiveNotifications()
        ?.then((value) => setState(() {
              _notifs = value;
            }))
        ?.whenComplete(() async {
      print("Done refresh list");
      await _showOngoingNotification();
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
    final DateFormat dateFormatter = DateFormat('MMM dd,');

    await flutterLocalNotificationsPlugin.show(
      hashValues(
        timestamp.year.hashCode,
        timestamp.month.hashCode,
        timestamp.day.hashCode,
        timestamp.hour.hashCode,
        timestamp.minute.hashCode,
        (timestamp.second ~/ (60 / 12)).hashCode,
        //count incoming messages with same user/content within 5s intervals as same msg
        title.hashCode,
        content.hashCode,
      ),
      title,
      "[" + dateFormatter.add_jms().format(timestamp) + "] " + content,
      platformChannelSpecifics,
      payload: "Pressed regular notif",
    );
    _showOngoingNotification();
  }

  Future<void> _showOngoingNotification() async {
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
    final DateFormat dateFormatter = DateFormat('MMM dd,');

    await flutterLocalNotificationsPlugin.show(
      0,
      REPLAYER_MESSAGE,
      "Last updated " + dateFormatter.add_jms().format(DateTime.now()),
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
          floatingActionButton: filteredNotifs.isEmpty
              ? null
              : FloatingActionButton(
                  tooltip: "Clear all notifications",
                  child: Icon(Icons.delete),
                  onPressed: () async {
                    await flutterLocalNotificationsPlugin.cancelAll();
                    await _refreshNotificationDisplayList();
                  },
                ),
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
                        final RegExp parseBodyRegex = RegExp(
                            r"^\[(.*), (\d+:\d+)(:.*)(AM|PM)\] (.*)",
                            dotAll: true);
                        var parsedBody = parseBodyRegex.allMatches(bodyString);
                        var hmTime = parsedBody.first.group(2);
                        var amPm = parsedBody.first.group(4);
                        var contentString = parsedBody.first.group(5);
                        String receivedTimeString = RegExp(r"^\[(.*)\](.*)")
                            .allMatches(bodyString)
                            .first
                            .group(1);

                        return Card(
                          child: ListTile(
                            visualDensity: VisualDensity.compact,
                            title: Text(titleString),
                            subtitle: Text(
                              contentString.toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing:
                                Text(hmTime.toString() + " " + amPm.toString()),
                            dense: false,
                            onLongPress: () {
                              showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(titleString,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headline6),
                                          SizedBox(
                                            height: 4,
                                          ),
                                          Text(receivedTimeString,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .caption),
                                        ],
                                      ),
                                      content: SingleChildScrollView(
                                          child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(contentString,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyText2),
                                        ],
                                      )),
                                    );
                                  });
                            },
                          ),
                        );
                      }),
            ),
          )),
    );
  }
}
