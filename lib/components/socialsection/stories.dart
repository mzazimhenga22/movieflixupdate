// stories.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StoryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final int initialIndex;
  final void Function(String type, Map<String, dynamic> data)?
      onStoryInteraction;
  final String currentUserId;

  const StoryScreen({
    Key? key,
    required this.stories,
    required this.currentUserId,
    this.initialIndex = 0,
    this.onStoryInteraction,
  }) : super(key: key);

  @override
  _StoryScreenState createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  VideoPlayerController? _videoController;
  int _currentIndex = 0;
  final TextEditingController _replyController = TextEditingController();
  late List<Map<String, dynamic>> _activeStories;
  final FocusNode _replyFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _activeStories = widget.stories;
    _currentIndex = widget.initialIndex.clamp(0, _activeStories.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )
      ..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _nextStory();
      });
    _loadStory(_currentIndex);

    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _animationController.stop();
        if (_videoController != null && _videoController!.value.isPlaying) {
          _videoController!.pause();
        }
      } else {
        if (_videoController != null) {
          _videoController!.play();
        } else {
          _animationController.forward();
        }
      }
    });
  }

  void _loadStory(int index) {
    _animationController.reset();
    _videoController?.dispose();
    final story = _activeStories[index];
    final DateTime storyTime = DateTime.parse(story['timestamp']);
    if (DateTime.now().difference(storyTime) >= const Duration(hours: 24)) {
      _deleteStory(index);
      return;
    }
    if (story['type'] == 'video') {
      _videoController = VideoPlayerController.network(story['media'])
        ..initialize().then((_) {
          setState(() {
            _videoController!.play();
            _animationController.duration = _videoController!.value.duration;
            _animationController.forward();
          });
        });
    } else {
      _animationController.duration = const Duration(seconds: 5);
      _animationController.forward();
    }
  }

  void _nextStory() {
    if (_currentIndex < _activeStories.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    }
  }

  void _deleteStory(int index) {
    final story = _activeStories[index];
    if (story['userId'] == widget.currentUserId) {
      FirebaseFirestore.instance
          .collection('stories')
          .doc(story['id'])
          .delete();
      setState(() {
        _activeStories.removeAt(index);
        if (_activeStories.isEmpty) {
          Navigator.pop(context);
          return;
        }
        _currentIndex = index.clamp(0, _activeStories.length - 1);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Story deleted.")));
    }
  }

  void _updateChatWithInteraction(String type, String content) {
    if (widget.onStoryInteraction != null) {
      widget.onStoryInteraction!(type, {
        'storyUser': _activeStories[_currentIndex]['user'],
        'storyUserId': _activeStories[_currentIndex]['userId'],
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _videoController?.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeStories.isEmpty) {
      return const Scaffold(body: Center(child: Text("No active stories")));
    }
    final story = _activeStories[_currentIndex];
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! > 0) {
              _previousStory();
            } else if (details.primaryVelocity! < 0) {
              _nextStory();
            }
          }
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _activeStories.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                _loadStory(index);
              },
              itemBuilder: (context, index) {
                final story = _activeStories[index];
                return Stack(
                  children: [
                    Center(
                      child: story['type'] == 'video' &&
                              _videoController != null &&
                              _videoController!.value.isInitialized
                          ? AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            )
                          : CachedNetworkImage(
                              imageUrl: story['media'],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) =>
                                  const Center(
                                      child: Icon(Icons.broken_image,
                                          size: 50, color: Colors.white)),
                            ),
                    ),
                    Positioned(
                      top: 40,
                      left: 16,
                      right: 16,
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _animationController.value,
                            backgroundColor: Colors.white54,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                story['user'],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 18),
                              ),
                              if (story['userId'] == widget.currentUserId)
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  onPressed: () => _deleteStory(index),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  children: [
                    if (story['userId'] != widget.currentUserId) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.favorite_border,
                                color: Colors.white),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        "Liked story by ${story['user']}")),
                              );
                              _updateChatWithInteraction("like", "");
                            },
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.comment, color: Colors.white),
                            onPressed: () {
                              FocusScope.of(context)
                                  .requestFocus(_replyFocusNode);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.share, color: Colors.white),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Shared story")),
                              );
                              _updateChatWithInteraction("share", "");
                            },
                          ),
                        ],
                      ),
                      TextField(
                        controller: _replyController,
                        focusNode: _replyFocusNode,
                        decoration: InputDecoration(
                          hintText: "Reply to ${story['user']}...",
                          hintStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.black54,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (value) {
                          if (value.trim().isEmpty) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Replied: $value")),
                          );
                          _updateChatWithInteraction("reply", value);
                          _replyController.clear();
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
