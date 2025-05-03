import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:movie_app/downloads_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

class StreamingService {
  static final _logger = Logger();

  static Future<Map<String, String>> getStreamingLink({
    required String tmdbId,
    required String title,
    required String resolution,
    required bool enableSubtitles,
    int? season,
    int? episode,
  }) async {
    _logger.i('Calling backend for streaming link: $tmdbId');

    final url = Uri.parse('https://moviflxpro.onrender.com/media-links');
    final isShow = season != null && episode != null;
    final body = {
      'type': isShow ? 'show' : 'movie',
      'tmdbId': tmdbId,
      'title': title,
      'releaseYear': DateTime.now().year,
      if (isShow) ...{
        'seasonNumber': season,
        'seasonTmdbId': tmdbId,
        'episodeNumber': episode,
        'episodeTmdbId': tmdbId,
      }
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        _logger.e('Backend error: ${response.statusCode} ${response.body}');
        throw Exception('Failed to get streaming link');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _logger.d('Raw backend JSON: $data');

      List<Map<String, dynamic>> streamsList;
      if (data['streams'] != null) {
        streamsList = List<Map<String, dynamic>>.from(data['streams']);
      } else if (data['stream'] != null) {
        streamsList = [
          {
            'sourceId': data['sourceId'],
            'stream': Map<String, dynamic>.from(data['stream']),
          }
        ];
      } else {
        streamsList = [];
      }

      if (streamsList.isEmpty) {
        _logger.w('No streams found in backend response: $data');
        throw Exception('No streaming links available');
      }

      final streamData = streamsList[0]['stream'] as Map<String, dynamic>;

      String streamUrl = '';
      String streamType = 'm3u8';
      String subtitleUrl = '';

      final playlistEncoded = streamData['playlist'] as String?;
      if (playlistEncoded != null &&
          playlistEncoded.startsWith('data:application/vnd.apple.mpegurl;base64,')) {
        final base64Part = playlistEncoded.split(',')[1];
        final decodedPlaylist = utf8.decode(base64Decode(base64Part));
        _logger.i('Decoded M3U8 playlist:');
        _logger.i(decodedPlaylist);

        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$tmdbId-playlist.m3u8');
        await file.writeAsString(decodedPlaylist);
        streamUrl = file.path;

        streamType = 'm3u8';
      } else {
        streamUrl = streamData['url'] ?? '';
        if (streamUrl.isEmpty) {
          _logger.e('No stream URL provided: $streamData');
          throw Exception('No stream URL');
        }
        if (streamUrl.endsWith('.m3u8')) {
          streamType = 'm3u8';
        } else if (streamUrl.endsWith('.mp4')) {
          streamType = 'mp4';
        } else {
          streamType = streamData['type'] ?? 'm3u8';
        }
      }

      if (enableSubtitles && streamData['captions'] != null) {
        final caps = streamData['captions'] as List<dynamic>;
        if (caps.isNotEmpty) {
          final cap = caps.firstWhere(
            (c) => c['language'] == 'en',
            orElse: () => caps[0],
          );
          subtitleUrl = cap['url'] ?? '';
        }
      }

      return {
        'url': streamUrl,
        'type': streamType,
        'title': title,
        'subtitleUrl': subtitleUrl,
      };
    } catch (e, st) {
      _logger.e('Error fetching stream', error: e, stackTrace: st);
      throw Exception('Failed to retrieve stream');
    }
  }

  static Future<void> prepareDownload({
    required BuildContext context,
    required String tmdbId,
    required String title,
    required String resolution,
    required bool subtitles,
    int? season,
    int? episode,
  }) async {
    try {
      final streamingInfo = await getStreamingLink(
        tmdbId: tmdbId,
        title: title,
        resolution: resolution,
        enableSubtitles: subtitles,
        season: season,
        episode: episode,
      );
      final downloadUrl = streamingInfo['url'];
      final urlType = streamingInfo['type'] ?? 'unknown';

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('Download URL not available');
      }

      if (await Permission.storage.request().isGranted) {
        final directory = Platform.isAndroid
            ? (await getExternalStorageDirectory())!
            : await getApplicationDocumentsDirectory();
        final fileName =
            "${title.replaceAll(RegExp(r'[^\w\s-]'), '')}-$resolution.${urlType == 'm3u8' ? 'mp4' : urlType}";
        final taskId = await FlutterDownloader.enqueue(
          url: downloadUrl,
          savedDir: directory.path,
          fileName: fileName,
          showNotification: true,
          openFileFromNotification: true,
        );

        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DownloadsScreen(taskId: taskId),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Storage permission not granted")),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Download failed: $e")),
        );
      }
    }
  }
}