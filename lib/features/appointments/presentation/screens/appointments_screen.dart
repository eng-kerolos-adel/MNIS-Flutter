import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/appointment_models.dart';
import '../../../../core/providers/data_providers.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/services/app_permissions_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/utils/providers.dart';
import '../../../../core/utils/shared_widgets.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/responsive_center.dart';

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  AppointmentType? _filterType;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final apptsAsync = ref.watch(appointmentsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(l.appointmentsTitle),
        leading: IconButton(
          icon: Icon(isAr ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRequestSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.requestAppointment),
      ),
      body: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(appointmentsProvider);
            await ref.read(appointmentsProvider.future).catchError((_) => <AppointmentModel>[]);
          },
          child: AsyncValueView<List<AppointmentModel>>(
            value: apptsAsync,
            isAr: isAr,
            onRetry: () => ref.invalidate(appointmentsProvider),
            builder: (context, list) {
              final filtered = _filterType == null
                  ? list
                  : list.where((a) => a.type == _filterType).toList();

              return ResponsiveCenter(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(isAr ? 'الكل (${list.length})' : 'All (${list.length})'),
                              selected: _filterType == null,
                              onSelected: (_) => setState(() => _filterType = null),
                            ),
                            ChoiceChip(
                              avatar: const Icon(Icons.local_hospital_rounded, size: 16),
                              label: Text(
                                '${l.appointmentTypeClinic} (${list.where((a) => a.type == AppointmentType.clinic).length})',
                              ),
                              selected: _filterType == AppointmentType.clinic,
                              onSelected: (_) => setState(() => _filterType = AppointmentType.clinic),
                            ),
                            ChoiceChip(
                              avatar: const Icon(Icons.biotech_rounded, size: 16),
                              label: Text(
                                '${l.appointmentTypeLab} (${list.where((a) => a.type == AppointmentType.lab).length})',
                              ),
                              selected: _filterType == AppointmentType.lab,
                              onSelected: (_) => setState(() => _filterType = AppointmentType.lab),
                            ),
                            ChoiceChip(
                              avatar: const Icon(Icons.radar_rounded, size: 16),
                              label: Text(
                                '${l.appointmentTypeRadiology} (${list.where((a) => a.type == AppointmentType.radiology).length})',
                              ),
                              selected: _filterType == AppointmentType.radiology,
                              onSelected: (_) => setState(() => _filterType = AppointmentType.radiology),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                const SizedBox(height: 60),
                                EmptyState(
                                  icon: Icons.event_busy_rounded,
                                  message: list.isEmpty
                                      ? l.appointmentsEmpty
                                      : (isAr
                                          ? 'لا توجد مواعيد مسجلة في هذا التصنيف'
                                          : 'No appointments in this category'),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _AppointmentTile(
                                l: l,
                                cs: cs,
                                isAr: isAr,
                                appt: filtered[i],
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openRequestSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RequestAppointmentSheet(),
    );
  }
}

class _AppointmentTile extends ConsumerWidget {
  final AppLocalizations l;
  final ColorScheme cs;
  final bool isAr;
  final AppointmentModel appt;
  const _AppointmentTile({
    required this.l,
    required this.cs,
    required this.isAr,
    required this.appt,
  });

  ({String label, Color bg, Color fg}) _style() {
    switch (appt.status) {
      case AppointmentStatus.confirmed:
        return (
          label: l.statusConfirmed(isAr),
          bg: cs.tertiaryContainer.withOpacity(0.5),
          fg: cs.onTertiaryContainer,
        );
      case AppointmentStatus.rejected:
        return (
          label: l.statusRejected(isAr),
          bg: cs.errorContainer,
          fg: cs.onErrorContainer,
        );
      case AppointmentStatus.cancelled:
        return (
          label: l.statusCancelled(isAr),
          bg: cs.surfaceContainerHigh,
          fg: cs.onSurfaceVariant,
        );
      case AppointmentStatus.completed:
        return (
          label: l.statusCompleted(isAr),
          bg: cs.secondaryContainer.withOpacity(0.5),
          fg: cs.onSecondaryContainer,
        );
      case AppointmentStatus.requested:
        return (
          label: l.statusRequested(isAr),
          bg: cs.surfaceContainerHigh,
          fg: cs.secondary,
        );
    }
  }

  IconData _typeIcon() {
    switch (appt.type) {
      case AppointmentType.clinic:
        return Icons.local_hospital_rounded;
      case AppointmentType.lab:
        return Icons.biotech_rounded;
      case AppointmentType.radiology:
        return Icons.radar_rounded;
    }
  }

  String _typeLabel() {
    switch (appt.type) {
      case AppointmentType.clinic:
        return l.appointmentTypeClinic;
      case AppointmentType.lab:
        return l.appointmentTypeLab;
      case AppointmentType.radiology:
        return l.appointmentTypeRadiology;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat.yMMMd(isAr ? 'ar' : 'en').add_Hm();
    final s = _style();
    final date = appt.scheduledAt ?? appt.preferredDate;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                StatusBadge(label: s.label, backgroundColor: s.bg, textColor: s.fg, fontSize: 10),
                const SizedBox(width: 6),
                StatusBadge(
                  label: _typeLabel(),
                  backgroundColor: cs.primaryContainer.withOpacity(0.5),
                  textColor: cs.onPrimaryContainer,
                  fontSize: 10,
                ),
                const SizedBox(width: 4),
                Icon(_typeIcon(), size: 14, color: cs.onSurfaceVariant),
              ]),
              Text(df.format(date), style: AppTypography.labelMd.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if ((appt.type == AppointmentType.lab || appt.type == AppointmentType.radiology) &&
              appt.testPanel != null)
            Text(appt.testPanel!, style: AppTypography.headlineSm.copyWith(color: cs.primary), textAlign: TextAlign.right),
          Text(appt.reason, style: AppTypography.bodyMd.copyWith(color: cs.onSurface), textAlign: TextAlign.right),
          if (appt.doctorName != null &&
              (appt.doctorName!.ar.isNotEmpty || appt.doctorName!.en.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    appt.doctorSpeciality != null &&
                            (appt.doctorSpeciality!.ar.isNotEmpty ||
                                appt.doctorSpeciality!.en.isNotEmpty)
                        ? '${appt.doctorName!.pick(Locale(isAr ? 'ar' : 'en'))} • ${appt.doctorSpeciality!.pick(Locale(isAr ? 'ar' : 'en'))}'
                        : appt.doctorName!.pick(Locale(isAr ? 'ar' : 'en')),
                    style: AppTypography.labelSm.copyWith(color: cs.secondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.medical_services_rounded, size: 13, color: cs.secondary),
              ],
            ),
          ],
          if (appt.facilityName != null &&
              (appt.facilityName!.ar.isNotEmpty || appt.facilityName!.en.isNotEmpty)) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    appt.facilityName!.pick(Locale(isAr ? 'ar' : 'en')),
                    style: AppTypography.labelSm.copyWith(color: cs.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(_typeIcon(), size: 13, color: cs.primary),
              ],
            ),
          ],
          if (appt.note != null && appt.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(appt.note!, style: AppTypography.labelSm.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.right),
          ],
          if (appt.isCancellable) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l.cancelAppointment),
                      content: Text(l.cancelAppointmentConfirm),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.notNow)),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.cancelAppointment)),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  try {
                    await ref.read(repositoryProvider).cancelAppointment(appt.id);
                    ref.invalidate(appointmentsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.appointmentCancelled)));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(friendlyError(e, isAr: isAr))));
                    }
                  }
                },
                icon: Icon(Icons.close_rounded, size: 16, color: cs.error),
                label: Text(l.cancelAppointment, style: AppTypography.labelMd.copyWith(color: cs.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestAppointmentSheet extends ConsumerStatefulWidget {
  const _RequestAppointmentSheet();

  @override
  ConsumerState<_RequestAppointmentSheet> createState() => _RequestAppointmentSheetState();
}

class _RequestAppointmentSheetState extends ConsumerState<_RequestAppointmentSheet> {
  final _reasonCtrl = TextEditingController();
  final _testPanelCtrl = TextEditingController();
  final _providerSearchCtrl = TextEditingController();
  String _providerSearch = '';
  AppointmentType _type = AppointmentType.clinic;
  DateTime? _date;
  String? _doctorId;
  String? _labId;
  List<String> _slots = const [];
  String? _selectedTime;
  bool _loadingSlots = false;
  bool _busy = false;
  bool _detectingGeo = true;
  LiveGeoContext? _geoContext;
  LiveGeoFailure? _geoFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_detectGeo());
  }

  Future<void> _detectGeo() async {
    if (mounted) {
      setState(() {
        _detectingGeo = true;
        _geoFailure = null;
      });
    }
    final res = await LocationService.instance
        .detectLiveLocation(ref.read(repositoryProvider));
    if (!mounted) return;
    setState(() {
      _detectingGeo = false;
      _geoContext = res.context;
      _geoFailure = res.failure;
      _doctorId = null;
      _labId = null;
      _slots = const [];
      _selectedTime = null;
    });
  }

  Future<void> _openDirections(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static const _commonLabPanels = [
    'Complete Blood Count (CBC)',
    'HbA1c & Fasting Glucose',
    'Liver & Kidney Function (LFT/KFT)',
    'Lipid Profile',
    'Thyroid Profile (TSH/FT4)',
  ];

  static const _commonRadiologyStudies = [
    'Chest X-Ray (أشعة عادية على الصدر)',
    'CT Scan (أشعة مقطعية)',
    'MRI Scan (رنين مغناطيسي)',
    'Abdominal Ultrasound (سونار بطن وحوض)',
    'Echocardiogram (إيكو ودوبلر على القلب)',
  ];

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _testPanelCtrl.dispose();
    _providerSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDoctorSlots() async {
    if (_type != AppointmentType.clinic || _doctorId == null || _date == null) {
      if (mounted) setState(() => _slots = const []);
      return;
    }
    final d = _date!;
    final dateYmd =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() {
      _loadingSlots = true;
      _selectedTime = null;
    });
    try {
      final list = await ref.read(repositoryProvider).doctorSlots(_doctorId!, dateYmd);
      if (mounted) {
        setState(() {
          _slots = list;
          if (list.isNotEmpty) _selectedTime = list.first;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _slots = const []);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final isAr = ref.read(localeProvider).languageCode == 'ar';
    void warn(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    if (_type == AppointmentType.clinic && _doctorId == null) {
      warn(isAr ? 'اختر العيادة والطبيب أولاً' : 'Please choose a clinic & physician');
      return;
    }
    if (_type == AppointmentType.lab && _labId == null) {
      warn(isAr ? 'اختر معمل التحاليل أولاً' : 'Please choose a medical analysis lab');
      return;
    }
    if (_type == AppointmentType.radiology && _labId == null) {
      warn(isAr ? 'اختر مركز الأشعة أولاً' : 'Please choose a radiology center');
      return;
    }
    if ((_type == AppointmentType.lab || _type == AppointmentType.radiology) &&
        _testPanelCtrl.text.trim().isEmpty) {
      warn(
        _type == AppointmentType.radiology
            ? (isAr ? 'حدد نوع الأشعة المطلوبة' : 'Please enter the required imaging study')
            : (isAr ? 'حدد نوع التحليل المطلوب' : 'Please enter the required lab test panel'),
      );
      return;
    }
    if (_date == null) {
      warn(isAr ? 'اختر التاريخ المفضل للحجز' : 'Please pick a preferred date');
      return;
    }
    if (_reasonCtrl.text.trim().length < 3) {
      warn(isAr ? 'اكتب سبب الحجز باختصار (3 أحرف على الأقل)' : 'Please enter a short booking reason');
      return;
    }

    setState(() => _busy = true);
    try {
      final isLabOrRad = _type == AppointmentType.lab || _type == AppointmentType.radiology;
      await ref.read(repositoryProvider).requestAppointment(
            preferredDate: _date!,
            preferredTime: _type == AppointmentType.clinic ? _selectedTime : null,
            reason: _reasonCtrl.text.trim(),
            doctorId: _type == AppointmentType.clinic ? _doctorId : null,
            labId: isLabOrRad ? _labId : null,
            type: _type,
            testPanel: isLabOrRad ? _testPanelCtrl.text.trim() : null,
          );
      ref.invalidate(appointmentsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.appointmentRequestSent)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, isAr: isAr))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final loc = Locale(isAr ? 'ar' : 'en');
    final geo = _geoContext;
    final GeoScopeArgs? geoArgs = geo == null
        ? null
        : (
            lat: geo.latitude,
            lng: geo.longitude,
            governorate: geo.governorateCode,
            strictGeo: true,
          );
    final doctorsAsync = geoArgs == null
        ? const AsyncValue<List<DoctorOption>>.data(<DoctorOption>[])
        : ref.watch(geoDoctorsProvider(geoArgs));
    final labsAsync = geoArgs == null
        ? const AsyncValue<List<LabFacilityOption>>.data(<LabFacilityOption>[])
        : ref.watch(geoLabsProvider(geoArgs));
    final isRadiologyTab = _type == AppointmentType.radiology;
    final isAnalysisTab = _type == AppointmentType.lab;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.requestAppointment, style: AppTypography.headlineMd.copyWith(color: cs.onSurface)),
                const SizedBox(height: 14),
                Text(l.chooseAppointmentType, style: AppTypography.labelLg.copyWith(color: cs.onSurface)),
                const SizedBox(height: 8),
                SegmentedButton<AppointmentType>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: AppointmentType.clinic,
                      icon: const Icon(Icons.local_hospital_rounded, size: 17),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(l.appointmentTypeClinic, maxLines: 1),
                      ),
                    ),
                    ButtonSegment(
                      value: AppointmentType.lab,
                      icon: const Icon(Icons.biotech_rounded, size: 17),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(l.appointmentTypeLab, maxLines: 1),
                      ),
                    ),
                    ButtonSegment(
                      value: AppointmentType.radiology,
                      icon: const Icon(Icons.radar_rounded, size: 17),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(l.appointmentTypeRadiology, maxLines: 1),
                      ),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) {
                    setState(() {
                      _type = s.first;
                      _doctorId = null;
                      _labId = null;
                      _slots = const [];
                      _selectedTime = null;
                      _providerSearch = '';
                      _providerSearchCtrl.clear();
                      _testPanelCtrl.clear();
                    });
                    if (_type == AppointmentType.clinic) _fetchDoctorSlots();
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _type == AppointmentType.clinic
                            ? Icons.support_agent_rounded
                            : isRadiologyTab
                                ? Icons.radar_rounded
                                : Icons.biotech_rounded,
                        size: 18,
                        color: cs.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _type == AppointmentType.clinic
                              ? (isAr
                                  ? 'يعرض هذا القسم العيادات الخارجية فقط؛ ويُرسل الحجز لمساعد الطبيب لتأكيد الموعد.'
                                  : 'Shows outpatient Clinics only; request goes directly to the clinic assistant.')
                              : isRadiologyTab
                                  ? (isAr
                                      ? 'يعرض هذا القسم مراكز ومعامل الأشعة فقط؛ لتأكيد موعد الأشعة التشخيصية مباشرة.'
                                      : 'Shows Radiology & Imaging centers only for diagnostic scan bookings.')
                                  : (isAr
                                      ? 'يعرض هذا القسم معامل التحاليل الطبية فقط؛ لتأكيد الموعد وإصدار باركود العينة.'
                                      : 'Shows Medical Analysis Labs only to confirm your booking and issue sample barcode.'),
                          style: AppTypography.labelSm.copyWith(color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _geoFailure != null
                        ? cs.errorContainer.withOpacity(0.55)
                        : cs.primaryContainer.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_geoFailure != null ? cs.error : cs.primary)
                          .withOpacity(0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _detectingGeo
                                ? Icons.my_location_rounded
                                : _geoFailure != null
                                    ? Icons.location_off_rounded
                                    : Icons.location_on_rounded,
                            size: 18,
                            color:
                                _geoFailure != null ? cs.error : cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _detectingGeo
                                  ? (isAr
                                      ? 'جارٍ تحديد موقعك الجغرافي الفعلي لمطابقة أقرب العيادات...'
                                      : 'Detecting your live GPS location to match nearby providers...')
                                  : _geoFailure != null
                                      ? (isAr
                                          ? _geoFailure!.messageAr
                                          : _geoFailure!.messageEn)
                                      : (isAr
                                          ? 'موقعك الفعلي الآن: ${geo!.governorateAr} — تظهر العيادات والمعامل في نطاق موقعك الحالي فقط (بصرف النظر عن عنوان البطاقة)'
                                          : 'Live GPS Area: ${geo!.governorateEn} — strictly showing doctors & labs at your current location'),
                              style: AppTypography.labelSm.copyWith(
                                color: _geoFailure != null
                                    ? cs.onErrorContainer
                                    : cs.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _detectingGeo ? null : _detectGeo,
                            tooltip:
                                isAr ? 'تحديث الموقع' : 'Refresh GPS',
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                          ),
                        ],
                      ),
                      if (_geoFailure != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _detectGeo,
                              icon: const Icon(Icons.my_location_rounded,
                                  size: 16),
                              label: Text(
                                isAr ? 'تحديد الموقع الآن' : 'Enable / Retry GPS',
                              ),
                            ),
                            if (_geoFailure!.openLocationSettings)
                              OutlinedButton(
                                onPressed: () async {
                                  await Geolocator.openLocationSettings();
                                  await _detectGeo();
                                },
                                child: Text(isAr
                                    ? 'إعدادات GPS'
                                    : 'Location Settings'),
                              ),
                            if (_geoFailure!.openAppSettings)
                              OutlinedButton(
                                onPressed: () async {
                                  await AppPermissionsService.instance
                                      .openDeviceSettings();
                                  await _detectGeo();
                                },
                                child: Text(isAr
                                    ? 'صلاحيات التطبيق'
                                    : 'App Permissions'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_type == AppointmentType.clinic && geo != null) ...[
                  Text(
                    isAr ? 'اختر العيادة والطبيب المعالج' : 'Choose Clinic & Physician',
                    style: AppTypography.labelLg.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _providerSearchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: isAr
                          ? 'ابحث باسم العيادة أو الطبيب أو التخصص...'
                          : 'Filter by clinic, physician, or specialty...',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _providerSearch = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  doctorsAsync.when(
                    data: (doctors) {
                      final clinicDocs = doctors.where((d) => d.isClinicOnly).toList();
                      final filteredDocs = _providerSearch.isEmpty
                          ? clinicDocs
                          : clinicDocs
                              .where((d) =>
                                  '${d.name.en} ${d.name.ar} ${d.speciality.en} ${d.speciality.ar} ${d.facility.en} ${d.facility.ar}'
                                      .toLowerCase()
                                      .contains(_providerSearch))
                              .toList();
                      final selectedVal =
                          filteredDocs.any((d) => d.id == _doctorId) ? _doctorId : null;
                      final chosenDoc = selectedVal == null
                          ? null
                          : filteredDocs
                              .where((d) => d.id == selectedVal)
                              .firstOrNull;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: selectedVal,
                            hint: Text(
                              filteredDocs.isEmpty
                                  ? (isAr
                                      ? 'لا توجد عيادة في نطاق موقعك الحالي'
                                      : 'No clinics in your current GPS area')
                                  : (isAr
                                      ? '— اختر من عيادات ${geo.governorateAr} القريبة —'
                                      : '— Select Clinic in ${geo.governorateEn} —'),
                            ),
                            items: [
                              for (final d in filteredDocs)
                                DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    '${d.name.pick(loc)} — ${d.speciality.pick(loc)}${d.distanceKm != null ? ' (${d.distanceKm!.toStringAsFixed(1)} ${isAr ? "كم" : "km"})' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              setState(() => _doctorId = v);
                              _fetchDoctorSlots();
                            },
                          ),
                          if (chosenDoc != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.pin_drop_outlined,
                                      size: 16, color: cs.secondary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (chosenDoc.facility.pick(loc).isNotEmpty)
                                          chosenDoc.facility.pick(loc),
                                        if (chosenDoc.formattedAddress(isAr).isNotEmpty)
                                          chosenDoc.formattedAddress(isAr),
                                        if (chosenDoc.distanceKm != null)
                                          '${chosenDoc.distanceKm!.toStringAsFixed(1)} ${isAr ? "كم من موقعك" : "km away"}',
                                      ].join(' • '),
                                      style: AppTypography.labelSm,
                                    ),
                                  ),
                                  if (chosenDoc.latitude != null &&
                                      chosenDoc.longitude != null)
                                    TextButton.icon(
                                      onPressed: () => _openDirections(
                                          chosenDoc.latitude,
                                          chosenDoc.longitude),
                                      icon: const Icon(Icons.directions_rounded,
                                          size: 16),
                                      label: Text(
                                          isAr ? 'خرائط' : 'Map'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => Text(
                      isAr ? 'تعذر تحميل قائمة العيادات' : 'Could not load clinics list',
                      style: AppTypography.labelSm.copyWith(color: cs.error),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if ((isAnalysisTab || isRadiologyTab) && geo != null) ...[
                  Text(
                    isRadiologyTab
                        ? (isAr ? 'اختر معمل / مركز الأشعة المسجل' : 'Choose Registered Radiology Center')
                        : (isAr ? 'اختر معمل التحاليل المسجل بالمنظومة' : 'Choose Registered Analysis Laboratory'),
                    style: AppTypography.labelLg.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _providerSearchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: isRadiologyTab
                          ? (isAr ? 'ابحث باسم مركز الأشعة أو الفرع...' : 'Filter by radiology center or branch...')
                          : (isAr ? 'ابحث باسم معمل التحاليل أو الفرع...' : 'Filter by analysis lab name or branch...'),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _providerSearch = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  labsAsync.when(
                    data: (labs) {
                      final typeScopedLabs = labs
                          .where((l) => isRadiologyTab ? l.isRadiology : l.isAnalysis)
                          .toList();
                      final filteredLabs = _providerSearch.isEmpty
                          ? typeScopedLabs
                          : typeScopedLabs
                              .where((l) =>
                                  '${l.name.en} ${l.name.ar} ${l.staffName.en} ${l.staffName.ar}'
                                      .toLowerCase()
                                      .contains(_providerSearch))
                              .toList();
                      final selectedLab =
                          filteredLabs.any((l) => l.id == _labId) ? _labId : null;
                      final chosenLab = selectedLab == null
                          ? null
                          : filteredLabs
                              .where((l) => l.id == selectedLab)
                              .firstOrNull;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: selectedLab,
                            hint: Text(
                              filteredLabs.isEmpty
                                  ? (isRadiologyTab
                                      ? (isAr ? 'لا يوجد مركز أشعة في نطاق موقعك' : 'No radiology centers in area')
                                      : (isAr ? 'لا يوجد معمل تحاليل في نطاق موقعك' : 'No analysis labs in area'))
                                  : (isRadiologyTab
                                      ? (isAr ? '— مراكز الأشعة في ${geo.governorateAr} —' : '— Radiology Centers in ${geo.governorateEn} —')
                                      : (isAr ? '— معامل التحاليل في ${geo.governorateAr} —' : '— Analysis Labs in ${geo.governorateEn} —')),
                            ),
                            items: [
                              for (final lab in filteredLabs)
                                DropdownMenuItem(
                                  value: lab.id,
                                  child: Text(
                                    '${lab.name.pick(loc)}${lab.distanceKm != null ? ' (${lab.distanceKm!.toStringAsFixed(1)} ${isAr ? "كم" : "km"})' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _labId = v),
                          ),
                          if (chosenLab != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.pin_drop_outlined,
                                      size: 16, color: cs.secondary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (chosenLab.formattedAddress(isAr).isNotEmpty)
                                          chosenLab.formattedAddress(isAr),
                                        if (chosenLab.distanceKm != null)
                                          '${chosenLab.distanceKm!.toStringAsFixed(1)} ${isAr ? "كم من موقعك" : "km away"}',
                                      ].join(' • '),
                                      style: AppTypography.labelSm,
                                    ),
                                  ),
                                  if (chosenLab.latitude != null &&
                                      chosenLab.longitude != null)
                                    TextButton.icon(
                                      onPressed: () => _openDirections(
                                          chosenLab.latitude,
                                          chosenLab.longitude),
                                      icon: const Icon(Icons.directions_rounded,
                                          size: 16),
                                      label: Text(isAr ? 'خرائط' : 'Map'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => Text(
                      isRadiologyTab
                          ? (isAr ? 'تعذر تحميل قائمة مراكز الأشعة' : 'Could not load radiology centers list')
                          : (isAr ? 'تعذر تحميل قائمة معامل التحاليل' : 'Could not load analysis laboratories list'),
                      style: AppTypography.labelSm.copyWith(color: cs.error),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isRadiologyTab ? l.radiologyStudyLabel : l.testPanelLabel,
                    style: AppTypography.labelLg.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final panel in (isRadiologyTab ? _commonRadiologyStudies : _commonLabPanels))
                        ActionChip(
                          label: Text(panel, style: AppTypography.labelSm),
                          onPressed: () => setState(() => _testPanelCtrl.text = panel),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _testPanelCtrl,
                    maxLength: 120,
                    decoration: InputDecoration(
                      hintText: isRadiologyTab ? l.radiologyStudyHint : l.testPanelHint,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(l.appointmentReasonLabel, style: AppTypography.labelLg.copyWith(color: cs.onSurface)),
                const SizedBox(height: 6),
                TextField(controller: _reasonCtrl, maxLength: 300, maxLines: 2),
                const SizedBox(height: 8),
                Text(l.preferredDateLabel, style: AppTypography.labelLg.copyWith(color: cs.onSurface)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 120)),
                      initialDate: now.add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                      _fetchDoctorSlots();
                    }
                  },
                  icon: Icon(Icons.calendar_month_rounded, color: cs.primary),
                  label: Text(
                    _date == null ? l.preferredDateLabel : DateFormat.yMMMd(isAr ? 'ar' : 'en').format(_date!),
                  ),
                ),
                if (_type == AppointmentType.clinic && _doctorId != null && _date != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    isAr ? 'المواعيد المتاحة في جدول العيادة المختارة:' : 'Clinic Available Time Slots:',
                    style: AppTypography.labelLg.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 6),
                  if (_loadingSlots)
                    const LinearProgressIndicator()
                  else if (_slots.isEmpty)
                    Text(
                      isAr ? 'لا توجد فترات متاحة في هذا اليوم — اختر يوماً آخر' : 'No open slots on this date',
                      style: AppTypography.labelSm.copyWith(color: cs.onSurfaceVariant),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in _slots)
                          ChoiceChip(
                            label: Text(s),
                            selected: _selectedTime == s,
                            onSelected: (sel) => setState(() => _selectedTime = sel ? s : null),
                          ),
                      ],
                    ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : Text(l.submitRequest),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
