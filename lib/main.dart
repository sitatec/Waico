import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:waico/core/gemma3n.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!await FlutterGemmaPlugin.instance.modelManager.isModelInstalled) {
    await FlutterGemmaPlugin.instance.modelManager.downloadModelFromNetwork(
      'http://192.168.63.170:8000/gemma-3n-E2B-it-int4.task',
    );
  }
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
  final model = Gemma3n();
  bool isModelReady = false;

  @override
  void initState() {
    super.initState();
    model
        .initializeModel()
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
      appBar: AppBar(title: const Text('Gemma 3n')),
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
