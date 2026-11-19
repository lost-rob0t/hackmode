:- module(logicstrike_relationships,
          [ subtype_of/2,
            possible_via/2,
            part_of_phase/2,
            informed_by/2,
            has_attribute/2,
            discovers/2
          ]).
/** <module> Typed relationships for LogicStrike */

%% Subtypes
subtype_of(blind_sqli, sqli).
subtype_of(url_input, input).
subtype_of(form_input, input).
subtype_of(json_input, input).

%% Possible approaches to an objective or capability
possible_via(foothold, rce).
possible_via(foothold, shell).
possible_via(rce, exploit).

%% Phase membership
part_of_phase(exploit, exploitation).
part_of_phase(vuln_discovery, recon).
part_of_phase(content_search, recon).

%% Informational dependencies
informed_by(exploit, vuln_discovery).

%% Reconnaissance relationships
has_attribute(url_input, input_type).
discovers(content_search, input).
