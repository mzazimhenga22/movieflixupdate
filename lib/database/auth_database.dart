import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sembast/sembast.dart' as sembast;
import 'package:sembast_web/sembast_web.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:movie_app/users.dart';

class AuthDatabase {
  static final AuthDatabase instance = AuthDatabase._init();

  sqflite.Database? _sqfliteDb;
  sembast.Database? _sembastDb;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _userStore = sembast.stringMapStoreFactory.store('users');
  final _profileStore = sembast.stringMapStoreFactory.store('profiles');
  final _messageStore = sembast.stringMapStoreFactory.store('messages');
  final _conversationStore =
      sembast.stringMapStoreFactory.store('conversations');
  final _followersStore = sembast.stringMapStoreFactory.store('followers');

  late final Users _users;

  AuthDatabase._init() {
    _users = Users(
      firestore: _firestore,
      database: _sqfliteDb,
      dbFactory: kIsWeb ? databaseFactoryWeb : null,
      userStore: _userStore,
    );
  }

  Future<dynamic> get database async {
    if (kIsWeb) {
      _sembastDb ??= await databaseFactoryWeb.openDatabase('auth.db');
      return _sembastDb!;
    } else {
      if (_sqfliteDb == null) {
        final dbPath = await sqflite.getDatabasesPath();
        final path = join(dbPath, 'auth.db');
        _sqfliteDb = await sqflite.openDatabase(
          path,
          version: 1, // Simplified to a single version
          onConfigure: (db) async =>
              await db.execute('PRAGMA foreign_keys = ON'),
          onCreate: _createSQLiteDB,
        );
      }
      return _sqfliteDb!;
    }
  }

