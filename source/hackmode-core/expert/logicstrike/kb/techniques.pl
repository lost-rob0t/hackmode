:- module(logicstrike_techniques,
          [ technique/3,
            requires_surface/2
          ]).
/** <module> Technique catalog and input surface associations */

%% technique(Context, Method, Family).
%% Context may currently be an objective, phase or activity.
technique(exploit, shell_injection, injection).
technique(exploit, sqli, injection).
technique(exploit, blind_sqli, injection).
technique(recon, graphql_introspection, schema_discovery).

technique(recon, subdomain_discovery, asset_discovery).
technique(recon, asn_range, asset_discovery).
technique(recon, port_scan, asset_discovery).

%% Each row is an accepted surface type in the current ontology.
%% Multiple entries represent alternatives here, not an AND requirement.
requires_surface(sqli, input).
requires_surface(blind_sqli, input).
requires_surface(subdomain_discovery, domain).
requires_surface(subdomain_discovery, ip).   % Reverse IP lookup / related discovery
requires_surface(asn_range, ip).             % IP to ASN lookup
requires_surface(port_scan, ip).
requires_surface(port_scan, domain).

