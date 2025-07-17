import 'dart:async';
import 'dart:developer';

import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/ai_agent/tool_parser.dart';
import 'package:waico/core/ai_agent/tools.dart';
import 'package:waico/core/ai_models/chat_model.dart';

/// A robust AI agent that manages chat interactions and tool executions
class AiAgent {
  final ChatModel _chatModel;
  final Map<String, Tool> _tools;
  final int _maxToolIterations;

  /// Creates an AI agent with the provided tools and optional chat model
  AiAgent({
    ChatModel? chatModel,
    String? systemPrompt,
    required List<Tool> tools,
    int maxToolIterations = 5,
    double temperature = 1.0,
    int topK = 64,
    double topP = 0.95,
    bool supportImageInput = true,
  }) : _chatModel =
           chatModel ??
           ChatModel(
             systemPrompt: _enhanceSystemPromptWithTools(systemPrompt, tools),
             temperature: temperature,
             topK: topK,
             topP: topP,
             supportImageInput: supportImageInput,
           ),
       _tools = {for (var tool in tools) tool.name: tool},
       _maxToolIterations = maxToolIterations;

  /// Factory method to create a counselor AI agent with predefined system prompt
  factory AiAgent.counselor({
    required List<Tool> tools,
    int maxToolIterations = 5,
    double temperature = 1.0,
    int topK = 64,
    double topP = 0.95,
  }) {
    const systemPrompt =
        "You are Waico, a compassionate and trustworthy AI counselor. "
        "Your role is to provide emotional support, active listening, and thoughtful guidance rooted in evidence-based therapeutic principles (such as CBT, ACT, and mindfulness). "
        "Respond with empathy, clarity, and non-judgment. Encourage self-reflection, validate emotions, and offer practical coping strategies when appropriate. "
        "You are not a licensed therapist and do not diagnose or treat mental health conditions—always recommend speaking to a qualified professional when needed. "
        "Prioritize safety, confidentiality, and the well-being of the user in every interaction.";

    return AiAgent(
      systemPrompt: systemPrompt,
      tools: tools,
      maxToolIterations: maxToolIterations,
      temperature: temperature,
      topK: topK,
      topP: topP,
    );
  }

  /// Enhances the system prompt with tool information
  static String _enhanceSystemPromptWithTools(String? basePrompt, List<Tool> tools) {
    if (basePrompt == null || basePrompt.isEmpty) {
      basePrompt = 'You are Waico, a helpful Wellbeing AI Assistant.';
    }

    if (tools.isEmpty) return basePrompt;

    final toolDefinitions = tools.map((tool) => tool.definition).join('\n---\n');

    return '$basePrompt\n\n'
        'TOOL CALLING:\n'
        'You have access to the tools below that you can call to satisfy a user query or when you think it is appropriate.\n'
        '$toolDefinitions\n\n'
        "If a tool requires an input that you don't know or the user query is ambiguous, ask for clarification. If you can't perform the action requested and there is no tool to perform it, politely let the user know that you don't have that ability.\n\n";
  }

  /// Initializes the AI agent by setting up the chat model
  Future<void> initialize() async {
    await _chatModel.initialize();
  }

  /// Sends a message to the AI agent and returns a stream of text
  /// Tool calls are handled automatically, only text responses are yielded.
  Stream<String> sendMessage(String message, {Iterable<Attachment> attachments = const []}) async* {
    try {
      int iterationCount = 0;
      String currentMessage = message;

      while (iterationCount < _maxToolIterations) {
        final toolParser = ToolParser();
        final responseStream = _chatModel.sendMessageStream(currentMessage, attachments: attachments);

        // Transform the stream to parse tool calls
        final textStream = responseStream.transform(toolParser);

        final toolOutputs = <Future<ToolOutput>>[];
        // Listen to tool calls in parallel
        final toolCallSubscription = toolParser.toolCalls.listen((toolCall) {
          toolOutputs.add(_executeToolCall(toolCall));
        });

        yield* textStream;

        await toolCallSubscription.cancel();
        if (toolOutputs.isEmpty) break; // It was just a text response without tool use
        // Execute tool calls and prepare next iteration
        final toolResult = _formatToolOutputs(await toolOutputs.wait);
        if (toolResult.isEmpty) break; // No tool results, exit loop (Less likely to happen)

        currentMessage = toolResult; // Use tool results as the next message
        iterationCount++;
        // We already sent attachments in the first iteration, so clear them for subsequent iterations
        // Attachments in tool outputs are not supported yet.
        attachments = const [];
      }

      if (iterationCount >= _maxToolIterations) {
        yield '\n\nSorry, I have reached the maximum number of tool iterations allowed. '
            'Please try rephrasing your request or ask a different question.';
      }
    } catch (e, stackTrace) {
      log('Error in AiAgent.sendMessage', error: e, stackTrace: stackTrace);
      yield '\n\nI apologize, but I encountered an error while processing your request. Please try again.';
    }
  }

  /// Executes a list of tool calls and returns their results
  Future<ToolOutput> _executeToolCall(ToolCall toolCall) async {
    try {
      final tool = _tools[toolCall.toolName];
      if (tool == null) {
        return ToolOutput(
          toolName: toolCall.toolName,
          result: 'Error: Unknown tool "${toolCall.toolName}"',
          success: false,
        );
      }

      final result = await tool(toolCall.arguments);
      log('Tool executed successfully: ${toolCall.toolName}');
      return ToolOutput(toolName: toolCall.toolName, result: result, success: true);
    } catch (e, stackTrace) {
      log('Error executing tool ${toolCall.toolName}', error: e, stackTrace: stackTrace);
      return ToolOutput(toolName: toolCall.toolName, result: 'Error executing tool: $e', success: false);
    }
  }

  /// Formats tool results into a message for the next iteration
  String _formatToolOutputs(List<ToolOutput> output) {
    /// Example format:
    /// ```tool_output
    /// From toolName1:
    /// result1
    /// ---
    /// From toolName2:
    /// result2
    /// ```
    ///
    if (output.isEmpty) return '';
    return '```tool_output\n'
        '${output.map((output) => 'From ${output.toolName}:\n${output.result}').join('\n---\n')}\n'
        '```';
  }

  /// Gets the current chat history
  Iterable<ChatMessage> get history => _chatModel.history;

  /// Sets the chat history (useful for restoring previous conversations)
  set history(Iterable<ChatMessage> history) => _chatModel.history = history;

  /// Clears the current conversation history
  Future<void> clearHistory() async {
    await _chatModel.initialize(); // Reinitialize to clear history
  }

  /// Gets the available tools and their definitions
  Map<String, String> get availableTools => _tools.map((name, tool) => MapEntry(name, tool.definition));

  /// Adds a new tool to the agent
  void addTool(Tool tool) {
    _tools[tool.name] = tool;
  }

  /// Removes a tool from the agent
  void removeTool(String toolName) {
    _tools.remove(toolName);
  }

  /// Disposes of the AI agent and its resources
  Future<void> dispose() async {
    await _chatModel.dispose();
  }
}

/// Represents the result of a tool execution
class ToolOutput {
  final String toolName;
  final String result;
  final bool success;

  ToolOutput({required this.toolName, required this.result, required this.success});

  @override
  String toString() => 'ToolResult($toolName: $result, success: $success)';
}
