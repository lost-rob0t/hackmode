% Durable knowledge: ZAP daemon provider backends for the declared pentest tools.
% Verified 2026-11-24/25 in worktree branch mcp/zap-probe-backends (base dd4defb):
% all suites green via the local core gate (incl. new :hackmode-provider-zap),
% prolog-verify PASS, boundary denylist clean, LIVE hm-mcp e2e pass
% (real race probe verdict=uniform spreadMs=1.53; real spider scan 40 findings;
% capability_list reports all eight zap backends registered).

zap_provider_system(hackmode_provider_zap, 'source/hackmode-providers/zap').
zap_capability_pair('zap', 'web-vuln-scan'/zap).
zap_capability_pair('zap-race-probe', 'race-probe'/zap-race-probe).
zap_capability_pair('zap-smuggle-probe', 'smuggle-probe'/zap-smuggle-probe).
zap_capability_pair('zap-jwt-toolkit', 'jwt-toolkit'/zap-jwt-toolkit).
zap_capability_pair('zap-param-miner', 'param-miner'/zap-param-miner).
zap_capability_pair('zap-authz-diff', 'authz-diff'/zap-authz-diff).
zap_capability_pair('zap-content-discovery', 'content-discovery'/zap-content-discovery).
zap_capability_pair('zap-graphql-probe', 'graphql-probe'/zap-graphql-probe).

zap_rule(spec_first,
         'the novel capability surface is DECLARED in pentest.star (tool-name/vuln-tool enums, library 1.0.0 -> 1.1.0); the MCP catalog derives verbatim — never hand-write JS tool tables alongside (operator correction 2026-11-24: "define rules in star lang")').
zap_rule(options_threading,
         'run-capability/execute-provider-job/invoke-provider take :options; the provider struct gained options-p — register with :options-p t to receive the caller option map as a second handler argument; unary handlers keep the original contract').
zap_rule(daemon_client,
         'REST client = curl subprocess with argv list (no shell), API key from HACKMODE_ZAP_API_KEY or /tmp/opencode/zap-api-key; daemon API errors raise zap-error carrying the complete response body (lossless)').
zap_rule(query_string_shape,
         'daemon paths are /JSON/<component>/<kind>/<name>/?<query> — the /? separator is REQUIRED; apply on a bare string spreads its characters as arguments (use funcall); missing separator produced silently-misrouted paths and a wrong e2e failure').
zap_rule(script_contract,
         'novel plugins are GraalJS standalone scripts under zap-scripts/, executed headless: setGlobalVar(zmcp.params)=JSON params in -> script/load -> runStandAloneScript (synchronous) -> script/globalVar(zmcp.result)=JSON result out; the runner removes the script before load because the daemon load action returns already_exists on re-registration').
zap_rule(plugin_findings,
         'every plugin result becomes exactly ONE typed finding whose data is the plugin result JSON verbatim (lossless); plugin verdicts ride inside the JSON, severity stays an analyst call').
zap_rule(scan_bounded,
         'classic zap backend = spider + active scan + alert harvest, each phase under a wall-clock deadline; deadline cuts stop the phase through the daemon and record a zap-scan-note finding ("deadlineReached":true) — no silent partial scans').
zap_rule(mcp_tool_names,
         'declared names are verbatim from the spec enum: HYPHENS (zap-race-probe), not underscores — MCP clients must call the hyphenated names').

zap_trap(graaljs_static_lookup,
         'GraalJS re-resolves java.lang.System per call at ~18 ms; hoisting to a var takes nanoTime to ~6 us — hoist EVERY Java reference once (measured in-daemon 2026-11-24)').
zap_trap(graaljs_class_location,
         'org.zaproxy.zap.network.HttpRequestBody (moved from parosproxy); HttpSender has no getInstance in 2.17 — use new HttpSender(HttpSender.MANUAL_REQUEST_INITIATOR); GraalJS engine name string is "ECMAScript : Graal.js"').
zap_trap(zap_api_doc_discovery,
         'enumerate the daemon API from its own UI pages /UI/<component>/ (hrefs carry view/action names + params); several legacy endpoints (core cookies, break views) are gone in 2.17 — verify empirically, never from memory').
zap_trap(nix_zap_config,
         'packaged config.xml is 444; the daemon re-copies it and cannot save its own home — mcp/zap-launch.sh pre-seeds a writable config and wins the chmod race (reusable for any headless ZAP run)').

zap_e2e_recipe(hm_mcp_e2e,
               'build hm-mcp (make build-mcp with CL_SOURCE_REGISTRY star-lang+pins, LD_LIBRARY_PATH lmdb/openssl), drive stdio JSON-RPC: initialize -> tools/list (21) -> op_create/op_use -> zap-race-probe with options -> zap spider scan -> asset_query -> capability_list; script /tmp/opencode/hm-zap-e2e.py (ephemeral — rebuild from this fold)').
