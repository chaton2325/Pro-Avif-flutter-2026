import 'package:url_launcher/url_launcher.dart';

/// Ouvre une conversation WhatsApp pré-remplie avec [message] vers [phone] (numéro
/// complet indicatif inclus, tel que saisi par l'admin — espaces/tirets/"+" tolérés,
/// wa.me n'accepte que des chiffres). Retourne false si le numéro est vide après
/// nettoyage ou si aucune app/navigateur ne peut ouvrir le lien, pour que l'appelant
/// prévienne l'utilisateur plutôt que d'échouer silencieusement.
Future<bool> openWhatsAppReminder(String? phone, String message) async {
  final digits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;
  final uri = Uri.parse(
    'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
  );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
