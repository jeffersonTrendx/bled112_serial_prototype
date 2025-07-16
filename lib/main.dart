import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:BLED112_serial_prototype/models.dart';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UsbPort? _port;
  UsbDevice? _device;
  StreamSubscription<Uint8List>? _subscription;

  String _status = "Idle";
  bool _isScanning = false;

  List<Widget> _ports = [];
  final List<Widget> _serialData = [];
  // final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Ouve eventos de conexão/desconexão USB
    UsbSerial.usbEventStream?.listen((UsbEvent event) {
      _getPorts();
    });

    _getPorts();
  }

  @override
  void dispose() {
    _connectTo(null);
    super.dispose();
  }

  // Envia comando binário via serial
  Future<void> sendCommand(List<int> data) async {
    if (_port != null) {
      await _port!.write(Uint8List.fromList(data));
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // Obtém lista de portas USB disponíveis
  void _getPorts() async {
    _ports = [];
    List<UsbDevice> devices = await UsbSerial.listDevices();

    if (!devices.contains(_device)) {
      _connectTo(null);
    }

    for (var device in devices) {
      _ports.add(
        SizedBox(
          height: 40,
          child: ListTile(
            leading: const Icon(Icons.usb),
            title: Text(device.productName ?? "Unknown Device"),
            trailing: ElevatedButton(
              child: Text(_device == device ? "Disconnect" : "Connect"),
              onPressed: () {
                _connectTo(_device == device ? null : device).then((_) {
                  _getPorts();
                });
              },
            ),
          ),
        ),
      );
    }

    setState(() {});
  }

  // Conecta ou desconecta de um dispositivo
  Future<bool> _connectTo(device) async {
    try {
      _serialData.clear();

      await _subscription?.cancel();
      _subscription = null;

      await _port?.close();
      _port = null;

      if (device == null) {
        _device = null;
        setState(() => _status = "Disconnected");
        return true;
      }

      _port = await device.create();
      if (!await _port!.open()) {
        setState(() => _status = "Failed to open port");
        return false;
      }

      _device = device;
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
          115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      // Ouve dados da porta serial
      _subscription = _port!.inputStream!.listen((Uint8List data) {
        final parsed = parseScanResponsePacket(data);

        if (parsed.containsKey("error")) return;

        final device = DiscoveredDevice(
          id: parsed['macAddress'] ?? '',
          name: parsed['name'] ?? '',
          rssi: parsed['rssi'] ?? 0,
          manufacturerData:
              Uint8List.fromList(parsed['manufacturerData'] ?? []),
          serviceUuids: List<String>.from(
            (parsed['uuid16bit'] ?? []).map((e) => e.toString()),
          ),
          serviceData: {},
        );

        try {
          final myBeat = myBeatDeviceBroadcastsSerializer.from(device);
          setState(() {
            if (myBeat.id == 22) {
              _serialData.add(_buildBroadcastCard(myBeat));

              if (_serialData.length > 20) {
                _serialData.removeAt(0);
              }
            }
          });
        } catch (e) {
          setState(() {
            log('Erro ao decodificar broadcast: $device');
            _serialData.add(const Text('Erro ao decodificar broadcast'));
          });
        }
      });

      setState(() => _status = "Connected");

      // Envia stop scan para garantir estado inicial
      await sendCommand([0x00, 0x00, 0x06, 0x03]);
      return true;
    } catch (e) {
      debugPrint('Erro ao conectar: $e');
      setState(() => _status = "Error connecting to device");
      return false;
    }
  }

  // Interpreta resposta de scan BLE (gap_scan_response)
  Map<String, dynamic> parseScanResponsePacket(Uint8List data) {
    // Verificações básicas do pacote BGAPI de scan_response
    if (data.length < 15 ||
        data[0] != 0x80 ||
        data[2] != 0x06 ||
        data[3] != 0x00) {
      return {"error": "Pacote inválido ou não é scan_response"};
    }

    // RSSI (signed int8)
    final rssi = data[4] > 127 ? data[4] - 256 : data[4];

    // MAC Address (inverter ordem)
    final mac = List.generate(6, (i) => data[11 - i])
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');

    final addressType = data[12];
    final bonding = data[13];
    final advLength = data[14];

    if (data.length < 15 + advLength) {
      return {"error": "Dados incompletos"};
    }

    final advertisingData = data.sublist(15, 15 + advLength);

    // Variáveis a serem preenchidas com os dados extraídos
    String? name;
    List<int>? manufacturerData;
    List<String> uuids16BitHex = [];

    // Leitura em formato TLV (Length-Type-Value)
    int i = 0;
    while (i < advertisingData.length) {
      final length = advertisingData[i];

      // Verificação de limite de segurança
      if (length == 0 || i + length >= advertisingData.length) break;

      final type = advertisingData[i + 1];
      final value = advertisingData.sublist(i + 2, i + 1 + length);

      switch (type) {
        case 0x01:
          // Flags (pode ser ignorado ou tratado)
          break;

        case 0x09:
          // Nome do dispositivo
          name = String.fromCharCodes(value);
          break;

        case 0xFF:
          // Manufacturer Specific Data
          if (value.length >= 2) {
            manufacturerData = value;
          }
          break;

        case 0x03:
          // UUIDs de 16 bits (Lista)
          for (int j = 0; j < value.length; j += 2) {
            if (j + 1 < value.length) {
              final uuid = (value[j + 1] << 8) | value[j];
              uuids16BitHex.add(
                  '0x${uuid.toRadixString(16).padLeft(4, '0').toUpperCase()}');
            }
          }
          break;
      }

      i += length + 1;
    }

    // Resultado final do parsing
    return {
      "macAddress": mac,
      "rssi": rssi,
      "name": name,
      "uuid16bit": uuids16BitHex,
      "manufacturerData": manufacturerData,
      "addressType": addressType,
      "bonding": bonding,
    };
  }

  // Faz parsing dos advertising data (TLV)
  List<Map<String, dynamic>> parseAdvertisingData(Uint8List advData) {
    List<Map<String, dynamic>> parsed = [];
    int i = 0;

    while (i < advData.length) {
      final length = advData[i];
      if (length == 0 || i + length >= advData.length) break;

      final type = advData[i + 1];
      final value = advData.sublist(i + 2, i + 1 + length);
      final valueHex =
          value.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

      Map<String, dynamic> interpreted = {
        "type": type,
        "typeHex": type.toRadixString(16).padLeft(2, '0'),
        "value": value,
        "valueHex": valueHex,
      };

      // Interpretação por tipo
      switch (type) {
        case 0x01:
          interpreted["description"] = "Flags";
          interpreted["flags"] = _parseFlags(value.first);
          break;
        case 0x09:
          interpreted["description"] = "Complete Local Name";
          interpreted["name"] = String.fromCharCodes(value);
          break;
        case 0x0A:
          interpreted["description"] = "TX Power";
          interpreted["txPower"] =
              value.first > 127 ? value.first - 256 : value.first;
          break;
        case 0xFF:
          interpreted["description"] = "Manufacturer Specific Data";
          if (value.length >= 2) {
            final companyId = (value[1] << 8) | value[0];
            interpreted["companyId"] =
                "0x${companyId.toRadixString(16).padLeft(4, '0')}";
            interpreted["companyName"] = _bleCompanyId(companyId);
          }
          break;
        default:
          interpreted["description"] = "Unknown / Raw";
      }

      parsed.add(interpreted);
      i += length + 1;
    }

    return parsed;
  }

  // Mapeia o ID da empresa BLE para nome
  String _bleCompanyId(int id) {
    switch (id) {
      case 0x004C:
        return "Apple, Inc.";
      case 0x0006:
        return "Microsoft";
      case 0x000F:
        return "Broadcom Corporation";
      default:
        return "Unknown";
    }
  }

  // Decodifica os flags do byte 0x01
  List<String> _parseFlags(int byte) {
    return [
      if ((byte & 0x01) != 0) "LE Limited Discoverable Mode",
      if ((byte & 0x02) != 0) "LE General Discoverable Mode",
      if ((byte & 0x04) != 0) "BR/EDR Not Supported",
      if ((byte & 0x08) != 0) "Simultaneous LE and BR/EDR (Controller)",
      if ((byte & 0x10) != 0) "Simultaneous LE and BR/EDR (Host)",
    ];
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('USB Serial Plugin example app')),
        body: SingleChildScrollView(
          child: Center(
            child: Column(
              children: <Widget>[
                Text(
                  _ports.isNotEmpty
                      ? "Available Serial Ports"
                      : "No serial devices available",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ..._ports,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text('Status: $_status'),
                    Text('isScanning: $_isScanning'),
                  ],
                ),
                Text('info: ${_port.toString()}'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        await sendCommand([0x00, 0x00, 0x01, 0x01]);
                        _serialData.clear();
                      },
                      child: const Text("reset"),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await sendCommand([0x00, 0x01, 0x06, 0x02, 0x02]);
                        setState(() => _isScanning = true);
                      },
                      child: const Text("iniciar varredura"),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await sendCommand([0x00, 0x00, 0x06, 0x04]);
                        setState(() => _isScanning = false);
                      },
                      child: const Text("parar varredura"),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text("Result Data",
                    style: Theme.of(context).textTheme.titleLarge),
                ..._serialData,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBroadcastCard(MyBeatDeviceBroadcast broadcast) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      width: 150,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('ID: ${broadcast.id}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('HR: ${broadcast.heartRate} bpm',
              style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
