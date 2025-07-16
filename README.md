# 🔌 BLED112 BLE Broadcast Listener (Flutter)

Este projeto é um protótipo Flutter que se comunica com o dongle **BLED112** (USB) utilizando porta serial. Ele interpreta pacotes de **broadcast BLE** recebidos no formato **BGAPI** e extrai dados como nome, fabricante, UUIDs e RSSI.

## 🧪 Propósito

Projetado para leitura em tempo real de dados publicitários BLE usando o dongle BLED112 da **Bluegiga**, com foco em dispositivos como o **MyBeat**, **Keiser M3i**, e outros sensores com advertising.

## 🧱 Recursos

- Comunicação direta com o dongle BLED112 via `SerialPort` (USB)
- Envio de comando `gap_discover`
- Recebimento e parsing de:
  - `gap_scan_response`
  - Nome (`0x09`)
  - Fabricante (`0xFF`)
  - UUIDs (`0x03`)
- MAC extraído corretamente (little-endian → big-endian)
- RSSI com sinal negativo (signed int8)

---

## 🔌 Pré-requisitos

- Dongle **Bluegiga BLED112** conectado via USB
- Permissão para acesso à porta serial no SO
- Plataforma: Android (com suporte USB Host),

## 🚀 Como usar

### 1. Configure o acesso à porta serial

Instale o pacote adequado, ex: [`usb_serial`](https://pub.dev/packages/usb_serial), [`dart_serial_port`](https://pub.dev/packages/dart_serial_port) ou `ffi` com `libusb`.

> Para testes no desktop, use `dart_serial_port` + `dart:ffi`.

### 2. Envie o comando de descoberta:

```dart
// gap_discover(mode = 2 = generic)
final command = Uint8List.fromList([0x00, 0x06, 0x06, 0x02]);
serialPort.write(command);
3. Escute as respostas:

if (data[0] == 0x80 && data[1] == 0x06 && data[2] == 0x00) {
  final scanResponse = data.sublist(3); // payload
  final parsed = parseGapScanResponse(scanResponse);
  print(parsed);
}
📦 Estrutura do pacote gap_scan_response

| Byte     | Significado                  |
|----------|------------------------------|
| 0        | RSSI (int8)                  |
| 1-6      | Endereço MAC (inverso)       |
| 7        | Endereço Type                |
| 8        | Bonding                      |
| 9-n      | Advertising (TLV)            |
TLV (Advertising Data)
0x09: Nome do dispositivo

0xFF: Dados do fabricante (ex: ID, HR)

0x03: UUIDs 16-bit

🔍 Exemplo de Saída
json
Copiar
Editar
{
  "mac": "C2:C4:0E:3A:BB:9D",
  "rssi": -52,
  "name": "mybeat",
  "manufacturerData": [0xD0, 0x07, 0x16, ...],
  "uuids": ["0x180D"]
}

para mais detalhes, leia a seguinte documentação : https://docs.google.com/document/d/1eJAz1166HeghQHyDFgqamgd8a4G8THP5/edit?usp=sharing&ouid=109016576676281329142&rtpof=true&sd=true

💡 Dicas
O MAC Address no BGAPI vem invertido: [6]..[1], por isso reversed.

RSSI vem como inteiro com sinal (int8): se >127, subtrair 256.

Verifique se o dongle está em modo de scan contínuo (gap_discover mode=2).

🛠️ Tecnologias
Flutter 3.7.1

Dart

BLED112 + BGAPI

Serial Communication (dart:io, dart:ffi, usb_serial, etc.)

