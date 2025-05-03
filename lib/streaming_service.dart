import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Thrown when streaming data is unavailable or invalid.
class StreamingNotAvailableException implements Exception {
  final String message;
  StreamingNotAvailableException(this.message);

  @override
  String toString() => 'StreamingNotAvailableException: $message';
}

class StreamingService {
  static final _logger = Logger();

  /// Retrieves a streaming link or playlist for a movie or TV show.
  static Future<Map<String, String>> getStreamingLink({
    required String tmdbId,
    required String title,
    required String resolution,
    required bool enableSubtitles,
    int? season,
    int? episode,
    String? seasonTmdbId,
    String? episodeTmdbId,
    bool forDownload = false,
  }) async {
    _logger.i('Calling backend for streaming link: $tmdbId');

    final url = Uri.parse('https://moviflxpro.onrender.com/media-links');
    final isShow = season != null && episode != null;

    final body = <String, String>{
      'type': isShow ? 'show' : 'movie',
      'tmdbId': tmdbId,
      'title': title,
      'releaseYear': DateTime.now().year.toString(),
      'releaseYear': DateTime.now().year.toString(),
      if (isShow) ...{
        'seasonNumber': season.toString(),
        'seasonTmdbId': seasonTmdbId ?? tmdbId,
        'episodeNumber': episode.toString(),
        'episodeTmdbId': episodeTmdbId ?? tmdbId,
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
        throw StreamingNotAvailableException(
          'Failed to get streaming link: ${response.statusCode}',
        );
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _logger.e('Invalid response format: $decoded');
        throw StreamingNotAvailableException('Invalid response format.');
      }
      final data = decoded;
      _logger.d('Raw backend JSON: $data');

      List<Map<String, dynamic>> streamsList;
      if (data['streams'] != null) {
        streamsList = List<Map<String, dynamic>>.from(data['streams'] as List);
      } else if (data['stream'] != null) {
        streamsList = [
          {
            'sourceId': data['sourceId']?.toString() ?? 'unknown',
            'stream': Map<String, dynamic>.from(data['stream'] as Map<String, dynamic>),
          }
        ];
      } else {
        _logger.w('No streams found: $data');
        throw StreamingNotAvailableException('No streaming links available.');
      }

      if (streamsList.isEmpty) {
        _logger.w('Streams list is empty.');
        throw StreamingNotAvailableException('No streaming links available.');
      }

      final selected = streamsList.firstWhere(
        (s) => s['stream'] != null,
        orElse: () {
          _logger.w('No valid stream in list: $streamsList');
          throw StreamingNotAvailableException('No valid stream available.');
        },
      );

      final streamData = selected['stream'] as Map<String, dynamic>;

      String? playlist;
      String streamType;
      late String streamUrl;
      String subtitleUrl = '';

      final playlistEncoded = streamData['playlist'] as String?;
      if (playlistEncoded != null &&
          playlistEncoded.startsWith('data:application/vnd.apple.mpegurl;base64,')) {
        final base64Part = playlistEncoded.split(',')[1];
        playlist = utf8.decode(base64Decode(base64Part));
        streamType = 'm3u8';

        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$tmdbId-playlist.m3u8');
        await file.writeAsString(playlist);
        await file.writeAsString(playlist);
        streamUrl = file.path;
      } else {
        final urlValue = streamData['url']?.toString();
        if (urlValue == null || urlValue.isEmpty) {
          _logger.e('No stream URL provided: $streamData');
          throw StreamingNotAvailableException('No stream URL available.');
        }
        streamUrl = urlValue;

        if (streamUrl.endsWith('.m3u8')) {
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
              _logger.e(
                'Failed to fetch M3U8 playlist: ${playlistResponse.statusCode}',
              );
              throw StreamingNotAvailableException('Failed to fetch playlist.');
            }
          }
        } else if (streamUrl.endsWith('.mp4')) {
          streamType = 'mp4';
        } else {
          streamType = streamData['type']?.toString() ?? 'm3u8';
        }
      }

      final captionsList = streamData['captions'] as List<dynamic>?;
      if (enableSubtitles && captionsList != null && captionsList.isNotEmpty) {
        final selectedCap = captionsList.firstWhere(
          (c) => c['language'] == 'en',
          orElse: () => captionsList.first,
        );
        subtitleUrl = selectedCap['url']?.toString() ?? '';
      }

      final result = <String, String>{
        'title': title,
        'type': streamType,
        'url': streamUrl,
      };
      if (playlist != null) {
        result['playlist'] = playlist;
      }
      if (subtitleUrl.isNotEmpty) {
        result['subtitleUrl'] = subtitleUrl;
      }

      _logger.i('Streaming link retrieved: $result');
      return result;
    } catch (e, st) {
      _logger.e('Error fetching stream for tmdbId: $tmdbId', error: e, stackTrace: st);
      rethrow;
    }
  }
}
