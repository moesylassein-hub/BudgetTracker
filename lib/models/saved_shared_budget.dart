class SavedSharedBudget {
  final String sheetId;
  final String name;
  final String? accountEmail;
  const SavedSharedBudget({
    required this.sheetId,
    required this.name,
    this.accountEmail,
  });
  Map<String, dynamic> toJson() => {
    'sheetId': sheetId,
    'name': name,
    'accountEmail': accountEmail,
  };
}
