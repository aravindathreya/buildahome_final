import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import 'app_theme.dart';

class FullScreenImage extends StatefulWidget {
  final String id;
  final List<String>? imageUrls;
  final int initialIndex;

  const FullScreenImage(
    this.id, {
    super.key,
    this.imageUrls,
    this.initialIndex = 0,
  });

  List<String> get urls {
    if (imageUrls != null && imageUrls!.isNotEmpty) return imageUrls!;
    return [id];
  }

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<FullScreenImage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final urls = widget.urls;
    _currentIndex = widget.initialIndex.clamp(0, urls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ImageProvider _imageProvider(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return CachedNetworkImageProvider(url);
    }

    final file = File(url);
    if (file.existsSync()) {
      return FileImage(file);
    }

    return CachedNetworkImageProvider(url);
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final hasMultiple = urls.length > 1;

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            hasMultiple
                ? 'Photo ${_currentIndex + 1} of ${urls.length}'
                : 'Image preview',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: urls.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return PhotoView(
                      backgroundDecoration:
                          const BoxDecoration(color: Colors.black),
                      minScale: PhotoViewComputedScale.contained,
                      imageProvider: _imageProvider(urls[index]),
                      loadingBuilder: (context, event) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load image',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (hasMultiple) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(urls.length, (index) {
                    final active = index == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
