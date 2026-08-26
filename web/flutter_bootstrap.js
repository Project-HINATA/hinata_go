{{flutter_js}}
{{flutter_build_config}}

const buildId = "__WEB_BUILD_ID__";
const config = {};

if (buildId && !buildId.startsWith("__")) {
  config.canvasKitBaseUrl = "runtime/" + buildId + "/canvaskit/";
  config.entrypointBaseUrl = "runtime/" + buildId + "/";
}

_flutter.loader.load({
  config: config,
});
