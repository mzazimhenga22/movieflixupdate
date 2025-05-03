import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:movie_app/main_videoplayer.dart';
import 'package:movie_app/tmdb_api.dart' as tmdb;
import 'package:movie_app/streaming_service.dart';
import 'package:movie_app/settings_provider.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';

class TVShowEpisodesSection extends StatefulWidget {
  final dynamic tvId;
  final List<dynamic> seasons;
  final String tvShowName;

  const TVShowEpisodesSection({
    Key? key,
    required this.tvId,
    required this.seasons,
    required this.tvShowName,
  }) : super(key: key);

  @override
  _TVShowEpisodesSectionState createState() => _TVShowEpisodesSectionState();
}

class _TVShowEpisodesSectionState extends State<TVShowEpisodesSection> {
  int _selectedSeasonIndex = 0;
  List<Map<String, dynamic>> _episodes = [];
  bool _isLoadingEpisodes = true;
  String _selectedResolution = "720p";
  bool _enableSubtitles = false;

  @override
  void initState() {
    super.initState();
    _fetchEpisodesForSeason(_selectedSeasonIndex);
  }

  Future<void> _fetchEpisodesForSeason(int seasonIndex) async {
    setState(() {
      _isLoadingEpisodes = true;
      _episodes = [];
    });

    try {
      final season = widget.seasons[seasonIndex];
      final seasonNumber = season['season_number']?.toInt() ?? 1;
      final episodeDetails = await tmdb.TMDBApi.fetchTVSeasonDetails(
          widget.tvId, seasonNumber);
      if (mounted) {
        setState(() {
          _episodes = (episodeDetails['episodes'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _isLoadingEpisodes = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch episodes: $e');
      if (mounted) {
        setState(() {
          _isLoadingEpisodes = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load episodes: $e")),
        );
      }
    }
  }

  void _showEpisodeOptionsModal(Map<String, dynamic> episode, int seasonNumber) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String resolution = _selectedResolution;
        bool subtitles = _enableSubtitles;
        return _EpisodeOptionsModal(
          initialResolution: resolution,
          initialSubtitles: subtitles,
          onPlay: (res, subs) {
            _playEpisode(episode, seasonNumber, res, subs);
          },
          onDownload: (res, subs) {
            _downloadEpisode(episode, seasonNumber, res, subs);
          },
        );
      },
    );
  }

  Future<void> _playEpisode(
    Map<String, dynamic> episode,
    int seasonNumber,
    String resolution,
    bool subtitles,
  ) async {
    debugPrint('Playing episode: ${episode['name']}');
    if (!mounted) return;
    _showLoadingDialog();

    try {
      final episodeNumber = episode['episode_number']?.toInt() ?? 1;
      final streamingInfo = await StreamingService.getStreamingLink(
        tmdbId: widget.tvId.toString(),
        title: widget.tvShowName,
        season: seasonNumber,
        episode: episodeNumber,
        resolution: resolution,
        enableSubtitles: subtitles,
      );

      if (streamingInfo['url'] != null && streamingInfo['type'] == 'm3u8') {
        try {
          final decodedBytes = base64Decode(streamingInfo['url']!);
          final decodedString = utf8.decode(decodedBytes);
          if (Uri.tryParse(decodedString)?.isAbsolute == true) {
            streamingInfo['url'] = decodedString;
          } else if (decodedString.startsWith('#EXTM3U')) {
            streamingInfo['url'] = decodedString;
          }
        } catch (e) {
          debugPrint('Base64 decoding for streaming URL failed: $e');
        }
      }

      final streamUrl = streamingInfo['url'] ?? '';
      final urlType = streamingInfo['type'] ?? 'unknown';
      final subtitleUrl = streamingInfo['subtitleUrl'];

      if (streamUrl.isEmpty) {
        throw Exception('Streaming URL not available');
      }

      if (!mounted) {
        Navigator.pop(context);
        return;
      }

      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MainVideoPlayer(
            videoPath: streamUrl,
            title:
                '${widget.tvShowName} - S${seasonNumber}E${episodeNumber}',
            isFullSeason: false,
            episodeFiles: [],
            similarMovies: [],
            subtitleUrl: subtitleUrl,
            isHls: urlType == 'm3u8',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error playing episode: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<bool> _requestStoragePermissions() async {
    if (Platform.isAndroid) {
      // For Android 13+ (API 33+), use videos permission for media files
      if (await _isAndroid13OrAbove()) {
        final status = await Permission.videos.request();
        if (status.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    "Storage permission denied. Please enable it in settings."),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return false;
        }
        return status.isGranted;
      } else {
        // For Android 12 and below, use storage permission
        final status = await Permission.storage.request();
        if (status.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    "Storage permission denied. Please enable it in settings."),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return false;
        }
        return status.isGranted;
      }
    } else {
      // For iOS, no explicit storage permission is needed for app directories
      return true;
    }
  }

  Future<bool> _isAndroid13OrAbove() async {
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      return deviceInfo.version.sdkInt >= 33;
    }
    return false;
  }

  Future<void> _downloadEpisode(
    Map<String, dynamic> episode,
    int seasonNumber,
    String resolution,
    bool subtitles,
  ) async {
    final episodeNumber = episode['episode_number']?.toInt() ?? 1;
    final title =
        '${widget.tvShowName}-S${seasonNumber}E${episodeNumber}';
    Map<String, String> streamingInfo;
    try {
      streamingInfo = await StreamingService.getStreamingLink(
        tmdbId: widget.tvId.toString(),
        title: title,
        season: seasonNumber,
        episode: episodeNumber,
        resolution: resolution,
        enableSubtitles: subtitles,
        forDownload: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to get download link: $e")),
      );
      return;
    }

    final streamType = streamingInfo['type'] ?? 'm3u8';
    final directory = Platform.isAndroid
        ? (await getExternalStorageDirectory())!
        : await getApplicationDocumentsDirectory();
    final contentDir = Directory('${directory.path}/${widget.tvId}/S${seasonNumber}E${episodeNumber}');
    await contentDir.create(recursive: true);

    String? playlistContent = streamingInfo['playlist'];
    String? streamUrl = streamingInfo['url'];
    String baseUrl = '';

    if (streamUrl != null && streamType == 'm3u8') {
      try {
        final decodedBytes = base64Decode(streamUrl);
        final decodedString = utf8.decode(decodedBytes);
        if (decodedString.startsWith('#EXTM3U')) {
          playlistContent = decodedString;
          streamUrl = null;
        } else if (Uri.tryParse(decodedString)?.isAbsolute == true) {
          streamUrl = decodedString;
          final response = await http.get(Uri.parse(streamUrl));
          if (response.statusCode == 200) {
            playlistContent = response.body;
          } else {
            throw Exception('Failed to fetch M3U8 playlist');
          }
        }
      } catch (e) {
        debugPrint('Base64 decoding failed or not Base64: $e');
        if (streamUrl != null && playlistContent == null) {
          final response = await http.get(Uri.parse(streamUrl));
          if (response.statusCode == 200) {
            playlistContent = response.body;
          } else {
            throw Exception('Failed to fetch M3U8 playlist');
          }
        }
      }
    }

    if (streamType == 'm3u8' && playlistContent != null) {
      baseUrl = streamUrl != null
          ? Uri.parse(streamUrl).resolve('.').toString()
          : '';
      final fileName = '$title-$resolution.m3u8';
      final segmentDir = Directory('${contentDir.path}/segments');
      await segmentDir.create(recursive: true);

      final lines = playlistContent.split('\n');
      final segmentUrls = <String>[];
      for (var line in lines) {
        if (line.trim().endsWith('.ts')) {
          final segmentUrl = baseUrl.isNotEmpty
              ? Uri.parse(baseUrl).resolve(line.trim()).toString()
              : line.trim();
          segmentUrls.add(segmentUrl);
        }
      }

      if (await _requestStoragePermissions()) {
        for (var i = 0; i < segmentUrls.length; i++) {
          final segmentUrl = segmentUrls[i];
          final segmentFile = 'segment_$i.ts';
          await FlutterDownloader.enqueue(
            url: segmentUrl,
            savedDir: segmentDir.path,
            fileName: segmentFile,
            showNotification: false,
          );
        }

        final modifiedPlaylist = lines.map((line) {
          if (line.trim().endsWith('.ts')) {
            final index =
                segmentUrls.indexWhere((url) => url.endsWith(line.trim()));
            return 'segments/segment_$index.ts';
          }
          return line;
        }).join('\n');

        final playlistFile = File('${contentDir.path}/$fileName');
        await playlistFile.writeAsString(modifiedPlaylist);

        await FlutterDownloader.enqueue(
          url: 'file://${playlistFile.path}',
          savedDir: contentDir.path,
          fileName: fileName,
          showNotification: true,
          openFileFromNotification: true,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Downloading $title (M3U8)")),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Storage permission not granted")),
        );
      }
    } else {
      if (streamUrl == null || streamUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Download URL not available")),
        );
        return;
      }

      if (await _requestStoragePermissions()) {
        final fileName = streamType == 'mp4'
            ? '$title-$resolution.mp4'
            : '$title-$resolution.m3u8';
        final taskId = await FlutterDownloader.enqueue(
          url: streamUrl,
          savedDir: contentDir.path,
          fileName: fileName,
          showNotification: true,
          openFileFromNotification: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Download started (Task ID: $taskId)")),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Storage permission not granted")),
        );
      }
    }
  }

  void _showLoadingDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _TVLoadingDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seasons and Episodes',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          DropdownButton<int>(
            value: _selectedSeasonIndex,
            dropdownColor: Colors.black87,
            items: widget.seasons.asMap().entries.map((entry) {
              final index = entry.key;
              final season = entry.value;
              final seasonName = season['name'] ?? 'Season ${index + 1}';
              return DropdownMenuItem(
                value: index,
                child: Text(
                  seasonName,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }).toList(),
            onChanged: (index) {
              if (index != null) {
                setState(() {
                  _selectedSeasonIndex = index;
                });
                _fetchEpisodesForSeason(index);
              }
            },
          ),
          const SizedBox(height: 16),
          _isLoadingEpisodes
              ? Shimmer.fromColors(
                  baseColor: Colors.grey[800]!,
                  highlightColor: Colors.grey[600]!,
                  child: Column(
                    children: List.generate(
                      3,
                      (index) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        height: 100,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                )
              : _episodes.isEmpty
                  ? const Text(
                      'No episodes available.',
                      style: TextStyle(color: Colors.white70),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final episode = _episodes[index];
                        final episodeNumber =
                            episode['episode_number']?.toInt() ?? index + 1;
                        final episodeTitle =
                            episode['name'] ?? 'Episode $episodeNumber';
                        final stillPath = episode['still_path'];
                        final seasonNumber = widget
                                .seasons[_selectedSeasonIndex]['season_number']
                                ?.toInt() ??
                            1;

                        return Card(
                          color: Colors.grey[900],
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: stillPath != null
                                ? CachedNetworkImage(
                                    imageUrl:
                                        'https://image.tmdb.org/t/p/w200$stillPath',
                                    width: 80,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Shimmer.fromColors(
                                      baseColor: Colors.grey[800]!,
                                      highlightColor: Colors.grey[600]!,
                                      child: Container(
                                          width: 80, color: Colors.grey[800]),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                            width: 80, color: Colors.grey),
                                  )
                                : Container(
                                    width: 80,
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.image_not_supported,
                                        color: Colors.white),
                                  ),
                            title: Text(
                              'E$episodeNumber: $episodeTitle',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              episode['overview']?.isNotEmpty == true
                                  ? episode['overview'].length > 50
                                      ? '${episode['overview'].substring(0, 50)}...'
                                      : episode['overview']
                                  : 'No description available.',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_circle_fill,
                                  color: Colors.white),
                              onPressed: () => _showEpisodeOptionsModal(
                                  episode, seasonNumber),
                            ),
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }
}

class _EpisodeOptionsModal extends StatefulWidget {
  final String initialResolution;
  final bool initialSubtitles;
  final void Function(String, bool) onPlay;
  final void Function(String, bool) onDownload;

  const _EpisodeOptionsModal({
    required this.initialResolution,
    required this.initialSubtitles,
    required this.onPlay,
    required this.onDownload,
  });

  @override
  _EpisodeOptionsModalState createState() => _EpisodeOptionsModalState();
}

class _EpisodeOptionsModalState extends State<_EpisodeOptionsModal> {
  late String _resolution;
  late bool _subtitles;

  @override
  void initState() {
    super.initState();
    _resolution = widget.initialResolution;
    _subtitles = widget.initialSubtitles;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    return Container(
      padding: const EdgeInsets.all(16),
      height: 350,
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Episode Options",
            style: TextStyle(
                fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text("Select Resolution:",
              style: TextStyle(color: Colors.white)),
          DropdownButton<String>(
            value: _resolution,
            dropdownColor: Colors.black87,
            items: const [
              DropdownMenuItem(
                  value: "480p",
                  child: Text("480p", style: TextStyle(color: Colors.white))),
              DropdownMenuItem(
                  value: "720p",
                  child: Text("720p", style: TextStyle(color: Colors.white))),
              DropdownMenuItem(
                  value: "1080p",
                  child: Text("1080p", style: TextStyle(color: Colors.white))),
            ],
            onChanged: (value) => setState(() => _resolution = value!),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text("Enable Subtitles:",
                  style: TextStyle(color: Colors.white)),
              Switch(
                value: _subtitles,
                activeColor: settings.accentColor,
                onChanged: (value) => setState(() => _subtitles = value),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: settings.accentColor),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onPlay(_resolution, _subtitles);
                },
                child:
                    const Text("Play", style: TextStyle(color: Colors.black)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: settings.accentColor),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDownload(_resolution, _subtitles);
                },
                child: const Text("Download",
                    style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TVLoadingDialog extends StatefulWidget {
  const _TVLoadingDialog({Key? key}) : super(key: key);

  @override
  _TVLoadingDialogState createState() => _TVLoadingDialogState();
}

class _TVLoadingDialogState extends State<_TVLoadingDialog> {
  bool _showSecondMessage = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showSecondMessage = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black87,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            "Preparing your episode...",
            style: TextStyle(color: Colors.white),
          ),
          if (_showSecondMessage) ...[
            const SizedBox(height: 8),
            const Text(
              "This may take a moment.",
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}