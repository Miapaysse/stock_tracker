enum UserRole {
  technician,     // Técnico
  admin,          // Admin (Gabriel)
  advancedAdmin,  // Admin Avanzado (Facu)
}

class AppUser {
  final String id;
  final String name;
  final UserRole role;

  AppUser({
    required this.id,
    required this.name,
    required this.role,
  });

  String get roleDisplayName {
    switch (role) {
      case UserRole.technician:
        return 'Técnico';
      case UserRole.admin:
        return 'Administrador';
      case UserRole.advancedAdmin:
        return 'Admin Avanzado';
    }
  }
}