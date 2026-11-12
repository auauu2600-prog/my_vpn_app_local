import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:v2ray_box/v2ray_box.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const VpnHomePage(),
    );
  }
}

class VpnHomePage extends StatefulWidget {
  const VpnHomePage({super.key});

  @override
  State<VpnHomePage> createState() => _VpnHomePageState();
}

class _VpnHomePageState extends State<VpnHomePage> {
  final TextEditingController _subController = TextEditingController();
  final V2rayBox _v2rayBox = V2rayBox();

  bool isInitialized = false;
  bool isLoading = false;
  bool isConnected = false;
  bool isConnecting = false;
  String ping = '--- мс';
  
  // Добавлено слово final, как просил анализатор
  final List<String> _serverLinks = [];
  final List<String> _serverNames = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _initV2rayBox();
  }

  Future<void> _initV2rayBox() async {
    try {
      await _v2rayBox.initialize(
        notificationStopButtonText: 'Отключить',
      );
      setState(() => isInitialized = true);
      debugPrint('V2rayBox инициализирован');
    } catch (e) {
      debugPrint('Ошибка инициализации V2rayBox: $e');
    }
  }

  Future<void> loadSubscription() async {
    String url = _subController.text.trim();
    if (url.isEmpty) {
      _showError('Вставьте ссылку на подписку');
      return;
    }

    if (url.startsWith('://')) {
      url = 'https$url';
    } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    setState(() {
      isLoading = true;
      _serverLinks.clear();
      _serverNames.clear();
      isConnected = false;
      ping = '--- мс';
    });

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      String rawData = response.body;
      if (!rawData.contains('://')) {
        try {
          rawData = utf8.decode(base64.decode(rawData));
        } catch (e) {
          debugPrint('Не удалось декодировать Base64: $e');
        }
      }

      final lines = rawData.split('\n');
      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('vless://') || line.startsWith('vmess://') || line.startsWith('trojan://')) {
          _serverLinks.add(line);
          String name = 'Сервер ${_serverLinks.length}';
          if (line.contains('#')) {
            try {
              name = Uri.decodeComponent(line.split('#').last);
            } catch (_) {}
          }
          _serverNames.add(name);
        }
      }

      if (_serverLinks.isEmpty) {
        throw Exception('В подписке не найдено серверов');
      }

      setState(() {
        _selectedIndex = 0;
      });
      debugPrint('Загружено серверов: ${_serverLinks.length}');

    } catch (e) {
      _showError('Ошибка загрузки: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> toggleConnection() async {
    if (isConnecting || !isInitialized) return;

    if (isConnected) {
      setState(() => isConnecting = true);
      try {
        await _v2rayBox.disconnect();
        setState(() {
          isConnected = false;
          ping = '--- мс';
        });
      } catch (e) {
        _showError('Ошибка отключения: $e');
      } finally {
        setState(() => isConnecting = false);
      }
      return;
    }

    if (_serverLinks.isEmpty) {
      _showError('Сначала загрузите подписку');
      return;
    }

    setState(() => isConnecting = true);
    try {
      final link = _serverLinks[_selectedIndex];
      final name = _serverNames[_selectedIndex];

      final success = await _v2rayBox.connect(link, name: name);
      if (success) {
        setState(() {
          isConnected = true;
          ping = 'Считаем...';
        });
        checkPing();
      } else {
        _showError('Не удалось подключиться');
      }
    } catch (e) {
      debugPrint('Ошибка подключения: $e');
      _showError('Ошибка подключения: $e');
    } finally {
      setState(() => isConnecting = false);
    }
  }

  Future<void> checkPing() async {
    if (_serverLinks.isEmpty) return;
    setState(() => ping = 'Замер...');
    try {
      final link = _serverLinks[_selectedIndex];
      final delay = await _v2rayBox.ping(link, timeout: 5000);
      setState(() => ping = delay == -1 ? 'Ошибка' : '$delay мс');
    } catch (e) {
      setState(() => ping = 'Ошибка');
      debugPrint('Ошибка пинга: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой VPN Клиент'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple.shade100,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _subController,
              decoration: const InputDecoration(
                labelText: 'Ссылка на подписку (https://...)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : loadSubscription,
                icon: isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(isLoading ? 'Загрузка...' : 'Загрузить серверы'),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _serverLinks.isEmpty
                  ? const Center(child: Text('Вставьте ссылку и нажмите "Загрузить"'))
                  : ListView.builder(
                      itemCount: _serverLinks.length,
                      itemBuilder: (context, index) {
                        final isSelected = _selectedIndex == index;
                        return Card(
                          color: isSelected ? Colors.deepPurple.shade50 : null,
                          child: ListTile(
                            leading: Icon(Icons.dns, color: isSelected ? Colors.deepPurple : Colors.grey),
                            title: Text(_serverNames[index], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              isConnected ? 'Пинг: $ping' : 'Пинг: --- мс',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isConnected && ping.contains('мс') ? Colors.green : Colors.grey),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: toggleConnection,
              child: Container(
                width: 100,
                height: 100,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? Colors.green : Colors.grey.shade300,
                  boxShadow: [
                    BoxShadow(
                      color: isConnected ? Colors.green.withValues(alpha: 0.5) : Colors.black12,
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: isConnecting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Icon(Icons.power_settings_new, size: 50, color: isConnected ? Colors.white : Colors.grey.shade600),
                ),
              ),
            ),
            Text(
              isConnecting ? 'ПОДОЖДИТЕ...' : (isConnected ? 'ПОДКЛЮЧЕНО' : 'ОТКЛЮЧЕНО'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: isConnected ? Colors.green : Colors.grey),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}