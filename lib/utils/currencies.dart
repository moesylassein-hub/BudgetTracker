class AppCurrency {
  final String code;
  final String name;
  final String symbol;
  final int decimalDigits;

  const AppCurrency(
    this.code,
    this.name,
    this.symbol, {
    this.decimalDigits = 2,
  });
}

class AppCurrencies {
  static const values = <AppCurrency>[
    AppCurrency('EGP', 'Egyptian Pound', 'EGP '),
    AppCurrency('USD', 'US Dollar', r'$'),
    AppCurrency('EUR', 'Euro', '€'),
    AppCurrency('SAR', 'Saudi Riyal', 'SAR '),
    AppCurrency('AED', 'UAE Dirham', 'AED '),
    AppCurrency('GBP', 'British Pound', '£'),
    AppCurrency('KWD', 'Kuwaiti Dinar', 'KWD ', decimalDigits: 3),
  ];

  static AppCurrency byCode(String code) {
    return values.firstWhere(
      (item) => item.code == code,
      orElse: () => values.first,
    );
  }
}
