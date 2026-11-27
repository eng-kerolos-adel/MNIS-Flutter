import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';

/// Schedules periodic local medication alarms whenever a prescription is
/// dispensed (`RxStatus.dispensed`) and allows testing/updating schedules.
class MedicationReminderService {
  MedicationReminderService._();
  static final MedicationReminderService instance =
      MedicationReminderService._();

  static const AndroidNotificationChannel _medChannel =
      AndroidNotificationChannel(
    'mnis_med_reminders',
    'تنبيهات مواعيد الأدوية',
    description: 'تذكير دوري بمواعيد تناول الأدوية المصروفة من الصيدلية',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(_medChannel);
      await androidImpl?.requestNotificationsPermission();
    } catch (_) {}
  }

  int _alarmId(String reminderId, int slotIndex) {
    final hash = reminderId.hashCode.abs() % 100000;
    return 20000 + (hash * 10) + slotIndex;
  }

  Future<void> syncReminders(
    List<MedicationReminderModel> reminders, {
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await initialize();

    final now = DateTime.now();
    for (final rem in reminders) {
      final active = rem.isActive && rem.endsAt.isAfter(now);
      for (var i = 0; i < 8; i++) {
        final id = _alarmId(rem.id, i);
        if (!active || i >= rem.scheduleTimes.length) {
          await _plugin.cancel(id: id).catchError((_) {});
          continue;
        }
        final parts = rem.scheduleTimes[i].split(':');
        final hh = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
        final mm = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

        final scheduled = _nextInstanceOfTime(hh, mm);
        final loc = Locale(isAr ? 'ar' : 'en');
        final drugLabel = rem.drugName.pick(loc);
        final freqLabel = rem.frequency.pick(loc);
        final title = isAr
            ? '💊 موعد جرعة الدواء: $drugLabel'
            : '💊 Medication Time: $drugLabel';
        final body = isAr
            ? 'الجرعة: ${rem.dose} ($freqLabel) — اضغط لتسجيل أخذ الجرعة'
            : 'Dose: ${rem.dose} ($freqLabel) — Tap to log your dose';

        try {
          await _plugin.zonedSchedule(
            id: id,
            title: title,
            body: body,
            scheduledDate: scheduled,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                _medChannel.id,
                _medChannel.name,
                channelDescription: _medChannel.description,
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: 'PRESCRIPTION_DISPENSED',
          );
        } catch (_) {}
      }
    }
  }

  Future<void> scheduleTestReminderIn5Seconds(
    MedicationReminderModel rem, {
    required bool isAr,
  }) async {
    if (kIsWeb) return;
    await initialize();
    final drugLabel = rem.drugName.pick(Locale(isAr ? 'ar' : 'en'));
    final scheduled =
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));
    try {
      await _plugin.zonedSchedule(
        id: 99000 + (rem.id.hashCode.abs() % 900),
        title: isAr
            ? '💊 تذكير فوري بموعد الدواء: $drugLabel'
            : '💊 Medication Reminder: $drugLabel',
        body: isAr
            ? 'موعد الجرعة (${rem.dose}) — الروشتة المصروفة نشطة'
            : 'Time for your (${rem.dose}) dose from dispensed Rx',
        scheduledDate: scheduled,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _medChannel.id,
            _medChannel.name,
            channelDescription: _medChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'PRESCRIPTION_DISPENSED',
      );
    } catch (_) {}
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
