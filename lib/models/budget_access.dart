class BudgetMember {
  final String name;
  final String email;
  final String role;
  final String type;
  final String domain;
  final bool discoverable;
  BudgetMember(Map<String, dynamic> data)
    : name = data['displayName'] as String? ?? '',
      email = data['emailAddress'] as String? ?? '',
      role = data['role'] as String? ?? 'unknown',
      type = data['type'] as String? ?? 'user',
      domain = data['domain'] as String? ?? '',
      discoverable = data['allowFileDiscovery'] == true;
  String get label {
    if (type == 'anyone') {
      return discoverable ? 'Anyone on the internet' : 'Anyone with the link';
    }
    if (type == 'domain') {
      return domain.isEmpty ? 'Domain access' : 'People at $domain';
    }
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return type == 'group' ? 'Google group' : 'Google account';
  }

  String get roleLabel => switch (role) {
    'owner' => 'Owner',
    'writer' => 'Editor',
    'reader' => 'Viewer',
    'commenter' => 'Commenter',
    'organizer' => 'Manager',
    'fileOrganizer' => 'Content manager',
    _ => 'Unknown role',
  };
  Map<String, dynamic> toJson() => {
    'displayName': name,
    'emailAddress': email,
    'role': role,
    'type': type,
    'domain': domain,
    'allowFileDiscovery': discoverable,
  };
}

class BudgetAccess {
  final List<BudgetMember> members;
  final bool? canEdit;
  final bool? canShare;
  final bool complete;
  final DateTime checkedAt;
  BudgetAccess({
    required this.members,
    required this.checkedAt,
    required this.complete,
    this.canEdit,
    this.canShare,
  });
  String roleFor(String? email) {
    if (email == null) return 'Unknown';
    final own = members
        .where(
          (member) =>
              member.type == 'user' &&
              member.email.toLowerCase() == email.toLowerCase(),
        )
        .toList();
    if (own.any((member) => member.role == 'owner')) return 'Owner';
    if (canEdit == true) {
      return own.any((member) => member.role == 'writer')
          ? 'Invited editor'
          : 'Editor';
    }
    if (canEdit == false) {
      return own.any((member) => member.role == 'commenter')
          ? 'Commenter'
          : 'Viewer';
    }
    return 'Unknown';
  }

  Map<String, dynamic> toJson() => {
    'members': members.map((member) => member.toJson()).toList(),
    'canEdit': canEdit,
    'canShare': canShare,
    'complete': complete,
    'checkedAt': checkedAt.toIso8601String(),
  };
  factory BudgetAccess.fromJson(Map<String, dynamic> data) => BudgetAccess(
    members: (data['members'] as List)
        .map((raw) => BudgetMember(Map<String, dynamic>.from(raw as Map)))
        .toList(),
    canEdit: data['canEdit'] as bool?,
    canShare: data['canShare'] as bool?,
    complete: data['complete'] == true,
    checkedAt: DateTime.parse(data['checkedAt'] as String),
  );
}
