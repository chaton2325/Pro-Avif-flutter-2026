/// Formate une quantité (kg, kg/t, litres...) en conservant ses décimales
/// significatives : un nombre entier s'affiche sans décimale, sinon jusqu'à
/// [maxDecimals] décimales, sans zéro inutile en fin (12.50 -> "12.5").
///
/// À utiliser à la place de `toStringAsFixed(0)` pour toute quantité de matière
/// première, d'aliment ou de livraison : ces valeurs ne sont pas forcément des
/// entiers, et arrondir à l'unité masque silencieusement de vrais écarts.
String formatQty(num value, {int maxDecimals = 2}) {
  if (value.isNaN || value.isInfinite) return value.toString();
  var s = value.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}
