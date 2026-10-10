import 'dart:io';
import 'dart:typed_data';

/// 流式 SHA-256（纯 Dart 实现，避免为校验引入 crypto 依赖）。
/// 用法：`final s = Sha256(); s.update(bytes); s.hexDigest();`
class Sha256 {
  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final Uint8List _block = Uint8List(64);
  final Uint32List _w = Uint32List(64);
  final Uint32List _h = Uint32List.fromList(<int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);
  int _blockLen = 0;
  int _totalBytes = 0;
  bool _finalized = false;
  Uint8List? _digest;

  void update(List<int> data) {
    if (_finalized) {
      throw StateError('Sha256 已完成，不能再 update');
    }
    _totalBytes += data.length;
    var offset = 0;
    if (_blockLen > 0) {
      final need = 64 - _blockLen;
      final take = need < data.length ? need : data.length;
      _block.setRange(_blockLen, _blockLen + take, data);
      _blockLen += take;
      offset = take;
      if (_blockLen == 64) {
        _compress(_block, 0);
        _blockLen = 0;
      }
    }
    while (offset + 64 <= data.length) {
      _compress(data, offset);
      offset += 64;
    }
    final rest = data.length - offset;
    if (rest > 0) {
      _block.setRange(0, rest, data, offset);
      _blockLen = rest;
    }
  }

  Uint8List digest() {
    final cached = _digest;
    if (cached != null) {
      return cached;
    }
    final bitLen = _totalBytes * 8;
    final padLen = _blockLen < 56 ? 56 - _blockLen : 120 - _blockLen;
    final tail = Uint8List(padLen + 8);
    tail[0] = 0x80;
    var v = bitLen;
    for (var i = padLen + 7; i >= padLen; i--) {
      tail[i] = v & 0xff;
      v >>= 8;
    }
    update(tail);
    _finalized = true;
    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      final h = _h[i];
      out[i * 4] = (h >> 24) & 0xff;
      out[i * 4 + 1] = (h >> 16) & 0xff;
      out[i * 4 + 2] = (h >> 8) & 0xff;
      out[i * 4 + 3] = h & 0xff;
    }
    _digest = out;
    return out;
  }

  String hexDigest() {
    final d = digest();
    final sb = StringBuffer();
    for (final b in d) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  void _compress(List<int> block, int offset) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      final j = offset + (i << 2);
      w[i] = (block[j] << 24) | (block[j + 1] << 16) | (block[j + 2] << 8) | block[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final x = w[i - 15];
      final y = w[i - 2];
      final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >> 3);
      final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e) & g);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    _h[0] = (_h[0] + a) & 0xffffffff;
    _h[1] = (_h[1] + b) & 0xffffffff;
    _h[2] = (_h[2] + c) & 0xffffffff;
    _h[3] = (_h[3] + d) & 0xffffffff;
    _h[4] = (_h[4] + e) & 0xffffffff;
    _h[5] = (_h[5] + f) & 0xffffffff;
    _h[6] = (_h[6] + g) & 0xffffffff;
    _h[7] = (_h[7] + h) & 0xffffffff;
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
}

/// 流式计算文件 SHA-256（十六进制小写）
Future<String> sha256OfFile(String path, {int chunkSize = 1 << 20}) async {
  final s = Sha256();
  await for (final chunk in File(path).openRead()) {
    s.update(chunk);
  }
  return s.hexDigest();
}