  Future<void> _createSQLiteDB(sqflite.Database db, int version) async {
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

    await db.execute('CREATE INDEX idx_profiles_user_id ON profiles(user_id)');

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
        final result = await (await database).query(
          'followers',
          where: 'follower_id = ? AND following_id = ?',
          whereArgs: [followerId, followingId],
        );
        return result.isNotEmpty;
      }
    } catch (e) {
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
        await (await database).insert(
          'followers',
          {'follower_id': followerId, 'following_id': followingId},
          conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
        );
      }
    } catch (e) {
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
        await (await database).delete(
          'followers',
          where: 'follower_id = ? AND following_id = ?',
          whereArgs: [followerId, followingId],
        );
      }
    } catch (e) {
      throw Exception('Failed to unfollow user: $e');
    }
  }

  Future<String> createProfile(Map<String, dynamic> profile) async {
    final profileData = {
      'user_id': profile['user_id'].toString(),
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

    try {
      String newId;
      if (kIsWeb) {
        newId = await _profileStore.add(await database, profileData);
        await _firestore.collection('profiles').doc(newId).set(profileData);
      } else {
        newId = DateTime.now().millisecondsSinceEpoch.toString();
        profileData['id'] = newId;
        await (await database).insert('profiles', profileData,
            conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
        await _firestore.collection('profiles').doc(newId).set(profileData);
      }
      return newId;
    } catch (e) {
      throw Exception('Failed to create profile: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getProfilesByUserId(String userId) async {
    try {
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
        final result = await (await database).query(
          'profiles',
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'created_at ASC',
        );
        localProfiles = result.map((r) {
          final profileData = Map<String, dynamic>.from(r);
          profileData['id'] = profileData['id'].toString();
          return profileData;
        }).toList();
      }

      final allProfilesMap = <String, Map<String, dynamic>>{};
      for (var profile in firestoreProfiles) {
        final profileId = profile['id'].toString();
        if (profileId.isNotEmpty) {
          allProfilesMap[profileId] = profile;
        }
      }
      for (var profile in localProfiles) {
        final profileId = profile['id'].toString();
        if (profileId.isNotEmpty) {
          allProfilesMap[profileId] = {
            ...allProfilesMap[profileId] ?? {},
            ...profile,
          };
        }
      }

      return allProfilesMap.values.toList();
    } catch (e) {
      throw Exception('Failed to fetch profiles: $e');
    }
  }

  Future<Map<String, dynamic>?> getProfileById(String profileId) async {
    try {
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
        final result = await (await database)
            .query('profiles', where: 'id = ?', whereArgs: [profileId]);
        if (result.isNotEmpty) {
          final profileData = Map<String, dynamic>.from(result.first);
          profileData['id'] = profileData['id'].toString();
          return profileData;
        }
        return null;
      }
    } catch (e) {
      throw Exception('Failed to fetch profile: $e');
    }
  }

  Future<Map<String, dynamic>?> getActiveProfileByUserId(String userId) async {
    try {
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
        final result = await (await database).query(
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
      throw Exception('Failed to fetch active profile: $e');
    }
  }

  Future<String> updateProfile(Map<String, dynamic> profile) async {
    final profileData = Map<String, dynamic>.from(profile);
    profileData['user_id'] = profileData['user_id'].toString();
    profileData['updated_at'] = DateTime.now().toIso8601String();

    try {
      final profileId = profileData['id'].toString();
      await _firestore
          .collection('profiles')
          .doc(profileId)
          .update(profileData);
      if (kIsWeb) {
        await _profileStore
            .record(profileId)
            .update(await database, profileData);
      } else {
        await (await database).update(
          'profiles',
          profileData,
          where: 'id = ?',
          whereArgs: [profileId],
        );
      }
      return profileId;
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  Future<int> deleteProfile(String profileId) async {
    try {
      await _firestore.collection('profiles').doc(profileId).delete();
      if (kIsWeb) {
        await _profileStore.record(profileId).delete(await database);
        return 1;
      } else {
        return await (await database)
            .delete('profiles', where: 'id = ?', whereArgs: [profileId]);
      }
    } catch (e) {
      throw Exception('Failed to delete profile: $e');
    }
  }

  Future<String> createMessage(Map<String, dynamic> message) async {
    final messageData = {
      'sender_id': message['sender_id'].toString(),
      'receiver_id': message['receiver_id'].toString(),
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
        await (await database).insert('messages', messageData,
            conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      }
      return newId;
    } catch (e) {
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
        final result = await (await database).query(
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
        final result = await (await database).query('conversations');
        return result
            .map((row) {
              final convo =
                  jsonDecode(row['data'] as String) as Map<String, dynamic>;
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
      throw Exception('Failed to fetch conversations: $e');
    }
  }

  Future<int> deleteMessage(String messageId) async {
    try {
      if (kIsWeb) {
        await _messageStore.record(messageId).delete(await database);
        return 1;
      } else {
        return await (await database)
            .delete('messages', where: 'id = ?', whereArgs: [messageId]);
      }
    } catch (e) {
      throw Exception('Failed to delete message: $e');
    }
  }

  Future<String> updateMessage(Map<String, dynamic> message) async {
    final messageData = Map<String, dynamic>.from(message);
    messageData['sender_id'] = messageData['sender_id'].toString();
    messageData['receiver_id'] = messageData['receiver_id'].toString();
    try {
      final messageId = messageData['id'].toString();
      if (kIsWeb) {
        await _messageStore
            .record(messageId)
            .update(await database, messageData);
      } else {
        await (await database).update(
          'messages',
          messageData,
          where: 'id = ?',
          whereArgs: [messageId],
        );
      }
      return messageId;
    } catch (e) {
      throw Exception('Failed to update message: $e');
    }
  }

  Future<void> insertConversation(Map<String, dynamic> conversation) async {
    final conversationData = Map<String, dynamic>.from(conversation);
    try {
      if (kIsWeb) {
        await _conversationStore.add(await database, conversationData);
      } else {
        await (await database).insert(
          'conversations',
          {'data': jsonEncode(conversationData)},
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
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
        final result = await (await database).query('conversations');
        final idsToDelete = result
            .map((row) =>
                jsonDecode(row['data'] as String) as Map<String, dynamic>)
            .where((convo) =>
                (convo['participants'] as List<dynamic>).contains(userId))
            .map((convo) => convo['id'])
            .toList();
        for (final id in idsToDelete) {
          await (await database)
              .delete('conversations', where: 'id = ?', whereArgs: [id]);
        }
      }
    } catch (e) {
      throw Exception('Failed to clear conversations: $e');
    }
  }

  Future<void> close() async {
    try {
      if (kIsWeb) {
        await _sembastDb?.close();
      } else {
        await _sqfliteDb?.close();
      }
    } catch (e) {
      throw Exception('Failed to close database: $e');
    }
  }

  // Delegate user-related methods to Users class
  Future<String> createUser(Map<String, dynamic> user) async {
    return await _users.createUser(user);
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    return await _users.getUserByEmail(email);
  }

  Future<Map<String, dynamic>?> getUserById(String id) async {
    return await _users.getUserById(id);
  }

  Future<String> updateUser(Map<String, dynamic> user) async {
    return await _users.updateUser(user);
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    return await _users.getAllUsers();
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    return await _users.searchUsers(query);
  }

  Future<Map<String, dynamic>?> getUserByToken(String token) async {
    return await _users.getUserByToken(token);
  }
}
