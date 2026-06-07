import 'package:encrypt/encrypt.dart';

class QRCrypto {
  // Hardcoded key provided by the user (256-bit hex)
  static const String _hexKey = "e927ed3b37a823926a66b108d5815416dc9fc8ba554cfbe01f46ad58c2b379d6";
  
  // Fixed IV to keep QR code size small and consistent
  static const String _fixedIV = "funky_n_queens_v1"; // 16 bytes

  static final _key = Key.fromBase16(_hexKey);
  static final _iv = IV.fromUtf8(_fixedIV.substring(0, 16));
  static final _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  /// Encrypts plain JSON text into a Base64 encoded encrypted string
  static String encrypt(String plainText) {
    try {
      final encrypted = _encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      print("Encryption error: $e");
      return plainText; // Fallback to plain if something goes wrong
    }
  }

  /// Decrypts a Base64 encoded encrypted string back into plain JSON text
  static String decrypt(String encryptedText) {
    try {
      // Check if it's likely Base64 and encrypted
      // (Simple check to avoid crashing if it's actually plain text)
      if (!encryptedText.contains('{') && !encryptedText.contains('[')) {
        final decrypted = _encrypter.decrypt64(encryptedText, iv: _iv);
        return decrypted;
      }
      return encryptedText; // Probably already plain text
    } catch (e) {
      print("Decryption error: $e");
      return encryptedText; // Fallback
    }
  }
}
