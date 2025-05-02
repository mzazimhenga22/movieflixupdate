import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class FeaturedMovieCard extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String releaseDate;
  final List<int> genres;
  final double rating;
  final String trailerUrl;
  final bool isCurrentPage; // New: Indicates if this card is currently visible
  final VoidCallback? onTap;

  const FeaturedMovieCard({
    Key? key,
    required this.imageUrl,
    required this.title,
    required this.releaseDate,
    required this.genres,
    required this.rating,
    required this.trailerUrl,
    required this.isCurrentPage,
    this.onTap,
  }) : super(key: key);

  @override
  _FeaturedMovieCardState createState() => _FeaturedMovieCardState();
}

class _FeaturedMovieCardState extends State<FeaturedMovieCard> {
  bool isFavorite = false;
  bool _showVideo = false;
  Timer? _videoTimer;
  YoutubePlayerController? _videoController;

  final Map<int, String> genreMap = {
    28: "Action",
    12: "Adventure",
    16: "Animation",
    35: "Comedy",
    80: "Crime",
    18: "Drama",
    10749: "Romance",
    878: "Sci-Fi",
  };

  String getGenresText() {
    return widget.genres.map((id) => genreMap[id] ?? "Unknown").join(', ');
  }

  @override
  void didUpdateWidget(FeaturedMovieCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrentPage != oldWidget.isCurrentPage) {
      if (widget.isCurrentPage) {
        // Start timer to switch to video after 3 seconds when card is current
        _videoTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && widget.isCurrentPage && widget.trailerUrl.isNotEmpty) {
            final videoId = YoutubePlayer.convertUrlToId(widget.trailerUrl);
            if (videoId != null) {
              setState(() {
                _showVideo = true;
                _videoController = YoutubePlayerController(
                  initialVideoId: videoId,
                  flags: const YoutubePlayerFlags(
                    autoPlay: true,
                    mute: false,
                    hideControls: true,
                    controlsVisibleAtStart: false,
                  ),
                );
              });
            }
          }
        });
      } else {
        // Cancel timer and pause video when card is no longer current
        _videoTimer?.cancel();
        if (_videoController != null) {
          _videoController!.pause();
          _videoController!.dispose();
          _videoController = null;
        }
        setState(() {
          _showVideo = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: _showVideo && _videoController != null
                    ? YoutubePlayer(
                        key: const ValueKey('video'),
                        controller: _videoController!,
                        showVideoProgressIndicator: false,
                        aspectRatio: 16 / 9,
                      )
                    : Hero(
                        key: const ValueKey('image'),
                        tag: widget.imageUrl,
                        child: Image.network(
                          widget.imageUrl,
                          height: 320,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 320,
                              color: Colors.black12,
                              child: const Center(child: CircularProgressIndicator()),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 320,
                            color: Colors.grey,
                            child: const Center(
                              child: Icon(Icons.error, color: Colors.red, size: 50),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black,
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Release Date: ${widget.releaseDate}',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.yellow, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            widget.rating.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Genres: ${getGenresText()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: widget.onTap,
                        icon: const Icon(Icons.play_arrow, color: Colors.black),
                        label: const Text('Watch Trailer', style: TextStyle(color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            isFavorite = !isFavorite;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isFavorite
                                ? Colors.redAccent
                                : Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: isFavorite ? Colors.white : Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 