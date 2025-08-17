import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Message {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  Message({
    required this.content,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'content': content,
    'isUser': isUser,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    content: json['content'],
    isUser: json['isUser'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  bool _isLoading = false;

  // Default Ollama server URL
  String baseUrl = 'http://localhost:11434';
  String currentModel = 'llama3.2'; // Default model
  List<String> availableModels = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadChatHistory();
    _loadAvailableModels();
  }

  @override
  void dispose() {
    _saveChatHistory();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      baseUrl = prefs.getString('baseUrl') ?? 'http://localhost:11434';
      currentModel = prefs.getString('currentModel') ?? 'llama3.2';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('currentModel', currentModel);
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('chatHistory');
    if (historyJson != null) {
      final historyList = jsonDecode(historyJson) as List;
      setState(() {
        _messages.clear();
        _messages.addAll(historyList.map((json) => Message.fromJson(json)).toList());
      });
      _scrollToBottom();
    }
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = jsonEncode(_messages.map((msg) => msg.toJson()).toList());
    await prefs.setString('chatHistory', historyJson);
  }

  Future<void> _clearChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chatHistory');
    setState(() {
      _messages.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat history cleared')),
    );
  }

  Future<void> _loadAvailableModels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/tags'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['models'] as List;
        setState(() {
          availableModels = models.map((model) => model['name'] as String).toList();
          if (availableModels.isNotEmpty && !availableModels.contains(currentModel)) {
            currentModel = availableModels.first;
            _saveSettings();
          }
        });
      }
    } catch (e) {
      print('Error loading models: $e');
      // Set some common default models if connection fails
      setState(() {
        availableModels = ['llama3.2', 'llama2', 'codellama', 'mistral'];
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();

    setState(() {
      _messages.add(Message(content: text, isUser: true, timestamp: DateTime.now()));
      _messages.add(Message(content: '', isUser: false, timestamp: DateTime.now())); // placeholder
      _isLoading = true;
    });
    _scrollToBottom();
    _saveChatHistory(); // Save after adding user message

    try {
      final requestBody = {
        'model': currentModel,
        'prompt': text,
        'stream': true,
      };

      final req = http.Request('POST', Uri.parse('$baseUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(requestBody);

      final resp = await http.Client().send(req);

      if (resp.statusCode != 200) {
        throw Exception('Server returned ${resp.statusCode}');
      }

      final buf = StringBuffer();
      final completer = Completer<void>();

      resp.stream.transform(utf8.decoder).listen((chunk) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final data = jsonDecode(line);
            final response = data['response'] as String? ?? '';
            final done = data['done'] as bool? ?? false;
            
            if (response.isNotEmpty) {
              buf.write(response);
              setState(() {
                _messages[_messages.length - 1] = Message(
                  content: buf.toString(),
                  isUser: false,
                  timestamp: DateTime.now(),
                );
              });
              _scrollToBottom();
            }
            
            if (done) {
              _saveChatHistory(); // Save when response is complete
              completer.complete();
              break;
            }
          } catch (e) {
            print('Error parsing JSON: $e');
          }
        }
      }, onError: (e) {
        if (!completer.isCompleted) {
          setState(() {
            _isLoading = false;
            _messages[_messages.length - 1] = Message(
              content: '⚠️ Error streaming: $e',
              isUser: false,
              timestamp: DateTime.now(),
            );
          });
          _saveChatHistory();
          completer.completeError(e);
        }
      }, onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await completer.future;
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages[_messages.length - 1] = Message(
          content: '⚠️ Could not connect to Ollama: $e\n\nMake sure Ollama is running and accessible at $baseUrl',
          isUser: false,
          timestamp: DateTime.now(),
        );
      });
      _saveChatHistory();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSettingsDialog() {
    final urlController = TextEditingController(text: baseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Settings', style: TextStyle(color: Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.black),
              decoration: const InputDecoration(
                labelText: 'Ollama Server URL',
                labelStyle: TextStyle(color: Colors.black54),
                hintText: 'http://localhost:11434',
                hintStyle: TextStyle(color: Colors.black38),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black26),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (availableModels.isNotEmpty) ...[
              const Text('Current Model:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: currentModel,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black),
                items: availableModels.map((model) {
                  return DropdownMenuItem(
                    value: model, 
                    child: Text(model, style: const TextStyle(color: Colors.black)),
                  );
                }).toList(),
                onChanged: (newModel) {
                  if (newModel != null) {
                    setState(() => currentModel = newModel);
                    _saveSettings();
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _clearChatHistory,
                icon: const Icon(Icons.delete_outline, color: Colors.black54),
                label: const Text('Clear Chat History', style: TextStyle(color: Colors.black54)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.black26),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          TextButton(
            onPressed: () async {
              final newUrl = urlController.text.trim();
              if (newUrl != baseUrl) {
                setState(() => baseUrl = newUrl);
                await _saveSettings();
                await _loadAvailableModels(); // Reload models for new URL
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Settings updated. Using model: $currentModel'),
                  backgroundColor: Colors.black87,
                ),
              );
            },
            child: const Text('Save', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Ollama Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: Colors.black),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Model: $currentModel • Server: $baseUrl',
                    style: const TextStyle(color: Colors.black87, fontSize: 12),
                  ),
                ),
                if (availableModels.isEmpty)
                  const Icon(Icons.warning_outlined, size: 16, color: Colors.black54),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(Icons.chat_outlined, size: 48, color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Start chatting with $currentModel',
                          style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Make sure Ollama is running locally',
                          style: TextStyle(color: Colors.black54, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : Container(
                    color: Colors.grey.shade50,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _buildMessageBubble(_messages[i]),
                    ),
                  ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _sendMessage(),
                    maxLines: null,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Ask ${availableModels.isNotEmpty ? currentModel : 'AI'} anything…',
                      hintStyle: const TextStyle(color: Colors.black38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.black26),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.black26),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.black, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      prefixIcon: availableModels.isNotEmpty 
                          ? Container(
                              margin: const EdgeInsets.only(left: 4, right: 4),
                              child: PopupMenuButton<String>(
                                icon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.circle, size: 12, color: Colors.black),
                                    const SizedBox(width: 6),
                                    Text(
                                      currentModel.length > 12 ? '${currentModel.substring(0, 12)}...' : currentModel,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black54),
                                  ],
                                ),
                                tooltip: 'Select Model',
                                color: Colors.white,
                                itemBuilder: (context) => availableModels.map((model) {
                                  return PopupMenuItem<String>(
                                    value: model,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 12,
                                          color: model == currentModel ? Colors.black : Colors.black26,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          model,
                                          style: TextStyle(
                                            fontWeight: model == currentModel ? FontWeight.w500 : FontWeight.normal,
                                            color: model == currentModel ? Colors.black : Colors.black87,
                                          ),
                                        ),
                                        if (model == currentModel) ...[
                                          const Spacer(),
                                          const Icon(Icons.check, size: 16, color: Colors.black),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onSelected: (model) {
                                  setState(() => currentModel = model);
                                  _saveSettings();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Switched to $model'),
                                      backgroundColor: Colors.black87,
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                            )
                          : const Padding(
                              padding: EdgeInsets.only(left: 12, right: 8),
                              child: Icon(
                                Icons.circle,
                                size: 16,
                                color: Colors.black26,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _isLoading ? Colors.grey.shade200 : Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20, height: 20, 
                            child: CircularProgressIndicator(
                              strokeWidth: 2, 
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message m) {
    final bubbleColor = m.isUser ? Colors.black : Colors.grey.shade100;
    final textColor = m.isUser ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: m.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!m.isUser)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black26),
              ),
              child: const Icon(Icons.circle, size: 12, color: Colors.black),
            ),
          if (!m.isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bubbleColor, 
                borderRadius: BorderRadius.circular(14),
                border: m.isUser ? null : Border.all(color: Colors.black12),
              ),
              child: m.isUser
                  ? SelectableText(m.content, style: TextStyle(color: textColor, fontSize: 16))
                  : _AiRichMessage(text: m.content),
            ),
          ),
          if (m.isUser) const SizedBox(width: 8),
          if (m.isUser)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person_outline, size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _AiRichMessage extends StatelessWidget {
  final String text;
  const _AiRichMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    final segments = _splitByCodeFences(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments) ...[
          if (seg.isCode)
            _CodeBlock(seg.text)
          else
            _InlineCodeText(seg.text),
          const SizedBox(height: 6),
        ]
      ],
    );
  }

  static List<_Segment> _splitByCodeFences(String input) {
    final segs = <_Segment>[];
    final re = RegExp(r'```(\w+)?\n([\s\S]*?)```', multiLine: true);
    int last = 0;

    for (final m in re.allMatches(input)) {
      if (m.start > last) {
        segs.add(_Segment(input.substring(last, m.start), false));
      }
      final code = (m.group(2) ?? '').trimRight();
      segs.add(_Segment(code, true));
      last = m.end;
    }
    if (last < input.length) {
      segs.add(_Segment(input.substring(last), false));
    }
    return segs;
  }
}

class _InlineCodeText extends StatelessWidget {
  final String text;
  const _InlineCodeText(this.text);

  @override
  Widget build(BuildContext context) {
    // Render inline `code` inside normal text.
    final spans = <TextSpan>[];
    final re = RegExp(r'`([^`]+)`');
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Color(0xFFE5E5E5),
          color: Colors.black,
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return SelectableText.rich(
      TextSpan(style: const TextStyle(fontSize: 16, color: Colors.black87), children: spans),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black26),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          code.isEmpty ? ' ' : code,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _Segment {
  final String text;
  final bool isCode;
  _Segment(this.text, this.isCode);
}