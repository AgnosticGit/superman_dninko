import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class Signaling {
  Signaling(
    this.localRenderer,
    this.remoteRenderer,
  );

  Map<String, dynamic> configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  final RTCVideoRenderer remoteRenderer;
  final RTCVideoRenderer localRenderer;

  late final RTCPeerConnection peerConnection;

  late final MediaStream localStream;
  MediaStream? remoteStream;

  // final host = '192.168.56.1:9545';
  final host = '94.41.19.174:9545';

  Future<void> initConnection() async {
    peerConnection = await createPeerConnection(configuration);
    peerConnection.onAddStream = (stream) {
      remoteStream = stream;
      remoteRenderer.srcObject = stream;
    };
    peerConnection.onTrack = (event) async {
      remoteStream ??= await createLocalMediaStream('remoteStream');
      event.streams[0].getTracks().forEach((track) => remoteStream!.addTrack(track));
    };
    peerConnection.onIceGatheringState = (state) => log(state.toString());
    peerConnection.onIceConnectionState = (state) => log(state.toString());

    final userMedia = await navigator.mediaDevices.getUserMedia({
      'video': true,
      'audio': false,
    });
    localStream = userMedia;
    localStream.getTracks().forEach((track) => peerConnection.addTrack(track, localStream));
    localRenderer.srcObject = userMedia;
  }

  Future<void> createRoom() async {
    log('Создание комнаты');
    await Dio().post(
      'http://$host/write/answer',
      options: Options(headers: {"Content-Type": "application/json"}),
      data: {'1': '1'},
    );

    final data = await _createRoom();

    log('Комната создана');

    await Dio().post(
      'http://$host/write/creator',
      options: Options(headers: {"Content-Type": "application/json"}),
      data: data,
    );

    log('Комната записана на сервер');

    while (true) {
      try {
        final response = await Dio().get(
          'http://$host/read/answer',
          options: Options(headers: {"Content-Type": "application/json"}),
        );

        log('Ждем ответа');
        if (response.data.containsKey('calleeCandidates')) {
          final rawCalleeCandidates = response.data['calleeCandidates'] as List<dynamic>;
          final calleeCandidates = rawCalleeCandidates.map(
            (e) => RTCIceCandidate(e['candidate'], e['sdpMid'], e['sdpMLineIndex']),
          );

          for (final c in calleeCandidates) {
            peerConnection.addCandidate(c);
          }

          if (calleeCandidates.isNotEmpty) {
            log('Ответ получен');
            final answer = RTCSessionDescription(
              response.data['answer']['sdp'],
              response.data['answer']['type'],
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
    final offerData = await Dio().get(
      'http://$host/read/creator',
      options: Options(headers: {"Content-Type": "application/json"}),
    );
    log('Подключаемся к комнате');
    final offer = RTCSessionDescription(
      offerData.data['offer']['sdp'],
      offerData.data['offer']['type'],
    );

    await peerConnection.setRemoteDescription(offer);
    final answerData = await _joinRoom(offerData.data);

    await Dio().post(
      'http://$host/write/answer',
      options: Options(headers: {"Content-Type": "application/json"}),
      data: answerData,
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
      log("Caller candidate");
      log(candidate.toString());
    };

    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    offerData['offer'] = offer.toMap();

    // while (true) {
    //   if (await peerConnection.getIceGatheringState() ==
    //       RTCIceGatheringState.RTCIceGatheringStateComplete) {
    //     break;
    //   }
    await Future.delayed(Duration(seconds: 1));
    // }
    print(offerData['callerCandidates'].length);

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
      log("Answer candidate");
      log(candidate.toString());
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

    // while (true) {
    //   if (await peerConnection.getIceGatheringState() ==
    //       RTCIceGatheringState.RTCIceGatheringStateComplete) {
    //     break;
    //   }
    await Future.delayed(Duration(seconds: 1));
    // }
    return answerData;
  }
}
