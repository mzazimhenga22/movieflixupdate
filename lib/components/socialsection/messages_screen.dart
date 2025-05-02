import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:movie_app/database/auth_database.dart';
import 'chat_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class MessagesScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final List<Map<String, dynamic>> otherUsers;

  const MessagesScreen({
    Key? key,
    required this.currentUser,
    required this.otherUsers,
  }) : super(key: key);

  @override
  _MessagesScreenState createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _conversations = [];
  StreamSubscription<QuerySnapshot>? _convoSubscription;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _setupFirestoreListener();
  }

  @override
  void dispose() {
    _convoSubscription?.cancel();
    super.dispose();
  }

  /// Loads conversations from the local database.
  Future<void> _loadConversations() async {
    try {
      final convos = await AuthDatabase.instance
          .getConversationsForUser(widget.currentUser['id']);
      setState(() {
        _conversations = convos;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load local conversations: $e';
      });
    }
  }

  /// Sets up a Firestore listener to sync conversations in real-time.
  void _setupFirestoreListener() {
    try {
      String userId = widget.currentUser['id'].toString();
      _convoSubscription = FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: userId)
          .snapshots()
          .listen((snapshot) async {
        if (!snapshot.metadata.hasPendingWrites) {
          final convos = snapshot.docs
              .map((doc) => {
                    'id': doc.id,
                    ...doc.data(),
                  })
              .toList();
          await _updateLocalDatabase(convos);
          _loadConversations();
          setState(() {
            _errorMessage = null;
          });
        }
      }, onError: (error) {
        setState(() {
          _errorMessage = 'Firestore error: $error';
        });
        _loadConversations();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to set up Firestore listener: $e';
      });
      _loadConversations();
    }
  }

  /// Updates the local database with Firestore data.
  Future<void> _updateLocalDatabase(List<Map<String, dynamic>> convos) async {
    try {
      await AuthDatabase.instance
          .clearConversationsForUser(widget.currentUser['id']);
      for (var convo in convos) {
        final timestamp =
            (convo['timestamp'] as Timestamp?)?.toDate().toIso8601String() ??
                '';
        final localConvo = {
          ...convo,
          'timestamp': timestamp,
        };
        await AuthDatabase.instance.insertConversation(localConvo);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to update local database: $e';
      });
    }
  }

  /// Fetches user status from Firestore.
  Future<String> _getUserStatus(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      return doc.exists ? (doc.data()?['status'] ?? 'Offline') : 'Offline';
    } catch (e) {
      return 'Offline';
    }
  }

  /// Builds a status indicator with a colored dot and text.
  Widget _buildStatusIndicator(String status) {
    Color dotColor;
    switch (status.toLowerCase()) {
      case 'online':
        dotColor = Colors.green;
        break;
      case 'busy':
        dotColor = Colors.orange;
        break;
      case 'offline':
      default:
        dotColor = Colors.red;
        break;
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          status,
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        _loadConversations();
                        _setupFirestoreListener();
                      },
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              )
            : _conversations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "No conversations yet.",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NewChatScreen(
                                  currentUser: widget.currentUser,
                                  otherUsers: widget.otherUsers,
                                ),
                              ),
                            ).then((_) => _loadConversations());
                          },
                          child: const Text("Start a Chat"),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _conversations.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final convo = _conversations[index];
                      final username =
                          convo['username']?.toString() ?? 'Unknown';
                      final userId = convo['user_id']?.toString();
                      final timestampString =
                          convo['timestamp']?.toString() ?? '';
                      String formattedTime = '';
                      if (timestampString.isNotEmpty) {
                        try {
                          final timestamp = DateTime.parse(timestampString);
                          formattedTime = DateFormat('MMM d, yyyy h:mm a')
                              .format(timestamp);
                        } catch (e) {
                          formattedTime = '';
                        }
                      }
                      return Card(
                        color: const Color(0xFF111927).withOpacity(0.85),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurpleAccent,
                            radius: 24,
                            child: Text(
                              username.isNotEmpty
                                  ? username[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20),
                            ),
                          ),
                          title: Text(
                            username,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: userId != null
                              ? FutureBuilder<String>(
                                  future: _getUserStatus(userId),
                                  builder: (context, snapshot) {
                                    String status =
                                        snapshot.data ?? 'Loading...';
                                    return _buildStatusIndicator(status);
                                  },
                                )
                              : const Text(
                                  'User ID not found',
                                  style: TextStyle(color: Colors.white70),
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (formattedTime.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Text(
                                    formattedTime,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white70),
                                  ),
                                ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: userId != null
                                    ? () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ChatScreen(
                                              currentUser: widget.currentUser,
                                              otherUser: {
                                                'id': userId,
                                                'username': username,
                                              },
                                            ),
                                          ),
                                        ).then((_) => _loadConversations());
                                      }
                                    : null,
                                child: const Text(
                                  'Chat',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          onTap: userId != null
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatScreen(
                                        currentUser: widget.currentUser,
                                        otherUser: {
                                          'id': userId,
                                          'username': username,
                                        },
                                      ),
                                    ),
                                  ).then((_) => _loadConversations());
                                }
                              : null,
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NewChatScreen(
                currentUser: widget.currentUser,
                otherUsers: widget.otherUsers,
              ),
            ),
          ).then((_) => _loadConversations());
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// NewChatScreen lets the user pick an available chat partner.
class NewChatScreen extends StatelessWidget {
  final Map<String, dynamic> currentUser;
  final List<Map<String, dynamic>> otherUsers;

  const NewChatScreen({
    Key? key,
    required this.currentUser,
    required this.otherUsers,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print('Current User ID: ${this.currentUser['id']}'); // Debug print
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Chat"),
        backgroundColor: Colors.deepPurple,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error fetching users: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          print(
              'Fetched documents: ${snapshot.data!.docs.length}'); // Debug print
          final users = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            print('User document: $data'); // Debug print
            return data;
          }).where((user) {
            final matches =
                user['id']?.toString() != this.currentUser['id']?.toString();
            print(
                'User ID: ${user['id']}, Current User ID: ${this.currentUser['id']}, Matches: $matches'); // Debug print
            return matches;
          }).toList();
          if (users.isEmpty) {
            return const Center(
              child: Text(
                'No other users found.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16.0),
            itemCount: users.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final user = users[index];
              final userId = user['id']?.toString();
              final username = user['username']?.toString() ?? 'Unknown';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.deepPurpleAccent,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(username),
                onTap: userId != null
                    ? () async {
                        try {
                          final convoId = '${this.currentUser['id']}_$userId';
                          await FirebaseFirestore.instance
                              .collection('conversations')
                              .doc(convoId)
                              .set({
                            'participants': [
                              this.currentUser['id'].toString(),
                              userId,
                            ],
                            'username': username,
                            'user_id': userId,
                            'timestamp': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                          await AuthDatabase.instance.insertConversation({
                            'id': convoId,
                            'participants': [
                              this.currentUser['id'].toString(),
                              userId,
                            ],
                            'username': username,
                            'user_id': userId,
                            'timestamp': DateTime.now().toIso8601String(),
                          });
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                currentUser: this.currentUser,
                                otherUser: {
                                  'id': userId,
                                  'username': username,
                                },
                              ),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to start chat: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
