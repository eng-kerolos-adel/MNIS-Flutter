import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';

@immutable
class LiveQueueSnapshot {
  const LiveQueueSnapshot({
    required this.doctorId,
    required this.facilityKey,
    required this.currentTicketNo,
    required this.waitingCount,
    required this.emergencyWaitingCount,
    required this.updatedAt,
  });

  final String doctorId;
  final String facilityKey;
  final String? currentTicketNo;
  final int waitingCount;
  final int emergencyWaitingCount;
  final DateTime? updatedAt;

  factory LiveQueueSnapshot.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['updatedAt'];
    return LiveQueueSnapshot(
      doctorId: (data['doctorId'] as String?) ?? doc.id,
      facilityKey: (data['facilityKey'] as String?) ?? 'national',
      currentTicketNo: data['currentTicketNo'] as String?,
      waitingCount: (data['waitingCount'] as num?)?.toInt() ?? 0,
      emergencyWaitingCount:
          (data['emergencyWaitingCount'] as num?)?.toInt() ?? 0,
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

@immutable
class UserSignal {
  const UserSignal({
    required this.uid,
    required this.lastEventType,
    required this.unreadCount,
    required this.updatedAt,
  });

  final String uid;
  final String lastEventType;
  final int unreadCount;
  final DateTime? updatedAt;

  factory UserSignal.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['updatedAt'];
    return UserSignal(
      uid: (data['uid'] as String?) ?? doc.id,
      lastEventType: (data['lastEventType'] as String?) ?? '',
      unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0,
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class FirebaseRealtimeService {
  FirebaseRealtimeService._();
  static final FirebaseRealtimeService instance = FirebaseRealtimeService._();

  bool get _canRead =>
      FirebaseBootstrap.isInitialized &&
      FirebaseAuth.instance.currentUser != null;

  Stream<LiveQueueSnapshot?> streamLiveQueue(String doctorId) {
    if (!_canRead || doctorId.isEmpty) {
      return const Stream<LiveQueueSnapshot?>.empty();
    }
    return FirebaseFirestore.instance
        .collection('live_queues')
        .doc(doctorId)
        .snapshots()
        .map((doc) => doc.exists ? LiveQueueSnapshot.fromFirestore(doc) : null)
        .handleError((_) => null);
  }

  Stream<UserSignal?> streamUserSignal(String userId) {
    if (!_canRead || userId.isEmpty) {
      return const Stream<UserSignal?>.empty();
    }
    return FirebaseFirestore.instance
        .collection('user_signals')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? UserSignal.fromFirestore(doc) : null)
        .handleError((_) => null);
  }
}
