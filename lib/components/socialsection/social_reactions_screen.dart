import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movie_app/helpers/movie_account_helper.dart';
import 'stories.dart';
import 'package:movie_app/database/auth_database.dart';
import 'messages_screen.dart';
import 'search_screen.dart';
import 'user_profile_screen.dart';
import 'realtime_feed_service.dart';
import 'streak_section.dart';
import 'notifications_section.dart';
export 'watch_party_screen.dart';
import 'chat_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:movie_app/components/trending_movies_widget.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class SocialReactionsScreen extends StatefulWidget {
  final Color accentColor; // Define accentColor as a required prop
  const SocialReactionsScreen({Key? key, required this.accentColor})
      : super(key: key);

  @override
  SocialReactionsScreenState createState() => SocialReactionsScreenState();
}

class SocialReactionsScreenState extends State<SocialReactionsScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _users = [];
  final List<String> _notifications = [];
  List<Map<String, dynamic>> _stories = [];
  int _movieStreak = 0;
  List<Map<String, dynamic>> _feedPosts = [];
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _checkMovieAccount();
    await _loadLocalData();
    await _loadFeedPostsFromLocal();
    await _loadUsers();
    await _loadUserData();
    RealtimeFeedService.instance.updateFeedPosts(
      _feedPosts
          .map((e) => e.map((key, value) => MapEntry(key, value.toString())))
          .toList(),
    );
  }

  Future<void> _checkMovieAccount() async {
    try {
      bool exists = await MovieAccountHelper.doesMovieAccountExist();
      if (exists) {
        final movieData = await MovieAccountHelper.getMovieAccountData();
      }
    } catch (e) {
      debugPrint('Error checking movie account: $e');
    }
  }

  Future<void> _loadLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storiesString = prefs.getString('stories');
      final movieStreak = prefs.getInt('movieStreak');
      if (storiesString != null) {
        _stories = List<Map<String, dynamic>>.from(jsonDecode(storiesString));
      }
      if (movieStreak != null) {
        _movieStreak = movieStreak;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading local data: $e');
    }
  }

  Future<void> _saveLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('stories', jsonEncode(_stories));
      await prefs.setInt('movieStreak', _movieStreak);
    } catch (e) {
      debugPrint('Error saving local data: $e');
    }
  }

  Future<void> _loadFeedPostsFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final feedPostsString = prefs.getString('feedPosts');
      if (feedPostsString != null) {
        _feedPosts =
            List<Map<String, dynamic>>.from(jsonDecode(feedPostsString));
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading feed posts: $e');
    }
  }

  Future<void> _saveFeedPostsToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('feedPosts', jsonEncode(_feedPosts));
    } catch (e) {
      debugPrint('Error saving feed posts: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentUserEmail');
      if (email != null) {
        final userData = await AuthDatabase.instance.getUserByEmail(email);
        if (!mounted) return;
        setState(() => _currentUser = userData);
      } else if (_users.isNotEmpty) {
        _currentUser = _users.first;
        await prefs.setString('currentUserEmail', _currentUser!['email']);
        if (!mounted) return;
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadUsers() async {
    try {
      final users = await AuthDatabase.instance.getUsers();
      if (mounted) {
        setState(() =>
            _users = users.map((u) => Map<String, dynamic>.from(u)).toList());
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
    }
  }

  void _onTabTapped(int index) {
    if (mounted) setState(() => _selectedIndex = index);
  }

  String _generateWatchCode() => (100000 + Random().nextInt(900000)).toString();

  Future<String> uploadMedia(String path, String type) async {
    try {
      final file = File(path);
      final mediaId = const Uuid().v4();
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('media/$mediaId.${type == 'photo' ? 'jpg' : 'mp4'}');
      await storageRef.putFile(file);
      final url = await storageRef.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint('Error uploading media: $e');
      return 'https://via.placeholder.com/150';
    }
  }

  Future<void> _postStory() async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text("Upload Photo"),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text("Upload Video"),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );

    if (choice != null && mounted) {
      final pickedFile = choice == 'photo'
          ? await picker.pickImage(source: ImageSource.gallery)
          : await picker.pickVideo(source: ImageSource.gallery);
      if (pickedFile != null) {
        final localPath = pickedFile.path;
        final user = _currentUser?['username'] ?? 'CurrentUser';
        final timestamp = DateTime.now().toIso8601String();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text("Uploading..."),
              ],
            ),
          ),
        );
        final uploadedUrl = await uploadMedia(localPath, choice);
        if (!mounted) return;
        Navigator.pop(context);
        if (uploadedUrl.isNotEmpty) {
          final story = {
            'user': user,
            'userId': _currentUser?['id'].toString() ?? '',
            'media': uploadedUrl,
            'type': choice,
            'timestamp': timestamp,
          };
          final docRef =
              await FirebaseFirestore.instance.collection('stories').add(story);
          setState(() {
            story['id'] = docRef.id;
            _stories.add(story);
            final newPost = {
              'user': user,
              'post': '$user posted a story.',
              'type': 'story',
              'liked': 'false',
            };
            _feedPosts.add(newPost);
            RealtimeFeedService.instance.addPost(
                newPost.map((key, value) => MapEntry(key, value.toString())));
          });
          await _saveFeedPostsToLocal();
          await _saveLocalData();
        }
      }
    }
  }

  Future<void> _postMovieReview() async {
    final movieController = TextEditingController();
    final reviewController = TextEditingController();
    String? mediaPath;
    String? mediaType;

    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color.fromARGB(255, 17, 25, 40),
            title: const Text("Write a Movie Review",
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: movieController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "Movie Name",
                      hintStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reviewController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "Enter your review...",
                      hintStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  mediaPath != null
                      ? mediaType == 'photo'
                          ? Image.file(
                              File(mediaPath!),
                              height: 150,
                              fit: BoxFit.cover,
                            )
                          : const Text("Video selected",
                              style: TextStyle(color: Colors.white70))
                      : const SizedBox(),
                  TextButton.icon(
                    icon: const Icon(Icons.image, color: Colors.white70),
                    label: const Text("Pick Media",
                        style: TextStyle(color: Colors.white70)),
                    onPressed: () async {
                      final choice = await showModalBottomSheet<String>(
                        context: context,
                        builder: (context) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.photo,
                                    color: Colors.white),
                                title: const Text("Upload Photo",
                                    style: TextStyle(color: Colors.white)),
                                onTap: () => Navigator.pop(context, 'photo'),
                              ),
                              ListTile(
                                leading: const Icon(Icons.videocam,
                                    color: Colors.white),
                                title: const Text("Upload Video",
                                    style: TextStyle(color: Colors.white)),
                                onTap: () => Navigator.pop(context, 'video'),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (choice != null) {
                        final picked = choice == 'photo'
                            ? await ImagePicker()
                                .pickImage(source: ImageSource.gallery)
                            : await ImagePicker()
                                .pickVideo(source: ImageSource.gallery);
                        if (picked != null) {
                          setStateDialog(() {
                            mediaPath = picked.path;
                            mediaType = choice;
                          });
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel",
                    style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () {
                  if (movieController.text.trim().isEmpty ||
                      reviewController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Please fill in all fields")),
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    'movie': movieController.text.trim(),
                    'review': reviewController.text.trim(),
                    'media': mediaPath,
                    'mediaType': mediaType,
                  });
                },
                child:
                    const Text("Post", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    ).then((result) async {
      if (result != null && mounted) {
        String? mediaUrl;
        if (result['media'] != null) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text("Uploading media..."),
                ],
              ),
            ),
          );
          mediaUrl = await uploadMedia(result['media']!, result['mediaType']!);
          Navigator.pop(context);
          if (mediaUrl.isEmpty) {
            mediaUrl = 'https://via.placeholder.com/150';
          }
        } else {
          mediaUrl = '';
        }
        if (!mounted) return;
        final newPost = {
          'user': _currentUser?['username'] ?? 'CurrentUser',
          'post': "Reviewed ${result['movie']}: ${result['review']}",
          'type': 'review',
          'liked': 'false',
          'movie': result['movie'],
          'media': mediaUrl,
          'mediaType': result['mediaType'] ?? '',
        };
        final docRef =
            await FirebaseFirestore.instance.collection('feeds').add(newPost);
        setState(() {
          newPost['id'] = docRef.id;
          _feedPosts.add(newPost);
          RealtimeFeedService.instance.addPost(
            newPost.map((key, value) => MapEntry(key, value.toString())),
          );
          _notifications.add(
              "${_currentUser?['username'] ?? 'CurrentUser'} posted a review for ${result['movie']}");
        });
        await _saveFeedPostsToLocal();
      }
    });
  }

  Widget _buildFeedTab() {
    return Container(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor, // Use prop
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              ),
              onPressed: _postMovieReview,
              icon: const Icon(Icons.rate_review),
              label: const Text("Post Movie Review"),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('feeds').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white)));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final posts = snapshot.data!.docs
                    .map((doc) => {
                          ...doc.data() as Map<String, dynamic>,
                          'id': doc.id,
                        })
                    .toList();
                if (posts.isEmpty) {
                  return const Center(
                      child: Text("No posts available.",
                          style: TextStyle(color: Colors.white)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12.0),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    final user = _users.firstWhere(
                      (u) => u['username'] == post['user'],
                      orElse: () => {
                        'username': post['user'],
                        'avatar':
                            "https://source.unsplash.com/random/200x200/?face",
                      },
                    );
                    if (post['type'] == 'review') {
                      return Card(
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.accentColor.withOpacity(0.2), // Use prop
                                widget.accentColor.withOpacity(0.4), // Use prop
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: widget.accentColor
                                    .withOpacity(0.5)), // Use prop
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                    backgroundImage:
                                        NetworkImage(user['avatar']),
                                    radius: 24),
                                title: Text(post['user'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black45,
                                          offset: Offset(1, 1),
                                          blurRadius: 2,
                                        ),
                                      ],
                                    )),
                              ),
                              (post['media']?.isNotEmpty ?? false)
                                  ? CachedNetworkImage(
                                      imageUrl: post['media']!,
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          const Center(
                                              child:
                                                  CircularProgressIndicator()),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        height: 200,
                                        color: Colors.grey[300],
                                        child: const Center(
                                            child: Icon(Icons.error, size: 50)),
                                      ),
                                    )
                                  : Container(
                                      height: 200,
                                      color: Colors.grey[300],
                                      child: const Center(
                                          child: Icon(Icons.image, size: 50)),
                                    ),
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(post['post'] ?? '',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.white70)),
                                    const SizedBox(height: 8),
                                    Text("Movie: ${post['movie'] ?? 'Unknown'}",
                                        style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.white70)),
                                  ],
                                ),
                              ),
                              const Divider(color: Colors.white54),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      (post['liked'] == 'true')
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: (post['liked'] == 'true')
                                          ? Colors.red
                                          : Colors.white.withOpacity(0.5),
                                    ),
                                    onPressed: () {
                                      if (!mounted) return;
                                      setState(() {
                                        final updatedPost =
                                            Map<String, dynamic>.from(post);
                                        updatedPost['liked'] =
                                            (updatedPost['liked'] != 'true')
                                                .toString();
                                        FirebaseFirestore.instance
                                            .collection('feeds')
                                            .doc(post['id'])
                                            .update(updatedPost);
                                      });
                                    },
                                  ),
                                  IconButton(
                                      icon: Icon(Icons.comment,
                                          color: Colors.white.withOpacity(0.5)),
                                      onPressed: () => _showComments(post)),
                                  IconButton(
                                      icon: Icon(Icons.share,
                                          color: Colors.white.withOpacity(0.5)),
                                      onPressed: () => _sharePost(post)),
                                  IconButton(
                                    icon: Icon(Icons.send,
                                        color: Colors.white.withOpacity(0.5)),
                                    onPressed: () {
                                      String code = _generateWatchCode();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  "Started Watch Party: Code $code")));
                                      _notifications.add(
                                          "${_currentUser?['username'] ?? 'CurrentUser'} started a watch party with code $code");
                                    },
                                  ),
                                  if (post['userId'] == _currentUser?['id'])
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () async {
                                        await FirebaseFirestore.instance
                                            .collection('feeds')
                                            .doc(post['id'])
                                            .delete();
                                        setState(() {
                                          _feedPosts.removeWhere(
                                              (p) => p['id'] == post['id']);
                                        });
                                        await _saveFeedPostsToLocal();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      return Card(
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.accentColor.withOpacity(0.2), // Use prop
                                widget.accentColor.withOpacity(0.4), // Use prop
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: widget.accentColor
                                    .withOpacity(0.5)), // Use prop
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                    backgroundImage:
                                        NetworkImage(user['avatar']),
                                    radius: 24),
                                title: Text(post['user'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black45,
                                          offset: Offset(1, 1),
                                          blurRadius: 2,
                                        ),
                                      ],
                                    )),
                                subtitle: Text(post['post'] ?? '',
                                    style:
                                        const TextStyle(color: Colors.white70)),
                              ),
                              const Divider(color: Colors.white54),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      (post['liked'] == 'true')
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: (post['liked'] == 'true')
                                          ? Colors.red
                                          : Colors.white.withOpacity(0.5),
                                    ),
                                    onPressed: () {
                                      if (!mounted) return;
                                      setState(() {
                                        final updatedPost =
                                            Map<String, dynamic>.from(post);
                                        updatedPost['liked'] =
                                            (updatedPost['liked'] != 'true')
                                                .toString();
                                        FirebaseFirestore.instance
                                            .collection('feeds')
                                            .doc(post['id'])
                                            .update(updatedPost);
                                      });
                                    },
                                  ),
                                  IconButton(
                                      icon: Icon(Icons.comment,
                                          color: Colors.white.withOpacity(0.5)),
                                      onPressed: () => _showComments(post)),
                                  IconButton(
                                      icon: Icon(Icons.share,
                                          color: Colors.white.withOpacity(0.5)),
                                      onPressed: () => _sharePost(post)),
                                  IconButton(
                                    icon: Icon(Icons.send,
                                        color: Colors.white.withOpacity(0.5)),
                                    onPressed: () {
                                      String code = _generateWatchCode();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  "Started Watch Party: Code $code")));
                                      _notifications.add(
                                          "${_currentUser?['username'] ?? 'CurrentUser'} started a watch party with code $code");
                                    },
                                  ),
                                  if (post['userId'] == _currentUser?['id'])
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () async {
                                        await FirebaseFirestore.instance
                                            .collection('feeds')
                                            .doc(post['id'])
                                            .delete();
                                        setState(() {
                                          _feedPosts.removeWhere(
                                              (p) => p['id'] == post['id']);
                                        });
                                        await _saveFeedPostsToLocal();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Recommended Movies",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black45,
                          offset: Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    )),
                const SizedBox(height: 8),
                const TrendingMoviesWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showComments(Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color.fromARGB(255, 17, 25, 40),
      builder: (context) {
        final controller = TextEditingController();
        List<String> comments = [];
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Text("Comments",
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Expanded(
                    child: ListView.builder(
                      itemCount: comments.length,
                      itemBuilder: (_, i) => ListTile(
                          title: Text(comments[i],
                              style: const TextStyle(color: Colors.white70))),
                    ),
                  ),
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Add a comment",
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor, // Use prop
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {
                      if (controller.text.isNotEmpty) {
                        setModalState(() => comments.add(controller.text));
                        controller.clear();
                      }
                    },
                    child: const Text("Post"),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _sharePost(Map<String, dynamic> post) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Shared post: ${post['post'] ?? 'Unknown'}")),
    );
  }

  Widget _buildStoriesTab() {
    return Container(
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('stories').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white)));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final stories = snapshot.data!.docs
                    .map((doc) => {
                          ...doc.data() as Map<String, dynamic>,
                          'id': doc.id,
                        })
                    .where((story) {
                  final DateTime storyTime = DateTime.parse(story['timestamp']);
                  return DateTime.now().difference(storyTime) <
                      const Duration(hours: 24);
                }).toList();
                if (stories.isEmpty) {
                  return const Center(
                      child: Text("No stories available.",
                          style: TextStyle(color: Colors.white)));
                }
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: stories.length,
                  itemBuilder: (context, index) {
                    final story = stories[index];
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoryScreen(
                              stories: stories,
                              initialIndex: index,
                              currentUserId:
                                  (_currentUser?['id'] ?? '').toString(),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                                radius: 40,
                                backgroundImage: NetworkImage(story['media'])),
                            Text(story['user'] ?? 'Unknown',
                                style: const TextStyle(
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black45,
                                      offset: Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accentColor, // Use prop
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            ),
            onPressed: _postStory,
            icon: const Icon(Icons.add_a_photo),
            label: const Text("Post Story"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildFeedTab(),
      _buildStoriesTab(),
      NotificationsSection(notifications: _notifications),
      StreakSection(
        movieStreak: _movieStreak,
        onStreakUpdated: (newStreak) {
          if (mounted) setState(() => _movieStreak = newStreak);
        },
      ),
      _currentUser != null
          ? UserProfileScreen(
              user: _currentUser!,
              showAppBar: false,
              accentColor: widget.accentColor, // Pass the accentColor prop
            )
          : const Center(child: CircularProgressIndicator()),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title:
            const Text("Social section", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.message, color: Colors.white),
            onPressed: () => _currentUser != null
                ? Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MessagesScreen(
                        currentUser: _currentUser!,
                        otherUsers: _users
                            .where((u) => u['email'] != _currentUser!['email'])
                            .toList(),
                      ),
                    ),
                  )
                : ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("User data not loaded"))),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          if (_currentUser != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                  child: Text("Hello, ${_currentUser!['username']}",
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: Colors.white))),
            ),
        ],
      ),
      body: Theme(
        data: ThemeData.dark(),
        child: Stack(
          children: [
            Container(
                decoration: const BoxDecoration(color: Color(0xFF111927))),
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.06, -0.34),
                  radius: 1.0,
                  colors: [
                    widget.accentColor.withOpacity(0.5), // Use prop
                    const Color.fromARGB(255, 0, 0, 0),
                  ],
                  stops: const [0.0, 0.59],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.64, 0.3),
                  radius: 1.0,
                  colors: [
                    widget.accentColor.withOpacity(0.3), // Use prop
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55],
                ),
              ),
            ),
            Positioned.fill(
              top: kToolbarHeight + MediaQuery.of(context).padding.top,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.5,
                      colors: [
                        widget.accentColor.withOpacity(0.3), // Use prop
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor.withOpacity(0.5), // Use prop
                        blurRadius: 12,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(160, 17, 19, 40),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.125)),
                        ),
                        child: tabs[_selectedIndex],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.accentColor, // Use prop
        onPressed: () => _currentUser != null
            ? Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewChatScreen(
                    currentUser: _currentUser!,
                    otherUsers: _users
                        .where((u) => u['email'] != _currentUser!['email'])
                        .toList(),
                    accentColor: widget.accentColor, // Pass to NewChatScreen
                  ),
                ),
              )
            : ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("User data not loaded"))),
        child: const Icon(Icons.message, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        backgroundColor: Colors.black54,
        selectedItemColor: const Color(0xffffeb00),
        unselectedItemColor: widget.accentColor.withOpacity(0.6), // Use prop
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Feed"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Stories"),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: "Notifications"),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_fire_department), label: "Streak"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

