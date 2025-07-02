import 'package:flutter/material.dart';
import 'package:waico/pages/ai_model_init_page.dart';

void main() async {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Gemma 3n Chat',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: AiModelsInitializationPage(
      downloadItems: [
        DownloadItem(
          url: 'https://httpbin.org//stream-bytes/1000000',
          fileName: 'test0145.json',
          displayName: 'Base Model',
        ),
        DownloadItem(url: 'https://httpbin.org/delay/3', fileName: 'test24.json', displayName: 'Test24'),
        DownloadItem(url: 'https://httpbin.org/json', fileName: 'test34.json', displayName: 'Test34'),
        DownloadItem(
          url: 'https://jsonplaceholder.typicode.com/posts/12',
          fileName: 'post1F.json',
          displayName: 'Post1F',
        ),
        DownloadItem(
          url: 'https://jsonplaceholder.typicode.com/posts/2',
          fileName: 'post2G.json',
          displayName: 'Post2G',
        ),
        DownloadItem(
          url: 'https://jsonplaceholder.typicode.com/posts/2',
          fileName: 'post2J.json',
          displayName: 'Post2J',
        ),
      ],
    ),
  );
}
