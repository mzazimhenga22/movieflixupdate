import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sembast/sembast.dart' as sembast;
import 'package:sqflite/sqflite.dart' as sqflite;

class Users {
  final FirebaseFirestore _firestore;
  final sqflite.Database? _sqfliteDb;
  final sembast.DatabaseFactory? _dbFactory;
  final sembast.StoreRef _userStore;
  sembast.Database? _sembastDb;

  Users({
    required FirebaseFirestore firestore,
    sqflite.Database? database,
    sembast.DatabaseFactory? dbFactory,
    sembast.StoreRef? userStore,
  })  : _firestore = firestore,
        _sqfliteDb = database,
        _dbFactory = dbFactory,
        _userStore = userStore ?? sembast.StoreRef.main();

  String _coerceToString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  Map<String, dynamic> _normalizeUserData(Map<String, dynamic> user) {
    return {
      'id': _coerceToString(user['id']),
      'username': _coerceToString(user['username']),
      'email': _coerceToString(user['email']),
      'bio': _coerceToString(user['bio']),
      'password': _coerceToString(user['password']),
      'auth_provider': _coerceToString(user['auth_provider']),
      'token': _coerceToString(user['token']),
      'created_at': _coerceToString(user['created_at']),
      'updated_at': _coerceToString(user['updated_at']),
      'followers_count': user['followers_count'] is int
          ? user['followers_count']
          : int.tryParse(_coerceToString(user['followers_count'])) ?? 0,
      'following_count': user['following_count'] is int
          ? user['following_count']
          : int.tryParse(_coerceToString(user['following_count'])) ?? 0,
      'profile_id': _coerceToString(user['profile_id']),
      'avatar': _coerceToString(user['avatar']),
      'profile_name': _coerceToString(user['profile_name']),
    };
  }

  Future<dynamic> get database async {
    if (kIsWeb) {
      _sembastDb ??= await _dbFactory!.openDatabase('auth.db');
      return _sembastDb!;
    } else {
      if (_sqfliteDb == null) {
        throw Exception('SQLite database not provided');
      }
      return _sqfliteDb!;
    }
  }

