class PaymentProvider {
  const PaymentProvider._(this.value, this.label);

  final String value;
  final String label;

  static const telebirr = PaymentProvider._('telebirr', 'Telebirr');
  static const cbe = PaymentProvider._('cbe', 'CBE');
  static const dashen = PaymentProvider._('dashen', 'Dashen');
  static const abyssinia = PaymentProvider._('abyssinia', 'Abyssinia');
  static const cbebirr = PaymentProvider._('cbebirr', 'CBE Birr');

  static const values = <PaymentProvider>[
    telebirr,
    cbe,
    dashen,
    abyssinia,
    cbebirr,
  ];
}

class NormalizedVerification {
  NormalizedVerification({
    required this.status,
    this.provider,
    this.reference,
    this.amount,
    this.payer,
    this.date,
    this.source,
    this.confidence,
    required this.raw,
  });

  final String status; // SUCCESS|FAILED|PENDING
  final String? provider;
  final String? reference;
  final double? amount;
  final String? payer;
  final String? date;
  final String? source; // upstream|local
  final String? confidence; // high|medium|low
  final Map<String, dynamic> raw;

  factory NormalizedVerification.fromJson(Map<String, dynamic> json) {
    final amountVal = json['amount'];
    double? amount;
    if (amountVal is num) amount = amountVal.toDouble();
    if (amountVal is String) amount = double.tryParse(amountVal);

    return NormalizedVerification(
      status: (json['status'] as String?) ?? 'PENDING',
      provider: json['provider'] as String?,
      reference: json['reference'] as String?,
      amount: amount,
      payer: json['payer'] as String?,
      date: json['date'] as String?,
      source: json['source'] as String?,
      confidence: json['confidence'] as String?,
      raw:
          (json['raw'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
    );
  }
}
