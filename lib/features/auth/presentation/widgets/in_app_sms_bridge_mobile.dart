import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../../core/theme/app_typography.dart';

class SmsBridgeException implements Exception {
  final String code;
  final String message;

  const SmsBridgeException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// Embedded in-app bridge to Firebase Phone Auth Web SDK on MNIS's authorized
/// domain (`https://mnis-egypt-dev-citizen.web.app/sms-bridge.html`). Keeps all
/// reCAPTCHA verification and SMS dispatch strictly inside the MNIS app so
/// sideloaded APKs never redirect out to Chrome.
class InAppSmsBridgeController {
  static const String _bridgeOrigin = 'https://mnis-egypt-dev-citizen.web.app';
  static const Set<String> _allowedSubframeHosts = {
    'mnis-egypt-dev-citizen.web.app',
    'mnis-egypt-dev.firebaseapp.com',
    'google.com',
    'gstatic.com',
    'recaptcha.net',
    'googleapis.com',
  };

  InAppSmsBridgeController({
    required this.isAr,
    required this.isDark,
    this.onCodeSent,
    this.onVerified,
    this.onError,
    this.onVerifyError,
  }) {
    if (isSupported) {
      _initWebView();
    }
  }

  final bool isAr;
  final bool isDark;
  final VoidCallback? onCodeSent;
  final ValueChanged<String>? onVerified;
  final void Function(String code, String message)? onError;
  final void Function(String code, String message)? onVerifyError;

  final ValueNotifier<bool> challengeVisible = ValueNotifier<bool>(false);

  WebViewController? _webView;
  bool _ready = false;
  bool _disposed = false;
  ({String phoneE164, bool isAr})? _pendingSend;
  Timer? _readyTimeoutTimer;

  bool get isSupported =>
      !kIsWeb &&
      WebViewPlatform.instance != null &&
      (Platform.isAndroid || Platform.isIOS);

  WebViewController? get webViewController => _webView;

  Uri get _bridgeUri => Uri.parse(
        '$_bridgeOrigin/sms-bridge.html?lang=${isAr ? 'ar' : 'en'}&dark=${isDark ? '1' : '0'}',
      );

  void _initWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'about' ||
                uri.scheme == 'data' ||
                uri.scheme == 'blob') {
              return NavigationDecision.navigate;
            }
            if (uri.scheme != 'https') return NavigationDecision.prevent;
            final host = uri.host.toLowerCase();
            if (req.isMainFrame) {
              if (host == 'mnis-egypt-dev-citizen.web.app' ||
                  host == 'mnis-egypt-dev.firebaseapp.com') {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
            }
            final allowed = _allowedSubframeHosts.any(
              (d) => host == d || host.endsWith('.$d'),
            );
            return allowed
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (err) {
            if (_disposed) return;
            if (err.isForMainFrame == true && _pendingSend != null) {
              _cancelReadyTimer();
              _pendingSend = null;
              challengeVisible.value = false;
              onError?.call('network-request-failed', err.description);
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'MnisSmsBridge',
        onMessageReceived: _handleBridgeMessage,
      );

    final platformCtrl = controller.platform;
    if (platformCtrl is AndroidWebViewController) {
      final cookieManager = AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      );
      unawaited(cookieManager.setAcceptThirdPartyCookies(platformCtrl, true));
    }

    _webView = controller;
    unawaited(controller.loadRequest(_bridgeUri));
  }

  void _handleBridgeMessage(JavaScriptMessage msg) {
    if (_disposed) return;
    try {
      final decoded = jsonDecode(msg.message);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'] as String?;
      switch (type) {
        case 'ready':
          _ready = true;
          _cancelReadyTimer();
          final pending = _pendingSend;
          if (pending != null) {
            _pendingSend = null;
            unawaited(_dispatchSendSms(pending.phoneE164, isAr: pending.isAr));
          }
        case 'challengeVisible':
          final visible = (decoded['visible'] as bool?) ?? false;
          challengeVisible.value = visible;
        case 'codeSent':
          challengeVisible.value = false;
          onCodeSent?.call();
        case 'verified':
          challengeVisible.value = false;
          final token = decoded['idToken'] as String?;
          if (token != null && token.isNotEmpty) {
            onVerified?.call(token);
          } else {
            onVerifyError?.call('unknown', 'EMPTY_ID_TOKEN');
          }
        case 'error':
          challengeVisible.value = false;
          final code = (decoded['code'] as String?) ?? 'unknown';
          final message = (decoded['message'] as String?) ?? 'SMS failed';
          onError?.call(_normalizeCode(code), message);
        case 'verifyError':
          final code = (decoded['code'] as String?) ?? 'invalid-verification-code';
          final message = (decoded['message'] as String?) ?? 'Verification failed';
          onVerifyError?.call(_normalizeCode(code), message);
      }
    } catch (_) {
      // Ignore malformed bridge events safely.
    }
  }

