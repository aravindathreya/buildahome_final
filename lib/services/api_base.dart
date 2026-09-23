/// Canonical production API host for Flask `/API/...` endpoints.
///
/// Site-proof (single + multi-material), approved POs, and workflow item-runs
/// must use this host. Do not fall back to `app.buildahome.in` — that host
/// currently serves an SSL cert for `office.buildahome.in` and causes
/// `CERTIFICATE_VERIFY_FAILED: Hostname mismatch`.
const String kProductionApiBaseUrl = 'https://office.buildahome.in';
