// Generated from Firebase CLI SDK configs for project: mnis-egypt-dev
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC-D89IBFC6Ad1XGq3zeWcNdpFUUhDNKDM',
    appId: '1:994868849909:web:e340a60fe0d820a27b29bc',
    messagingSenderId: '994868849909',
    projectId: 'mnis-egypt-dev',
    authDomain: 'mnis-egypt-dev.firebaseapp.com',
    storageBucket: 'mnis-egypt-dev.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD-YVdBdOboBi4TqtKXVvHCuLGzIaJxD5Q',
    appId: '1:994868849909:android:0c6d6e96438556437b29bc',
    messagingSenderId: '994868849909',
    projectId: 'mnis-egypt-dev',
    storageBucket: 'mnis-egypt-dev.firebasestorage.app',
  );
}
