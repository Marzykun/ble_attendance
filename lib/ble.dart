import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'protocol.dart';

/// Asks for the advertise/connect (and, on Android 11 and older, location)
/// permissions. flutter_blue_plus asks for the scan permission itself.
Future<bool> requestBlePermissions() async {
  const refused = [
    PeripheralBluetoothState.denied,
    PeripheralBluetoothState.permanentlyDenied,
    PeripheralBluetoothState.restricted,
  ];
  if (refused.contains(await _peripheral.requestPermission())) return false;
  if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
    await FlutterBluePlus.turnOn();
  }
  return true;
}

/// Scans for our app's advertisements and reports each payload with its RSSI.
Stream<({List<int> data, int rssi})> scanPayloads() async* {
  await FlutterBluePlus.startScan(
    withMsd: [MsdFilter(kManufacturerId)],
    continuousUpdates: true,
  );
  await for (final results in FlutterBluePlus.onScanResults) {
    for (final r in results) {
      final data = r.advertisementData.manufacturerData[kManufacturerId];
      if (data != null) yield (data: data, rssi: r.rssi);
    }
  }
}

Future<void> stopScan() => FlutterBluePlus.stopScan();

final _peripheral = FlutterBlePeripheral();

Future<void> startAdvertising(Uint8List payload) => _peripheral.start(
      advertiseData: AdvertiseDataCore(
        manufacturerId: kManufacturerId,
        manufacturerData: payload,
      ),
    );

Future<void> stopAdvertising() => _peripheral.stop();
