import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  Signaling(
    this.localStream,
    this.onAddRemoteStream,
  );

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

  final MediaStream localStream;
  final StreamStateCallback onAddRemoteStream;

  late final RTCPeerConnection peerConnection;
  MediaStream? remoteStream; // Обновлено для предотвращения повторной инициализации

  // String host = '192.168.56.1:9545';
  String host = '94.41.19.174:9545';

  Future<void> initConnection() async {
    peerConnection = await createPeerConnection(configuration);
    registerPeerConnectionListeners();
    localStream.getTracks().forEach((track) => peerConnection.addTrack(track, localStream));
    peerConnection.onTrack = (event) async {
      log('Event!');
      remoteStream ??= await createLocalMediaStream('remoteStream');
      event.streams[0].getTracks().forEach((track) => remoteStream!.addTrack(track));
      onAddRemoteStream(remoteStream!);
    };
  }

  Future<void> createRoom() async {
    log('ЧТО ТО ПРОИСХОДИТ');
    await http.post(
      Uri.parse('http://$host/write/answer'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({'': ''}),
    );

    final data = await _createRoom();

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

  Future<void> joinRoom() async {
    final offerData = await http.get(
      Uri.parse('http://$host/read/creator'),
    );

    final body = jsonDecode(offerData.body);
    final offer = RTCSessionDescription(
      body['offer']['sdp'],
      body['offer']['type'],
    );

    await peerConnection.setRemoteDescription(offer);

    final answerData = await _joinRoom(body);

    await http.post(
      Uri.parse('http://$host/write/answer'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(answerData),
    );
  }

  Future<Map<String, dynamic>> _createRoom() async {
    final Map<String, dynamic> offerData = {
      'callerCandidates': <Map<String, dynamic>>[],
      'offer': <Map<String, dynamic>>{},
    };

    peerConnection.onIceCandidate = (candidate) {
      final callerCandidates = offerData['callerCandidates'] as List<Map<String, dynamic>>;
      callerCandidates.add(candidate.toMap());
    };

    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    offerData['offer'] = offer.toMap();

    await Future.delayed(Duration(seconds: 1));

    return offerData;
  }

  Future<Map<String, dynamic>> _joinRoom(Map<String, dynamic> offerData) async {
    final Map<String, dynamic> answerData = {
      'calleeCandidates': <Map<String, dynamic>>[],
      'answer': <Map<String, dynamic>>{},
    };

    peerConnection.onIceCandidate = (candidate) {
      final callerCandidates = answerData['calleeCandidates'] as List<Map<String, dynamic>>;
      callerCandidates.add(candidate.toMap());
    };

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

  void registerPeerConnectionListeners() {
    peerConnection.onIceGatheringState = (state) {
      log('ICE gathering state changed: $state');
    };

    peerConnection.onConnectionState = (state) {
      log('Connection state change: $state');
    };

    peerConnection.onSignalingState = (state) {
      log('Signaling state change: $state');
    };

    peerConnection.onIceConnectionState = (state) {
      log('ICE connection state change: $state');
    };

    peerConnection.onAddStream = (stream) {
      log("Add remote stream");
      if (remoteStream == null) {
        remoteStream = stream;
        onAddRemoteStream(remoteStream!);
      }
    };
  }
}
