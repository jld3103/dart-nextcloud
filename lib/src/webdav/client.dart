import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../nextcloud.dart';
import '../network.dart';

/// WebDavClient class
class WebDavClient {
  // ignore: public_member_api_docs
  WebDavClient(
    this._baseUrl,
    this._network,
  ) : _davUrl = '$_baseUrl/remote.php/dav';

  final String _baseUrl;
  late final String _davUrl;

  final Network _network;

  String? _username;

  bool _useBackwardsCompatiblePaths = false;

  /// XML namespaces supported by this client.
  ///
  /// For Nextcloud namespaces see [WebDav/Requesting properties](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/WebDAV/basic.html#requesting-properties).
  final Map<String, String> namespaces = {
    'DAV:': 'd',
    'http://owncloud.org/ns': 'oc',
    'http://nextcloud.org/ns': 'nc',
    'http://open-collaboration-services.org/ns': 'ocs',
    'http://open-cloud-mesh.org/ns': 'ocm',
    'http://sabredav.org/ns': 's', // mostly used in error responses
  };

  /// get url from given [path]
  Future<String> _getUrl(String path) async {
    path = path.trim();
    path = await _addFilesPath(path);
    return '$_davUrl/$path';
  }

  Future<String> _addFilesPath(String path) async {
    if (path.startsWith('/files/')) {
      _useBackwardsCompatiblePaths = true;
      return path;
    }
    if (path.startsWith('/')) {
      path = path.substring(1, path.length);
    }
    _username =
        _username ?? (await UserClient(_baseUrl, _network).getUser()).id;
    return '/files/$_username/$path';
  }

  Future<String> _removeFilesPath(String path) async {
    if (_useBackwardsCompatiblePaths) {
      return path;
    }
    _username =
        _username ?? (await UserClient(_baseUrl, _network).getUser()).id;
    return path.replaceFirst('/files/$_username/', '');
  }

  Future<http.Response> _send(
    String method,
    String url,
    List<int> expectedCodes, {
    Uint8List? data,
    Map<String, String>? headers,
  }) {
    headers = headers ?? {};
    headers[HttpHeaders.contentTypeHeader] = ContentType.xml.value;
    return _network.send(
      method,
      url,
      expectedCodes,
      data: data,
      headers: headers,
    );
  }

  /// Registers a custom namespace for properties.
  ///
  /// Requires a unique [namespaceUri] and [prefix].
  void registerNamespace(String namespaceUri, String prefix) =>
      namespaces.putIfAbsent(namespaceUri, () => prefix);

  /// returns the WebDAV capabilities of the server
  Future<WebDavStatus> status() async {
    final response = await _send('OPTIONS', _davUrl, [200]);
    final davCapabilities = response.headers['dav'] ?? '';
    final davSearchCapabilities = response.headers['dasl'] ?? '';
    return WebDavStatus(
      davCapabilities.split(',').map((e) => e.trim()).toSet(),
      davSearchCapabilities.split(',').map((e) => e.trim()).toSet(),
    );
  }

  /// make a dir with [path] under current dir
  Future<http.Response> mkdir(String path, [bool safe = true]) async {
    final expectedCodes = [
      201,
      if (safe) ...[
        301,
        405,
      ],
    ];
    return _send(
      'MKCOL',
      await _getUrl(path),
      expectedCodes,
    );
  }

  /// just like mkdir -p
  Future mkdirs(String path) async {
    path = path.trim();
    final dirs = path.split('/')..removeWhere((value) => value == '');
    if (dirs.isEmpty) {
      return;
    }
    if (path.startsWith('/')) {
      dirs[0] = '/${dirs[0]}';
    }
    for (final dir in dirs) {
      await mkdir(dir);
    }
  }

  /// remove dir with given [path]
  Future delete(String path) async => _send(
        'DELETE',
        await _getUrl(path),
        [204],
      );

  /// upload a new file with [localData] as content to [remotePath]
  Future upload(Uint8List localData, String remotePath) async => _send(
        'PUT',
        await _getUrl(remotePath),
        [200, 201, 204],
        data: localData,
      );

