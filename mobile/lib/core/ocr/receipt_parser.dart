String? extractReference(String text) {
  final normalized = text
      .toUpperCase()
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // 1) Keyword-based capture (best when OCR keeps labels)
  // Examples from samples:
  // - "REFERENCE NO. FT240..."
  // - "TRANSACTION ID: FT23WY..."
  // - "TRANSACTION NUMBER IS BB752..."
  final keywordPatterns = <RegExp>[
    RegExp(r'(REFERENCE\s*(NO\.?|NUMBER)?\s*[:\-]?\s*)([A-Z0-9]{6,})'),
    RegExp(r'(TRANSACTION\s*(ID|NO\.?|NUMBER)?\s*[:\-]?\s*)([A-Z0-9]{6,})'),
    RegExp(r'(RECEIPT\s*(NO\.?|NUMBER)?\s*[:\-]?\s*)([A-Z0-9]{6,})'),
  ];
  for (final p in keywordPatterns) {
    final m = p.firstMatch(normalized);
    if (m != null) {
      final v = m.group(3);
      if (v != null && v.length >= 6) return v;
    }
  }

  // 2) Format-based patterns (fallback)
  final patterns = <RegExp>[
    // CBE references often start with FT...
    RegExp(r'\bFT[0-9A-Z]{6,}\b'),

    // Telebirr often has transaction/receipt like BB752FXG5J
    RegExp(r'\bBB[0-9A-Z]{6,}\b'),

    // Dashen sample shows Transaction reference like 012FTO0251770009
    RegExp(r'\b\d{3}FTO\d{6,}\b'),

    // Generic TRX/TX patterns
    RegExp(r'\bTRX[0-9A-Z]{6,}\b'),
    RegExp(r'\bTX[0-9A-Z]{6,}\b'),
  ];

  for (final p in patterns) {
    final m = p.firstMatch(normalized);
    if (m != null) return m.group(0);
  }

  return null;
}
