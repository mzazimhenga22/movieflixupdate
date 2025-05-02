// lib/search_screen.dart
import 'package:flutter/material.dart';
import 'package:movie_app/tmdb_api.dart' as tmdb;
import 'package:movie_app/movie_detail_screen.dart';
import 'package:movie_app/components/movie_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key); // Explicit Key parameter

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Future<List<dynamic>>? _searchResults;
  List<String> _previousSearches = [];

  @override
  void initState() {
    super.initState();
    _loadPreviousSearches();
  }

  Future<void> _loadPreviousSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _previousSearches = prefs.getStringList('previousSearches') ?? [];
    });
  }

  Future<void> _savePreviousSearch(String query) async {
    if (!_previousSearches.contains(query)) {
      _previousSearches.insert(0, query);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('previousSearches', _previousSearches);
    }
  }

  /// Called when the user submits a query.
  void _performSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
      });
      return;
    }
    _savePreviousSearch(query);
    setState(() {
      // Use the multi-search method to fetch both movies and TV shows.
      _searchResults = tmdb.TMDBApi.fetchSearchMulti(query);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: _controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search movies & TV shows...',
          hintStyle: const TextStyle(color: Colors.white54),
          border: InputBorder.none,
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    _controller.clear();
                    setState(() {
                      _searchResults = null;
                    });
                  },
                )
              : null,
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: _performSearch,
        onChanged: (value) {
          if (value.trim().isEmpty && _searchResults != null) {
            setState(() {
              _searchResults = null;
            });
          }
        },
      ),
    );
  }

  Widget _buildPreviousSearches() {
    if (_previousSearches.isEmpty) {
      return const Center(
        child: Text(
          'Enter a movie or TV show title above to search',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _previousSearches.length,
      itemBuilder: (context, index) {
        final searchQuery = _previousSearches[index];
        return ListTile(
          title: Text(
            searchQuery,
            style: const TextStyle(color: Colors.white),
          ),
          leading: const Icon(Icons.history, color: Colors.white54),
          onTap: () {
            _controller.text = searchQuery;
            _performSearch(searchQuery);
          },
        );
      },
    );
  }

  Widget _buildCategorySection(String categoryTitle, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            categoryTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.7,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MovieDetailScreen(movie: item),
                  ),
                );
              },
              // Use the factory constructor to build the MovieCard from JSON.
              child: MovieCard.fromJson(
                item,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MovieDetailScreen(movie: item),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSearchResults(List<dynamic> results) {
    // Filter the results to only include movies and TV shows.
    final moviesOnly =
        results.where((item) => item['media_type'] == 'movie').toList();
    final tvShows =
        results.where((item) => item['media_type'] == 'tv').toList();

    List<Widget> sections = [];
    if (moviesOnly.isNotEmpty) {
      sections.add(_buildCategorySection("Movies", moviesOnly));
    }
    if (tvShows.isNotEmpty) {
      sections.add(_buildCategorySection("TV Shows", tvShows));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: _buildSearchField(),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _performSearch(_controller.text),
          )
        ],
      ),
      body: _searchResults == null
          ? _buildPreviousSearches()
          : FutureBuilder<List<dynamic>>(
              future: _searchResults,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }
                final results = snapshot.data!;
                if (results.isEmpty) {
                  return const Center(
                    child: Text(
                      'No results found',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }
                return _buildSearchResults(results);
              },
            ),
    );
  }
}