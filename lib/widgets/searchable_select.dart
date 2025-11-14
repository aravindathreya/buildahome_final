import 'package:flutter/material.dart';
import '../app_theme.dart';

class SearchableSelect extends StatefulWidget {
  final String title;
  final List<dynamic> items;
  final String Function(dynamic)? itemLabel;
  final dynamic selectedItem;
  final Function(dynamic) onItemSelected;
  final int defaultVisibleCount;

  const SearchableSelect({
    Key? key,
    required this.title,
    required this.items,
    this.itemLabel,
    this.selectedItem,
    required this.onItemSelected,
    this.defaultVisibleCount = 5,
  }) : super(key: key);

  @override
  State<SearchableSelect> createState() => _SearchableSelectState();
}

class _SearchableSelectState extends State<SearchableSelect> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _filteredItems = [];
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterItems);
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems() {
    setState(() {
      final query = _searchController.text.toLowerCase();
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((item) {
          final label = widget.itemLabel != null
              ? widget.itemLabel!(item)
              : item.toString();
          return label.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  String _getItemLabel(dynamic item) {
    if (widget.itemLabel != null) {
      return widget.itemLabel!(item);
    }
    return item.toString();
  }

  @override
  Widget build(BuildContext context) {
    final itemsToShow = _showAll || _filteredItems.length <= widget.defaultVisibleCount
        ? _filteredItems
        : _filteredItems.take(widget.defaultVisibleCount).toList();
    final hasMore = _filteredItems.length > widget.defaultVisibleCount && !_showAll;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppTheme.backgroundSecondary,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.backgroundPrimary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppTheme.primaryColorConst),
                filled: true,
                fillColor: AppTheme.backgroundPrimary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColorConst.withOpacity(0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColorConst.withOpacity(0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColorConst,
                    width: 2,
                  ),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),

          // Results List
          Expanded(
            child: _filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: AppTheme.textSecondary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No results found',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: itemsToShow.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (hasMore && index == itemsToShow.length) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _showAll = true;
                              });
                            },
                            child: Text(
                              'Show all ${_filteredItems.length} results',
                              style: TextStyle(
                                color: AppTheme.primaryColorConst,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }

                      final item = itemsToShow[index];
                      final label = _getItemLabel(item);
                      final isSelected = widget.selectedItem == item;

                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                         
                          border: Border(bottom: BorderSide(color: AppTheme.textPrimary.withOpacity(0.1), width: 1)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              widget.onItemSelected(item);
                              Navigator.pop(context, item);
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle,
                                      color: AppTheme.primaryColorConst,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

