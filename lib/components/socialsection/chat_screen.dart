import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:movie_app/database/auth_database.dart';
import 'chat_settings_screen.dart';
import 'stories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final Map<String, dynamic> otherUser;
  final List<Map<String, dynamic>> storyInteractions;

  const ChatScreen({
    Key? key,
    required this.currentUser,
    required this.otherUser,
    this.storyInteractions = const [],
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Map<String, dynamic>> _messages = [];
  late List<Map<String, dynamic>> _interactions;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int? _replyingToMessageId;

  // Chat background settings
  Color _chatBgColor = Colors.white;
  String? _chatBgImage;
  String? _cinematicTheme;

  // Search settings
  String _searchTerm = "";
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Callback for when a story interaction occurs
  void _handleStoryInteraction(String type, Map<String, dynamic> data) {
    if (type == 'reply') {
      final replyText = data['content'];
      final newMessage = {
        'sender_id': widget.currentUser['id'],
        'receiver_id': data['storyUserId'],
        'message': replyText,
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
        'is_pinned': false,
        'replied_to': null,
      };
      _sendMessageToBoth(newMessage);
    } else {
      setState(() {
        _interactions.add({
          'type': type,
          'storyUser': data['storyUser'],
          'content': data['content'],
          'timestamp': data['timestamp'],
        });
      });
      _scrollToBottom();
    }
  }

  Future<void> _loadMessages() async {
    final messages = await AuthDatabase.instance.getMessagesBetween(
      widget.currentUser['id'],
      widget.otherUser['id'],
    );
    setState(() {
      _messages = messages;
    });
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final message = {
      'sender_id': widget.currentUser['id'],
      'receiver_id': widget.otherUser['id'],
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
      'is_read': false,
      'is_pinned': false,
      'replied_to': _replyingToMessageId,
    };
    _sendMessageToBoth(message);
    _controller.clear();
    _replyingToMessageId = null;
    _scrollToBottom();
  }

  void _sendMessageToBoth(Map<String, dynamic> message) async {
    // Store in local database
    await AuthDatabase.instance.createMessage(message);

    // Store in Firestore
    final sortedIds = [
      widget.currentUser['id'].toString(),
      widget.otherUser['id'].toString()
    ]..sort();
    final conversationId = sortedIds.join('_');
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .add({
      'sender_id': message['sender_id'],
      'receiver_id': message['receiver_id'],
      'message': message['message'],
      'timestamp': FieldValue.serverTimestamp(),
      'is_read': message['is_read'],
      'is_pinned': message['is_pinned'],
      'replied_to': message['replied_to'],
    });

    // Update conversation metadata
    await _firestore.collection('conversations').doc(conversationId).set({
      'participants': sortedIds,
      'last_message': message['message'],
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _updateChatBackground({
    Color? color,
    String? imageUrl,
    String? cinematicTheme,
  }) {
    setState(() {
      if (color != null) _chatBgColor = color;
      if (imageUrl != null) _chatBgImage = imageUrl;
      if (cinematicTheme != null) _cinematicTheme = cinematicTheme;
    });
  }

  void _deleteMessage(int index) async {
    final messageId = _messages[index]['id'];
    await AuthDatabase.instance.deleteMessage(messageId);
    setState(() {
      _messages = List<Map<String, dynamic>>.from(_messages);
      _messages.removeAt(index);
    });
  }

  void _toggleReadStatus(int index) async {
    final message = Map<String, dynamic>.from(_messages[index]);
    final bool isRead = message['is_read'] == 1;
    final updatedMessage = {'id': message['id'], 'is_read': isRead ? 0 : 1};
    await AuthDatabase.instance.updateMessage(updatedMessage);
    setState(() {
      _messages[index]['is_read'] = isRead ? 0 : 1;
    });
  }

  void _replyToMessage(int index) {
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    _replyingToMessageId = message['id'];
    _controller.text = "Replying to: ${message['message']}";
  }

  void _pinMessage(int index) async {
    final message = Map<String, dynamic>.from(_messages[index]);
    final bool isPinned = message['is_pinned'] == 1;
    final updatedMessage = {'id': message['id'], 'is_pinned': isPinned ? 0 : 1};
    await AuthDatabase.instance.updateMessage(updatedMessage);
    setState(() {
      _messages[index]['is_pinned'] = isPinned ? 0 : 1;
    });
  }

  List<Map<String, dynamic>> _searchMessages() {
    if (_searchTerm.isEmpty) return _messages;
    return _messages.where((message) {
      final msgText = (message['message'] as String).toLowerCase();
      return msgText.contains(_searchTerm.toLowerCase());
    }).toList();
  }

  void _openStoryScreen() {
    List<Map<String, dynamic>> otherUserStories = [
      {
        'user': widget.otherUser['username'],
        'userId': widget.otherUser['id'].toString(),
        'type': 'image',
        'media': 'https://via.placeholder.com/300',
        'timestamp': DateTime.now().toIso8601String(),
      },
    ];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryScreen(
          stories: otherUserStories,
          currentUserId: widget.currentUser['id'].toString(),
          onStoryInteraction: _handleStoryInteraction,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _interactions = List<Map<String, dynamic>>.from(widget.storyInteractions);
    _loadMessages();
    _listenToFirestoreMessages();
  }

  void _listenToFirestoreMessages() {
    final sortedIds = [
      widget.currentUser['id'].toString(),
      widget.otherUser['id'].toString()
    ]..sort();
    final conversationId = sortedIds.join('_');
    _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      final firestoreMessages = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        data['created_at'] =
            (data['timestamp'] as Timestamp?)?.toDate().toIso8601String() ??
                DateTime.now().toIso8601String();
        data['is_read'] = data['is_read'] ?? false;
        data['is_pinned'] = data['is_pinned'] ?? false;
        return data;
      }).toList();

      // Sync Firestore messages to local database
      for (var msg in firestoreMessages) {
        AuthDatabase.instance.createMessage({
          'sender_id': msg['sender_id'],
          'receiver_id': msg['receiver_id'],
          'message': msg['message'],
          'created_at': msg['created_at'],
          'is_read': msg['is_read'] ? 1 : 0,
          'is_pinned': msg['is_pinned'] ? 1 : 0,
          'replied_to': msg['replied_to'],
        });
      }

      _loadMessages();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  BoxDecoration _buildChatDecoration() {
    if (_chatBgImage != null && _chatBgImage!.isNotEmpty) {
      return BoxDecoration(
        image: DecorationImage(
          image: NetworkImage(_chatBgImage!),
          fit: BoxFit.cover,
        ),
      );
    } else if (_cinematicTheme != null) {
      if (_cinematicTheme == "Classic Film") {
        return const BoxDecoration(color: Colors.black87);
      } else if (_cinematicTheme == "Modern Blockbuster") {
        return const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueGrey, Colors.black],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      } else if (_cinematicTheme == "Indie Vibes") {
        return BoxDecoration(color: Colors.brown.shade200);
      } else if (_cinematicTheme == "Sci-Fi Adventure") {
        return const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple, Colors.black],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      } else if (_cinematicTheme == "Noir") {
        return BoxDecoration(color: Colors.grey.shade900);
      }
    }
    return BoxDecoration(color: _chatBgColor);
  }

  void _showMessageOptions(BuildContext context, Map<String, dynamic> message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(context);
              _replyToMessage(_messages.indexOf(message));
            },
          ),
          ListTile(
            leading: Icon(
              message['is_read'] == 1
                  ? Icons.check_circle
                  : Icons.check_circle_outline,
            ),
            title: Text(
              message['is_read'] == 1 ? 'Mark as unread' : 'Mark as read',
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleReadStatus(_messages.indexOf(message));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(context);
              _deleteMessage(_messages.indexOf(message));
            },
          ),
          ListTile(
            leading: Icon(
              message['is_pinned'] == 1
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
            ),
            title: Text(message['is_pinned'] == 1 ? 'Unpin' : 'Pin'),
            onTap: () {
              Navigator.pop(context);
              _pinMessage(_messages.indexOf(message));
            },
          ),
        ],
      ),
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String getHeaderText(DateTime date) {
    final now = DateTime.now();
    if (isSameDay(date, now)) return "Today";
    if (isSameDay(date, now.subtract(const Duration(days: 1))))
      return "Yesterday";
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredMessages = _searchMessages();
    List<Map<String, dynamic>> combinedItems = [
      ...filteredMessages.map((m) => {
            'type': 'message',
            'data': m,
            'timestamp': DateTime.parse(m['created_at'].toString()),
          }),
      ..._interactions.map((i) => {
            'type': 'interaction',
            'data': i,
            'timestamp': i['timestamp'] is DateTime
                ? i['timestamp']
                : DateTime.parse(i['timestamp'].toString()),
          }),
    ];
    combinedItems.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));

    List<Widget> listWidgets = [];
    for (int i = 0; i < combinedItems.length; i++) {
      final item = combinedItems[i];
      if (item['type'] == 'message') {
        final DateTime currentDate = item['timestamp'];
        if (i == 0 ||
            (combinedItems[i - 1]['type'] == 'message' &&
                !isSameDay(currentDate, combinedItems[i - 1]['timestamp']))) {
          listWidgets.add(
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Text(
                getHeaderText(currentDate),
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        listWidgets.add(
          MessageWidget(
            message: item['data'],
            isMe: item['data']['sender_id'] == widget.currentUser['id'],
            onReply: () => _replyToMessage(_messages.indexOf(item['data'])),
            onShare: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sharing message...')));
            },
            onLongPress: () => _showMessageOptions(context, item['data']),
            onTapOriginal: () {
              final originalMessage = _messages.firstWhere(
                (m) => m['id'] == item['data']['replied_to'],
                orElse: () => {},
              );
              if (originalMessage.isNotEmpty) {
                final index = _messages.indexOf(originalMessage);
                if (index != -1) {
                  _scrollController.animateTo(
                    index * 100.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              }
            },
          ),
        );
      } else {
        listWidgets.add(
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.deepPurple),
            title: Text(
              item['data']['type'] == 'like'
                  ? "You liked their story"
                  : item['data']['type'] == 'share'
                      ? "You shared their story"
                      : "Unknown interaction",
            ),
            subtitle: Text(
                DateFormat('MMM d, yyyy h:mm a').format(item['timestamp'])),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: widget.otherUser['profile_picture'] != null
            ? CircleAvatar(
                backgroundImage:
                    NetworkImage(widget.otherUser['profile_picture']))
            : null,
        title: Text("Chat with ${widget.otherUser['username']}"),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Initiating call...')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Initiating video call...')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _openStoryScreen,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchTerm = "";
                  _searchController.clear();
                }
              });
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'change_background') {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatSettingsScreen(
                      currentColor: _chatBgColor,
                      currentImage: _chatBgImage,
                    ),
                  ),
                );
                if (result != null && result is Map<String, dynamic>) {
                  _updateChatBackground(
                    color: result['color'],
                    imageUrl: result['image'],
                    cinematicTheme: result['cinematicTheme'],
                  );
                }
              }
            },
            itemBuilder: (BuildContext context) {
              return const [
                PopupMenuItem<String>(
                  value: 'change_background',
                  child: Text('Change Background'),
                ),
              ];
            },
          ),
        ],
        bottom: _showSearch
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchTerm = value;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: "Search messages...",
                      fillColor: Colors.white,
                      filled: true,
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: Container(
        decoration: _buildChatDecoration(),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: listWidgets,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: const Color.fromARGB(255, 136, 38, 38),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: Colors.white),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Uploading attachment...')));
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration.collapsed(
                            hintText: "Type a message..."),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    _controller.text.isEmpty
                        ? IconButton(
                            icon: const Icon(Icons.mic, color: Colors.white),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Recording audio...')));
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MessageWidget extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final VoidCallback onReply;
  final VoidCallback onShare;
  final VoidCallback onLongPress;
  final VoidCallback onTapOriginal;

  const MessageWidget({
    Key? key,
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.onShare,
    required this.onLongPress,
    required this.onTapOriginal,
  }) : super(key: key);

  @override
  _MessageWidgetState createState() => _MessageWidgetState();
}

