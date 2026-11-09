import 'dart:convert';
import 'dart:typed_data';

import '../models/server_config.dart';

/// Decoder for TrustTunnel `tt://?` deep links, as exported by
/// `trusttunnel_endpoint` (see DEEP_LINK.md in the TrustTunnel repository).
///
/// The payload is base64url (no padding) over a sequence of TLV entries whose
/// tag and length are QUIC/TLS varints (RFC 9000 §16).

/// Highest deep-link format version this decoder understands.
const int kMaxDeepLinkVersion = 2;

class DeepLinkException implements Exception {
  final String message;
  const DeepLinkException(this.message);
  @override
  String toString() => message;
}

/// Everything a deep link can carry, decoded but not yet mapped onto a
/// [ServerConfig] (the address may still be a host name that needs resolving).
class DeepLinkConfig {
  final int version;
  final String hostname;
  final List<String> addresses;
  final String customSni;
  final bool hasIpv6;
  final String username;
  final String password;
  final bool skipVerification;

  /// PEM chain, empty when the endpoint uses a publicly trusted certificate.
  final String certificate;
  final String upstreamProtocol;
  final bool antiDpi;
  final String clientRandomPrefix;
  final String name;
  final List<String> dnsUpstreams;
  final String subscriptionUrl;
  final String clientRandomAuthKey;

  const DeepLinkConfig({
    this.version = 0,
    this.hostname = '',
    this.addresses = const [],
    this.customSni = '',
    this.hasIpv6 = true,
    this.username = '',
    this.password = '',
    this.skipVerification = false,
    this.certificate = '',
    this.upstreamProtocol = 'http2',
    this.antiDpi = false,
    this.clientRandomPrefix = '',
    this.name = '',
    this.dnsUpstreams = const [],
    this.subscriptionUrl = '',
    this.clientRandomAuthKey = '',
  });

  /// First address split into host and port. The port defaults to 443.
  (String host, int port) get primaryAddress {
    if (addresses.isEmpty) return ('', 443);
    return splitHostPort(addresses.first);
  }

  /// Map onto a [ServerConfig] using [address] (an IP, already resolved from
  /// [primaryAddress] by the caller) in place of the link's own host.
  ServerConfig toServerConfig({required String address}) {
    final (_, port) = primaryAddress;
    return ServerConfig(
      name: name,
      hostname: hostname,
      address: address,
      port: port,
      hasIpv6: hasIpv6,
      username: username,
      password: password,
      skipVerification: skipVerification,
      certificate: certificate,
      upstreamProtocol: upstreamProtocol,
      antiDpi: antiDpi,
      customSni: customSni,
      clientRandomPrefix: clientRandomPrefix,
    );
  }
}

/// Split `host:port`, `[v6]:port` or a bare host. Port defaults to 443.
(String, int) splitHostPort(String s) {
  final v = s.trim();
  if (v.startsWith('[')) {
    final end = v.indexOf(']');
    if (end > 0) {
      final host = v.substring(1, end);
      final rest = v.substring(end + 1);
      final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
      return (host, port ?? 443);
    }
  }
  final colon = v.lastIndexOf(':');
  // More than one colon without brackets is a bare IPv6 address.
  if (colon > 0 && v.indexOf(':') == colon) {
    final port = int.tryParse(v.substring(colon + 1));
    if (port != null) return (v.substring(0, colon), port);
  }
  return (v, 443);
}

/// True if [text] looks like a deep link (leading/trailing whitespace allowed).
bool isDeepLink(String text) => text.trim().toLowerCase().startsWith('tt://');

