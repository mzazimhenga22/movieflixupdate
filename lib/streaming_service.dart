import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

class StreamingService {
  static final _logger = Logger();

  static Future<Map<String, String>> getStreamingLink({
    required String tmdbId,
    required String title,
    required String resolution,
    required bool enableSubtitles,
    int? season,
    int? episode,
    bool forDownload = false,
  }) async {
    _logger.i('Calling backend for streaming link: $tmdbId');

    final url = Uri.parse('https://moviflxpro.onrender.com/media-links');
    final isShow = season != null && episode != null;
    final body = {
      'type': isShow ? 'show' : 'movie',
      'tmdbId': tmdbId,
      'title': title,
      'releaseYear': DateTime.now().year.toString(),
      if (isShow) ...{
        'seasonNumber': season.toString(),
        'seasonTmdbId': tmdbId,
        'episodeNumber': episode.toString(),
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

      final selectedStream = streamsList[0];
      final streamData = selectedStream['stream'] as Map<String, dynamic>;

      String? playlist;
      String? streamUrl;
      String streamType;
      String subtitleUrl = '';

      final playlistEncoded = streamData['playlist'] as String?;
      if (playlistEncoded != null &&
          playlistEncoded.startsWith('data:application/vnd.apple.mpegurl;base64,')) {
        final base64Part = playlistEncoded.split(',')[1];
        playlist = utf8.decode(base64Decode(base64Part));
        streamType = 'm3u8';
        _logger.i('Decoded M3U8 playlist:\n$playlist');

        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$tmdbId-playlist.m3u8');
        await file.writeAsString(playlist);
        streamUrl = file.path;
      } else {
        streamUrl = streamData['url'];
        if ((streamUrl ?? '').isEmpty) {
          _logger.e('No stream URL provided: $streamData');
          throw Exception('No stream URL');
        }

        if (streamUrl != null && streamUrl.endsWith('.m3u8')) {
          streamType = 'm3u8';
          if (forDownload) {
            final playlistResponse = await http.get(Uri.parse(streamUrl));
            if (playlistResponse.statusCode == 200) {
              playlist = playlistResponse.body;

              final dir = await getTemporaryDirectory();
              final file = File('${dir.path}/$tmdbId-playlist.m3u8');
              await file.writeAsString(playlist);
              streamUrl = file.path;
            } else {
              throw Exception('Failed to fetch M3U8 playlist');
            }
          }
        } else if (streamUrl != null && streamUrl.endsWith('.mp4')) {
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

      final result = {
        'title': title,
        'type': streamType,
        'subtitleUrl': subtitleUrl,
      };

      if (playlist != null) {
        result['playlist'] = playlist;
        if (streamUrl != null) {
          result['url'] = streamUrl;
        }
      } else if (streamUrl != null) {
        result['url'] = streamUrl;
      } else {
        throw Exception('No stream URL or playlist available');
      }

      return result;
    } catch (e, st) {
      _logger.e('Error fetching stream', error: e, stackTrace: st);
      throw Exception('Failed to retrieve stream');
    }
  }
}

