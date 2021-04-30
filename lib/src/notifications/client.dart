import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crypton/crypton.dart';

import '../network.dart';
import 'notification.dart';

// ignore: public_member_api_docs
class NotificationsClient {
  // ignore: public_member_api_docs
  NotificationsClient(
    String baseUrl,
    this._network,
  ) : _baseUrl = '$baseUrl/ocs/v2.php/apps/notifications/api/v2';

  final String _baseUrl;

  final Network _network;

  /// Register a device at a Nextcloud Server
  ///
  /// The [pushToken] of a device (obtained from FCM or APNS) to receive notifications
  ///
  /// A RSA 2048 keypair needs to be generated once and the public key of the [keypair] needs
  /// to be send to the server
  Future<ServerSubscription> registerDeviceAtServer(
    String pushToken,
    RSAKeypair keypair, {
    String proxyServerUrl = 'https://push-notifications.nextcloud.com',
    bool skipPushProxyRegistration = false,
  }) async {
    final url = '$_baseUrl/push';
    final response = await _network.send(
      'POST',
      url,
      [200, 201],
      data: Uint8List.fromList(
        utf8.encode(
          json.encode({
            'pushTokenHash': sha512.convert(utf8.encode(pushToken)).toString(),
            'devicePublicKey': keypair.publicKey.toFormattedPEM(),
            'proxyServer': proxyServerUrl,
          }),
        ),
      ),
    );
    final data = json.decode(response.body)['ocs']['data'];

    final serverSubscription = ServerSubscription(
      data['publicKey'] as String,
      data['deviceIdentifier'] as String,
      data['signature'] as String,
    );
    if (!skipPushProxyRegistration && response.statusCode == 201) {
      await registerDeviceAtPushProxy(
        pushToken,
        serverSubscription,
        keypair,
        proxyServerUrl: proxyServerUrl,
      );
    }
    return serverSubscription;
  }

  /// Register a device at the push proxy
  ///
  /// Can be called individually, but it's better using the
  /// [registerDeviceAtServer] method which also automatically registers
  /// the device at the push proxy
  Future registerDeviceAtPushProxy(
    String pushToken,
    ServerSubscription serverSubscription,
    RSAKeypair keypair, {
    String proxyServerUrl = 'https://push-notifications.nextcloud.com',
  }) async {
    final url = '$proxyServerUrl/devices';
    await _network.send(
      'POST',
      url,
      [200],
      data: Uint8List.fromList(
        utf8.encode(
          _encodeMap({
            'pushToken': pushToken,
            'deviceIdentifier': serverSubscription.deviceIdentifier,
            'deviceIdentifierSignature': serverSubscription.signature,
            'userPublicKey': serverSubscription.publicKey,
          }),
        ),
      ),
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
      },
    );
  }

  /// Get all notifications
  Future<List<Notification>> getAllNotifications() async {
    final url = '$_baseUrl/notifications';
    final response = await _network.send(
      'GET',
      url,
      [200],
    );
    final data = json.decode(response.body)['ocs']['data'] as List;
    return data
        .map<Notification>(
          (n) => Notification.fromJson(n as Map<String, dynamic>),
        )
        .toList();
  }

  /// Get a notification by the given [id]
  Future<Notification> getNotification(int id) async {
    final url = '$_baseUrl/notifications/$id';
    final response = await _network.send(
      'GET',
      url,
      [200],
    );
    final data = json.decode(response.body)['ocs']['data'];
    return Notification.fromJson(data as Map<String, dynamic>);
  }

  /// Delete a notification by the given [id]
  Future deleteNotification(int id) async {
    final url = '$_baseUrl/notifications/$id';
    await _network.send(
      'DELETE',
      url,
      [200],
    );
  }
}

String _encodeMap(Map data) => data.keys
    .map(
      (key) =>
          '${Uri.encodeComponent(key as String)}=${Uri.encodeComponent(data[key] as String)}',
    )
    .join('&');

// ignore: public_member_api_docs
class ServerSubscription {
  // ignore: public_member_api_docs
  ServerSubscription(this.publicKey, this.deviceIdentifier, this.signature);

  // ignore: public_member_api_docs
  final String publicKey;

  // ignore: public_member_api_docs
  final String deviceIdentifier;

  // ignore: public_member_api_docs
  final String signature;
}
