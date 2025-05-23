import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sembast/sembast.dart' as sembast;
import 'package:sembast_web/sembast_web.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthDatabase {
  static final AuthDatabase instance = AuthDatabase._init();

  sqflite.Database? _sqfliteDb;
  sembast.Database? _sembastDb;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isInitialized = false;

  final _userStore = sembast.stringMapStoreFactory.store('users');
  final _profileStore = sembast.stringMapStoreFactory.store('profiles');
  final _messageStore = sembast.stringMapStoreFactory.store('messages');
  final _conversationStore =
      sembast.stringMapStoreFactory.store('conversations');
  final _followersStore = sembast.stringMapStoreFactory.store('followers');

  AuthDatabase._init();

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await database; // Ensure database is initialized
      _isInitialized = true;
      debugPrint('Database initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize database: $e');
      rethrow;
    }
  }

  Future<dynamic> get database async {
    if (kIsWeb) {
      _sembastDb ??= await databaseFactoryWeb.openDatabase('auth.db');
      return _sembastDb!;
    } else {
      _sqfliteDb ??= await _initializeSqflite();
      return _sqfliteDb!;
    }
  }

  Future<sqflite.Database> _initializeSqflite() async {
    try {
      final dbPath = await sqflite.getDatabasesPath();
      final path = join(dbPath, 'auth.db');
      final db = await sqflite.openDatabase(
        path,
        version: 1,
        onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSQLiteDB,
      );
      debugPrint('SQLite database opened at $path');
      return db;
    } catch (e) {
      debugPrint('Failed to initialize SQLite database: $e');
      throw Exception('Failed to initialize SQLite database: $e');
    }
  }

  Future<void> _createSQLiteDB(sqflite.Database db, int version) async {
    try {
      const idType = 'TEXT PRIMARY KEY';
      const textType = 'TEXT NOT NULL';

      await db.execute('''
        CREATE TABLE users (
          id $idType,
          username $textType,
          email $textType,
          bio TEXT,
          password $textType,
          auth_provider $textType,
          token TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE profiles (
          id $idType,
          user_id TEXT NOT NULL,
          name $textType,
          avatar $textType,
          backgroundImage TEXT,
          pin TEXT,
          locked INTEGER NOT NULL DEFAULT 0,
          preferences TEXT DEFAULT '',
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');

      await db
          .execute('CREATE INDEX idx_profiles_user_id ON profiles(user_id)');

      await db.execute('''
        CREATE TABLE messages (
          id $idType,
          sender_id TEXT NOT NULL,
          receiver_id TEXT NOT NULL,
          message $textType,
          created_at TEXT,
          is_read INTEGER NOT NULL DEFAULT 0,
          is_pinned INTEGER NOT NULL DEFAULT 0,
          replied_to TEXT,
          FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE conversations (
          id $idType,
          data $textType
        )
      ''');

      await db.execute('''
        CREATE TABLE followers (
          follower_id TEXT NOT NULL,
          following_id TEXT NOT NULL,
          PRIMARY KEY (follower_id, following_id),
          FOREIGN KEY (follower_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY (following_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');

      debugPrint('SQLite tables created successfully');
    } catch (e) {
      debugPrint('Error creating SQLite tables: $e');
      throw Exception('Error creating SQLite tables: $e');
    }
  }

  Future<bool> _tableExists(sqflite.Database db, String tableName) async {
    try {
      final result = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName],
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking table existence for $tableName: $e');
      return false;
    }
  }

  Future<bool> isFollowing(String followerId, String followingId) async {
    try {
      final firestoreResult = await _firestore
          .collection('followers')
          .where('follower_id', isEqualTo: followerId)
          .where('following_id', isEqualTo: followingId)
          .get();
      if (firestoreResult.docs.isNotEmpty) {
        return true;
      }

      if (kIsWeb) {
        final finder = sembast.Finder(
          filter: sembast.Filter.and([
            sembast.Filter.equals('follower_id', followerId),
            sembast.Filter.equals('following_id', followingId),
          ]),
        );
        final record =
            await _followersStore.findFirst(await database, finder: finder);
        return record != null;
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query(
          'followers',
          where: 'follower_id = ? AND following_id = ?',
          whereArgs: [followerId, followingId],
        );
        return result.isNotEmpty;
      }
    } catch (e) {
      debugPrint('Failed to check following status: $e');
      throw Exception('Failed to check following status: $e');
    }
  }

  Future<void> followUser(String followerId, String followingId) async {
    try {
      await _firestore.collection('followers').add({
        'follower_id': followerId,
        'following_id': followingId,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (kIsWeb) {
        await _followersStore.add(await database, {
          'follower_id': followerId,
          'following_id': followingId,
        });
      } else {
        final db = await database as sqflite.Database;
        await db.insert(
          'followers',
          {'follower_id': followerId, 'following_id': followingId},
          conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
        );
      }
    } catch (e) {
      debugPrint('Failed to follow user: $e');
      throw Exception('Failed to follow user: $e');
    }
  }

  Future<void> unfollowUser(String followerId, String followingId) async {
    try {
      final firestoreResult = await _firestore
          .collection('followers')
          .where('follower_id', isEqualTo: followerId)
          .where('following_id', isEqualTo: followingId)
          .get();
      for (var doc in firestoreResult.docs) {
        await doc.reference.delete();
      }

      if (kIsWeb) {
        final finder = sembast.Finder(
          filter: sembast.Filter.and([
            sembast.Filter.equals('follower_id', followerId),
            sembast.Filter.equals('following_id', followingId),
          ]),
        );
        await _followersStore.delete(await database, finder: finder);
      } else {
        final db = await database as sqflite.Database;
        await db.delete(
          'followers',
          where: 'follower_id = ? AND following_id = ?',
          whereArgs: [followerId, followingId],
        );
      }
    } catch (e) {
      debugPrint('Failed to unfollow user: $e');
      throw Exception('Failed to unfollow user: $e');
    }
  }

  Future<String> createProfile(Map<String, dynamic> profile) async {
    final profileData = {
      'id': profile['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'user_id': profile['user_id']?.toString() ?? '',
      'name': profile['name']?.toString() ?? 'Profile',
      'avatar':
          profile['avatar']?.toString() ?? 'https://via.placeholder.com/200',
      'backgroundImage': profile['backgroundImage']?.toString(),
      'pin': profile['pin']?.toString(),
      'locked': profile['locked']?.toInt() ?? 0,
      'preferences': profile['preferences']?.toString() ?? '',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (profileData['user_id'].isEmpty) {
      throw Exception('user_id cannot be empty');
    }

    try {
      debugPrint('Creating profile with data: $profileData');
      final newId = profileData['id'];
      if (kIsWeb) {
        await _profileStore.add(await database, profileData);
        await _firestore.collection('profiles').doc(newId).set(profileData);
      } else {
        final db = await database as sqflite.Database;
        await db.insert('profiles', profileData,
            conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
        await _firestore.collection('profiles').doc(newId).set(profileData);
      }
      debugPrint('Profile created with ID: $newId');
      return newId;
    } catch (e) {
      debugPrint('Failed to create profile: $e');
      throw Exception('Failed to create profile: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getProfilesByUserId(String userId) async {
    try {
      debugPrint('Fetching profiles for userId: $userId');
      final firestoreResult = await _firestore
          .collection('profiles')
          .where('user_id', isEqualTo: userId)
          .get();
      final firestoreProfiles = firestoreResult.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      List<Map<String, dynamic>> localProfiles;
      if (kIsWeb) {
        final finder = sembast.Finder(
            filter: sembast.Filter.equals('user_id', userId),
            sortOrders: [sembast.SortOrder('created_at')]);
        final records =
            await _profileStore.find(await database, finder: finder);
        localProfiles = records.map((r) {
          final profileData = Map<String, dynamic>.from(r.value);
          profileData['id'] = r.key;
          return profileData;
        }).toList();
      } else {
        final db = await database as sqflite.Database;
        if (!await _tableExists(db, 'profiles')) {
          debugPrint('Profiles table does not exist in SQLite');
          throw Exception('Profiles table not found');
        }
        final result = await db.query(
          'profiles',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'created_at ASC',
        );
        debugPrint('SQLite query result for userId $userId: $result');
        localProfiles = result.map((r) {
          final profileData = Map<String, dynamic>.from(r);
          profileData['id'] = profileData['id'].toString();
          return profileData;
        }).toList();
      }

      final allProfilesMap = <String, Map<String, dynamic>>{};
      for (var profile in firestoreProfiles) {
        final profileId = profile['id']?.toString() ?? '';
        if (profileId.isNotEmpty) {
          allProfilesMap[profileId] = profile;
        }
      }
      for (var profile in localProfiles) {
        final profileId = profile['id']?.toString() ?? '';
        if (profileId.isNotEmpty) {
          allProfilesMap[profileId] = {
            ...allProfilesMap[profileId] ?? {},
            ...profile,
          };
        }
      }

      final profiles = allProfilesMap.values.toList();
      debugPrint('Fetched ${profiles.length} profiles for userId: $userId');
      return profiles;
    } catch (e) {
      debugPrint('Failed to fetch profiles: $e');
      throw Exception('Failed to fetch profiles: $e');
    }
  }

  Future<Map<String, dynamic>?> getProfileById(String profileId) async {
    try {
      debugPrint('Fetching profile with ID: $profileId');
      final firestoreDoc =
          await _firestore.collection('profiles').doc(profileId).get();
      if (firestoreDoc.exists) {
        final data = firestoreDoc.data()!;
        data['id'] = firestoreDoc.id;
        return data;
      }

      if (kIsWeb) {
        final record =
            await _profileStore.record(profileId).get(await database);
        if (record != null) {
          final profileData = Map<String, dynamic>.from(record);
          profileData['id'] = profileId;
          return profileData;
        }
        return null;
      } else {
        final db = await database as sqflite.Database;
        if (!await _tableExists(db, 'profiles')) {
          debugPrint('Profiles table does not exist in SQLite');
          return null;
        }
        final result =
            await db.query('profiles', where: 'id = ?', whereArgs: [profileId]);
        if (result.isNotEmpty) {
          final profileData = Map<String, dynamic>.from(result.first);
          profileData['id'] = profileData['id'].toString();
          return profileData;
        }
        return null;
      }
    } catch (e) {
      debugPrint('Failed to fetch profile: $e');
      throw Exception('Failed to fetch profile: $e');
    }
  }

  Future<Map<String, dynamic>?> getActiveProfileByUserId(String userId) async {
    try {
      debugPrint('Fetching active profile for userId: $userId');
      final firestoreResult = await _firestore
          .collection('profiles')
          .where('user_id', isEqualTo: userId)
          .where('locked', isEqualTo: 0)
          .orderBy('created_at')
          .limit(1)
          .get();
      if (firestoreResult.docs.isNotEmpty) {
        final data = firestoreResult.docs.first.data();
        data['id'] = firestoreResult.docs.first.id;
        return data;
      }

      if (kIsWeb) {
        final finder = sembast.Finder(
          filter: sembast.Filter.and([
            sembast.Filter.equals('user_id', userId),
            sembast.Filter.equals('locked', 0),
          ]),
          sortOrders: [sembast.SortOrder('created_at')],
        );
        final record =
            await _profileStore.findFirst(await database, finder: finder);
        if (record != null) {
          final profileData = Map<String, dynamic>.from(record.value);
          profileData['id'] = record.key;
          return profileData;
        }
        return null;
      } else {
        final db = await database as sqflite.Database;
        if (!await _tableExists(db, 'profiles')) {
          debugPrint('Profiles table does not exist in SQLite');
          return null;
        }
        final result = await db.query(
          'profiles',
          where: 'user_id = ? AND locked = 0',
          whereArgs: [userId],
          orderBy: 'created_at ASC',
          limit: 1,
        );
        if (result.isNotEmpty) {
          final profileData = Map<String, dynamic>.from(result.first);
          profileData['id'] = profileData['id'].toString();
          return profileData;
        }
        return null;
      }
    } catch (e) {
      debugPrint('Failed to fetch active profile: $e');
      throw Exception('Failed to fetch active profile: $e');
    }
  }

  Future<String> updateProfile(Map<String, dynamic> profile) async {
    final profileData = Map<String, dynamic>.from(profile);
    profileData['user_id'] = profileData['user_id']?.toString() ?? '';
    profileData['updated_at'] = DateTime.now().toIso8601String();

    if (profileData['user_id'].isEmpty) {
      throw Exception('user_id cannot be empty');
    }

    try {
      final profileId = profileData['id']?.toString() ?? '';
      if (profileId.isEmpty) {
        throw Exception('profile id cannot be empty');
      }
      debugPrint('Updating profile with ID: $profileId');
      await _firestore
          .collection('profiles')
          .doc(profileId)
          .update(profileData);
      if (kIsWeb) {
        await _profileStore
            .record(profileId)
            .update(await database, profileData);
      } else {
        final db = await database as sqflite.Database;
        await db.update(
          'profiles',
          profileData,
          where: 'id = ?',
          whereArgs: [profileId],
        );
      }
      return profileId;
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      throw Exception('Failed to update profile: $e');
    }
  }

  Future<int> deleteProfile(String profileId) async {
    try {
      debugPrint('Deleting profile with ID: $profileId');
      await _firestore.collection('profiles').doc(profileId).delete();
      if (kIsWeb) {
        await _profileStore.record(profileId).delete(await database);
        return 1;
      } else {
        final db = await database as sqflite.Database;
        return await db
            .delete('profiles', where: 'id = ?', whereArgs: [profileId]);
      }
    } catch (e) {
      debugPrint('Failed to delete profile: $e');
      throw Exception('Failed to delete profile: $e');
    }
  }

  Future<String> createMessage(Map<String, dynamic> message) async {
    final messageData = {
      'sender_id': message['sender_id']?.toString() ?? '',
      'receiver_id': message['receiver_id']?.toString() ?? '',
      'message': message['message']?.toString(),
      'created_at': DateTime.now().toIso8601String(),
      'is_read': message['is_read']?.toInt() ?? 0,
      'is_pinned': message['is_pinned']?.toInt() ?? 0,
      'replied_to': message['replied_to']?.toString(),
    };

    try {
      String newId;
      if (kIsWeb) {
        newId = await _messageStore.add(await database, messageData);
      } else {
        newId = DateTime.now().millisecondsSinceEpoch.toString();
        messageData['id'] = newId;
        final db = await database as sqflite.Database;
        await db.insert('messages', messageData,
            conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      }
      return newId;
    } catch (e) {
      debugPrint('Failed to create message: $e');
      throw Exception('Failed to create message: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getMessagesBetween(
      String userId1, String userId2) async {
    try {
      if (kIsWeb) {
        final finder = sembast.Finder(
          filter: sembast.Filter.or([
            sembast.Filter.and([
              sembast.Filter.equals('sender_id', userId1),
              sembast.Filter.equals('receiver_id', userId2),
            ]),
            sembast.Filter.and([
              sembast.Filter.equals('sender_id', userId2),
              sembast.Filter.equals('receiver_id', userId1),
            ]),
          ]),
        );
        final records =
            await _messageStore.find(await database, finder: finder);
        return records.map((r) {
          final messageData = Map<String, dynamic>.from(r.value);
          messageData['id'] = r.key;
          return messageData;
        }).toList();
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query(
          'messages',
          where:
              '(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)',
          whereArgs: [userId1, userId2, userId2, userId1],
          orderBy: 'created_at ASC',
        );
        return result.map((r) {
          final messageData = Map<String, dynamic>.from(r);
          messageData['id'] = messageData['id'].toString();
          return messageData;
        }).toList();
      }
    } catch (e) {
      debugPrint('Failed to fetch messages: $e');
      throw Exception('Failed to fetch messages: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getConversationsForUser(
      String userId) async {
    try {
      if (kIsWeb) {
        final finder = sembast.Finder(
          filter: sembast.Filter.custom((record) {
            final participants = record['participants'] as List<dynamic>?;
            return participants?.contains(userId) ?? false;
          }),
        );
        final records =
            await _conversationStore.find(await database, finder: finder);
        return records.map((r) {
          final convoData = Map<String, dynamic>.from(r.value);
          convoData['id'] = r.key;
          return convoData;
        }).toList();
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query('conversations');
        return result
            .map((row) {
              final convo = jsonDecode(row['data'] as String);
              final participants = convo['participants'] as List<dynamic>;
              if (participants.contains(userId)) {
                convo['id'] = row['id'].toString();
                return convo;
              }
              return null;
            })
            .where((convo) => convo != null)
            .toList()
            .cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Failed to fetch conversations: $e');
      throw Exception('Failed to fetch conversations: $e');
    }
  }

  Future<int> deleteMessage(String messageId) async {
    try {
      if (kIsWeb) {
        await _messageStore.record(messageId).delete(await database);
        return 1;
      } else {
        final db = await database as sqflite.Database;
        return await db
            .delete('messages', where: 'id = ?', whereArgs: [messageId]);
      }
    } catch (e) {
      debugPrint('Failed to delete message: $e');
      throw Exception('Failed to delete message: $e');
    }
  }

  Future<String> updateMessage(Map<String, dynamic> message) async {
    final messageData = Map<String, dynamic>.from(message);
    messageData['sender_id'] = messageData['sender_id']?.toString() ?? '';
    messageData['receiver_id'] = messageData['receiver_id']?.toString() ?? '';
    try {
      final messageId = messageData['id']?.toString() ?? '';
      if (messageId.isEmpty) {
        throw Exception('message id cannot be empty');
      }
      if (kIsWeb) {
        await _messageStore
            .record(messageId)
            .update(await database, messageData);
      } else {
        final db = await database as sqflite.Database;
        await db.update(
          'messages',
          messageData,
          where: 'id = ?',
          whereArgs: [messageId],
        );
      }
      return messageId;
    } catch (e) {
      debugPrint('Failed to update message: $e');
      throw Exception('Failed to update message: $e');
    }
  }

  Future<void> insertConversation(Map<String, dynamic> conversation) async {
    final conversationData = Map<String, dynamic>.from(conversation);
    try {
      if (kIsWeb) {
        await _conversationStore.add(await database, conversationData);
      } else {
        final db = await database as sqflite.Database;
        await db.insert(
          'conversations',
          {'data': jsonEncode(conversationData)},
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('Failed to insert conversation: $e');
      throw Exception('Failed to insert conversation: $e');
    }
  }

  Future<void> clearConversationsForUser(String userId) async {
    try {
      if (kIsWeb) {
        final finder = sembast.Finder(
          filter: sembast.Filter.custom((record) {
            final participants = record['participants'] as List<dynamic>?;
            return participants?.contains(userId) ?? false;
          }),
        );
        await _conversationStore.delete(await database, finder: finder);
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query('conversations');
        final idsToDelete = result
            .map((row) => jsonDecode(row['data'] as String))
            .where((convo) =>
                (convo['participants'] as List<dynamic>).contains(userId))
            .map((convo) => convo['id'])
            .toList();
        for (final id in idsToDelete) {
          await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
        }
      }
    } catch (e) {
      debugPrint('Failed to clear conversations: $e');
      throw Exception('Failed to clear conversations: $e');
    }
  }

  Future<void> close() async {
    try {
      if (kIsWeb) {
        await _sembastDb?.close();
        _sembastDb = null;
      } else {
        await _sqfliteDb?.close();
        _sqfliteDb = null;
      }
      _isInitialized = false;
      debugPrint('Database closed');
    } catch (e) {
      debugPrint('Failed to close database: $e');
      throw Exception('Failed to close database: $e');
    }
  }

  Future<String> createUser(Map<String, dynamic> user) async {
    try {
      final userData = {
        'id': user['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'username': user['username']?.toString() ?? '',
        'email': user['email']?.toString() ?? '',
        'bio': user['bio']?.toString() ?? '',
        'password': user['password']?.toString() ?? '',
        'auth_provider': user['auth_provider']?.toString() ?? 'email',
        'token': user['token']?.toString(),
        'created_at':
            user['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        'updated_at':
            user['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
      };

      final definedColumns = [
        'id',
        'username',
        'email',
        'bio',
        'password',
        'auth_provider',
        'token',
        'created_at',
        'updated_at',
      ];
      final filteredUserData = Map.fromEntries(
        userData.entries.where((entry) => definedColumns.contains(entry.key)),
      );

      final userId = filteredUserData['id'] as String?;
      if (userId == null || userId.isEmpty) {
        throw Exception('User ID cannot be empty');
      }

      debugPrint('Creating user with data: $filteredUserData');
      if (kIsWeb) {
        await _userStore.add(await database, filteredUserData);
        await _firestore.collection('users').doc(userId).set(filteredUserData);
        debugPrint('User created with ID: $userId');
        return userId;
      } else {
        final db = await database as sqflite.Database;
        await db.insert(
          'users',
          filteredUserData,
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
        await _firestore.collection('users').doc(userId).set(filteredUserData);
        debugPrint('User created with ID: $userId');
        return userId;
      }
    } catch (e) {
      debugPrint('Failed to create user: $e');
      throw Exception('Failed to create user: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    try {
      final firestoreResult = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (firestoreResult.docs.isNotEmpty) {
        return firestoreResult.docs.first.data();
      }

      if (kIsWeb) {
        final finder =
            sembast.Finder(filter: sembast.Filter.equals('email', email));
        final record =
            await _userStore.findFirst(await database, finder: finder);
        return record?.value;
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query(
          'users',
          where: 'email = ?',
          whereArgs: [email],
        );
        return result.isNotEmpty
            ? Map<String, dynamic>.from(result.first)
            : null;
      }
    } catch (e) {
      debugPrint('Failed to get user by email: $e');
      throw Exception('Failed to get user by email: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserById(String id) async {
    try {
      final firestoreDoc = await _firestore.collection('users').doc(id).get();
      if (firestoreDoc.exists) {
        return firestoreDoc.data();
      }

      if (kIsWeb) {
        final record = await _userStore.record(id).get(await database);
        return record;
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [id],
        );
        return result.isNotEmpty
            ? Map<String, dynamic>.from(result.first)
            : null;
      }
    } catch (e) {
      debugPrint('Failed to get user by ID: $e');
      throw Exception('Failed to get user by ID: $e');
    }
  }

  Future<String> updateUser(Map<String, dynamic> user) async {
    try {
      final userData = Map<String, dynamic>.from(user);
      userData['updated_at'] = DateTime.now().toIso8601String();
      final userId = userData['id']?.toString() ?? '';
      if (userId.isEmpty) {
        throw Exception('User ID cannot be empty');
      }

      final definedColumns = [
        'id',
        'username',
        'email',
        'bio',
        'password',
        'auth_provider',
        'token',
        'created_at',
        'updated_at',
      ];
      final filteredUserData = Map.fromEntries(
        userData.entries.where((entry) => definedColumns.contains(entry.key)),
      );

      debugPrint('Updating user with ID: $userId');
      await _firestore.collection('users').doc(userId).update(filteredUserData);
      if (kIsWeb) {
        await _userStore
            .record(userId)
            .update(await database, filteredUserData);
      } else {
        final db = await database as sqflite.Database;
        await db.update(
          'users',
          filteredUserData,
          where: 'id = ?',
          whereArgs: [userId],
        );
      }
      debugPrint('User updated: $userId');
      return userId;
    } catch (e) {
      debugPrint('Failed to update user: $e');
      throw Exception('Failed to update user: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      await _firestore.collection('users').get();
      if (kIsWeb) {
        final records = await _userStore.find(await database);
        return records.map((r) => Map<String, dynamic>.from(r.value)).toList();
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query('users');
        return result.map((r) => Map<String, dynamic>.from(r)).toList();
      }
    } catch (e) {
      debugPrint('Failed to get all users: $e');
      throw Exception('Failed to get all users: $e');
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      await _firestore
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: query)
          .where('username', isLessThanOrEqualTo: '$query\uf8ff')
          .get();
      if (kIsWeb) {
        final finder = sembast.Finder(
            filter: sembast.Filter.matches('username', '^$query.*'));
        final records = await _userStore.find(await database, finder: finder);
        return records.map((r) => Map<String, dynamic>.from(r.value)).toList();
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query(
          'users',
          where: 'username LIKE ?',
          whereArgs: ['$query%'],
        );
        return result.map((r) => Map<String, dynamic>.from(r)).toList();
      }
    } catch (e) {
      debugPrint('Failed to search users: $e');
      throw Exception('Failed to search users: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserByToken(String token) async {
    try {
      final firestoreResult = await _firestore
          .collection('users')
          .where('token', isEqualTo: token)
          .limit(1)
          .get();
      if (firestoreResult.docs.isNotEmpty) {
        return firestoreResult.docs.first.data();
      }

      if (kIsWeb) {
        final finder =
            sembast.Finder(filter: sembast.Filter.equals('token', token));
        final record =
            await _userStore.findFirst(await database, finder: finder);
        return record?.value;
      } else {
        final db = await database as sqflite.Database;
        final result = await db.query(
          'users',
          where: 'token = ?',
          whereArgs: [token],
        );
        return result.isNotEmpty
            ? Map<String, dynamic>.from(result.first)
            : null;
      }
    } catch (e) {
      debugPrint('Failed to get user by token: $e');
      throw Exception('Failed to get user by token: $e');
    }
  }
}