  String _normalizeCode(String raw) {
    final cleaned = raw.trim();
    if (cleaned.startsWith('auth/')) {
      return cleaned.substring(5);
    }
    return cleaned;
  }

  void _cancelReadyTimer() {
    _readyTimeoutTimer?.cancel();
    _readyTimeoutTimer = null;
  }

  Future<void> sendSms(String phoneE164, {required bool isAr}) async {
    final ctrl = _webView;
    if (ctrl == null) {
      onError?.call('unavailable', 'WebView unavailable');
      return;
    }
    if (!_ready) {
      _pendingSend = (phoneE164: phoneE164, isAr: isAr);
      _cancelReadyTimer();
      _readyTimeoutTimer = Timer(const Duration(seconds: 20), () {
        if (_disposed || _ready || _pendingSend == null) return;
        _pendingSend = null;
        challengeVisible.value = false;
        onError?.call('network-request-failed', 'Timed out loading SMS bridge');
      });
      unawaited(ctrl.loadRequest(_bridgeUri));
      return;
    }
    await _dispatchSendSms(phoneE164, isAr: isAr);
  }

  Future<void> _dispatchSendSms(String phoneE164, {required bool isAr}) async {
    final ctrl = _webView;
    if (ctrl == null || _disposed) return;
    final lang = isAr ? 'ar' : 'en';
    await ctrl.runJavaScript(
      'window.mnisSendSms(${jsonEncode(phoneE164)}, ${jsonEncode(lang)})',
    );
  }

  Future<void> confirmOtp(String code) async {
    final ctrl = _webView;
    if (ctrl == null || _disposed) {
      onVerifyError?.call('unavailable', 'WebView unavailable');
      return;
    }
    await ctrl.runJavaScript('window.mnisConfirmOtp(${jsonEncode(code.trim())})');
  }

  Future<void> cancelChallenge() async {
    challengeVisible.value = false;
    await reset();
    onError?.call('captcha-check-failed', 'Verification cancelled by user');
  }

  Future<void> reset() async {
    _pendingSend = null;
    _cancelReadyTimer();
    challengeVisible.value = false;
    final ctrl = _webView;
    if (ctrl != null && _ready && !_disposed) {
      try {
        await ctrl.runJavaScript('window.mnisReset()');
      } catch (_) {}
    }
  }

  void dispose() {
    _disposed = true;
    _cancelReadyTimer();
    _pendingSend = null;
    challengeVisible.dispose();
  }
}

/// Hosts the embedded WebView at full real viewport bounds inside a [Stack]
/// (clipped outside visible bounds when invisible so Android PlatformView keeps
/// real geometry for Google's reCAPTCHA widget without overlapping clicks,
/// then smoothly surfaced as an in-app modal ONLY if an interactive puzzle is requested).
class InAppSmsBridgeHost extends StatelessWidget {
  const InAppSmsBridgeHost({super.key, required this.controller});

  final InAppSmsBridgeController controller;

  @override
  Widget build(BuildContext context) {
    final webCtrl = controller.webViewController;
    if (!controller.isSupported || webCtrl == null) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final cs = Theme.of(context).colorScheme;
    final isAr = controller.isAr;

    return ValueListenableBuilder<bool>(
      valueListenable: controller.challengeVisible,
      builder: (context, visible, child) {
        final modalW = (size.width - 24).clamp(280.0, 480.0);
        final modalH = (size.height * 0.78).clamp(360.0, 620.0);
        final left = visible ? (size.width - modalW) / 2 : size.width + 4000;
        final top = visible ? (size.height - modalH) / 2 : 0.0;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            if (visible)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.52),
                ),
              ),
            Positioned(
              left: left,
              top: top,
              width: modalW,
              height: modalH,
              child: IgnorePointer(
                ignoring: !visible,
                child: Material(
                  color: cs.surface,
                  elevation: visible ? 12 : 0,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.45),
                          border: Border(
                            bottom: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 20,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isAr
                                    ? 'تحقق الأمان داخل MNIS'
                                    : 'MNIS In-App Security Check',
                                style: AppTypography.labelLg.copyWith(
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  unawaited(controller.cancelChallenge()),
                              icon: Icon(
                                Icons.close_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: child!),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: WebViewWidget(controller: webCtrl),
    );
  }
}