/// Decode a `tt://?...` link. Throws [DeepLinkException] on anything malformed.
DeepLinkConfig parseDeepLink(String link) {
  var s = link.trim();
  if (!s.toLowerCase().startsWith('tt://')) {
    throw const DeepLinkException('Not a tt:// link');
  }
  s = s.substring(5);
  // draft 1 put the payload in the host part; current links use the query.
  if (s.startsWith('?')) s = s.substring(1);
  if (s.isEmpty) throw const DeepLinkException('The link has no payload');

  final Uint8List data;
  try {
    data = base64Url.decode(base64Url.normalize(s));
  } on FormatException {
    throw const DeepLinkException('The link is damaged (not valid base64url)');
  }

  var version = 0;
  var hostname = '';
  final addresses = <String>[];
  var customSni = '';
  var hasIpv6 = true;
  var username = '';
  String? password;
  var skipVerification = false;
  var certificate = '';
  var upstreamProtocol = 'http2';
  var antiDpi = false;
  var clientRandomPrefix = '';
  var name = '';
  var dnsUpstreams = <String>[];
  var subscriptionUrl = '';
  var clientRandomAuthKey = '';

  var offset = 0;
  while (offset < data.length) {
    final (tag, o1) = _readVarint(data, offset);
    final (length, o2) = _readVarint(data, o1);
    if (o2 + length > data.length) {
      throw const DeepLinkException('The link is truncated');
    }
    final value = Uint8List.sublistView(data, o2, o2 + length);
    offset = o2 + length;

    switch (tag) {
      case 0x00:
        version = _readVarint(value, 0).$1;
        if (version > kMaxDeepLinkVersion) {
          throw DeepLinkException(
            'Link format version $version is newer than this app supports '
            '($kMaxDeepLinkVersion)',
          );
        }
      case 0x01:
        hostname = _str(value);
      case 0x02:
        addresses.add(_str(value));
      case 0x03:
        customSni = _str(value);
      case 0x04:
        hasIpv6 = _bool(value);
      case 0x05:
        username = _str(value);
      case 0x06:
        password = _str(value);
      case 0x07:
        skipVerification = _bool(value);
      case 0x08:
        certificate = derToPem(value);
      case 0x09:
        final p = value.isEmpty ? 0 : value[0];
        upstreamProtocol = switch (p) {
          0x01 => 'http2',
          0x02 => 'http3',
          _ => throw DeepLinkException('Unknown upstream protocol 0x${p.toRadixString(16)}'),
        };
      case 0x0A:
        antiDpi = _bool(value);
      case 0x0B:
        clientRandomPrefix = _str(value);
      case 0x0C:
        name = _str(value);
      case 0x0D:
        dnsUpstreams = _strArray(value);
      case 0x0E:
        subscriptionUrl = _str(value);
      case 0x0F:
        clientRandomAuthKey = _str(value);
      default:
        // Unknown tags are ignored for forward compatibility.
        break;
    }
  }

  if (subscriptionUrl.isNotEmpty && !subscriptionUrl.startsWith('https://')) {
    throw const DeepLinkException('Subscription URL must start with https://');
  }
  if (subscriptionUrl.isEmpty) {
    final missing = [
      if (hostname.isEmpty) 'hostname',
      if (addresses.isEmpty) 'address',
      if (username.isEmpty) 'username',
      if (password == null) 'password',
    ];
    if (missing.isNotEmpty) {
      throw DeepLinkException('The link is missing: ${missing.join(', ')}');
    }
  }

  return DeepLinkConfig(
    version: version,
    hostname: hostname,
    addresses: addresses,
    customSni: customSni,
    hasIpv6: hasIpv6,
    username: username,
    password: password ?? '',
    skipVerification: skipVerification,
    certificate: certificate,
    upstreamProtocol: upstreamProtocol,
    antiDpi: antiDpi,
    clientRandomPrefix: clientRandomPrefix,
    name: name,
    dnsUpstreams: dnsUpstreams,
    subscriptionUrl: subscriptionUrl,
    clientRandomAuthKey: clientRandomAuthKey,
  );
}

(int, int) _readVarint(Uint8List data, int offset) {
  if (offset >= data.length) {
    throw const DeepLinkException('The link is truncated');
  }
  final size = 1 << (data[offset] >> 6);
  if (offset + size > data.length) {
    throw const DeepLinkException('The link is truncated');
  }
  var value = data[offset] & 0x3F;
  for (var i = 1; i < size; i++) {
    value = (value << 8) | data[offset + i];
  }
  return (value, offset + size);
}

String _str(Uint8List v) {
  try {
    return utf8.decode(v);
  } on FormatException {
    throw const DeepLinkException('The link contains invalid text');
  }
}

bool _bool(Uint8List v) => v.isNotEmpty && v[0] != 0;

List<String> _strArray(Uint8List v) {
  final out = <String>[];
  var offset = 0;
  while (offset < v.length) {
    final (len, o) = _readVarint(v, offset);
    if (o + len > v.length) {
      throw const DeepLinkException('The link is truncated');
    }
    out.add(_str(Uint8List.sublistView(v, o, o + len)));
    offset = o + len;
  }
  return out;
}

/// Concatenated DER certificates → PEM chain.
String derToPem(Uint8List der) {
  final blocks = <String>[];
  var offset = 0;
  while (offset < der.length) {
    if (der[offset] != 0x30) {
      throw const DeepLinkException('The certificate in the link is damaged');
    }
    var p = offset + 1;
    if (p >= der.length) {
      throw const DeepLinkException('The certificate in the link is damaged');
    }
    var bodyLen = der[p];
    p++;
    if (bodyLen >= 0x80) {
      final n = bodyLen & 0x7F;
      if (n == 0 || n > 4 || p + n > der.length) {
        throw const DeepLinkException('The certificate in the link is damaged');
      }
      bodyLen = 0;
      for (var i = 0; i < n; i++) {
        bodyLen = (bodyLen << 8) | der[p + i];
      }
      p += n;
    }
    final end = p + bodyLen;
    if (end > der.length) {
      throw const DeepLinkException('The certificate in the link is damaged');
    }
    final b64 = base64.encode(Uint8List.sublistView(der, offset, end));
    final lines = [
      for (var i = 0; i < b64.length; i += 64)
        b64.substring(i, i + 64 > b64.length ? b64.length : i + 64),
    ];
    blocks.add(
      '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----',
    );
    offset = end;
  }
  return blocks.isEmpty ? '' : '${blocks.join('\n')}\n';
}
