/// What a customer-account entry is called on screen. The codes are for the
/// server.
String ledgerEntryLabel(String type) => switch (type) {
  'deposit' => 'Top-up',
  'sale_debit' => 'Meal charged',
  'adjustment' => 'Correction',
  _ => type,
};