class _MessageWidgetState extends State<MessageWidget> {
  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    final messageTime = DateTime.parse(widget.message['created_at']);
    final formattedTime = DateFormat('h:mm a').format(messageTime);

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message['replied_to'] != null) ...[
          GestureDetector(
            onTap: widget.onTapOriginal,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Re: ${widget.message['replied_to']}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        Text(
          widget.message['message'],
          style: TextStyle(
            fontSize: 16,
            color: widget.isMe ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formattedTime,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (widget.message['is_pinned'] == 1)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.pin_drop, color: Colors.orange, size: 18),
          ),
      ],
    );

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset += details.delta.dx;
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset < -50) {
          widget.onReply();
        } else if (_dragOffset > 50) {
          widget.onShare();
        }
        setState(() {
          _dragOffset = 0.0;
        });
      },
      onLongPress: widget.onLongPress,
      child: Stack(
        children: [
          if (_dragOffset < 0)
            Positioned(
              right: 0,
              child: Container(
                color: Colors.blue,
                width: -_dragOffset,
                height: 50,
                alignment: Alignment.center,
                child:
                    const Text('Reply', style: TextStyle(color: Colors.white)),
              ),
            ),
          if (_dragOffset > 0)
            Positioned(
              left: 0,
              child: Container(
                color: Colors.green,
                width: _dragOffset,
                height: 50,
                alignment: Alignment.center,
                child:
                    const Text('Share', style: TextStyle(color: Colors.white)),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Align(
              alignment:
                  widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isMe
                      ? Colors.deepPurpleAccent
                      : Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(2, 2))
                  ],
                ),
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
