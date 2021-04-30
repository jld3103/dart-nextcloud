import 'dart:io';

import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextcloud/src/network.dart';
import 'package:test/test.dart';

void main() {
  group('Network', () {
    final httpClientMock = MockClient(
      (request) async => http.Response('', HttpStatus.ok),
    );
    late Request httpRequest;
    const authString = 'authString';
    const userAgent = 'dart-nextcloud';

    setUp(() => httpRequest = Request('GET', Uri.https('test', '')));

    test('should add defaultHeaders to request', () async {
      final network = NextCloudHttpClient(
        null,
        null,
        authString,
        {
          HttpHeaders.userAgentHeader: userAgent,
        },
        httpClientMock,
      );

      await network.send(httpRequest);

      expect(httpRequest.headers[HttpHeaders.userAgentHeader], userAgent);
    });

    test('should not override library headers', () async {
      final network = NextCloudHttpClient(
        null,
        null,
        authString,
        {
          HttpHeaders.authorizationHeader: 'wrong',
        },
        httpClientMock,
      );

      expect(
        () async => network.send(httpRequest),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should ignore case-sensitivity of defaultHeader keys', () async {
      final authKey = HttpHeaders.userAgentHeader.toUpperCase();
      final network = NextCloudHttpClient(
        null,
        null,
        authString,
        {
          authKey: 'wrong',
        },
        httpClientMock,
      );

      httpRequest.headers[HttpHeaders.userAgentHeader] = userAgent;

      await network.send(httpRequest);

      //default implementation of map is not case sensitive
      //this test will catch if someone replaces map with a case sensitve map
      expect(httpRequest.headers[authKey], userAgent);
    });

    test('should set user agent header based on app type', () async {
      final network = NextCloudHttpClient(
        AppType.talk,
        null,
        authString,
        {},
        httpClientMock,
      );
      await network.send(httpRequest);

      expect(
        httpRequest.headers[HttpHeaders.userAgentHeader],
        AppType.talk.userAgent,
      );
    });

    test('should set user agent header based on app type over default header',
        () async {
      final network = NextCloudHttpClient(
        AppType.talk,
        null,
        authString,
        {
          HttpHeaders.userAgentHeader: 'test',
        },
        httpClientMock,
      );
      await network.send(httpRequest);

      expect(
        httpRequest.headers[HttpHeaders.userAgentHeader],
        AppType.talk.userAgent,
      );
    });

    test('should set accept language header based on language', () async {
      final network = NextCloudHttpClient(
        null,
        'de',
        authString,
        {},
        httpClientMock,
      );
      await network.send(httpRequest);

      expect(
        httpRequest.headers[HttpHeaders.acceptLanguage],
        'de',
      );
    });

    test('should not override accept language header if language is set',
        () async {
      final network = NextCloudHttpClient(
        null,
        'de',
        authString,
        {
          HttpHeaders.acceptLanguage: 'en',
        },
        httpClientMock,
      );

      expect(
        () async => network.send(httpRequest),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
