import 'dart:convert';
import 'dart:io';

import 'package:nextcloud/nextcloud.dart';
import 'package:test/test.dart';

import 'config.dart';

void main() {
  final client = getClient();

  group('WebDav', () {
    test('Get status', () async {
      final status = await client.webDav.status();
      expect(status.capabilities, containsAll(['1', '3', 'access-control']));
      expect(status.searchCapabilities, contains('<DAV:basicsearch>'));
    });
    test('Create directory', () async {
      expect(
          (await client.webDav.mkdir(Config.testDir)).statusCode, equals(201));
    });
    test('List directory', () async {
      expect((await client.webDav.ls(Config.testDir)).length, equals(0));
    });
    test('Upload files', () async {
      expect(
          (await client.webDav.upload(
                  File('test/files/test.png').readAsBytesSync(),
                  '${Config.testDir}/test.png'))
              .statusCode,
          equals(201));
      expect(
          (await client.webDav.upload(
                  File('test/files/test.txt').readAsBytesSync(),
                  '${Config.testDir}/test.txt'))
              .statusCode,
          equals(201));
      final files = await client.webDav.ls(Config.testDir);
      expect(files.length, equals(2));
      expect(files.singleWhere((f) => f.name == 'test.png', orElse: () => null),
          isNotNull);
      expect(files.singleWhere((f) => f.name == 'test.txt', orElse: () => null),
          isNotNull);
    });
    test('List directory with properties', () async {
      final startTime = DateTime.now()
          // lastmodified is second-precision only
          .subtract(Duration(seconds: 2));
      final path = '${Config.testDir}/list-test.txt';
      final data = utf8.encode('WebDAV list-test');
      await client.webDav.upload(data, path);

      final files = await client.webDav.ls(Config.testDir);
      final file = files.singleWhere((f) => f.name == 'list-test.txt');
      expect(file.isDirectory, false);
      expect(file.name, 'list-test.txt');
      expect(startTime.isBefore(file.lastModified), isTrue,
          reason: 'Expected $startTime < ${file.lastModified}');
      expect(file.mimeType, 'text/plain');
      expect(file.path, path);
      expect(file.shareTypes, []);
      expect(file.size, data.length);
    });
    test('Copy file', () async {
      final response = await client.webDav.copy(
        '${Config.testDir}/test.txt',
        '${Config.testDir}/test2.txt',
      );
      expect(response.statusCode, 201);
      final files = await client.webDav.ls(Config.testDir);
      expect(files.where((f) => f.name == 'test.txt'), hasLength(1));
      expect(files.where((f) => f.name == 'test2.txt'), hasLength(1));
    });
    test('Copy file (no overwrite)', () async {
      final path = '${Config.testDir}/copy-test.txt';
      final data = utf8.encode('WebDAV copytest');
      await client.webDav.upload(data, path);

      expect(
          () => client.webDav.copy(
              '${Config.testDir}/test.txt', '${Config.testDir}/copy-test.txt',
              overwrite: false),
          throwsA(predicate((e) => e.statusCode == 412)));
    });
    test('Copy file (overwrite)', () async {
      final path = '${Config.testDir}/copy-test.txt';
      final data = utf8.encode('WebDAV copytest');
      await client.webDav.upload(data, path);

      final response = await client.webDav.copy(
          '${Config.testDir}/test.txt', '${Config.testDir}/copy-test.txt',
          overwrite: true);
      expect(response.statusCode, 204);
    });
    test('Move file', () async {
      final response = await client.webDav.move(
        '${Config.testDir}/test2.txt',
        '${Config.testDir}/test3.txt',
      );
      expect(response.statusCode, 201);
      final files = await client.webDav.ls(Config.testDir);
      expect(files.where((f) => f.name == 'test2.txt'), isEmpty);
      expect(files.where((f) => f.name == 'test3.txt'), hasLength(1));
    });
    test('Move file (no overwrite)', () async {
      final path = '${Config.testDir}/move-test.txt';
      final data = utf8.encode('WebDAV movetest');
      await client.webDav.upload(data, path);

      expect(
          () => client.webDav.move(
              '${Config.testDir}/test.txt', '${Config.testDir}/move-test.txt',
              overwrite: false),
          throwsA(predicate((e) => e.statusCode == 412)));
    });
    test('Move file (overwrite)', () async {
      final path = '${Config.testDir}/move-test.txt';
      final data = utf8.encode('WebDAV movetest');
      await client.webDav.upload(data, path);

      final response = await client.webDav.move(
          '${Config.testDir}/test.txt', '${Config.testDir}/move-test.txt',
          overwrite: true);
      expect(response.statusCode, 204);
    });
    test('Get file properties', () async {
      final startTime = DateTime.now().subtract(Duration(seconds: 2));
      final path = '${Config.testDir}/prop-test.txt';
      final data = utf8.encode('WebDAV proptest');
      await client.webDav.upload(data, path);

      final file = await client.webDav.getProps(path);
      expect(file.isDirectory, false);
      expect(file.name, 'prop-test.txt');
      expect(file.lastModified.isAfter(startTime), isTrue,
          reason: 'Expected lastModified: $startTime < ${file.lastModified}');
      expect(file.uploadedDate.isAfter(startTime), isTrue,
          reason: 'Expected uploadedDate: $startTime < ${file.uploadedDate}');
      expect(file.mimeType, 'text/plain');
      expect(file.path, path);
      expect(file.shareTypes, isEmpty);
      expect(file.size, data.length);
    });
    test('Get directory properties', () async {
      final path = Uri.parse(Config.testDir);
      final file = await client.webDav.getProps(path.toString());
      expect(file.isDirectory, true);
      expect(file.isCollection, true);
      expect(file.name, path.pathSegments.last);
      expect(file.lastModified, isNotNull);
      expect(file.mimeType, isNull);
      expect(file.path, '$path/');
      expect(file.shareTypes, isEmpty);
      expect(file.size, greaterThan(0));
    });
    test('Get additional properties', () async {
      final path = '${Config.testDir}/prop-test.txt';
      final file = await client.webDav.getProps(path);

      expect(file.getOtherProp('oc:comments-count', 'http://owncloud.org/ns'),
          '0');
      expect(file.getOtherProp('nc:has-preview', 'http://nextcloud.org/ns'),
          'true');
    });
    test('Filter files', () async {
      final path = '${Config.testDir}/filter-test.txt';
      final data = utf8.encode('WebDAV filtertest');
      final response = await client.webDav.upload(data, path);
      final id = response.headers['oc-fileid'];

      // Favorite file
      await client.webDav.updateProps(path, {WebDavProps.ocFavorite: '1'});

      // Find favorites
      final files = await client.webDav.filter(Config.testDir, {
        WebDavProps.ocFavorite: '1',
      }, props: {
        WebDavProps.ocId,
        WebDavProps.ocFileId,
        WebDavProps.ocFavorite,
      });
      final file = files.singleWhere((e) => e.name == 'filter-test.txt');
      expect(file.favorite, isTrue);
      expect(file.id, id);
    });
    test('Set properties', () async {
      final createdDate = DateTime.utc(1971, 2, 1);
      final createdEpoch = createdDate.millisecondsSinceEpoch / 1000;
      final path = '${Config.testDir}/prop-test.txt';
      final updated = await client.webDav.updateProps(path, {
        WebDavProps.ocFavorite: '1',
        WebDavProps.ncCreationTime: '$createdEpoch'
      });
      expect(updated, isTrue);

      final file = await client.webDav.getProps(path);
      expect(file.favorite, isTrue);
      expect(file.createdDate.isAtSameMomentAs(createdDate), isTrue,
          reason: 'Expected same time: $createdDate = ${file.createdDate}');
      expect(file.uploadedDate, isNotNull);
    });
    test('Set custom properties', () async {
      final customNamespaces = {
        'http://leonhardt.co.nz/ns': 'le',
        'http://test/ns': 'test'
      };
      final path = '${Config.testDir}/prop-test.txt';

      customNamespaces
          .forEach((ns, prefix) => client.webDav.registerNamespace(ns, prefix));

      final updated = await client.webDav.updateProps(path, {
        'le:custom': 'le-custom-prop-value',
        'le:custom2': 'le-custom-prop-value2',
        'test:custom': 'test-custom-prop-value',
      });
      expect(updated, isTrue);

      final file = await client.webDav.getProps(path, props: {
        'd:getlastmodified',
        'oc:fileid',
        'le:custom',
        'le:custom2',
        'test:custom',
      });
      expect(file.name, 'prop-test.txt');
      expect(file.getOtherProp('custom', customNamespaces.keys.first),
          'le-custom-prop-value');
      expect(file.getOtherProp('custom2', customNamespaces.keys.first),
          'le-custom-prop-value2');
      expect(file.getOtherProp('custom', customNamespaces.keys.elementAt(1)),
          'test-custom-prop-value');
    });
  });
}