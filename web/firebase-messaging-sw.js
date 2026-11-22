/* Firebase Cloud Messaging Service Worker for MNIS Citizen Web */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC-D89IBFC6Ad1XGq3zeWcNdpFUUhDNKDM',
  authDomain: 'mnis-egypt-dev.firebaseapp.com',
  projectId: 'mnis-egypt-dev',
  storageBucket: 'mnis-egypt-dev.firebasestorage.app',
  messagingSenderId: '994868849909',
  appId: '1:994868849909:web:e340a60fe0d820a27b29bc',
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const title = data.titleAr || payload.notification?.title || 'MNIS';
  const body = data.bodyAr || payload.notification?.body || '';
  return self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    data,
  });
});
