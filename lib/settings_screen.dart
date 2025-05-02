import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key); // Explicit Key parameter

  // A map of available background color options.
  static const Map<String, Color> availableBackgroundColors = {
    'Default (Purple)': Colors.purple,
    'Indigo': Colors.indigo,
    'Blue': Colors.blue,
    'Red': Colors.red,
    'Green': Colors.green,
    'Orange': Colors.orange,
  };

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    // Determine current selection by matching the provider's accentColor.
    String currentColorName = availableBackgroundColors.entries
        .firstWhere(
          (entry) => entry.value == settings.accentColor,
          orElse: () => const MapEntry('Default (Purple)', Colors.purple),
        )
        .key;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: ListView(
        children: [
          // Existing settings...
          ListTile(
            title: const Text("Download Quality"),
            trailing: DropdownButton<String>(
              value: settings.downloadQuality,
              items: const ['Low', 'Medium', 'High']
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) settings.setDownloadQuality(val);
              },
            ),
          ),
          SwitchListTile(
            title: const Text("Download over Wi-Fi Only"),
            value: settings.wifiOnlyDownloads,
            onChanged: settings.setWifiOnlyDownloads,
          ),
          ListTile(
            title: const Text("Playback Quality"),
            trailing: DropdownButton<String>(
              value: settings.playbackQuality,
              items: const ['480p', '720p', '1080p', '4K']
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) settings.setPlaybackQuality(val);
              },
            ),
          ),
          SwitchListTile(
            title: const Text("Subtitles"),
            value: settings.subtitlesEnabled,
            onChanged: settings.setSubtitlesEnabled,
          ),
          ListTile(
            title: const Text("Language"),
            trailing: DropdownButton<String>(
              value: settings.language,
              items: const ['English', 'Spanish', 'French', 'German']
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) settings.setLanguage(val);
              },
            ),
          ),
          SwitchListTile(
            title: const Text("Auto-play Trailers"),
            value: settings.autoPlayTrailers,
            onChanged: settings.setAutoPlayTrailers,
          ),
          SwitchListTile(
            title: const Text("Notifications"),
            value: settings.notificationsEnabled,
            onChanged: settings.setNotificationsEnabled,
          ),
          SwitchListTile(
            title: const Text("Parental Control"),
            value: settings.parentalControl,
            onChanged: settings.setParentalControl,
          ),
          SwitchListTile(
            title: const Text("Data Saver Mode"),
            value: settings.dataSaverMode,
            onChanged: settings.setDataSaverMode,
          ),
          ListTile(
            title: const Text("Clear Cache"),
            subtitle:
                Text("Cache size: ${settings.cacheSize.toStringAsFixed(1)} MB"),
            trailing: ElevatedButton(
              onPressed: () {
                settings.clearCache();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Cache cleared.")),
                );
              },
              child: const Text("Clear"),
            ),
          ),
          // Updated Background Color Setting
          ListTile(
            title: const Text("Background Color"),
            trailing: DropdownButton<String>(
              value: currentColorName,
              items: availableBackgroundColors.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.key),
                    ),
                  )
                  .toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  final newColor = availableBackgroundColors[newValue]!;
                  settings.setAccentColor(newColor);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}