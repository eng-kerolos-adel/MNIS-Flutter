import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../network/mnis_repository.dart';

class LiveGeoContext {
  final double latitude;
  final double longitude;
  final String governorateCode;
  final String governorateAr;
  final String governorateEn;

  const LiveGeoContext({
    required this.latitude,
    required this.longitude,
    required this.governorateCode,
    required this.governorateAr,
    required this.governorateEn,
  });
}

class LiveGeoFailure {
  final String messageAr;
  final String messageEn;
  final bool openLocationSettings;
  final bool openAppSettings;

  const LiveGeoFailure({
    required this.messageAr,
    required this.messageEn,
    this.openLocationSettings = false,
    this.openAppSettings = false,
  });
}

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static const _govCentroids = <({String code, String ar, String en, double lat, double lng})>[
    (code: 'CAIRO', ar: 'القاهرة', en: 'Cairo', lat: 30.0444, lng: 31.2357),
    (code: 'GIZA', ar: 'الجيزة', en: 'Giza', lat: 30.0131, lng: 31.2089),
    (code: 'ALEXANDRIA', ar: 'الإسكندرية', en: 'Alexandria', lat: 31.2001, lng: 29.9187),
    (code: 'QALYUBIA', ar: 'القليوبية', en: 'Qalyubia', lat: 30.4591, lng: 31.1786),
    (code: 'SHARKIA', ar: 'الشرقية', en: 'Sharqia', lat: 30.5877, lng: 31.5020),
    (code: 'DAKAHLIA', ar: 'الدقهلية', en: 'Dakahlia', lat: 31.0409, lng: 31.3785),
    (code: 'GHARBIA', ar: 'الغربية', en: 'Gharbia', lat: 30.7865, lng: 31.0004),
    (code: 'MONUFIA', ar: 'المنوفية', en: 'Monufia', lat: 30.5503, lng: 31.0106),
    (code: 'BEHEIRA', ar: 'البحيرة', en: 'Beheira', lat: 31.0420, lng: 30.4690),
    (code: 'KAFR_EL_SHEIKH', ar: 'كفر الشيخ', en: 'Kafr El Sheikh', lat: 31.1107, lng: 30.9388),
    (code: 'DAMIETTA', ar: 'دمياط', en: 'Damietta', lat: 31.4175, lng: 31.8144),
    (code: 'PORT_SAID', ar: 'بورسعيد', en: 'Port Said', lat: 31.2653, lng: 32.3019),
    (code: 'ISMAILIA', ar: 'الإسماعيلية', en: 'Ismailia', lat: 30.5965, lng: 32.2715),
    (code: 'SUEZ', ar: 'السويس', en: 'Suez', lat: 29.9668, lng: 32.5498),
    (code: 'FAYOUM', ar: 'الفيوم', en: 'Faiyum', lat: 29.3084, lng: 30.8428),
    (code: 'BENI_SUEF', ar: 'بني سويف', en: 'Beni Suef', lat: 29.0661, lng: 31.0994),
    (code: 'MINYA', ar: 'المنيا', en: 'Minya', lat: 28.0871, lng: 30.7618),
    (code: 'ASYUT', ar: 'أسيوط', en: 'Asyut', lat: 27.1783, lng: 31.1859),
    (code: 'SOHAG', ar: 'سوهاج', en: 'Sohag', lat: 26.5591, lng: 31.6957),
    (code: 'QENA', ar: 'قنا', en: 'Qena', lat: 26.1551, lng: 32.7160),
    (code: 'LUXOR', ar: 'الأقصر', en: 'Luxor', lat: 25.6872, lng: 32.6396),
    (code: 'ASWAN', ar: 'أسوان', en: 'Aswan', lat: 24.0889, lng: 32.8998),
    (code: 'RED_SEA', ar: 'البحر الأحمر', en: 'Red Sea', lat: 27.2579, lng: 33.8116),
    (code: 'NEW_VALLEY', ar: 'الوادي الجديد', en: 'New Valley', lat: 25.4390, lng: 30.5586),
    (code: 'MATROUH', ar: 'مطروح', en: 'Matrouh', lat: 31.3543, lng: 27.2373),
    (code: 'NORTH_SINAI', ar: 'شمال سيناء', en: 'North Sinai', lat: 31.1321, lng: 33.8033),
    (code: 'SOUTH_SINAI', ar: 'جنوب سيناء', en: 'South Sinai', lat: 27.9158, lng: 34.3299),
  ];

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  ({String code, String ar, String en}) nearestGovernorateOffline(double lat, double lng) {
    var best = _govCentroids.first;
    var bestD = double.infinity;
    for (final g in _govCentroids) {
      final d = _haversine(lat, lng, g.lat, g.lng);
      if (d < bestD) {
        bestD = d;
        best = g;
      }
    }
    return (code: best.code, ar: best.ar, en: best.en);
  }

  Future<({LiveGeoContext? context, LiveGeoFailure? failure})> detectLiveLocation(
    MnisRepository repo,
  ) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return (
        context: null,
        failure: const LiveGeoFailure(
          messageAr: 'خدمة تحديد الموقع (GPS) مغلقة على جهازك. يرجى تشغيلها لعرض الأطباء والمراكز القريبة من موقعك الحالي.',
          messageEn: 'Location services (GPS) are turned off. Please enable GPS to view nearby clinics and centers.',
          openLocationSettings: true,
        ),
      );
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return (
        context: null,
        failure: const LiveGeoFailure(
          messageAr: 'يجب منح التطبيق صلاحية الموقع الجغرافي لعرض العيادات والمعامل في محافظتك الحالية فقط.',
          messageEn: 'Location permission is required to filter doctors and labs to your current area.',
        ),
      );
    }
    if (perm == LocationPermission.deniedForever) {
      return (
        context: null,
        failure: const LiveGeoFailure(
          messageAr: 'صلاحية الموقع مرفوضة دائماً. افتح إعدادات التطبيق وفعّل الموقع الجغرافي.',
          messageEn: 'Location permission is permanently denied. Please allow it in App Settings.',
          openAppSettings: true,
        ),
      );
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final fallback = nearestGovernorateOffline(pos.latitude, pos.longitude);
      try {
        final resolved = await repo.resolveLocation(pos.latitude, pos.longitude);
        return (
          context: LiveGeoContext(
            latitude: pos.latitude,
            longitude: pos.longitude,
            governorateCode: (resolved['governorateCode'] as String?) ?? fallback.code,
            governorateAr: (resolved['governorateAr'] as String?) ?? fallback.ar,
            governorateEn: (resolved['governorateEn'] as String?) ?? fallback.en,
          ),
          failure: null,
        );
      } catch (_) {
        return (
          context: LiveGeoContext(
            latitude: pos.latitude,
            longitude: pos.longitude,
            governorateCode: fallback.code,
            governorateAr: fallback.ar,
            governorateEn: fallback.en,
          ),
          failure: null,
        );
      }
    } catch (_) {
      return (
        context: null,
        failure: const LiveGeoFailure(
          messageAr: 'تعذر قراءة إحداثيات GPS حالياً. تأكد من فتح الموقع وحاول مرة أخرى.',
          messageEn: 'Could not obtain live GPS coordinates. Please retry.',
        ),
      );
    }
  }
}
