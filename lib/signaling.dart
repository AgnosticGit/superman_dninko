import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;

import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          "stun:stun.l.google.com:19302",
          "stun:stun1.l.google.com:19302",
          "stun:stun2.l.google.com:19302",
          "stun:stun3.l.google.com:19302",
          "stun:stun4.l.google.com:19302"
        ]
      }
    ]
  };

  late RTCPeerConnection peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;
  String? currentRoomText;
  StreamStateCallback? onAddRemoteStream;
  // String host = '192.168.56.1:9545';
  String host = '94.41.19.174:9545';

  Future<void> init() async {
    peerConnection = await createPeerConnection(configuration);
    registerPeerConnectionListeners();
  }

  Future<void> createRoom(RTCVideoRenderer remoteRenderer) async {
    log('ЧТО ТО ПРОИСХОДИТ');
    await http.post(
      Uri.parse('http://$host/write/answer'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({'': ''}),
    );

    final data = await _createRoom(remoteRenderer);

    log('Комната создана');

    await http.post(
      Uri.parse('http://$host/write/creator'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    log('Комната записана на сервак');

    while (true) {
      try {
        final data = await http.get(
          Uri.parse('http://$host/read/answer'),
        );

        log('Получение ответа');

        if (data.body.contains('calleeCandidates')) {
          final body = jsonDecode(data.body);
          final rawCalleeCandidates = body['calleeCandidates'] as List<dynamic>;
          final calleeCandidates = rawCalleeCandidates.map(
            (e) => RTCIceCandidate(e['candidate'], e['sdpMid'], e['sdpMLineIndex']),
          );

          for (final c in calleeCandidates) {
            peerConnection.addCandidate(c);
          }

          if (calleeCandidates.isNotEmpty) {
            log('Ответ получен');
            final body = jsonDecode(data.body);
            final answer = RTCSessionDescription(
              body['answer']['sdp'],
              body['answer']['type'],
            );

            await peerConnection.setRemoteDescription(answer);

            break;
          }
        }

        await Future.delayed(Duration(seconds: 3));
      } catch (e) {
        log(e.toString());
      }
    }
  }

  Future<Map<String, dynamic>> _createRoom(RTCVideoRenderer remoteRenderer) async {
    final Map<String, dynamic> offerData = {
      'callerCandidates': <Map<String, dynamic>>[],
      'offer': <Map<String, dynamic>>{},
    };

    localStream?.getTracks().forEach((track) {
      peerConnection.addTrack(track, localStream!);
    });

    peerConnection.onIceCandidate = (candidate) {
      final callerCandidates = offerData['callerCandidates'] as List<Map<String, dynamic>>;
      callerCandidates.add(candidate.toMap());
    };

    // Add code for creating a room
    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);

    offerData['offer'] = offer.toMap();

    // Created a Room
    peerConnection.onTrack = (event) {
      log(event.toString());
      log('!!!!!!!!!!!!!');
      event.streams[0].getTracks().forEach((track) => remoteStream?.addTrack(track));
    };

    await Future.delayed(Duration(seconds: 1));

    return offerData;
  }

  Future<void> joinRoom(RTCVideoRenderer remoteRenderer) async {
    final offerData = await http.get(
      Uri.parse('http://$host/read/creator'),
    );

    final body = jsonDecode(offerData.body);
    final offer = RTCSessionDescription(
      body['offer']['sdp'],
      body['offer']['type'],
    );

    await peerConnection.setRemoteDescription(offer);

    final answerData = await _joinRoom(body, remoteRenderer);

    await http.post(
      Uri.parse('http://$host/write/answer'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(answerData),
    );
  }

  Future<Map<String, dynamic>> _joinRoom(
    Map<String, dynamic> offerData,
    RTCVideoRenderer remoteVideo,
  ) async {
    final Map<String, dynamic> answerData = {
      'calleeCandidates': <Map<String, dynamic>>[],
      'answer': <Map<String, dynamic>>{},
    };

    localStream?.getTracks().forEach((track) => peerConnection.addTrack(track, localStream!));

    peerConnection.onIceCandidate = (candidate) {
      final callerCandidates = answerData['calleeCandidates'] as List<Map<String, dynamic>>;
      callerCandidates.add(candidate.toMap());
    };

    peerConnection.onTrack = (event) {
      event.streams[0].getTracks().forEach((track) => remoteStream?.addTrack(track));
    };

    // Code for creating SDP answer below
    final offer = offerData['offer'];
    await peerConnection.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);

    answerData['answer'] = {'type': answer.type, 'sdp': answer.sdp};

    final callerCandidates = offerData['callerCandidates'] as List<dynamic>;

    for (final data in callerCandidates) {
      final iceCandidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      peerConnection.addCandidate(iceCandidate);
    }

    await Future.delayed(Duration(seconds: 1));

    return answerData;
  }

  Future<void> openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo,
  ) async {
    final stream = await navigator.mediaDevices.getUserMedia({'video': true, 'audio': false});

    localVideo.srcObject = stream;
    localStream = stream;

    // remoteVideo.srcObject = await createLocalMediaStream('key');
  }

  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    // List<MediaStreamTrack> tracks = localVideo.srcObject!.getTracks();
    // tracks.forEach((track) {
    //   track.stop();
    // });

    // if (remoteStream != null) {
    //   remoteStream!.getTracks().forEach((track) => track.stop());
    // }
    // if (peerConnection != null) peerConnection!.close();

    // if (roomId != null) {
    //   var db = FirebaseFirestore.instance;
    //   var roomRef = db.collection('rooms').doc(roomId);
    //   var calleeCandidates = await roomRef.collection('calleeCandidates').get();
    //   calleeCandidates.docs.forEach((document) => document.reference.delete());

    //   var callerCandidates = await roomRef.collection('callerCandidates').get();
    //   callerCandidates.docs.forEach((document) => document.reference.delete());

    //   await roomRef.delete();
    // }

    // localStream!.dispose();
    // remoteStream?.dispose();
  }

  void registerPeerConnectionListeners() {
    peerConnection.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE gathering state changed: $state');
    };

    peerConnection.onConnectionState = (RTCPeerConnectionState state) {
      print('Connection state change: $state');
    };

    peerConnection.onSignalingState = (RTCSignalingState state) {
      print('Signaling state change: $state');
    };

    peerConnection.onIceGatheringState = (RTCIceGatheringState state) {
      print('ICE connection state change: $state');
    };

    peerConnection.onAddStream = (MediaStream stream) {
      print("Add remote stream");
      onAddRemoteStream?.call(stream);
      remoteStream = stream;
    };
  }
}

Future<void> _waitForIceCompletion(RTCPeerConnection peerConnection) async {
  final completer = Completer<void>();

  if (peerConnection.iceConnectionState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
    completer.complete();
    return completer.future;
  }

  peerConnection.onIceConnectionState = (state) {
    if (state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  };

  return completer.future;
}
