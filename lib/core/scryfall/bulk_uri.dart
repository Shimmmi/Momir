String? bulkDownloadUri(Map<String, dynamic> item) {
  final jsonl = item['jsonl_download_uri'];
  if (jsonl is String && jsonl.isNotEmpty) return jsonl;
  final json = item['download_uri'];
  if (json is String && json.isNotEmpty) return json;
  return null;
}

bool isGzipUri(String uri) =>
    uri.endsWith('.gz') || uri.contains('.gz?');

bool isJsonlUri(String uri) => uri.contains('.jsonl');
