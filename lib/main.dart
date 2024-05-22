import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:webrtc_test/signaling.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final signaling = Signaling();
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  String? roomId;
  final textEditingController = TextEditingController(text: '');

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await signaling.init();

      _localRenderer.initialize();
      _remoteRenderer.initialize();

      signaling.onAddRemoteStream = ((stream) {
        log('Stream!!!!!');
        log(stream.toString());
        _remoteRenderer.srcObject = stream;
        log(stream.id);
        log(stream.getVideoTracks().length.toString());
        setState(() {});
      });

      signaling.openUserMedia(_localRenderer, _remoteRenderer);

      Timer.periodic(Duration(seconds: 1), (_) {
        setState(() {});
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: 28),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () async {
                  await signaling.createRoom(_remoteRenderer);
                  setState(() {});
                },
                child: Text("Create room"),
              ),
              ElevatedButton(
                onPressed: () {
                  signaling.joinRoom(_remoteRenderer);
                },
                child: Text("Join room"),
              ),
              ElevatedButton(
                onPressed: () {
                  signaling.hangUp(_localRenderer);
                },
                child: Text("Hangup"),
              )
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all()),
                      child: RTCVideoView(_localRenderer, mirror: true),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all()),
                      child: RTCVideoView(_remoteRenderer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: TextFormField(
                    controller: textEditingController,
                  ),
                )
              ],
            ),
          ),
          SizedBox(height: 8)
        ],
      ),
    );
  }
}
