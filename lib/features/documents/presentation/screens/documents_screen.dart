import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:share_plus/share_plus.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/appointment_models.dart';
import '../../../../core/providers/data_providers.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/services/app_permissions_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/utils/providers.dart';
import '../../../../core/utils/shared_widgets.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/responsive_center.dart';

const _allowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
const _maxBytes = 4 * 1000 * 1000; // matches the backend's ~4MB cap

String _mimeFor(String extension) => switch (extension.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final docsAsync = ref.watch(documentsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        centerTitle: true,
        title: Text(l.myDocuments),
        leading: IconButton(
          icon: Icon(
              isAr ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openUploadSheet(context),
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(l.uploadDocument),
      ),
      body: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(documentsProvider);
            await ref
                .read(documentsProvider.future)
                .catchError((_) => <DocumentModel>[]);
          },
          child: AsyncValueView<List<DocumentModel>>(
            value: docsAsync,
            isAr: isAr,
            onRetry: () => ref.invalidate(documentsProvider),
            builder: (context, docs) {
              if (docs.isEmpty) {
                return ResponsiveCenter(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SizedBox(height: 40),
                      EmptyState(
                          icon: Icons.folder_open_rounded,
                          message: l.documentsEmpty),
                      const SizedBox(height: 8),
                      Text(l.documentsHint,
                          textAlign: TextAlign.center,
                          style: AppTypography.labelSm
                              .copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                );
              }
              return ResponsiveCenter(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) =>
                      _DocumentTile(l: l, cs: cs, isAr: isAr, doc: docs[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openUploadSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UploadSheet(),
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  final AppLocalizations l;
  final ColorScheme cs;
  final bool isAr;
  final DocumentModel doc;
  const _DocumentTile(
      {required this.l,
      required this.cs,
      required this.isAr,
      required this.doc});

  String _sizeLabel() {
    final kb = doc.fileSizeBytes / 1024;
    return kb < 1024
        ? '${kb.toStringAsFixed(0)} KB'
        : '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _view(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(repositoryProvider).documentFile(doc.id);
      final bytes = base64Decode(file.fileBase64);
      if (!context.mounted) return;
      if (doc.isImage) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(child: Image.memory(bytes)),
          ),
        );
      } else {
        await Share.shareXFiles([
          XFile.fromData(bytes,
              mimeType: doc.mimeType, name: '${doc.label}.pdf')
        ]);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, isAr: isAr))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat.yMMMd(isAr ? 'ar' : 'en');
    final pending = doc.status == DocumentStatus.pendingReview;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: cs.secondaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(
                doc.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                color: cs.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.label,
                    style: AppTypography.bodyMd.copyWith(color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${df.format(doc.createdAt)} • ${_sizeLabel()}',
                    style: AppTypography.labelSm
                        .copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                StatusBadge(
                  label: pending ? l.pendingReview : l.reviewed,
                  backgroundColor: pending
                      ? cs.surfaceContainerHigh
                      : cs.tertiaryContainer.withOpacity(0.5),
                  textColor:
                      pending ? cs.onSurfaceVariant : cs.onTertiaryContainer,
                  fontSize: 10,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _view(context, ref),
            icon: Icon(
                doc.isImage
                    ? Icons.visibility_outlined
                    : Icons.ios_share_rounded,
                color: cs.secondary),
            tooltip: doc.isImage ? l.openFile : l.shareOrSaveFile,
          ),
        ],
      ),
    );
  }
}

class _UploadSheet extends ConsumerStatefulWidget {
  const _UploadSheet();

  @override
  ConsumerState<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<_UploadSheet> {
  final _labelCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  PlatformFile? _picked;
  int _pickedSize = 0;
  Uint8List? _capturedBytes;
  String? _capturedName;
  String? _capturedExt;
  bool _busy = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final l = AppLocalizations.of(context);
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (file == null) return;
    final size = file.lengthSync() ?? await file.length() ?? 0;
    if (size > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.fileTooLarge)));
      }
      return;
    }
    setState(() {
      _picked = file;
      _pickedSize = size;
      _capturedBytes = null;
      _capturedName = null;
      _capturedExt = null;
    });
  }

  Future<void> _captureCamera() async {
    final l = AppLocalizations.of(context);
    final isAr = ref.read(localeProvider).languageCode == 'ar';
    final status = await AppPermissionsService.instance.requestCamera();
    if (!mounted) return;
    if (status != CapabilityStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == CapabilityStatus.permanentlyDenied
                ? (isAr
                    ? 'تم حظر إذن الكاميرا — فعّله من إعدادات الجهاز'
                    : 'Camera permission blocked — enable in Settings')
                : (isAr
                    ? 'يرجى السماح بالوصول إلى الكاميرا لتصوير المستند'
                    : 'Please allow Camera access to capture your document'),
          ),
          action: status == CapabilityStatus.permanentlyDenied
              ? SnackBarAction(
                  label: isAr ? 'الإعدادات' : 'Settings',
                  onPressed: () =>
                      AppPermissionsService.instance.openDeviceSettings(),
                )
              : null,
        ),
      );
      return;
    }

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (bytes.length > _maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.fileTooLarge)));
        }
        return;
      }
      final parts = photo.name.split('.');
      final rawExt = parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
      final ext = _allowedExtensions.contains(rawExt) ? rawExt : 'jpg';
      if (mounted) {
        setState(() {
          _capturedBytes = bytes;
          _capturedName = photo.name;
          _capturedExt = ext;
          _picked = null;
          _pickedSize = bytes.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, isAr: isAr))));
      }
    }
  }

  Future<void> _upload() async {
    final l = AppLocalizations.of(context);
    final isAr = ref.read(localeProvider).languageCode == 'ar';
    final hasFile = _capturedBytes != null || _picked != null;
    if (!hasFile || _labelCtrl.text.trim().isEmpty) return;

    final String ext;
    final Uint8List bytes;
    if (_capturedBytes != null) {
      ext = _capturedExt ?? 'jpg';
      bytes = _capturedBytes!;
    } else {
      final file = _picked!;
      ext = (file.extension ?? '').toLowerCase();
      if (!_allowedExtensions.contains(ext)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.unsupportedFileType)));
        return;
      }
      bytes = await file.readAsBytes();
    }

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).uploadDocument(
            label: _labelCtrl.text.trim(),
            mimeType: _mimeFor(ext),
            fileBase64: base64Encode(bytes),
          );
      ref.invalidate(documentsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.documentUploaded)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, isAr: isAr))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sizeLabel(int bytes) {
    final kb = bytes / 1024;
    return kb < 1024
        ? '${kb.toStringAsFixed(0)} KB'
        : '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isAr = ref.watch(localeProvider).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final canSubmit = (_picked != null || _capturedBytes != null) &&
        _labelCtrl.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.uploadDocument,
                  style:
                      AppTypography.headlineMd.copyWith(color: cs.onSurface)),
              const SizedBox(height: 16),
              TextField(
                controller: _labelCtrl,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: l.documentLabelHint),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(
                        _picked == null
                            ? l.chooseFile
                            : '${_picked!.name} (${_sizeLabel(_pickedSize)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _captureCamera,
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: Text(
                        _capturedBytes == null
                            ? (isAr ? 'تصوير بالكاميرا' : 'Take Photo')
                            : '${_capturedName ?? "Photo"} (${_sizeLabel(_pickedSize)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (_capturedBytes != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _capturedBytes!,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: (_busy || !canSubmit) ? null : _upload,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onPrimary))
                    : Text(l.uploadDocument),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
