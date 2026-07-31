void main() {
  String album = 'Nonante‐cinq';
  String safe = album
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('\'', '')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('.', '')
      .replaceAll(RegExp(r'[\u2010-\u2015\u2212]'), '-');
  print(safe);
}
