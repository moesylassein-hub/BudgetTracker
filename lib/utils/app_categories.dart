import 'package:flutter/material.dart';

class CategoryIconOption {
  final String key;
  final String label;
  final IconData icon;

  const CategoryIconOption(this.key, this.label, this.icon);
}

class AppCategories {
  static const iconOptions = <CategoryIconOption>[
    CategoryIconOption('restaurant', 'Food', Icons.restaurant_rounded),
    CategoryIconOption('car', 'Transport', Icons.directions_car_filled_rounded),
    CategoryIconOption('shopping', 'Shopping', Icons.shopping_bag_rounded),
    CategoryIconOption('receipt', 'Bills', Icons.receipt_long_rounded),
    CategoryIconOption('movie', 'Entertainment', Icons.movie_rounded),
    CategoryIconOption('health', 'Health', Icons.health_and_safety_rounded),
    CategoryIconOption('school', 'Education', Icons.school_rounded),
    CategoryIconOption('home', 'Home', Icons.home_rounded),
    CategoryIconOption('travel', 'Travel', Icons.flight_takeoff_rounded),
    CategoryIconOption('fitness', 'Fitness', Icons.fitness_center_rounded),
    CategoryIconOption('pets', 'Pets', Icons.pets_rounded),
    CategoryIconOption('phone', 'Phone', Icons.phone_android_rounded),
    CategoryIconOption('salary', 'Salary', Icons.account_balance_wallet_rounded),
    CategoryIconOption('work', 'Work', Icons.work_rounded),
    CategoryIconOption('refund', 'Refund', Icons.currency_exchange_rounded),
    CategoryIconOption('gift', 'Gift', Icons.card_giftcard_rounded),
    CategoryIconOption('income', 'Income', Icons.trending_up_rounded),
    CategoryIconOption('savings', 'Savings', Icons.savings_rounded),
    CategoryIconOption('laptop', 'Laptop', Icons.laptop_mac_rounded),
    CategoryIconOption('category', 'Other', Icons.category_rounded),
  ];

  static IconData iconForKey(String key) {
    return iconOptions
        .firstWhere(
          (item) => item.key == key,
          orElse: () => iconOptions.last,
        )
        .icon;
  }

  static IconData iconFor(String category, {String? iconKey}) {
    if (iconKey != null) return iconForKey(iconKey);
    return switch (category) {
      'Food' => Icons.restaurant_rounded,
      'Transport' => Icons.directions_car_filled_rounded,
      'Shopping' => Icons.shopping_bag_rounded,
      'Bills' => Icons.receipt_long_rounded,
      'Entertainment' => Icons.movie_rounded,
      'Health' => Icons.health_and_safety_rounded,
      'Education' => Icons.school_rounded,
      'Salary' => Icons.account_balance_wallet_rounded,
      'Freelance' => Icons.work_rounded,
      'Refunds' => Icons.currency_exchange_rounded,
      'Gifts' => Icons.card_giftcard_rounded,
      'Other Income' => Icons.trending_up_rounded,
      _ => Icons.category_rounded,
    };
  }

  static Color colorFor(String category, ColorScheme scheme) {
    return switch (category) {
      'Food' => const Color(0xFFEA580C),
      'Transport' => const Color(0xFF2563EB),
      'Shopping' => const Color(0xFF9333EA),
      'Bills' => const Color(0xFFB45309),
      'Entertainment' => const Color(0xFFDB2777),
      'Health' => const Color(0xFFDC2626),
      'Education' => const Color(0xFF0891B2),
      'Salary' => const Color(0xFF059669),
      'Freelance' => const Color(0xFF0D9488),
      'Refunds' => const Color(0xFF16A34A),
      'Gifts' => const Color(0xFF7C3AED),
      'Other Income' => const Color(0xFF15803D),
      _ => scheme.primary,
    };
  }
}
