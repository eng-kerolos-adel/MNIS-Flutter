import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_bootstrap.dart';
import 'firebase_remote_config_service.dart';

class FirebaseAiService {
  FirebaseAiService._();
  static final FirebaseAiService instance = FirebaseAiService._();

  static final RegExp _nationalIdPattern = RegExp(r'\b\d{14}\b');

  static const String disclaimerAr =
      'ملاحظة: هذه المعلومات استرشادية للتوعية الصحية فقط ولا تغني عن الكشف الطبي.';
  static const String disclaimerEn =
      'Note: This guidance is educational only and does not replace professional medical advice.';

  String _validatePrompt(String prompt) {
    final clean = prompt.trim();
    if (clean.isEmpty) {
      throw ArgumentError('Prompt cannot be empty.');
    }
    if (_nationalIdPattern.hasMatch(clean)) {
      throw StateError('PII_NATIONAL_ID_NOT_ALLOWED');
    }
    if (!FirebaseBootstrap.isInitialized ||
        FirebaseAuth.instance.currentUser == null) {
      throw StateError('FIREBASE_AUTH_REQUIRED');
    }
    if (!FirebaseRemoteConfigService.instance.aiHealthAssistantEnabled) {
      throw StateError('AI_ASSISTANT_DISABLED');
    }
    return clean;
  }

  GenerativeModel _buildModel({required bool arabic}) {
    final rc = FirebaseRemoteConfigService.instance;
    final instruction = arabic
        ? 'أنت مساعد توعية صحية لمنظومة الهوية الطبية الوطنية (MNIS). قدّم شرحاً مبسطاً وواضحاً للمفاهيم الصحية أو الدوائية باللغة العربية دون أي تشخيص طبي قطعي أو طلب بيانات شخصية.'
        : 'You are a health literacy assistant for MNIS. Provide clear, plain-language explanations of general health or medication concepts without making medical diagnoses or requesting personal identifiers.';

    return FirebaseAI.googleAI().generativeModel(
      model: rc.aiGeminiModel,
      systemInstruction: Content.system(instruction),
      generationConfig: GenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 1024,
      ),
    );
  }

  Future<({String text, String disclaimer})> explainMedicalInfo(
    String prompt, {
    bool arabic = true,
  }) async {
    final clean = _validatePrompt(prompt);
    final model = _buildModel(arabic: arabic);
    final res = await model.generateContent([Content.text(clean)]);
    return (
      text: res.text ?? '',
      disclaimer: arabic ? disclaimerAr : disclaimerEn,
    );
  }

  Stream<String> streamMedicalExplanation(
    String prompt, {
    bool arabic = true,
  }) async* {
    final clean = _validatePrompt(prompt);
    final model = _buildModel(arabic: arabic);
    await for (final chunk in model.generateContentStream([Content.text(clean)])) {
      final piece = chunk.text;
      if (piece != null && piece.isNotEmpty) {
        yield piece;
      }
    }
  }
}
