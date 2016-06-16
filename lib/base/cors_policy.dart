part of aqueduct;

/// Describes a CORS policy for a [RequestHandler].
///
/// These instances can be set as a [RequestHandler]s [policy] property, which will
/// manage CORS requests according to the policy's properties.
class CORSPolicy {
  /// The default CORS policy.
  ///
  /// You may modify this default policy. All instances of [CORSPolicy] are instantiated
  /// using the values of this default policy.
  ///
  static CORSPolicy get DefaultPolicy {
    if (_defaultPolicy == null) {
      _defaultPolicy = new CORSPolicy._defaults();
    }
    return _defaultPolicy;
  }
  static CORSPolicy _defaultPolicy;

  /// List of 'Simple' CORS headers.
  ///
  /// These are headers that are considered acceptable as part of any CORS request. They are cache-control, content-language, content-type, expires, last-modified,
  /// pragma, accept, accept-language and origin.
  static List<String> SimpleHeaders = ["cache-control", "content-language", "content-type", "expires", "last-modified", "pragma", "accept", "accept-language", "origin"];

  /// Create a new instance of [CORSPolicy].
  ///
  /// Values are set to match [DefaultPolicy].
  CORSPolicy() {
    var defaultPolicy = DefaultPolicy;
    allowedOrigins = defaultPolicy.allowedOrigins;
    allowCredentials = defaultPolicy.allowCredentials;
    exposedResponseHeaders = defaultPolicy.exposedResponseHeaders;
    allowedMethods = defaultPolicy.allowedMethods;
    allowedRequestHeaders = defaultPolicy.allowedRequestHeaders;
    cacheInSeconds = defaultPolicy.cacheInSeconds;
  }

  CORSPolicy._defaults() {
    allowedOrigins = ["*"];
    allowCredentials = true;
    exposedResponseHeaders = [];
    allowedMethods = ["POST", "PUT", "DELETE", "GET"];
    allowedRequestHeaders = ["authorization", "x-requested-with", "x-forwarded-for"];
    cacheInSeconds = 86400;
  }

  /// The list of case-sensitive allowed origins.
  ///
  /// Defaults to '*'. Case-sensitive.
  List<String> allowedOrigins;

  /// Whether or not to allow use of credentials, including Authorization and cookies.
  ///
  /// Defaults to true.
  bool allowCredentials;

  /// Which response headers to expose to the client.
  ///
  /// Defaults to empty.
  List<String> exposedResponseHeaders;

  /// Which HTTP methods are allowed.
  ///
  /// Defaults to POST, PUT, DELETE, and GET. Case-sensitive.
  List<String> allowedMethods;

  /// The allowed request headers.
  ///
  /// Defaults to authorization, x-requested-with, x-forwarded-for. Must be lowercase.
  /// Use in conjunction with [SimpleHeaders].
  List<String> allowedRequestHeaders;

  /// The number of seconds to cache a pre-flight request for a requesting client.
  int cacheInSeconds;

  /// Returns a map of HTTP headers for a request based on this policy.
  ///
  /// This will add Access-Control-Allow-Origin, Access-Control-Expose-Headers and Access-Control-Allow-Credentials
  /// depending on the this policy.
  Map<String, dynamic> headersForRequest(Request request) {
    var origin = request.innerRequest.headers.value("origin");

    var headers = {};
    headers["Access-Control-Allow-Origin"] = origin;

    if (exposedResponseHeaders.length > 0) {
      headers["Access-Control-Expose-Headers"] = exposedResponseHeaders.join(", ");
    }

    headers["Access-Control-Allow-Credentials"] = allowCredentials ? "true" : "false";

    return headers;
  }

  /// Whether or not this policy allows the Origin of the [request].
  ///
  /// Will return true if [allowedOrigins] contains the case-sensitive Origin of the [request],
  /// or that [allowedOrigins] contains *.
  bool isRequestOriginAllowed(HttpRequest request) {
    var origin = request.headers.value("origin");
    if (!allowedOrigins.contains("*") && !allowedOrigins.contains(origin)) {
      return false;
    }
    return true;
  }

  /// Validates whether or not a preflight request matches this policy.
  ///
  /// Will return true if the policy agrees with the Access-Control-Request-* headers of the request, otherwise, false.
  bool validatePreflightRequest(HttpRequest request) {
    var method = request.headers.value("access-control-request-method");
    if (!allowedMethods.contains(method)) {
      return false;
    }

    var requestedHeaders = request.headers.value("access-control-request-headers").split(",").map((str) => str.trim()).toList();
    if (requestedHeaders != null) {
      var nonSimpleHeaders = requestedHeaders.where((str) => !SimpleHeaders.contains(str));
      if (nonSimpleHeaders.any((h) => !allowedRequestHeaders.contains(h))) {
        return false;
      }
    }

    return true;
  }

  /// Returns a preflight response for a given [Request].
  ///
  /// Contains the Access-Control-Allow-* headers for a CORS preflight request according
  /// to this policy.
  Response preflightResponse(Request req) {
    var headers = {
      "Access-Control-Allow-Origin" : req.innerRequest.headers.value("origin"),
      "Access-Control-Allow-Methods" : allowedMethods.join(", "),
      "Access-Control-Allow-Headers" : allowedRequestHeaders.join(", ")
    };

    if (allowCredentials) {
      headers["Access-Control-Allow-Credentials"] = "true";
    }

    if (cacheInSeconds != null) {
      headers["Access-Control-Max-Age"] = "$cacheInSeconds";
    }

    return new Response.ok(null, headers: headers);
  }
}