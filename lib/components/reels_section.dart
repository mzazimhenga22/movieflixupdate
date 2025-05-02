import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:movie_app/tmdb_api.dart'; // Your TMDB API helper
import '../reel_player_screen.dart'; // Adjust the import as necessary
import '../models/reel.dart'; // Import the shared Reel model

class ReelsSection extends StatefulWidget {
  const ReelsSection({Key? key}) : super(key: key);

  @override
  _ReelsSectionState createState() => _ReelsSectionState();
}

class _ReelsSectionState extends State<ReelsSection>
    with SingleTickerProviderStateMixin {
  List<dynamic> reelsData = [];
  late AnimationController _controller;
  late Animation<double> _shineAnimation;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _shineAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _isInitialized = true; // Mark as initialized after setting up animation
    fetchReels();
  }

  Future<void> fetchReels() async {
    try {
      final fetchedReels = await TMDBApi.fetchReels();
      if (mounted) {
        setState(() {
          reelsData = fetchedReels;
        });
      }
    } catch (e) {
      print("Error fetching reels: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 10.0),
          child: _isInitialized
              ? AnimatedBuilder(
                  animation: _shineAnimation,
                  builder: (context, child) {
                    return ShaderMask(
                      shaderCallback: (rect) {
                        return LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.red.withOpacity(0.8 - _shineAnimation.value * 0.4),
                            Colors.redAccent.withOpacity(0.8 + _shineAnimation.value * 0.4),
                            Colors.red.withOpacity(0.8 - _shineAnimation.value * 0.4),
                          ],
                          stops: [
                            0.0,
                            0.5 + _shineAnimation.value * 0.5,
                            1.0,
                          ],
                        ).createShader(rect);
                      },
                      child: const Text(
                        "Movie Reels",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.red, // Base color for non-shader fallback
                          shadows: [
                            Shadow(
                              color: Colors.red,
                              blurRadius: 10,
                              offset: Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                )
              : const Text(
                  "Movie Reels",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
        ),
        SizedBox(
          height: 360,
          child: reelsData.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: reelsData.length,
                  itemBuilder: (context, index) {
                    final reel = reelsData[index];
                    final title = reel['title'] ?? "Reel";
                    final thumbnailUrl = reel['thumbnail_url'] ?? "";

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 20.0),
                      child: GestureDetector(
                        onTap: () {
                          final List<Reel> reels = reelsData.map<Reel>((r) {
                            return Reel(
                              videoUrl: r['videoUrl'] ?? "",
                              movieTitle: r['title'] ?? "Reel",
                              movieDescription: "Watch the trailer",
                            );
                          }).toList();

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReelPlayerScreen(
                                reels: reels,
                                initialIndex: index,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: 160,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.deepPurple.withOpacity(0.4),
                                Colors.black.withOpacity(0.2),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepPurple.withOpacity(0.6),
                                blurRadius: 15,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(180, 17, 19, 40),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 2.0,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: thumbnailUrl.isNotEmpty
                                            ? Image.network(
                                                thumbnailUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) => Container(
                                                  color: Colors.grey[900],
                                                  child: const Icon(Icons.error, color: Colors.red, size: 40),
                                                ),
                                              )
                                            : Container(
                                                color: Colors.grey[900],
                                                child: const Icon(Icons.movie, color: Colors.white70, size: 40),
                                              ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withOpacity(0.7),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 10,
                                      left: 10,
                                      right: 10,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 4,
                                                  offset: Offset(1, 1),
                                                ),
                                              ],
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Container(
                                              padding: const EdgeInsets.all(6.0),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.deepPurpleAccent.withOpacity(0.9),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.deepPurple.withOpacity(0.5),
                                                    blurRadius: 8,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.play_arrow,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}