  /// download [remotePath] and store the response file contents to String
  Future<Uint8List> download(String remotePath) async => (await _send(
        'GET',
        await _getUrl(remotePath),
        [200],
      ))
          .bodyBytes;

  /// download [remotePath] and store the response file contents to ByteStream
  Future<http.ByteStream> downloadStream(String remotePath) async =>
      (await _network.download(
        'GET',
        await _getUrl(remotePath),
        [200],
      ))
          .stream;

  /// download [remotePath] and returns the received bytes
  Future<Uint8List> downloadDirectoryAsZip(String remotePath) async {
    final url =
        '$_baseUrl/index.php/apps/files/ajax/download.php?dir=$remotePath';
    final result = await _send(
      'GET',
      url,
      [200],
    );
    return result.bodyBytes;
  }

  /// download [remotePath] and returns a stream with the received bytes
  Future<http.ByteStream> downloadStreamDirectoryAsZip(
    String remotePath,
  ) async {
    final url =
        '$_baseUrl/index.php/apps/files/ajax/download.php?dir=$remotePath';
    return (await _network.download(
      'GET',
      url,
      [200],
    ))
        .stream;
  }

  /// list the directories and files under given [remotePath].
  ///
  /// Optionally populates the given [props] on the returned files.
  Future<List<WebDavFile>> ls(
    String remotePath, {
    Set<String> props = const {
      WebDavProps.davContentLength,
      WebDavProps.davContentType,
      WebDavProps.davLastModified,
      WebDavProps.ocId,
      WebDavProps.ocShareTypes,
    },
  }) async {
    final builder = XmlBuilder();
    builder
      ..processing('xml', 'version="1.0"')
      ..element(
        'd:propfind',
        nest: () {
          namespaces.forEach(builder.namespace);
          builder.element(
            'd:prop',
            nest: () {
              props.forEach(builder.element);
            },
          );
        },
      );
    final data = utf8.encode(builder.buildDocument().toString());
    final response = await _send(
      'PROPFIND',
      await _getUrl(remotePath),
      [207, 301],
      data: Uint8List.fromList(data),
    );
    if (response.statusCode == 301) {
      return ls(response.headers['location']!);
    }
    final decodedBody = utf8.decode(response.bodyBytes);
    final files = treeFromWebDavXml(decodedBody)..removeAt(0);
    for (final file in files) {
      file.path = await _removeFilesPath(file.path);
    }
    return files;
  }

  /// Runs the filter-files report with the given [propFilters] on the
  /// [remotePath].
  ///
  /// Optionally populates the given [props] on the returned files.
  Future<List<WebDavFile>> filter(
    String remotePath,
    Map<String, String> propFilters, {
    Set<String> props = const {},
  }) async {
    final builder = XmlBuilder();
    builder
      ..processing('xml', 'version="1.0"')
      ..element(
        'oc:filter-files',
        nest: () {
          namespaces.forEach(builder.namespace);
          builder
            ..element(
              'oc:filter-rules',
              nest: () {
                propFilters.forEach((key, value) {
                  builder.element(
                    key,
                    nest: () {
                      builder.text(value);
                    },
                  );
                });
              },
            )
            ..element(
              'd:prop',
              nest: () {
                props.forEach(builder.element);
              },
            );
        },
      );
    final data = utf8.encode(builder.buildDocument().toString());
    final response = await _send(
      'REPORT',
      await _getUrl(remotePath),
      [200, 207],
      data: Uint8List.fromList(data),
    );
    final files = treeFromWebDavXml(response.body);
    for (final file in files) {
      file.path = await _removeFilesPath(file.path);
    }
    return files;
  }

  /// Retrieves properties for the given [remotePath].
  ///
  /// Populates all available properties by default, but a reduced set can be
  /// specified via [props].
  Future<WebDavFile> getProps(
    String remotePath, {
    Set<String> props = WebDavProps.all,
  }) async {
    final builder = XmlBuilder();
    builder
      ..processing('xml', 'version="1.0"')
      ..element(
        'd:propfind',
        nest: () {
          namespaces.forEach(builder.namespace);
          builder.element(
            'd:prop',
            nest: () {
              props.forEach(builder.element);
            },
          );
        },
      );
    final data = utf8.encode(builder.buildDocument().toString());
    final response = await _send(
      'PROPFIND',
      await _getUrl(remotePath),
      [200, 207],
      data: Uint8List.fromList(data),
      headers: {'Depth': '0'},
    );
    final file = fileFromWebDavXml(response.body);
    return file..path = await _removeFilesPath(file.path);
  }

