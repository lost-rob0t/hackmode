:- module(logicstrike_concepts, [concept/2]).
/** <module> LogicStrike concept classifications

Declarative concept categories. A concept may have several roles,
e.g. recon is both a phase and an objective.
*/

%% Objectives and phases
concept(foothold, objective).
concept(recon, objective).
concept(recon, phase).
concept(exploitation, phase).

%% Capabilities
concept(rce, capability).
concept(shell, capability).

%% Activities
concept(exploit, activity).
concept(vuln_discovery, activity).
concept(content_search, activity).

%% Surfaces and attributes
concept(input, surface).
concept(url_input, surface).
concept(form_input, surface).
concept(json_input, surface).
concept(ip, surface).
concept(domain, surface).
concept(input_type, attribute).

%% Techniques
concept(shell_injection, technique).
concept(sqli, technique).
concept(blind_sqli, technique).
concept(subdomain_discovery, technique).
concept(asn_range, technique).
concept(port_scan, technique).
concept(graphql_introspection, technique).
