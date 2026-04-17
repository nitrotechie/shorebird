// print is used for diagnostic logs.
// ignore_for_file: avoid_print

import 'package:artifact_proxy/artifact_proxy.dart';
import 'package:artifact_proxy/config.dart';
import 'package:shelf/shelf.dart';

const String _explainerHtml = """
<html>
<head>
<title>Self-Hosted Shorebird Artifact Proxy</title>
</head>
<body>
<p>
This server proxies requests for Flutter artifacts to your local MinIO storage.
</p>
<p>
Source code can be found here:
<a
href='https://github.com/shorebirdtech/shorebird/tree/main/packages/artifact_proxy'>
https://github.com/shorebirdtech/shorebird/tree/main/packages/artifact_proxy</a>
</p>
</body>
</html>
""";

/// A [Handler] that proxies artifact requests to the correct location.
Handler artifactProxyHandler({required ArtifactManifestClient client}) {
  return (Request request) async {
    final path = request.url.path;
    if (path.isEmpty) {
      return Response.ok(
        _explainerHtml,
        headers: {'content-type': 'text/html'},
      );
    }

    RegExpMatch? engineArtifactMatch;
    for (final pattern in engineArtifactPatterns) {
      final match = RegExp(pattern).firstMatch(path);
      if (match != null && match.group(1) != null) {
        engineArtifactMatch = match;
        break;
      }
    }

    if (engineArtifactMatch != null) {
      final shorebirdEngineRevision = engineArtifactMatch.group(1)!;
      final ArtifactsManifest manifest;
      try {
        manifest = await client.getManifest(shorebirdEngineRevision);
      } on Exception catch (error) {
        return Response.notFound(
          'Failed to fetch manifest for $shorebirdEngineRevision\n$error',
        );
      }

      final normalizedPath = path.replaceAll(
        shorebirdEngineRevision,
        r'$engine',
      );

      final shouldOverride = manifest.artifactOverrides.contains(
        normalizedPath,
      );

      if (shouldOverride) {
        final location = getShorebirdArtifactLocation(
          artifactPath: normalizedPath,
          engine: shorebirdEngineRevision,
          bucket: manifest.storageBucket,
        );
        print('Shorebird engine artifact detected, forwarding to: $location');
        return Response.found(location);
      }

      final location = getFlutterArtifactLocation(
        artifactPath: normalizedPath,
        engine: manifest.flutterEngineRevision,
      );
      print('Flutter artifact detected, forwarding to: $location');
      return Response.found(location);
    }

    final isRecognizedFlutterArtifact = flutterArtifactPatterns.any(
      (pattern) => RegExp(pattern).hasMatch(path),
    );

    if (!isRecognizedFlutterArtifact) {
      return Response.notFound('Unrecognized artifact path: $path');
    }

    final location = getFlutterArtifactLocation(artifactPath: path);
    print('Flutter artifact detected, forwarding to: $location');
    return Response.found(location);
  };
}

/// Returns the location of the artifact at [artifactPath] using the
/// specified [engine] revision for original Flutter artifacts.
String getFlutterArtifactLocation({
  required String artifactPath,
  String? engine,
}) {
  final adjustedPath = engine != null
      ? artifactPath.replaceAll(r'$engine', engine)
      : artifactPath;

  // Self-hosted: Redirect to local MinIO
  return 'http://localhost:9000/shorebird-artifacts/$adjustedPath';
}

/// Returns the location of the artifact at [artifactPath] using the
/// specified [engine] revision for Shorebird artifacts.
String getShorebirdArtifactLocation({
  required String artifactPath,
  required String engine,
  required String bucket,
}) {
  final adjustedPath = artifactPath.replaceAll(r'$engine', engine);
  // Self-hosted: Redirect to local MinIO (overriding the bucket param)
  return 'http://localhost:9000/shorebird-artifacts/$adjustedPath';
}
