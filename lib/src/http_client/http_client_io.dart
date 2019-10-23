import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// ignore: public_member_api_docs
class HttpClient extends http.BaseClient {
  // ignore: public_member_api_docs
  HttpClient() : _client = IOClient();

  final http.BaseClient _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _client.send(request);
}