class NewChatScreen extends StatelessWidget {
  final Map<String, dynamic> currentUser;
  final List<Map<String, dynamic>> otherUsers;
  final Color accentColor; // Add accentColor prop

  const NewChatScreen({
    Key? key,
    required this.currentUser,
    required this.otherUsers,
    required this.accentColor, // Make it required
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("New Chat", style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(color: Color(0xFF111927))),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.06, -0.34),
                radius: 1.0,
                colors: [
                  accentColor.withOpacity(0.5),
                  const Color.fromARGB(255, 0, 0, 0),
                ],
                stops: const [0.0, 0.59],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.64, 0.3),
                radius: 1.0,
                colors: [
                  accentColor.withOpacity(0.3),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
          Positioned.fill(
            top: kToolbarHeight + MediaQuery.of(context).padding.top,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.5,
                    colors: [
                      accentColor.withOpacity(0.3),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(0.5),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(160, 17, 19, 40),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.125)),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: otherUsers.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white54),
                        itemBuilder: (context, index) {
                          final user = otherUsers[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: accentColor,
                              child: Text(
                                user['username'][0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(user['username'],
                                style: const TextStyle(color: Colors.white)),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  currentUser: currentUser,
                                  otherUser: {
                                    'id': user['id'],
                                    'username': user['username']
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