  /// Update (string) properties of the given [remotePath].
  ///
  /// Returns true if the update was successful.
  Future<bool> updateProps(String remotePath, Map<String, String> props) async {
    final builder = XmlBuilder();
    builder
      ..processing('xml', 'version="1.0"')
      ..element(
        'd:propertyupdate',
        nest: () {
          namespaces.forEach(builder.namespace);
          builder.element(
            'd:set',
            nest: () {
              builder.element(
                'd:prop',
                nest: () {
                  props.forEach((key, value) {
                    builder.element(
                      key,
                      nest: () {
                        builder.text(value);
                      },
                    );
                  });
                },
              );
            },
          );
        },
      );
    final data = utf8.encode(builder.buildDocument().toString());
    final response = await _send(
      'PROPPATCH',
      await _getUrl(remotePath),
      [200, 207],
      data: Uint8List.fromList(data),
    );
    return checkUpdateFromWebDavXml(response.body);
  }

  /// Move a file from [sourcePath] to [destinationPath]
  ///
  /// Throws a [RequestException] if the move operation failed.
  Future<http.Response> move(
    String sourcePath,
    String destinationPath, {
    bool overwrite = false,
  }) async =>
      _send(
        'MOVE',
        await _getUrl(sourcePath),
        [200, 201, 204],
        headers: {
          'Destination': await _getUrl(destinationPath),
          'Overwrite': overwrite ? 'T' : 'F',
        },
      );

  /// Copy a file from [sourcePath] to [destinationPath]
  ///
  /// Throws a [RequestException] if the copy operation failed.
  Future<http.Response> copy(
    String sourcePath,
    String destinationPath, {
    bool overwrite = false,
  }) async =>
      _send(
        'COPY',
        await _getUrl(sourcePath),
        [200, 201, 204],
        headers: {
          'Destination': await _getUrl(destinationPath),
          'Overwrite': overwrite ? 'T' : 'F',
        },
      );
}

/// WebDAV server status.
class WebDavStatus {
  /// Creates a new WebDavStatus.
  WebDavStatus(
    this.capabilities,
    this.searchCapabilities,
  );

  /// DAV capabilities as advertised by the server in the 'dav' header.
  Set<String> capabilities;

  /// DAV search and locating capabilities as advertised by the server in the
  /// 'dasl' header.
  Set<String> searchCapabilities;
}

/// Mapping of all WebDAV properties.
class WebDavProps {
  /// All WebDAV props supported by Nextcloud, in prefix form
  static const all = {
    davContentLength,
    davContentType,
    davETag,
    davLastModified,
    davResourceType,
    ncCreationTime,
    ncDataFingerprint,
    ncHasPreview,
    ncIsEncrypted,
    ncMetadataETag,
    ncMountType,
    ncNote,
    ncRichWorkspace,
    ncShareees,
    ncUploadTime,
    ocChecksums,
    ocCircle,
    ocCommentsCount,
    ocCommentsHref,
    ocCommentsUnread,
    ocDownloadURL,
    ocFavorite,
    ocFileId,
    ocId,
    ocOwnerDisplayName,
    ocOwnerId,
    ocPermissions,
    ocShareTypes,
    ocSize,
    ocSystemTag,
    ocTags,
  };

  /// Contains the Last-Modified header value  .
  static const davLastModified = 'd:getlastmodified';

  /// Contains the ETag header value.
  static const davETag = 'd:getetag';

  /// Contains the Content-Type header value.
  static const davContentType = 'd:getcontenttype';

  /// Specifies the nature of the resource.
  static const davResourceType = 'd:resourcetype';

  /// Contains the Content-Length header.
  static const davContentLength = 'd:getcontentlength';

