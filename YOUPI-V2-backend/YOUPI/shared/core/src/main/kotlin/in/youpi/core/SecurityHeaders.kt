package `in`.youpi.core

import org.springframework.http.HttpHeaders

/**
 * Standard security response headers, applied to every response.
 *
 * Split out as a shared function (rather than living only in a WebFilter)
 * because GlobalExceptionHandler's own comments already document that
 * headers set by an earlier WebFilter don't reliably survive onto error
 * responses on some Spring Boot/WebFlux versions -- see its CORS
 * re-stamping code, which hit exactly this problem. Same defensive
 * belt-and-braces approach applies here: SecurityHeadersFilter covers the
 * normal path, GlobalExceptionHandler re-applies the same headers on the
 * error path, both calling this single source of truth so they can't drift
 * apart.
 *
 * CSP note: the admin panel (admin-panel.html) compiles JSX live in the
 * browser via babel-standalone rather than at build time, which requires
 * 'unsafe-inline' and 'unsafe-eval' in script-src -- a real CSP script-src
 * is fundamentally limited by that architecture, not by this header
 * config. Tightening script-src properly needs precompiling the panel's
 * JSX at build time (e.g. a small esbuild step) and switching to a
 * nonce/hash-based policy -- that's a follow-up, not part of this fix.
 * Every other directive here (frame-ancestors, object-src, base-uri,
 * form-action) is fully locked down regardless and doesn't depend on that
 * follow-up.
 */
fun applySecurityHeaders(headers: HttpHeaders) {
    headers.set("X-Content-Type-Options", "nosniff")
    headers.set("X-Frame-Options", "DENY")
    // Only honored by browsers when the response is actually received over
    // HTTPS (RFC 6797) -- harmless to always send, including over local
    // plain-HTTP dev.
    headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
    headers.set("Referrer-Policy", "strict-origin-when-cross-origin")
    headers.set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
    headers.set(
        "Content-Security-Policy",
        "default-src 'self'; " +
            "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdnjs.cloudflare.com; " +
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " +
            "font-src 'self' https://fonts.gstatic.com; " +
            "img-src 'self' data:; " +
            "connect-src 'self'; " +
            "object-src 'none'; " +
            "base-uri 'self'; " +
            "form-action 'self'; " +
            "frame-ancestors 'none'"
    )
}