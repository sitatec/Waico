import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/gemma3n_model.dart';
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
    home: const ChatPage(),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final model = Gemma3nModel();
  bool isModelReady = false;

  @override
  void initState() {
    super.initState();
    model
        .initialize()
        .then((_) {
          setState(() {
            isModelReady = true;
          });
        })
        .catchError((error) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error initializing model: $error')));
        });
  }

  @override
  Future<void> dispose() async {
    await model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma 3n'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AiModelsInitializationPage(
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
                ),
              );
            },
            tooltip: 'Open Downloads',
          ),
        ],
      ),
      body: isModelReady
          ? LlmChatView(
              provider: model,
              welcomeMessage: "How can I help you today?",
              responseBuilder: (context, response) {
                return Text(response, style: const TextStyle(fontSize: 16, color: Colors.black87));
              },
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [const CircularProgressIndicator(), const SizedBox(height: 20), Text('Loading model...')],
              ),
            ),
    );
  }
}
