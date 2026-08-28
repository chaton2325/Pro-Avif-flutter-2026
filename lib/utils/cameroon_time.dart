/// Le Cameroun est en UTC+1 toute l'année (pas d'heure d'été) et l'heure de toute action du
/// module Usine Aliment doit provenir du serveur, jamais de l'horloge du téléphone (modifiable
/// par l'utilisateur). Le backend sérialise ses dates en UTC explicite (suffixe Z / +00:00) ;
/// on applique ici un décalage fixe de +1h plutôt qu'un `.toLocal()`, qui dépendrait du fuseau
/// configuré sur l'appareil et non de l'heure réelle du Cameroun.
const Duration cameroonOffset = Duration(hours: 1);

DateTime toCameroonTime(DateTime serverUtcValue) {
  final utc = serverUtcValue.isUtc ? serverUtcValue : serverUtcValue.toUtc();
  return utc.add(cameroonOffset);
}

DateTime? toCameroonTimeOrNull(DateTime? serverUtcValue) {
  if (serverUtcValue == null) return null;
  return toCameroonTime(serverUtcValue);
}

/// Équivalent de [toCameroonTime] à partir d'une chaîne ISO brute venant du serveur — pour
/// les `fromMap` qui parsent directement `map['champ'].toString()`.
DateTime? parseCameroonTime(String? isoValue) {
  if (isoValue == null) return null;
  final parsed = DateTime.tryParse(isoValue);
  if (parsed == null) return null;
  return toCameroonTime(parsed);
}
