import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:movie_app/tmdb_api.dart' as tmdb;
import '../story_player_screen.dart';

class StoriesSection extends StatefulWidget {
  const StoriesSection({Key? key}) : super(key: key);

  @override
  _StoriesSectionState createState() => _StoriesSectionState();
}

class _StoriesSectionState extends State<StoriesSection> {
  List<Map<String, dynamic>> _stories = [];
  int _currentIndex = 0;
  late PageController _pageController;
  Timer? _timer;
  final int itemsPerPage = 4; // Number of stories per page

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fetchStories();
    _startTimer();
  }

  Future<void> _fetchStories() async {
    try {
      // Fetch trending movies and TV shows from TMDB.
      final List<dynamic> movies = await tmdb.TMDBApi.fetchTrendingMovies();
      final List<dynamic> tvShows = await tmdb.TMDBApi.fetchTrendingTVShows();
      List<Map<String, dynamic>> storyList = [];

      // Process movies (only process if media_type is 'movie')
      for (var movie in movies) {
        if (movie['media_type'] != 'movie') continue;
        final int movieId = int.parse(movie['id'].toString());
        List<dynamic> videos = [];
        try {
          // Fetch movie trailers
          final videoResponse = await tmdb.TMDBApi.fetchTrailers(movieId);
          videos = videoResponse;
        } catch (e) {
          debugPrint("Failed to load video for movie id $movieId: $e");
        }

        // Select a video (Trailer, Teaser, Clip, or Featurette)
        String videoUrl = '';
        if (videos.isNotEmpty) {
          final selectedVideo = videos.firstWhere(
            (v) =>
                v['type'] == 'Trailer' ||
                v['type'] == 'Teaser' ||
                v['type'] == 'Clip' ||
                v['type'] == 'Featurette',
            orElse: () => videos[0],
          );
          if (selectedVideo['key'] != null) {
            videoUrl =
                'https://www.youtube.com/watch?v=${selectedVideo['key']}';
          }
        }
        // Fallback video if none found
        if (videoUrl.isEmpty) {
          videoUrl =
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
        }

        // Build image URL
        String imageUrl = movie['poster_path'] != null
            ? 'https://image.tmdb.org/t/p/w200${movie['poster_path']}'
            : 'https://source.unsplash.com/random/100x100/?movie';

        // Get the movie title by checking 'title' then 'original_title'
        String movieTitle = (movie['title']?.toString().trim() ?? '');
        if (movieTitle.isEmpty) {
          movieTitle = (movie['original_title']?.toString().trim() ?? '');
        }
        // If still empty, use a generic fallback
        if (movieTitle.isEmpty) {
          movieTitle = 'Untitled';
        }

        storyList.add({
          'name': movieTitle,
          'imageUrl': imageUrl,
          'videoUrl': videoUrl,
          'title': movieTitle,
          'description': movie['overview'] ?? 'Watch this trailer',
          'type': 'movie', // helps identify the media type
        });
      }

      // Process TV shows (unchanged)
      for (var tvShow in tvShows) {
        final int tvShowId = int.parse(tvShow['id'].toString());
        List<dynamic> videos = [];
        try {
          // Fetch TV show trailers
          final videoResponse =
              await tmdb.TMDBApi.fetchTrailers(tvShowId, isTVShow: true);
          videos = videoResponse;
        } catch (e) {
          debugPrint("Failed to load video for TV show id $tvShowId: $e");
        }

        // Select a video (Trailer, Teaser, Clip, or Featurette)
        String videoUrl = '';
        if (videos.isNotEmpty) {
          final selectedVideo = videos.firstWhere(
            (v) =>
                v['type'] == 'Trailer' ||
                v['type'] == 'Teaser' ||
                v['type'] == 'Clip' ||
                v['type'] == 'Featurette',
            orElse: () => videos[0],
          );
          if (selectedVideo['key'] != null) {
            videoUrl =
                'https://www.youtube.com/watch?v=${selectedVideo['key']}';
          }
        }
        // Fallback video if none found
        if (videoUrl.isEmpty) {
          videoUrl =
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
        }

        // Build image URL
        String imageUrl = tvShow['poster_path'] != null
            ? 'https://image.tmdb.org/t/p/w200${tvShow['poster_path']}'
            : 'https://source.unsplash.com/random/100x100/?tvshow';

        // Use the original approach for TV shows.
        String tvShowTitle = tvShow['name'] ??
            tvShow['original_name'] ??
            'TV Show';

        storyList.add({
          'name': tvShowTitle,
          'imageUrl': imageUrl,
          'videoUrl': videoUrl,
          'title': tvShowTitle,
          'description': tvShow['overview'] ?? 'Watch this trailer',
          'type': 'tvshow', // helps identify the media type
        });
      }

      setState(() {
        _stories = storyList;
      });
    } catch (e) {
      debugPrint("Error fetching stories: $e");
      // Fallback sample data
      setState(() {
        _stories = List.generate(5, (index) {
          return {
            'name': 'Movie ${index + 1}',
            'imageUrl':
                'https://source.unsplash.com/random/100x100/?movie,${index + 1}',
            'videoUrl':
                'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
            'title': 'Movie ${index + 1}',
            'description': 'Watch this trailer',
            'type': 'movie',
          };
        });
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    // Auto-advance every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_pageController.hasClients && _stories.isNotEmpty) {
  final int pageCount = (_stories.length / itemsPerPage).ceil();
  _currentIndex = (_currentIndex + 1) % pageCount;
  _pageController.animateToPage(
    _currentIndex,
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeInOut,
  );
}

    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _openStory(Map<String, dynamic> story) {
    // Get the index of the tapped story in the full list.
    final int currentIndex = _stories.indexOf(story);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryPlayerScreen(
          videoUrl: story['videoUrl'] ?? '',
          storyTitle: story['title'] ?? '',
          storyDescription: story['description'] ?? '',
          durationSeconds: 30,
          stories: _stories, // Supply the entire list.
          currentIndex: currentIndex, // Set the current index.
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // Calculate the number of pages
    final int pageCount = (_stories.length / itemsPerPage).ceil();
    return SizedBox(
      height: 150,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: pageCount,
        itemBuilder: (context, pageIndex) {
          final int startIndex = pageIndex * itemsPerPage;
          final int endIndex =
              min(startIndex + itemsPerPage, _stories.length);
          final pageStories = _stories.sublist(startIndex, endIndex);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: pageStories.map((story) {
                return GestureDetector(
                  onTap: () => _openStory(story),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.pinkAccent, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 35,
                          backgroundImage: NetworkImage(story['imageUrl']),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Wrap the title in a SizedBox with fixed width for responsiveness.
                      SizedBox(
                        width: 70,
                        child: Text(
                          story['name'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
