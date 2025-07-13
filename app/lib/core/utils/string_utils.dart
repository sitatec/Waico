extension StringUtils on String {
  String removeEmojis() {
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}' // Emoticons
      r'\u{1F300}-\u{1F5FF}' // Misc Symbols and Pictographs
      r'\u{1F680}-\u{1F6FF}' // Transport and Map
      r'\u{1F1E6}-\u{1F1FF}' // Regional country flags
      r'\u{2600}-\u{26FF}' // Misc symbols
      r'\u{2700}-\u{27BF}' // Dingbats
      r'\u{1F900}-\u{1F9FF}' // Supplemental Symbols and Pictographs
      r'\u{1FA70}-\u{1FAFF}' // Symbols and Pictographs Extended-A
      r'\u{1F018}-\u{1F270}' // Various Asian characters
      r'\u{238C}-\u{2454}' // Misc items
      r'\u{20D0}-\u{20FF}]', // Combining Diacritical Marks for Symbols
      unicode: true,
    );
    return replaceAll(emojiRegex, '');
  }
}
