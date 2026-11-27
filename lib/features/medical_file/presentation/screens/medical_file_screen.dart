import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/models.dart';
import '../../../../core/providers/data_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/providers.dart';
import '../../../../core/utils/shared_widgets.dart';
import '../../../../core/widgets/account_sheet.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/patient_avatar.dart';
import '../../../../core/widgets/responsive_center.dart';

class MedicalFileScreen extends ConsumerWidget {
  const MedicalFileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final isAr = locale.languageCode == 'ar';
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(summaryHubProvider);
            ref.invalidate(timelineProvider);
            await ref.read(profileProvider.future).catchError((_) => null);
          },
          child: CustomScrollView(
            controller: AppRoutes.tabScrollController(1),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: cs.surface.withOpacity(0.9),
                surfaceTintColor: Colors.transparent,
                title: Row(
                  children: [
                    const MnisShieldLogo(size: 28),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MNIS',
                            style: AppTypography.headlineSm
                                .copyWith(color: cs.primary, height: 1)),
                        Text(isAr ? 'الملف الطبي' : 'Medical File',
                            style: AppTypography.labelSm
                                .copyWith(color: cs.onSurface)),
                      ],
                    ),
                  ],
                ),
                actions: [
                  GestureDetector(
                    onTap: () => showAccountSheet(context, ref),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8, right: 4),
                      child: PatientAvatar(
                        url: profileAsync.value?.photoUrl,
                        size: 32,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    if ((profileAsync.value?.allergies.isNotEmpty) ?? false)
                      Container(
                        width: double.infinity,
                        color: cs.error,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: ResponsiveCenter(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Icon(Icons.warning_rounded,
                                        size: 16, color: cs.onError),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        l.clinicalAlert,
                                        style: AppTypography.labelSm.copyWith(
                                          color: cs.onError,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'MNIS-SEC',
                                  style: AppTypography.labelSm.copyWith(
                                    color: cs.onError,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ResponsiveCenter(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AsyncValueView<PatientProfile>(
                            value: profileAsync,
                            isAr: isAr,
                            onRetry: () => ref.invalidate(profileProvider),
                            builder: (context, patient) => _PatientCard(
                                l: l, cs: cs, patient: patient, locale: locale),
                          ),
                          const SizedBox(height: 16),
                          Consumer(builder: (context, ref, _) {
                            final hubAsync = ref.watch(summaryHubProvider);
                            return AsyncValueView<Map<String, dynamic>>(
                              value: hubAsync,
                              isAr: isAr,
                              onRetry: () => ref.invalidate(summaryHubProvider),
                              builder: (context, hub) => _SovereignSummaryHub(
                                cs: cs,
                                isAr: isAr,
                                hub: hub,
                              ),
                            );
                          }),
                          const SizedBox(height: 16),
                          Consumer(builder: (context, ref, _) {
                            final timeline = ref.watch(timelineProvider);
                            return AsyncValueView<List<TimelineEntry>>(
                              value: timeline,
                              isAr: isAr,
                              onRetry: () => ref.invalidate(timelineProvider),
                              builder: (context, entries) => _ClinicalTimeline(
                                  l: l, cs: cs, isAr: isAr, locale: locale, entries: entries),
                            );
                          }),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Patient Identity Card ──────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final AppLocalizations l;
  final ColorScheme cs;
  final PatientProfile patient;
  final Locale locale;
  const _PatientCard(
      {required this.l, required this.cs, required this.patient, required this.locale});

  bool get isAr => locale.languageCode == 'ar';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.06), blurRadius: 14),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -16,
            bottom: -16,
            child: Icon(Icons.health_and_safety,
                size: 96, color: cs.primary.withOpacity(0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Centered identity hero header
                Center(
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: cs.primary.withOpacity(0.25),
                                width: 2,
                              ),
                            ),
                            child: PatientAvatar(
                              url: patient.photoUrl,
                              size: 72,
                              borderRadius: BorderRadius.circular(36),
                            ),
                          ),
                          PositionedDirectional(
                            bottom: 0,
                            end: 0,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: cs.tertiary,
                                shape: BoxShape.circle,
                                border: Border.all(color: cs.surface, width: 2),
                              ),
                              child: Icon(Icons.verified_rounded,
                                  size: 12, color: cs.onTertiary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        patient.fullName.pick(locale),
                        textAlign: TextAlign.center,
                        style: AppTypography.headlineMd.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              '${patient.age} ${isAr ? 'سنة' : 'y'} • ${patient.isFemale ? l.femaleLabel : l.maleLabel}',
                              style: AppTypography.labelMd
                                  .copyWith(color: cs.onSurfaceVariant),
                            ),
                            Text('•',
                                style: AppTypography.labelMd
                                    .copyWith(color: cs.outline)),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                patient.nationalId,
                                style: AppTypography.mono.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Balanced symmetrical vital pills (Blood Type + Health Insurance)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.error.withOpacity(0.22)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.water_drop_rounded,
                                    size: 14, color: cs.error),
                                const SizedBox(width: 4),
                                Text(
                                  isAr ? 'فصيلة الدم' : 'Blood Type',
                                  style: AppTypography.labelSm.copyWith(
                                      color: cs.onErrorContainer),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                patient.bloodType,
                                style: AppTypography.headlineMd.copyWith(
                                  color: cs.error,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: patient.insuranceActive
                              ? cs.tertiaryContainer.withOpacity(0.45)
                              : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (patient.insuranceActive
                                    ? cs.tertiary
                                    : cs.outline)
                                .withOpacity(0.25),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  patient.insuranceActive
                                      ? Icons.verified_user_rounded
                                      : Icons.shield_outlined,
                                  size: 14,
                                  color: patient.insuranceActive
                                      ? cs.tertiary
                                      : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isAr ? 'التأمين الصحي' : 'Insurance',
                                  style: AppTypography.labelSm.copyWith(
                                      color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              patient.insuranceActive
                                  ? l.officiallyInsured
                                  : (isAr ? 'غير مؤمَّن' : 'Uninsured'),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLg.copyWith(
                                color: patient.insuranceActive
                                    ? cs.tertiary
                                    : cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (patient.allergies.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              color: cs.error, shape: BoxShape.circle),
                          child: Icon(Icons.emergency_rounded,
                              size: 18, color: cs.onError),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.allergyDrugs,
                                style: AppTypography.labelSm.copyWith(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: patient.allergies
                                    .map((a) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerLowest
                                                .withOpacity(0.9),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            a.pick(locale),
                                            style: AppTypography.labelMd
                                                .copyWith(
                                              color: cs.error,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (patient.chronicConditions.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.favorite_rounded,
                              size: 18, color: cs.secondary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.chronicConditions,
                                style: AppTypography.labelSm.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: patient.chronicConditions
                                    .map((c) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerLowest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: cs.outlineVariant
                                                  .withOpacity(0.4),
                                            ),
                                          ),
                                          child: Text(
                                            c.pick(locale),
                                            style: AppTypography.labelMd
                                                .copyWith(color: cs.onSurface),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Material(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => launchUrl(Uri.parse('tel:137')),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: cs.primary, shape: BoxShape.circle),
                            child: Icon(Icons.call_rounded,
                                size: 16, color: cs.onPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAr
                                      ? 'خط نجدة الإسعاف والطوارئ'
                                      : 'Emergency Ambulance Hotline',
                                  style: AppTypography.labelSm
                                      .copyWith(color: cs.outline),
                                ),
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    '137',
                                    style: AppTypography.labelLg.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.medical_services_rounded,
                              size: 20, color: cs.secondary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Clinical Timeline ───────────────────────────────────────────────────────

class _ClinicalTimeline extends StatelessWidget {
  final AppLocalizations l;
  final ColorScheme cs;
  final bool isAr;
  final Locale locale;
  final List<TimelineEntry> entries;
  const _ClinicalTimeline({
    required this.l,
    required this.cs,
    required this.isAr,
    required this.locale,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd(isAr ? 'ar' : 'en');

    Color nodeColor(TimelineEntry e) => switch (e.kind) {
          TimelineKind.visit => cs.secondary,
          TimelineKind.prescription => cs.tertiary,
          TimelineKind.lab => (e.data as LabResultPanel).hasAbnormal ? cs.error : cs.tertiary,
        };
    IconData icon(TimelineEntry e) => switch (e.kind) {
          TimelineKind.visit => Icons.local_hospital_rounded,
          TimelineKind.prescription => Icons.receipt_long_rounded,
          TimelineKind.lab => Icons.science_rounded,
        };
    String title(TimelineEntry e) => switch (e.kind) {
          TimelineKind.visit => (e.data as VisitModel).reason.pick(locale),
          TimelineKind.prescription =>
            '${isAr ? "روشتة" : "Prescription"} #${(e.data as PrescriptionModel).code}',
          TimelineKind.lab => (e.data as LabResultPanel).panel.pick(locale),
        };
    ({String label, Color bg, Color fg}) badge(TimelineEntry e) {
      switch (e.kind) {
        case TimelineKind.visit:
          return (label: isAr ? 'زيارة' : 'Visit', bg: cs.secondaryContainer, fg: cs.onSecondaryContainer);
        case TimelineKind.prescription:
          final p = e.data as PrescriptionModel;
          final dispensed = p.status == RxStatus.dispensed;
          return (
            label: dispensed ? (isAr ? 'مصروفة' : 'Dispensed') : (isAr ? 'سارية' : 'Active'),
            bg: dispensed ? cs.tertiaryContainer : cs.secondaryContainer,
            fg: dispensed ? cs.onTertiaryContainer : cs.onSecondaryContainer,
          );
        case TimelineKind.lab:
          final abnormal = (e.data as LabResultPanel).hasAbnormal;
          return (
            label: abnormal ? (isAr ? 'خارج النطاق' : 'Out of range') : (isAr ? 'طبيعي' : 'Normal'),
            bg: abnormal ? cs.errorContainer : cs.tertiaryContainer,
            fg: abnormal ? cs.onErrorContainer : cs.onTertiaryContainer,
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Icon(Icons.timeline_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.clinicalTimeline,
                  style: AppTypography.headlineSm.copyWith(color: cs.onSurface),
                ),
              ),
              if (entries.isNotEmpty)
                StatusBadge(
                  label: '${entries.length}',
                  backgroundColor: cs.primaryContainer.withOpacity(0.25),
                  textColor: cs.primary,
                  fontSize: 10,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          EmptyState(icon: Icons.timeline_rounded, message: l.noTimelineEvents)
        else
          ...entries.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final b = badge(e);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: nodeColor(e).withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: nodeColor(e), width: 2),
                      ),
                      child: Icon(icon(e), size: 14, color: nodeColor(e)),
                    ),
                    if (i < entries.length - 1)
                      Container(
                        width: 2,
                        height: 44,
                        color: cs.outlineVariant.withOpacity(0.7),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              df.format(e.date),
                              style: AppTypography.labelSm
                                  .copyWith(color: cs.onSurfaceVariant),
                            ),
                            StatusBadge(
                              label: b.label,
                              backgroundColor: b.bg,
                              textColor: b.fg,
                              fontSize: 10,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title(e),
                          textAlign: TextAlign.start,
                          style: AppTypography.headlineSm
                              .copyWith(color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
      ],
    );
  }
}

// ─── Sovereign Interconnectivity Hub (Referrals, PACS, Chronic, Audit) ───

class _SovereignSummaryHub extends StatelessWidget {
  final ColorScheme cs;
  final bool isAr;
  final Map<String, dynamic> hub;

  const _SovereignSummaryHub({
    required this.cs,
    required this.isAr,
    required this.hub,
  });

  List<Map<String, dynamic>> _list(String key) {
    final raw = hub[key];
    if (raw is List) {
      return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return const [];
  }

  String _localizedRole(String role) {
    if (!isAr) return role.replaceAll('_', ' ');
    return switch (role.toUpperCase()) {
      'DOCTOR' => 'طبيب معالج',
      'PHARMACIST' => 'صيدلي',
      'LAB_TECH' => 'أخصائي معمل',
      'HOSPITAL_STAFF' => 'طاقم مستشفى',
      'RECEPTIONIST' => 'استقبال',
      'ADMIN' => 'إدارة النظام',
      'EXECUTIVE' => 'متابعة قيادية',
      _ => role,
    };
  }

  String _localizedAction(String action) {
    final upper = action.toUpperCase();
    if (!isAr) {
      return upper.replaceAll('_', ' ').toLowerCase();
    }
    if (upper.contains('VIEW') || upper.contains('READ') || upper.contains('GET')) {
      return 'الاطلاع على السجل الطبي';
    }
    if (upper.contains('DISPENSE')) return 'صرف وصفة طبية';
    if (upper.contains('PRESCR')) return 'تحرير/توثيق روشتة';
    if (upper.contains('LAB') || upper.contains('SAMPLE')) return 'إجراء/اعتماد فحص معملي';
    if (upper.contains('SHARE')) return 'مشاركة مؤقتة للملف الطبي';
    if (upper.contains('ADMIT') || upper.contains('BED')) return 'تسكين/متابعة إقامة داخلية';
    return action.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final chronic = _list('chronicAllowances');
    final referrals = _list('referrals');
    final radiology = _list('radiology');
    final accessLogs = _list('accessLogs');
    final activeBed = hub['activeInpatientBed'] is Map
        ? (hub['activeInpatientBed'] as Map).cast<String, dynamic>()
        : null;
    final surgeries = _list('surgeries');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0. Active Inpatient Bed & Surgical Operations (Hospital / OR)
        if (activeBed != null || surgeries.isNotEmpty) ...[
          _SectionCard(
            cs: cs,
            icon: Icons.local_hospital_rounded,
            iconColor: cs.primary,
            title: isAr
                ? 'الإقامة الداخلية والعمليات الجراحية'
                : 'Hospital Inpatient & Surgical Care',
            accentBorder: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeBed != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isAr
                                ? 'قسم ${activeBed['wardAr'] ?? activeBed['wardEn'] ?? ''} • سرير ${activeBed['bedNumber'] ?? ''}'
                                : '${activeBed['wardEn'] ?? ''} • Bed ${activeBed['bedNumber'] ?? ''}',
                            style: AppTypography.labelMd.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.start,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: isAr ? 'مقيم حالياً' : 'ADMITTED',
                          backgroundColor: cs.primary,
                          textColor: cs.onPrimary,
                          fontSize: 10,
                        ),
                      ],
                    ),
                  ),
                ...surgeries.map((op) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAr
                                      ? '${op['procedureAr'] ?? op['procedureEn'] ?? ''}'
                                      : '${op['procedureEn'] ?? ''}',
                                  style: AppTypography.labelMd.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isAr
                                      ? '${op['surgeonNameAr'] ?? ''} • ${op['anaesthesiaAr'] ?? ''}'
                                      : '${op['surgeonNameEn'] ?? ''} • ${op['anaesthesiaEn'] ?? ''}',
                                  style: AppTypography.labelSm
                                      .copyWith(color: cs.onSurfaceVariant),
                                  textAlign: TextAlign.start,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                            label:
                                '${op['theaterNo'] ?? 'OR-01'} • ${op['status'] ?? 'SCHEDULED'}',
                            backgroundColor: cs.tertiaryContainer,
                            textColor: cs.onTertiaryContainer,
                            fontSize: 10,
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 1. Monthly Chronic Medication Allowances (with clean quota bar)
        if (chronic.isNotEmpty) ...[
          _SectionCard(
            cs: cs,
            icon: Icons.medication_liquid_rounded,
            iconColor: cs.secondary,
            title: isAr
                ? 'حصص الأدوية المزمنة الشهرية'
                : 'Monthly Chronic Drug Allowances',
            trailing: StatusBadge(
              label: '${chronic.length}',
              backgroundColor: cs.secondaryContainer.withOpacity(0.5),
              textColor: cs.onSecondaryContainer,
              fontSize: 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: chronic.map((c) {
                final limit = ((c['monthlyLimit'] as num?)?.toInt() ?? 1).clamp(1, 999);
                final used = ((c['dispensedThisMonth'] as num?)?.toInt() ?? 0).clamp(0, limit);
                final remaining = (limit - used).clamp(0, 999);
                final ratio = (remaining / limit).clamp(0.0, 1.0);
                final barColor = remaining > 0 ? cs.tertiary : cs.error;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: cs.outlineVariant.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.medication_rounded,
                                size: 17, color: cs.secondary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${c['drugName'] ?? ''}',
                                  style: AppTypography.labelLg.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                                if ((c['dosage'] ?? '').toString().isNotEmpty)
                                  Text(
                                    '${c['dosage']}',
                                    style: AppTypography.labelSm
                                        .copyWith(color: cs.onSurfaceVariant),
                                    textAlign: TextAlign.start,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                            label: isAr
                                ? 'متبقي $remaining / $limit'
                                : '$remaining / $limit left',
                            backgroundColor: remaining > 0
                                ? cs.tertiaryContainer.withOpacity(0.6)
                                : cs.errorContainer,
                            textColor: remaining > 0
                                ? cs.onTertiaryContainer
                                : cs.onErrorContainer,
                            fontSize: 10,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 5,
                          backgroundColor: cs.outlineVariant.withOpacity(0.35),
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 2. Clinical Referrals & PACS Radiology
        if (referrals.isNotEmpty || radiology.isNotEmpty) ...[
          _SectionCard(
            cs: cs,
            icon: Icons.hub_rounded,
            iconColor: cs.tertiary,
            title: isAr
                ? 'التحويلات الطبية وتقارير الأشعة (PACS)'
                : 'Clinical Referrals & PACS Radiology',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...referrals.map((r) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.compare_arrows_rounded,
                              size: 18, color: cs.secondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${isAr ? "تحويل إلى:" : "Referral to:"} ${r['targetFacility'] ?? r['targetType'] ?? ''}',
                                  style: AppTypography.labelMd.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                                if ((r['reason'] ?? '').toString().isNotEmpty)
                                  Text(
                                    '${r['reason']}',
                                    style: AppTypography.labelSm
                                        .copyWith(color: cs.onSurfaceVariant),
                                    textAlign: TextAlign.start,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                            label:
                                '${r['urgency'] ?? 'ROUTINE'} • ${r['status'] ?? 'PENDING'}',
                            backgroundColor: cs.secondaryContainer,
                            textColor: cs.onSecondaryContainer,
                            fontSize: 10,
                          ),
                        ],
                      ),
                    )),
                ...radiology.map((rad) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.radar_rounded,
                              size: 18, color: cs.tertiary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${isAr ? "أشعة:" : "Scan:"} ${rad['bodyPart'] ?? ''}',
                                  style: AppTypography.labelMd.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                                if ((rad['findings'] ?? '').toString().isNotEmpty)
                                  Text(
                                    '${rad['findings']}',
                                    style: AppTypography.labelSm
                                        .copyWith(color: cs.onSurfaceVariant),
                                    textAlign: TextAlign.start,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                            label: '${rad['modality'] ?? 'PACS'}',
                            backgroundColor: cs.tertiaryContainer,
                            textColor: cs.onTertiaryContainer,
                            fontSize: 10,
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 3. Sovereign Security Access Log — completely redesigned for clean AR & EN layout
        if (accessLogs.isNotEmpty) ...[
          _SectionCard(
            cs: cs,
            icon: Icons.shield_rounded,
            iconColor: cs.primary,
            title: isAr
                ? 'سجل الرقابة السيادي للملف الطبي'
                : 'Sovereign Medical Record Audit Trail',
            subtitle: isAr
                ? 'جميع عمليات الاطلاع على ملفك مسجلة ومشفرة'
                : 'Encrypted, tamper-evident record access log',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'AES-256',
                style: AppTypography.mono.copyWith(
                  color: cs.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: accessLogs.take(4).map((log) {
                final actor = isAr
                    ? ((log['actorNameAr'] as String?) ??
                        (log['actorNameEn'] as String?) ??
                        'MNIS')
                    : ((log['actorNameEn'] as String?) ??
                        (log['actorNameAr'] as String?) ??
                        'MNIS');
                final rawRole = (log['actorRole'] ?? 'SYSTEM').toString();
                final rawAction = (log['action'] ?? '').toString();
                final at = DateTime.tryParse(
                    (log['createdAt'] ?? log['at'] ?? '').toString());
                final timeLabel = at != null
                    ? DateFormat.MMMd(isAr ? 'ar' : 'en').add_Hm().format(at)
                    : '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.verified_user_outlined,
                            size: 16, color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              actor,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelMd.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              timeLabel.isNotEmpty
                                  ? '${_localizedAction(rawAction)} • $timeLabel'
                                  : _localizedAction(rawAction),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelSm
                                  .copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(
                        label: _localizedRole(rawRole),
                        backgroundColor: cs.secondaryContainer.withOpacity(0.45),
                        textColor: cs.onSecondaryContainer,
                        fontSize: 10,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final bool accentBorder;

  const _SectionCard({
    required this.cs,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.accentBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentBorder
              ? cs.primary.withOpacity(0.35)
              : cs.outlineVariant.withOpacity(0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          AppTypography.headlineSm.copyWith(color: cs.primary),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppTypography.labelSm
                            .copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}


