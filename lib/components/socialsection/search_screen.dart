import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<String> _results = []; // Simulated search results.
  final List<String> _recentSearches = ['Movie', 'Action', 'Drama', 'Comedy'];

  void _search(String query) {
    setState(() {
      if (query.isNotEmpty) {
        // Simulate search results.
        _results =
            List.generate(5, (index) => "Result ${index + 1} for \"$query\"");
      } else {
        _results = [];
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Search"),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple, Colors.indigo],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Styled search bar.
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: "Search posts, users, hashtags...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              _search('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onChanged: _search,
                  onSubmitted: _search,
                ),
              ),
              const SizedBox(height: 16),
              // Display recent searches or search results.
              Expanded(
                child: _controller.text.isEmpty
                    ? ListView(
                        children: [
                          const Text(
                            "Recent Searches",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: _recentSearches
                                .map(
                                  (search) => Chip(
                                    label: Text(search),
                                    backgroundColor: Colors.white70,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      )
                    : _results.isEmpty
                        ? const Center(
                            child: Text(
                              "No results found.",
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (context, index) =>
                                const Divider(color: Colors.white54),
                            itemBuilder: (context, index) => ListTile(
                              title: Text(
                                _results[index],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16),
                              ),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        "You selected: ${_results[index]}"),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
