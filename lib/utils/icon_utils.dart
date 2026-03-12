class IconUtils {
  static const List<String> availableIcons = [
    '🐻',
    '🐧',
    '🐱',
    '🚰',
    '💿',
    '🎹',
    '🎸',
    '🥁',
    '🕺',
    '💻',
  ];

  static String getEmoji(String iconName) {
    if (availableIcons.contains(iconName)) {
      return iconName;
    }
    // Default to the first one if not found or empty
    return '🐻';
  }
}
