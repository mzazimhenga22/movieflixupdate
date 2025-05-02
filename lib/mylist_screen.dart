// lib/mylist_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movie_app/movie_detail_screen.dart';
import 'package:movie_app/components/movie_card.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({Key? key}) : super(key: key); // Explicit Key parameter

  @override
  _MyListScreenState createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  Future<List<Map<String, dynamic>>> _getMyList() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> myList = prefs.getStringList('myList') ?? [];
    // Decode each JSON string into a map.
    return myList
        .map((jsonStr) => json.decode(jsonStr) as Map<String, dynamic>)
        .toList();
  }

  Future<void> _removeFromMyList(String movieId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> myList = prefs.getStringList('myList') ?? [];
    myList.removeWhere((jsonStr) {
      final movieMap = json.decode(jsonStr);
      return movieMap['id'].toString() == movieId;
    });
    await prefs.setStringList('myList', myList);
    setState(() {}); // Refresh the screen.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My List"),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getMyList(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final myList = snapshot.data!;
          if (myList.isEmpty) {
            return const Center(child: Text("Your list is empty."));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: myList.length,
            itemBuilder: (context, index) {
              final movie = myList[index];
              final posterPath = movie['poster_path'];
              final posterUrl = posterPath != null
                  ? 'https://image.tmdb.org/t/p/w500$posterPath'
                  : '';
              final title = movie['title'] ?? movie['name'] ?? 'No Title';
              final rating = movie['vote_average'] != null
                  ? double.tryParse(movie['vote_average'].toString())
                  : null;
              return MovieCard(
                imageUrl: posterUrl,
                title: title,
                rating: rating,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MovieDetailScreen(movie: movie),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}