  Future<String> createUser(Map<String, dynamic> user) async {
    final userData = Map<String, dynamic>.from(user);
    userData['username'] = _coerceToString(userData['username']);
    userData['email'] = _coerceToString(userData['email']);
    userData['bio'] = _coerceToString(userData['bio']);
    userData['password'] = _coerceToString(userData['password']);
    userData['auth_provider'] =
        _coerceToString(userData['auth_provider'] ?? 'firebase');
    userData['token'] = _coerceToString(userData['token']);
    userData['created_at'] = _coerceToString(
        userData['created_at'] ?? DateTime.now().toIso8601String());
    userData['updated_at'] = _coerceToString(
        userData['updated_at'] ?? DateTime.now().toIso8601String());
    userData['followers_count'] = userData['followers_count'] ?? 0;
    userData['following_count'] = userData['following_count'] ?? 0;
    userData['avatar'] = _coerceToString(
        userData['avatar'] ?? 'https://via.placeholder.com/200');

    if (userData['username'].isEmpty) {
      throw Exception('Username is required');
    }
    if (userData['email'].isEmpty) {
      throw Exception('Email is required');
    }

    try {
      String newId;
      if (kIsWeb) {
        newId =
            await (_userStore as sembast.StoreRef<String, Map<String, dynamic>>)
                .add(await database, userData);
        userData['id'] = newId;
        await _firestore.collection('users').doc(newId).set(userData);
      } else {
        newId =
            userData['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        userData['id'] = newId;
        await (await database as sqflite.Database).insert('users', userData,
            conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
        await _firestore.collection('users').doc(newId).set(userData);
      }
      return newId;
    } catch (e) {
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
        final data = firestoreResult.docs.first.data();
        data['id'] = _coerceToString(firestoreResult.docs.first.id);
        return _normalizeUserData(data);
      }

      if (kIsWeb) {
        final finder =
            sembast.Finder(filter: sembast.Filter.equals('email', email));
        final record =
            await (_userStore as sembast.StoreRef<String, Map<String, dynamic>>)
                .findFirst(await database, finder: finder);
        if (record != null) {
          final userData = Map<String, dynamic>.from(record.value);
          userData['id'] = _coerceToString(record.key);
          return _normalizeUserData(userData);
        }
        return null;
      } else {
        final result = await (await database as sqflite.Database)
            .query('users', where: 'email = ?', whereArgs: [email]);
        if (result.isNotEmpty) {
          final userData = Map<String, dynamic>.from(result.first);
          userData['id'] = _coerceToString(userData['id']);
          return _normalizeUserData(userData);
        }
        return null;
      }
    } catch (e) {
      throw Exception('Failed to fetch user by email: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserById(String id) async {
    try {
      final firestoreDoc = await _firestore.collection('users').doc(id).get();
      if (firestoreDoc.exists) {
        final data = firestoreDoc.data()!;
        data['id'] = _coerceToString(firestoreDoc.id);
        return _normalizeUserData(data);
      }

      if (kIsWeb) {
        final record =
            await (_userStore as sembast.StoreRef<String, Map<String, dynamic>>)
                .record(id)
                .get(await database);
        if (record != null) {
          final userData = Map<String, dynamic>.from(record);
          userData['id'] = _coerceToString(id);
          return _normalizeUserData(userData);
        }
        return null;
      } else {
        final result = await (await database as sqflite.Database)
            .query('users', where: 'id = ?', whereArgs: [id]);
        if (result.isNotEmpty) {
          final userData = Map<String, dynamic>.from(result.first);
          userData['id'] = _coerceToString(userData['id']);
          return _normalizeUserData(userData);
        }
        return null;
      }
    } catch (e) {
      throw Exception('Failed to fetch user by id: $e');
    }
  }

  Future<String> updateUser(Map<String, dynamic> user) async {
    final userData = Map<String, dynamic>.from(user);
    userData['id'] = _coerceToString(userData['id']);
    userData['username'] = _coerceToString(userData['username']);
    userData['email'] = _coerceToString(userData['email']);
    userData['bio'] = _coerceToString(userData['bio']);
    userData['password'] = _coerceToString(userData['password']);
    userData['auth_provider'] = _coerceToString(userData['auth_provider']);
    userData['token'] = _coerceToString(userData['token']);
    userData['created_at'] = _coerceToString(userData['created_at']);
    userData['updated_at'] = _coerceToString(
        userData['updated_at'] ?? DateTime.now().toIso8601String());
    userData['avatar'] = _coerceToString(userData['avatar']);
    userData.remove('profile_id');
    userData.remove('profile_name');

    try {
      final userId = userData['id'];
      await _firestore.collection('users').doc(userId).update(userData);
      if (kIsWeb) {
        await (_userStore as sembast.StoreRef<String, Map<String, dynamic>>)
            .record(userId)
            .update(await database, userData);
      } else {
        await (await database as sqflite.Database).update(
          'users',
          userData,
          where: 'id = ?',
          whereArgs: [userId],
        );
      }
      return userId;
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final firestoreUsers = await _firestore.collection('users').get();
      final firestoreUserList = firestoreUsers.docs.map((doc) {
        final data = doc.data();
        data['id'] = _coerceToString(doc.id);
        print('Firestore user ${doc.id}: $data');
        return _normalizeUserData(data);
      }).toList();

      List<Map<String, dynamic>> localUsers;
      if (kIsWeb) {
        final records =
            await (_userStore as sembast.StoreRef<String, Map<String, dynamic>>)
                .find(await database);
        localUsers = records.map((r) {
          final userData = Map<String, dynamic>.from(r.value);
          userData['id'] = _coerceToString(r.key);
          userData['username'] = _coerceToString(userData['username']);
          userData['email'] = _coerceToString(userData['email']);
          userData['bio'] = _coerceToString(userData['bio']);
          userData['password'] = _coerceToString(userData['password']);
          userData['auth_provider'] =
              _coerceToString(userData['auth_provider']);
          userData['token'] = _coerceToString(userData['token']);
          userData['created_at'] = _coerceToString(userData['created_at']);
          userData['updated_at'] = _coerceToString(userData['updated_at']);
          userData['avatar'] = _coerceToString(userData['avatar']);
          print('Sembast user ${r.key} (before normalization): $userData');
          final normalizedUser = _normalizeUserData(userData);
          print('Sembast user ${r.key} (after normalization): $normalizedUser');
          return normalizedUser;
        }).toList();
      } else {
        final result = await (await database as sqflite.Database).rawQuery('''
          SELECT u.*, p.id as profile_id, p.avatar, p.name as profile_name
          FROM users u
          LEFT JOIN profiles p ON u.id = p.user_id
        ''');
        localUsers = result.map((r) {
          final userData = Map<String, dynamic>.from(r);
          userData['id'] = _coerceToString(userData['id']);
          userData['profile_id'] = _coerceToString(userData['profile_id']);
          userData['username'] = _coerceToString(userData['username']);
          userData['email'] = _coerceToString(userData['email']);
          userData['bio'] = _coerceToString(userData['bio']);
          userData['password'] = _coerceToString(userData['password']);
          userData['auth_provider'] =
              _coerceToString(userData['auth_provider']);
          userData['token'] = _coerceToString(userData['token']);
          userData['created_at'] = _coerceToString(userData['created_at']);
          userData['updated_at'] = _coerceToString(userData['updated_at']);
          userData['avatar'] = _coerceToString(userData['avatar']);
          userData['profile_name'] = _coerceToString(userData['profile_name']);
          print(
              'SQLite user ${userData['id']} (before normalization): $userData');
          final normalizedUser = _normalizeUserData(userData);
          print(
              'SQLite user ${userData['id']} (after normalization): $normalizedUser');
          return normalizedUser;
        }).toList();
      }

      final allUsersMap = <String, Map<String, dynamic>>{};
      for (var user in firestoreUserList) {
        final userId = user['id'];
        if (userId.isNotEmpty) {
          allUsersMap[userId] = user;
        }
      }
      for (var user in localUsers) {
        final userId = user['id'];
        if (userId.isNotEmpty) {
          final mergedUser = {
            ...allUsersMap[userId] ?? {},
            ...user,
          };
          print('Merged user $userId: $mergedUser');
          allUsersMap[userId] = mergedUser;
        }
      }

      print('Final merged users: ${allUsersMap.values.toList()}');
      return allUsersMap.values.toList();
    } catch (e) {
      throw Exception('Failed to fetch users: $e');
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final normalizedQuery = query.toLowerCase().trim();
    try {
      final allUsers = await getAllUsers();
      return allUsers.where((user) {
        final username = user['username'] != null
            ? user['username'].toString().toLowerCase()
            : '';
        final email =
            user['email'] != null ? user['email'].toString().toLowerCase() : '';
        print('Searching user: $user, username: $username, email: $email');
        return username.contains(normalizedQuery) ||
            email.contains(normalizedQuery);
      }).toList();
    } catch (e) {
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
        final data = firestoreResult.docs.first.data();
        data['id'] = _coerceToString(firestoreResult.docs.first.id);
        return _normalizeUserData(data);
      }

      if (kIsWeb) {
        final finder =
            sembast.Finder(filter: sembast.Filter.equals('token', token));
        final record =
            await (_userStore as sembast.StoreRef<String, Map<String, dynamic>>)
                .findFirst(await database, finder: finder);
        if (record != null) {
          final userData = Map<String, dynamic>.from(record.value);
          userData['id'] = _coerceToString(record.key);
          return _normalizeUserData(userData);
        }
        return null;
      } else {
        final result = await (await database as sqflite.Database)
            .query('users', where: 'token = ?', whereArgs: [token]);
        if (result.isNotEmpty) {
          final userData = Map<String, dynamic>.from(result.first);
          userData['id'] = _coerceToString(userData['id']);
          return _normalizeUserData(userData);
        }
        return null;
      }
    } catch (e) {
      throw Exception('Failed to fetch user by token: $e');
    }
  }
}
