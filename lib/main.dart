import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_vless/flutter_vless.dart';
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
  late final FlutterVless _flutterVless;

  bool isLoading = false;
  bool isConnected = false;
  bool isConnecting = false;
  String ping = '--- мс';
  List<FlutterVlessURL> _servers = [];
  FlutterVlessURL? _selectedServer;

  @override
  void initState() {
    super.initState();
    _flutterVless = FlutterVless(
      onStatusChanged: (status) {
        debugPrint('VPN Status: state=${status.state}');
      },
    );
    _initVless();
  }

  Future<void> _initVless() async {
    try {
      await _flutterVless.initializeVless(
        providerBundleIdentifier: 'com.example.my_vpn_app',
        groupIdentifier: 'group.com.example.my_vpn_app',
      );
      debugPrint('FlutterVless успешно инициализирован');
    } catch (e) {
      debugPrint('Ошибка инициализации FlutterVless: $e');
    }
  }

  Future<void> loadSubscription() async {
    final url = _subController.text.trim();
    if (url.isEmpty) {
      _showError('Вставьте ссылку на подписку');
      return;
    }

    setState(() {
      isLoading = true;
      _servers.clear();
      _selectedServer = null;
      isConnected = false;
      ping = '--- мс';
    });

    try {
      final response = await http.get(Uri.parse(url));
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

      final parsedServers = FlutterVless.parseMany(rawData);
      if (parsedServers.isEmpty) {
        throw Exception('В подписке не найдено серверов');
      }

      setState(() {
        _servers = parsedServers;
        _selectedServer = _servers.first;
      });
    } catch (e) {
      _showError('Ошибка загрузки: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> toggleConnection() async {
    if (isConnecting) return;

    if (isConnected) {
      setState(() => isConnecting = true);
      try {
        await _flutterVless.stopVless();
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

    if (_selectedServer == null) {
      _showError('Сначала загрузите подписку и выберите сервер');
      return;
    }

    setState(() => isConnecting = true);
    try {
      final rawConfig = _selectedServer!.getFullConfiguration();
      Map<String, dynamic> configMap = jsonDecode(rawConfig);
      
      // --- ОЧИСТКА КОНФИГА ПЕРЕД ОТПРАВКОЙ ---
      if (configMap['outbounds'] != null) {
        for (var outbound in configMap['outbounds']) {
          outbound.remove('mux');
          if (outbound['streamSettings'] != null &&
              outbound['streamSettings']['tlsSettings'] != null) {
            outbound['streamSettings']['tlsSettings'].remove('alpn'); 
          }
        }
      }
      if (configMap['inbounds'] != null) {
        for (var inbound in configMap['inbounds']) {
          inbound.remove('sniffing'); 
        }
      }
      if (configMap['log'] != null) {
        configMap['log']['loglevel'] = 'warning';
      }
      
      final cleanedConfig = jsonEncode(configMap);

      final permissionGranted = await _flutterVless.requestPermission();
      if (!permissionGranted) {
        _showError('Вы отклонили запрос на создание VPN');
        return;
      }

      await _flutterVless.startVless(
        remark: _selectedServer!.remark,
        config: cleanedConfig,
      );

      setState(() {
        isConnected = true;
        ping = 'Считаем...';
      });
      checkPing();
    } catch (e, stackTrace) {
      debugPrint('Ошибка подключения: $e');
      _showError('Ошибка подключения. Подробности в консоли.');
    } finally {
      setState(() => isConnecting = false);
    }
  }

  Future<void> checkPing() async {
    if (_selectedServer == null) return;
    setState(() => ping = 'Замер...');
    try {
      final delay = await _flutterVless.getServerDelay(
        config: _selectedServer!.getFullConfiguration(),
        url: 'https://google.com/generate_204',
      );
      setState(() => ping = '$delay мс');
    } catch (e) {
      setState(() => ping = 'Сервер мертв');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              child: _servers.isEmpty
                  ? const Center(child: Text('Вставьте ссылку и нажмите "Загрузить"'))
                  : ListView.builder(
                      itemCount: _servers.length,
                      itemBuilder: (context, index) {
                        final server = _servers[index];
                        final isSelected = _selectedServer == server;
                        return Card(
                          color: isSelected ? Colors.deepPurple.shade50 : null,
                          child: ListTile(
                            leading: Icon(Icons.dns, color: isSelected ? Colors.deepPurple : Colors.grey),
                            title: Text(
                              server.remark.isNotEmpty ? server.remark : 'Сервер ${index + 1}',
                              style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                            ),
                            subtitle: Text('${server.network} • ${server.address}'),
                            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                            onTap: () {
                              setState(() {
                                _selectedServer = server;
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isConnected && ping.contains('мс') ? Colors.green : Colors.grey,
              ),
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
