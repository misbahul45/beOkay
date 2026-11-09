import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Mengambil foto untuk dibaca. Diperkecil di perangkat (sisi terpanjang 1280 px, JPEG) sehingga
/// metadata asli (lokasi, dll.) tidak ikut terkirim dan ukuran jauh di bawah batas server (1,5 MB).
abstract class FoodImagePicker {
  Future<Uint8List?> capture({required bool camera});
}

class DeviceFoodImagePicker implements FoodImagePicker {
  final _picker = ImagePicker();
  @override
  Future<Uint8List?> capture({required bool camera}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}

final foodImagePickerProvider = Provider<FoodImagePicker>((_) => DeviceFoodImagePicker());
