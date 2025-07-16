import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

enum ErrorType {
  gateway,
  repository,
}

abstract class BaseError extends Error with EquatableMixin {
  BaseError({required this.message, required this.type});

  final String message;
  final ErrorType type;

  @override
  String toString() => message;

  @override
  List<Object?> get props => [message, type];
}

abstract class Serializer<T extends Object, U> {
  T from(U json);
  U to(T object);
}

class SerializationError extends BaseError {
  SerializationError([String? message])
      : super(
          message: message ?? "Serialization Error",
          type: ErrorType.gateway,
        );
}

class DiscoveredDevice {
  /// The unique identifier of the device.
  final String id;
  final String name;
  final Map<String, Uint8List> serviceData;

  /// Advertised services
  final List<String> serviceUuids;

  final Uint8List manufacturerData;

  final int rssi;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.serviceData,
    required this.manufacturerData,
    required this.rssi,
    required this.serviceUuids,
  });

  @override
  String toString() {
    return 'DiscoveredDevice(id: $id, name: $name, serviceData: $serviceData, manufacturerData: $manufacturerData, rssi: $rssi, serviceUuids: $serviceUuids)';
  }
}

class MyBeatDeviceBroadcast extends Equatable {
  const MyBeatDeviceBroadcast({
    required this.id,
    required this.heartRate,
    required this.roomNumber,
  });

  final int id;
  final int heartRate;
  final int roomNumber;

  @override
  List<Object?> get props => [id, heartRate];
}

const mbInitialBroadcast =
    MyBeatDeviceBroadcast(id: 0, heartRate: 0, roomNumber: 0);

class MyBeatDeviceBroadcastsSerializer
    implements Serializer<MyBeatDeviceBroadcast, DiscoveredDevice> {
  @override
  MyBeatDeviceBroadcast from(DiscoveredDevice raw) {
    try {
      final id = raw.manufacturerData[2];
      final heardHate = raw.manufacturerData[5];
      final roomNumber = raw.manufacturerData[3] ~/ 16;
      final myBeat = MyBeatDeviceBroadcast(
          id: id, heartRate: heardHate, roomNumber: roomNumber);
      return myBeat;
    } catch (e) {
      throw SerializationError();
    }
  }

  @override
  DiscoveredDevice to(MyBeatDeviceBroadcast model) {
    throw UnimplementedError();
  }
}

final myBeatDeviceBroadcastsSerializer = MyBeatDeviceBroadcastsSerializer();