  /// The fileid namespaced by the instance id, globally unique
  static const ocId = 'oc:id';

  /// The unique id for the file within the instance
  static const ocFileId = 'oc:fileId';

  /// List of user specified tags. Can be modified.
  static const ocTags = 'oc:tags';

  /// Whether a resource is tagged as favorite.
  /// Can be modified and reported on with list-files.
  static const ocFavorite = 'oc:favorite';

  /// List of collaborative tags. Can be reported on with list-files.
  ///
  /// Valid system tags are:
  /// - oc:id
  /// - oc:display-name
  /// - oc:user-visible
  /// - oc:user-assignable
  /// - oc:groups
  /// - oc:can-assign
  static const ocSystemTag = 'oc:systemtag';

  /// Can be reported on with list-files.
  static const ocCircle = 'oc:circle';

  /// Link to the comments for this resource.
  static const ocCommentsHref = 'oc:comments-href';

  /// Number of comments.
  static const ocCommentsCount = 'oc:comments-count';

  /// Number of unread comments.
  static const ocCommentsUnread = 'oc:comments-unread';

  /// Download URL.
  static const ocDownloadURL = 'oc:downloadURL';

  /// The user id of the owner of a shared file
  static const ocOwnerId = 'oc:owner-id';

  /// The display name of the owner of a shared file
  static const ocOwnerDisplayName = 'oc:owner-display-name';

  /// Share types of this file.
  ///
  /// Returns a list of share-type objects where:
  /// - 0: user share
  /// - 1: group share
  /// - 2: usergroup share
  /// - 3: public link
  /// - 4: email
  /// - 5: contact
  /// - 6: remote (federated cloud)
  /// - 7: circle
  /// - 8: guest
  /// - 9: remote group
  /// - 10: room (talk conversation)
  /// - 11: userroom
  /// See also [OCS Share API](https://docs.nextcloud.com/server/19/developer_manual/client_apis/OCS/ocs-share-api.html)
  static const ocShareTypes = 'oc:share-types';

  /// List of users this file is shared with.
  ///
  /// Returns a list of sharee objects with:
  /// - id
  /// - display-name
  /// - type (share type)
  static const ncShareees = 'nc:sharees';

  /// Share note.
  static const ncNote = 'nc:note';

  /// Checksums as provided during upload.
  ///
  /// Returns a list of checksum objects.
  static const ocChecksums = 'oc:checksums';

  /// Unlike [[davContentLength]], this property also works for folders
  /// reporting the size of everything in the folder.
  static const ocSize = 'oc:size';

  /// WebDAV permissions:
  ///
  /// - S: shared
  /// - R: shareable
  /// - M: mounted
  /// - G: readable
  /// - D: deletable
  /// - NV: updateable, renameable, moveble
  /// - W: updateable (file)
  /// - CK: creatable
  static const ocPermissions = 'oc:permissions';

  /// Nextcloud CRUDS permissions:
  ///
  /// - 1: read
  /// - 2: update
  /// - 4: create
  /// - 8: delete
  /// - 16: share
  /// - 31: all
  static const ocsSharePermissions = 'ocs:share-permissions';

  /// OCM permissions:
  ///
  /// - share
  /// - read
  /// - write
  static const ocmSharePermissions = 'ocm:share-permissions';

  /// system data-fingerprint
  static const ncDataFingerprint = 'nc:data-fingerprint';

  /// Whether a preview is available.
  static const ncHasPreview = 'nc:has-preview';

  /// Mount type, e.g. global, group, user, personal, shared, shared-root, external
  static const ncMountType = 'nc:mount-type';

  /// Is this file is encrypted, 0 for false or 1 for true.
  static const ncIsEncrypted = 'nc:is-encrypted';

  // ignore: public_member_api_docs
  static const ncMetadataETag = 'nc:metadata_etag';

  /// Date this file was uploaded.
  static const ncUploadTime = 'nc:upload_time';

  /// Creation time of the file as provided during upload.
  static const ncCreationTime = 'nc:creation_time';

  // ignore: public_member_api_docs
  static const ncRichWorkspace = 'nc:rich-workspace';
}
