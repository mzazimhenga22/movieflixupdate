import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movie_app/users.dart';
import 'package:movie_app/user_manager.dart';
import 'package:movie_app/database/auth_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sembast/sembast.dart' as sembast;
import 'package:sembast_web/sembast_web.dart';
import 'dart:io' show File;
import 'dart:ui';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool showAppBar;
  final Color accentColor; // Add accentColor prop

  const UserProfileScreen({
    super.key,
    required this.user,
    this.showAppBar = true,
    required this.accentColor, // Make it required
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Map<String, dynamic> _user;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String? _avatarPath;
  late Users _users;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _usernameController.text = _user['username'] ?? _user['name'] ?? "";
    _emailController.text = _user['email'] ?? "";
    _bioController.text = _user['bio'] ?? "";
    _avatarPath = _user['avatar'];
    _users = Users(
      firestore: FirebaseFirestore.instance,
      database: null,
      dbFactory: kIsWeb ? databaseFactoryWeb : null,
      userStore: sembast.stringMapStoreFactory.store('users'),
    );
  }

  ImageProvider _buildAvatarImage() {
    if (_avatarPath != null && _avatarPath!.isNotEmpty) {
      if (kIsWeb || _avatarPath!.startsWith("http")) {
        return NetworkImage(_avatarPath!);
      } else {
        return FileImage(File(_avatarPath!));
      }
    }
    return const NetworkImage("https://via.placeholder.com/200");
  }

  Future<String> uploadMedia(String path) async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      return 'https://via.placeholder.com/400';
    } catch (e) {
      debugPrint('Error uploading media: $e');
      return 'https://via.placeholder.com/150';
    }
  }

  Future<void> _editProfile() async {
    final BuildContext parentContext = context;
    await showDialog(
      context: parentContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 17, 25, 40),
          title:
              const Text("Edit Profile", style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
                    final ImagePicker picker = ImagePicker();
                    final XFile? image =
                        await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      setState(() => _avatarPath = image.path);
                    }
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundImage: _buildAvatarImage(),
                    child: _avatarPath == null
                        ? Text(
                            (_usernameController.text.isNotEmpty
                                    ? _usernameController.text[0]
                                    : "G")
                                .toUpperCase(),
                            style: const TextStyle(
                                fontSize: 40, color: Colors.white),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Username",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Email",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                TextField(
                  controller: _bioController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Bio",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child:
                  const Text("Cancel", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () async {
                String? avatarUrl = _avatarPath;
                if (_avatarPath != null && !_avatarPath!.startsWith("http")) {
                  final BuildContext uploadContext = dialogContext;
                  showDialog(
                    context: uploadContext,
                    barrierDismissible: false,
                    builder: (_) => const AlertDialog(
                      content: Row(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 16),
                          Text("Uploading avatar...")
                        ],
                      ),
                    ),
                  );
                  avatarUrl = await uploadMedia(_avatarPath!);
                  if (uploadContext.mounted) {
                    Navigator.pop(uploadContext);
                  }
                }
                _user['username'] = _usernameController.text.trim();
                _user['email'] = _emailController.text.trim();
                _user['bio'] = _bioController.text.trim();
                _user['avatar'] = avatarUrl;
                await _users.updateUser(_user);
                if (_user.containsKey('profile_id') &&
                    _user['profile_id'] != null) {
                  await AuthDatabase.instance.updateProfile({
                    'id': _user['profile_id'] as String,
                    'user_id': _user['id'] as String,
                    'avatar': avatarUrl,
                    'name': _usernameController.text.trim(),
                    'updated_at': DateTime.now().toIso8601String(),
                  });
                } else {
                  String newProfileId =
                      await AuthDatabase.instance.createProfile({
                    'user_id': _user['id'] as String,
                    'avatar': avatarUrl,
                    'name': _usernameController.text.trim(),
                    'pin': '',
                    'locked': 0,
                    'created_at': DateTime.now().toIso8601String(),
                    'updated_at': DateTime.now().toIso8601String(),
                  });
                  _user['profile_id'] = newProfileId;
                }
                if (mounted) {
                  setState(() {});
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String displayName = _user['username'] ?? _user['name'] ?? "Guest";
    final currentUser = UserManager.instance.currentUser.value;
    final currentUserId = currentUser != null && currentUser.containsKey('id')
        ? currentUser['id'] as String?
        : null;
    final isOwnProfile = _user['id'] == currentUserId;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(displayName,
                  style: const TextStyle(color: Colors.white)),
            )
          : null,
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(color: Color(0xFF111927))),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.06, -0.34),
                radius: 1.0,
                colors: [
                  widget.accentColor.withOpacity(0.5),
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
                  widget.accentColor.withOpacity(0.3),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
          Positioned.fill(
            top: widget.showAppBar
                ? kToolbarHeight + MediaQuery.of(context).padding.top
                : 0,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.5,
                    colors: [
                      widget.accentColor.withOpacity(0.3),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(0.5),
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
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          top: widget.showAppBar ? 24.0 : 80.0,
                          left: 24.0,
                          right: 24.0,
                          bottom: 24.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 60,
                                backgroundColor: widget.accentColor,
                                child: ClipOval(
                                  child: Image(
                                    image: _buildAvatarImage(),
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Text(
                                          displayName.isNotEmpty
                                              ? displayName[0].toUpperCase()
                                              : "G",
                                          style: const TextStyle(
                                            fontSize: 48,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              displayName,
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black45,
                                      offset: Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ]),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Followers: ${_user['followers_count'] ?? 0}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'Following: ${_user['following_count'] ?? 0}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _user['email'] ?? "",
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _user['bio'] ?? "No bio available.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.8)),
                            ),
                            const SizedBox(height: 16),
                            if (!isOwnProfile && currentUserId != null)
                              FutureBuilder<bool>(
                                future: AuthDatabase.instance
                                    .isFollowing(currentUserId, _user['id']),
                                builder:
                                    (BuildContext futureContext, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const CircularProgressIndicator();
                                  }
                                  final isFollowing = snapshot.data ?? false;
                                  return ElevatedButton(
                                    onPressed: () async {
                                      if (isFollowing) {
                                        await AuthDatabase.instance
                                            .unfollowUser(
                                                currentUserId, _user['id']);
                                        setState(() {
                                          _user['followers_count'] =
                                              (_user['followers_count'] ?? 1) -
                                                  1;
                                        });
                                      } else {
                                        await AuthDatabase.instance.followUser(
                                            currentUserId, _user['id']);
                                        setState(() {
                                          _user['followers_count'] =
                                              (_user['following_count'] ?? 0) +
                                                  1;
                                        });
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: widget.accentColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                    ),
                                    child: Text(
                                        isFollowing ? 'Unfollow' : 'Follow'),
                                  );
                                },
                              ),
                            const SizedBox(height: 24),
                            if (isOwnProfile)
                              ElevatedButton.icon(
                                onPressed: _editProfile,
                                icon: const Icon(Icons.edit),
                                label: const Text("Edit Profile"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.accentColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 20),
                                ),
                              ),
                            const SizedBox(height: 24),
                            const Divider(color: Colors.white54, thickness: 1),
                            const SizedBox(height: 16),
                            const Text(
                              "User's Posts",
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black45,
                                      offset: Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ]),
                            ),
                            const SizedBox(height: 16),
                            Card(
                              elevation: 6,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      widget.accentColor.withOpacity(0.2),
                                      widget.accentColor.withOpacity(0.4),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          widget.accentColor.withOpacity(0.5)),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text(
                                    "User posts will be shown here.",
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.white70),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Divider(color: Colors.white54, thickness: 1),
                            const SizedBox(height: 16),
                            const Text(
                              "Find Users",
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black45,
                                      offset: Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ]),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: "Search by username or email",
                                hintStyle: TextStyle(
                                    color: Colors.white.withOpacity(0.6)),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.2),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon: const Icon(Icons.search,
                                    color: Colors.white),
                              ),
                              onChanged: (value) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _users
                                  .searchUsers(_searchController.text.trim()),
                              builder: (BuildContext futureContext, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const CircularProgressIndicator();
                                }
                                if (snapshot.hasError) {
                                  return Text(
                                    'Error: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.white),
                                  );
                                }
                                final users = snapshot.data!
                                    .where((u) => u['id'] != _user['id'])
                                    .toList();
                                if (users.isEmpty) {
                                  return const Text(
                                    "No users found.",
                                    style: TextStyle(color: Colors.white),
                                  );
                                }
                                return ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: users.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(color: Colors.white54),
                                  itemBuilder: (context, index) {
                                    final otherUser = users[index];
                                    String otherUserName =
                                        otherUser['username'] ??
                                            otherUser['name'] ??
                                            "Guest";
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: widget.accentColor,
                                        backgroundImage: otherUser['avatar'] !=
                                                    null &&
                                                otherUser['avatar'].isNotEmpty
                                            ? NetworkImage(otherUser['avatar'])
                                            : null,
                                        child: otherUser['avatar'] == null ||
                                                otherUser['avatar'].isEmpty
                                            ? Text(
                                                otherUserName.isNotEmpty
                                                    ? otherUserName[0]
                                                        .toUpperCase()
                                                    : "G",
                                                style: const TextStyle(
                                                    color: Colors.white),
                                              )
                                            : null,
                                      ),
                                      title: Text(
                                        otherUserName,
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                      subtitle: Text(
                                        otherUser['email'] ?? "",
                                        style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.6)),
                                      ),
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserProfileScreen(
                                            user: otherUser,
                                            showAppBar: true,
                                            accentColor: widget
                                                .accentColor, // Pass accentColor
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
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
