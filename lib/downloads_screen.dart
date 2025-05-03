import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'dart:io';
import 'package:movie_app/main_videoplayer.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  DownloadsScreenState createState() => DownloadsScreenState();
}

class DownloadsScreenState extends State<DownloadsScreen> {
  late Future<List<DownloadTask>?> _tasksFuture;

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  void _loadTasks() {
    _tasksFuture = FlutterDownloader.loadTasks();
  }

  void _refresh() {
    setState(() {
      _loadTasks();
    });
  }

  Future<void> _deleteTask(DownloadTask task) async {
    await FlutterDownloader.remove(
      taskId: task.taskId,
      shouldDeleteContent: true,
    );
    final file = File('${task.savedDir}/${task.filename}');
    if (file.existsSync()) {
      await file.delete();
    }
    _refresh();
  }

  Future<void> _playVideo(String savedDir, String filename, String title) async {
    final filePath = '$savedDir/$filename';
    if (await File(filePath).exists()) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MainVideoPlayer(
              videoPath: filePath,
              title: title,
              isHls: false,
              isLocal: true,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("File not found")),
        );
      }
    }
  }

  static void downloadCallback(String id, int status, int progress) {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      context.findAncestorStateOfType<DownloadsScreenState>()?._refresh();
    }
  }

  bool _isTvEpisode(String filename) {
    final lower = filename.toLowerCase();
    return lower.contains("s01") || lower.contains("episode") || RegExp(r's\d{2}e\d{2}').hasMatch(lower);
  }

  String _extractShowName(String filename) {
    final match = RegExp(r'^(.+?)\s[sS]\d{2}[eE]?\d{2}').firstMatch(filename);
    return match?.group(1)?.trim() ?? filename.split('Episode').first.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Downloads"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<DownloadTask>?>(
        future: _tasksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final tasks = snapshot.data ?? [];
          final movies = tasks.where((t) => !_isTvEpisode(t.filename ?? '')).toList();
          final episodes = tasks.where((t) => _isTvEpisode(t.filename ?? '')).toList();

          final Map<String, List<DownloadTask>> tvShows = {};
          for (var ep in episodes) {
            final show = _extractShowName(ep.filename ?? 'Unknown Show');
            tvShows.putIfAbsent(show, () => []).add(ep);
          }

          return ListView(
            children: [
              if (movies.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text("Movies", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: movies.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final task = movies[index];
                    return GestureDetector(
                      onTap: () => _playVideo(task.savedDir, task.filename!, task.filename!),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    color: Colors.black12,
                                    child: const Center(child: Icon(Icons.movie, size: 50)),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(task.filename ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.white),
                              onPressed: () => _deleteTask(task),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              if (tvShows.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text("TV Shows", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                ...tvShows.entries.map((entry) {
                  return ExpansionTile(
                    title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    children: entry.value.map((task) {
                      return ListTile(
                        leading: const Icon(Icons.video_library),
                        title: Text(task.filename ?? ''),
                        subtitle: Text("Saved at: ${task.savedDir}"),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteTask(task),
                        ),
                        onTap: () => _playVideo(task.savedDir, task.filename!, task.filename!),
                      );
                    }).toList(),
                  );
                }).toList(),
              ],
            ],
          );
        },
      ),
    );
  }
}
