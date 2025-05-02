import 'package:flutter/material.dart';

class SettingsProvider extends ChangeNotifier {
  // Existing settings
  String _downloadQuality = 'Medium';
  bool _wifiOnlyDownloads = true;
  String _playbackQuality = '720p';
  bool _subtitlesEnabled = true;
  String _language = 'English';
  bool _autoPlayTrailers = true;
  bool _notificationsEnabled = true;
  bool _parentalControl = false;
  bool _dataSaverMode = false;
  double _cacheSize = 125.0; // in MB

  // Accent color for UI elements and backgrounds (replaces backgroundColor)
  Color _accentColor = Colors.red; // Default to red to match HomeScreen

  // Getters for existing settings
  String get downloadQuality => _downloadQuality;
  bool get wifiOnlyDownloads => _wifiOnlyDownloads;
  String get playbackQuality => _playbackQuality;
  bool get subtitlesEnabled => _subtitlesEnabled;
  String get language => _language;
  bool get autoPlayTrailers => _autoPlayTrailers;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get parentalControl => _parentalControl;
  bool get dataSaverMode => _dataSaverMode;
  double get cacheSize => _cacheSize;

  // Getter for accent color
  Color get accentColor => _accentColor;

  // Gradient using accent color with cinematic opacities
  List<Color> get accentGradientColors => [
        _accentColor.withOpacity(0.5),
        _accentColor.withOpacity(0.3),
      ];

  // Setters that notify listeners
  void setDownloadQuality(String quality) {
    _downloadQuality = quality;
    notifyListeners();
  }

  void setWifiOnlyDownloads(bool value) {
    _wifiOnlyDownloads = value;
    notifyListeners();
  }

  void setPlaybackQuality(String quality) {
    _playbackQuality = quality;
    notifyListeners();
  }

  void setSubtitlesEnabled(bool value) {
    _subtitlesEnabled = value;
    notifyListeners();
  }

  void setLanguage(String lang) {
    _language = lang;
    notifyListeners();
  }

  void setAutoPlayTrailers(bool value) {
    _autoPlayTrailers = value;
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  void setParentalControl(bool value) {
    _parentalControl = value;
    notifyListeners();
  }

  void setDataSaverMode(bool value) {
    _dataSaverMode = value;
    notifyListeners();
  }

  // Set accent color
  void setAccentColor(Color color) {
    _accentColor = color;
    notifyListeners();
  }

  void clearCache() {
    _cacheSize = 0.0;
    notifyListeners();
  }
}