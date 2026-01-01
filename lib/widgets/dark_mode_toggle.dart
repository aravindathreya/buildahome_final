import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class DarkModeToggle extends StatelessWidget {
  final bool showLabel;
  
  const DarkModeToggle({Key? key, this.showLabel = true}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return InkWell(
      onTap: () {
        themeProvider.toggleTheme();
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: themeProvider.isDarkMode ? const Color.fromARGB(255, 246, 255, 0) : Colors.black, width: 1),
              ),
              child: Icon(
              themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: themeProvider.isDarkMode ? const Color.fromARGB(255, 246, 255, 0) : Colors.black,
              size: 20,
            ),
            ),
            if (showLabel) ...[
              SizedBox(width: 8),
              Text(
                themeProvider.isDarkMode ? 'Light Mode' : 'Dark Mode',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

