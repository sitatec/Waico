import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:itcares/core/gemma3n.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChatPage());
}

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gemma 3n')),
    body: LlmChatView(provider: Gemma3n(modelPath: '/Users/sitatech/LLMs/gemma-3n-E2B-it-int4.task')),
  );
}
