import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trusty/utils/deep_link.dart';

List<int> _tlv(int tag, List<int> value) {
  // Lengths here stay under 16384, so 1- or 2-byte varints are enough.
  List<int> varint(int v) =>
      v < 64 ? [v] : [0x40 | (v >> 8), v & 0xFF];
  return [...varint(tag), ...varint(value.length), ...value];
}

List<int> _s(String s) => utf8.encode(s);

String _link(List<int> payload) =>
    'tt://?${base64Url.encode(payload).replaceAll('=', '')}';

/// Minimal well-formed DER blob (SEQUENCE, long-form length).
final _fakeCert = Uint8List.fromList([0x30, 0x81, 0x03, 0x01, 0x02, 0x03]);

void main() {
  test('decodes a full link', () {
    final payload = [
      ..._tlv(0x00, [0x01]),
      ..._tlv(0x01, _s('vpn.example.com')),
      ..._tlv(0x05, _s('alice')),
      ..._tlv(0x06, _s('secret')),
      ..._tlv(0x02, _s('vpn.example.com:9443')),
      ..._tlv(0x02, _s('1.2.3.4:443')),
      ..._tlv(0x08, _fakeCert),
      ..._tlv(0x09, [0x02]),
      ..._tlv(0x0C, _s('NL 1')),
      ..._tlv(0x0D, [7, ..._s('1.1.1.1')]),
      ..._tlv(0x3F, [9, 9, 9]), // unknown tag: ignored
    ];
    final c = parseDeepLink(_link(payload));
    expect(c.version, 1);
    expect(c.hostname, 'vpn.example.com');
    expect(c.username, 'alice');
    expect(c.password, 'secret');
    expect(c.addresses, ['vpn.example.com:9443', '1.2.3.4:443']);
    expect(c.primaryAddress, ('vpn.example.com', 9443));
    expect(c.upstreamProtocol, 'http3');
    expect(c.name, 'NL 1');
    expect(c.dnsUpstreams, ['1.1.1.1']);
    expect(c.hasIpv6, isTrue);
    expect(c.certificate, startsWith('-----BEGIN CERTIFICATE-----\n'));
    expect(c.certificate, endsWith('-----END CERTIFICATE-----\n'));

    final cfg = c.toServerConfig(address: '5.6.7.8');
    expect(cfg.address, '5.6.7.8');
    expect(cfg.port, 9443);
    expect(cfg.certificate, c.certificate);
    final toml = cfg.toToml();
    expect(toml, contains('certificate = "-----BEGIN CERTIFICATE-----\\n'));
    expect(toml, contains('addresses = ["5.6.7.8:9443"]'));
  });

  test('accepts surrounding whitespace and padding-free base64', () {
    final payload = [
      ..._tlv(0x01, _s('h')),
      ..._tlv(0x02, _s('1.2.3.4')),
      ..._tlv(0x05, _s('u')),
      ..._tlv(0x06, _s('')),
    ];
    final c = parseDeepLink('  ${_link(payload)}\n');
    expect(c.primaryAddress, ('1.2.3.4', 443));
    expect(c.password, '');
  });

  test('rejects missing required fields', () {
    final payload = [..._tlv(0x01, _s('h'))];
    expect(() => parseDeepLink(_link(payload)),
        throwsA(isA<DeepLinkException>()));
  });

  test('rejects a newer format version', () {
    final payload = [..._tlv(0x00, [kMaxDeepLinkVersion + 1])];
    expect(() => parseDeepLink(_link(payload)),
        throwsA(isA<DeepLinkException>()));
  });

  test('rejects garbage', () {
    expect(() => parseDeepLink('https://example.com'),
        throwsA(isA<DeepLinkException>()));
    expect(() => parseDeepLink('tt://?'), throwsA(isA<DeepLinkException>()));
    expect(() => parseDeepLink('tt://?AQ'), throwsA(isA<DeepLinkException>()));
  });

  test('splitHostPort', () {
    expect(splitHostPort('[2001:db8::1]:8443'), ('2001:db8::1', 8443));
    expect(splitHostPort('2001:db8::1'), ('2001:db8::1', 443));
    expect(splitHostPort('host'), ('host', 443));
  });
}
