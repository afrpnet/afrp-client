// 校验 lib/core/sha256.dart：NIST 已知向量 + 分块流式一致性 + 可选文件哈希
// 用法：dart run tool/sha256_check.dart [文件路径]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:frp_oidc_app/core/sha256.dart';

var _failed = 0;

void _expect(String label, String got, String want) {
  if (got == want) {
    stdout.writeln('OK   $label');
  } else {
    _failed++;
    stdout.writeln('FAIL $label\n     got  $got\n     want $want');
  }
}

void main(List<String> args) async {
  const vectors = <String, String>{
    '': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq':
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno'
        'ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu':
        'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
  };

  vectors.forEach((msg, want) {
    final s = Sha256()..update(utf8.encode(msg));
    final label = msg.length > 24 ? 'sha256("${msg.substring(0, 24)}…")' : 'sha256("$msg")';
    _expect(label, s.hexDigest(), want);
  });

  // 1,000,000 个 'a'（分块喂入，覆盖 64 字节缓冲重填）
  final million = Sha256();
  final chunk = Uint8List(1000)..fillRange(0, 1000, 0x61);
  for (var i = 0; i < 1000; i++) {
    million.update(chunk);
  }
  _expect('sha256(1e6 x "a")', million.hexDigest(),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');

  // 边界长度：分块与一次性结果一致（验证尾部填充逻辑）
  for (final len in [55, 56, 57, 63, 64, 65, 119, 120, 128, 1000]) {
    final data = Uint8List(len);
    for (var i = 0; i < len; i++) {
      data[i] = (i * 31 + 7) & 0xff;
    }
    final oneShot = Sha256()..update(data);
    final chunked = Sha256();
    var off = 0;
    var step = 1;
    while (off < len) {
      final end = (off + step > len) ? len : off + step;
      chunked.update(Uint8List.sublistView(data, off, end));
      off = end;
      step = step % 7 + 1;
    }
    _expect('len=$len 分块==一次性', chunked.hexDigest(), oneShot.hexDigest());
  }

  // 大文件流式哈希（可选参数）：与 PHP hash_file('sha256') 交叉验证
  if (args.isNotEmpty) {
    final f = File(args.first);
    if (!f.existsSync()) {
      _failed++;
      stdout.writeln('FAIL 文件不存在：${args.first}');
    } else {
      stdout.writeln('FILE ${args.first}');
      stdout.writeln('     ${await sha256OfFile(args.first)}');
    }
  }

  stdout.writeln(_failed == 0 ? 'ALL OK' : 'SOME TESTS FAILED ($_failed)');
  exitCode = _failed == 0 ? 0 : 1;
}
