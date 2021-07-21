import 'package:intl/intl.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:xml/xml.dart' as xml;

/// WebDavFile class
class WebDavFile {
  /// Creates a new WebDavFile object with the given path
  WebDavFile(String path){
    this.path = Uri.decodeFull(path);
  }

  /// The path of file
  late String path;

  /// The fileid namespaced by the instance id, globally unique
  late String id;

  /// The unique id for the file within the instance
  late String fileId;

  /// Whether this is a collection resource type
  late bool isCollection = false;

  // ignore: public_member_api_docs
  String? mimeType;

  /// File content length or folder size
  late int size;

  /// The user id of the owner of a shared file
  late String ownerId;

  /// The display name of the owner of a shared file
  late String ownerDisplay;

  /// Share note
  late String note;

  // ignore: public_member_api_docs
  late DateTime lastModified;

  /// Upload date of the file.
  late DateTime uploadedDate;

  /// Creation date of the file as provided by uploader.
  late DateTime createdDate;

  // ignore: public_member_api_docs
  late List<int> shareTypes = [];

  /// User IDs of sharees.
  late List<String> sharees = [];

  /// Whether this file is marked as favorite.
  late bool favorite = false;

  /// Other properties, mapped by their prefixed name name
  final Map<String, String> _otherProps = {};

  /// Additional namespace-prefix mappings for custom properties
  final Map<String, String> _otherNamespaces = {};

  /// Add an additional property by [name] and [value]
  void addOtherProp(xml.XmlName name, String value) {
    _otherNamespaces[name.namespaceUri!] = name.prefix!;
    _otherProps[name.qualified] = value;
  }

  /// Lookup an additional property by [name] and [namespaceUri]
  String? getOtherProp(String name, String namespaceUri) {
    final localName = xml.XmlName.fromString(name).local;
    // find correct prefix
    final prefix = _otherNamespaces[namespaceUri];
    return _otherProps['$prefix:$localName'];
  }

  /// Returns the decoded name of the file / folder without the whole path
  String get name {
    final _path = path.substring(0, path.length - (path.endsWith('/') ? 1 : 0));
    return Uri(path: _path).pathSegments.last;
  }

  /// Returns if the file is a directory
  bool get isDirectory => path.endsWith('/') || isCollection;

  @override
  String toString() =>
      // ignore: lines_longer_than_80_chars
      'WebDavFile{name: $name, id: $id, isDirectory: $isDirectory, path: $path, mimeType: $mimeType, size: $size, modificationTime: $lastModified, shareTypes: $shareTypes}';
}

void _handleProp(xml.XmlElement prop, WebDavFile file) {
  if (prop.children.isEmpty && prop.text.isEmpty) {
    // Ignore empty properties
    return;
  }

  switch (prop.name.qualified) {
    case WebDavProps.davContentType:
      file.mimeType = prop.text;
      break;
    case WebDavProps.davContentLength:
      file.size = int.parse(prop.text);
      break;
    case WebDavProps.davLastModified:
      file.lastModified =
          DateFormat('E, d MMM yyyy HH:mm:ss', 'en_US').parseUtc(prop.text);
      break;
    case WebDavProps.davResourceType:
      file.isCollection = prop.getElement('d:collection') != null;
      break;
    case WebDavProps.ocId:
      file.id = prop.text;
      break;
    case WebDavProps.ocFileId:
      file.fileId = prop.text;
      break;
    case WebDavProps.ocFavorite:
      file.favorite = prop.text == '1';
      break;
    case WebDavProps.ocOwnerId:
      file.ownerId = prop.text;
      break;
    case WebDavProps.ocOwnerDisplayName:
      file.ownerDisplay = prop.text;
      break;
    case WebDavProps.ocShareTypes:
      file.shareTypes = prop
          .findElements('oc:share-type')
          .map((element) => int.parse(element.text))
          .toList();
      break;
    case WebDavProps.ncShareees:
      file.sharees = prop.findAllElements('nc:id').map((e) => e.text).toList();
      break;
    case WebDavProps.ncNote:
      file.note = prop.text;
      break;
    case WebDavProps.ocSize:
      file.size = int.parse(prop.text);
      break;
    case WebDavProps.ncCreationTime:
      file.createdDate =
          DateTime.fromMillisecondsSinceEpoch(int.parse(prop.text) * 1000);
      break;
    case WebDavProps.ncUploadTime:
      file.uploadedDate =
          DateTime.fromMillisecondsSinceEpoch(int.parse(prop.text) * 1000);
      break;
    default:
      // store with fully qualified name
      file.addOtherProp(prop.name, prop.text);
  }
}

/// Converts a single d:response to a [WebDavFile]
WebDavFile _fromWebDavXml(xml.XmlElement response) {
  final davItemName = response.findElements('d:href').single.text;
  //this makes sure that path parts that belong to the server location are filtered out
  final pathMath = RegExp(
    r'^.*remote.php/(?:web)?dav(.+)$',
  ).firstMatch(davItemName);
  //group(0) is always the whole string
  //group(1) is the group we need
  final file = WebDavFile(pathMath!.group(1)!);

  final propStatElements = response.findElements('d:propstat');
  for (final propStat in propStatElements) {
    final status = propStat.getElement('d:status')!.text;
    final props = propStat.getElement('d:prop');

    if (!status.contains('200')) {
      // Skip any props that are not returned correctly (e.g. not found)
      continue;
    }
    for (final prop in props!.nodes.whereType<xml.XmlElement>()) {
      _handleProp(prop, file);
    }
  }

  return file;
}

/// Extract a file from the webav xml
WebDavFile fileFromWebDavXml(String xmlStr) {
  final xmlDocument = xml.XmlDocument.parse(xmlStr);
  return _fromWebDavXml(xmlDocument.findAllElements('d:response').single);
}

/// Extract the file tree from the webdav xml
List<WebDavFile> treeFromWebDavXml(String xmlStr) {
  // Initialize a list to store the FileInfo Objects
  final tree = [];

  // parse the xml using the xml.XmlDocument.parse method
  final xmlDocument = xml.XmlDocument.parse(xmlStr);

  // Iterate over the response to find all folders / files and parse the information
  for (final response in xmlDocument.findAllElements('d:response')) {
    tree.add(_fromWebDavXml(response));
  }
  return tree.cast<WebDavFile>();
}

/// Returns false if some updates have failed.
bool checkUpdateFromWebDavXml(String xmlStr) {
  final xmlDocument = xml.XmlDocument.parse(xmlStr);
  final response = xmlDocument.findAllElements('d:response').single;
  final propStatElements = response.findElements('d:propstat');
  for (final propStat in propStatElements) {
    final status = propStat.getElement('d:status')!.text;
    if (!status.contains('200')) {
      return false;
    }
  }
  return true;
}
