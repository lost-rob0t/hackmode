:- begin_tests(logicstrike).
:- use_module('../logicstrike').

test(recon_has_both_roles, set(Type == [objective, phase])) :-
    concept(recon, Type).

test(blind_sqli_is_subtype) :-
    subtype_of(blind_sqli, sqli).

test(content_search_is_recon_activity) :-
    part_of_phase(content_search, recon).

test(expert_has_two_goals, set(Objective == [foothold, recon])) :-
    expert_goal(logicstrike, Objective, ip(10,50,50,18)).

test(original_recon_inference) :-
    candidate_recon(foothold, vuln_discovery).

test(recon_goal_not_in_original_inference, [fail]) :-
    candidate_recon(recon, _).

test(candidate_methods, set(Method == [
        asn_range,
        blind_sqli,
        graphql_introspection,
        port_scan,
        shell_injection,
        sqli,
        subdomain_discovery
    ])) :-
    candidate_technique(logicstrike, ip(10,50,50,18), Method, _).

test(graphql_is_schema_discovery) :-
    technique(recon, graphql_introspection, schema_discovery).

test(ip_is_known_surface) :-
    concept(ip, surface).

test(input_surfaces_are_concepts) :-
    concept(url_input, surface),
    concept(form_input, surface),
    concept(json_input, surface).

test(surface_exact_match) :-
    surface_matches(ip, ip).

test(surface_input_subtypes_match) :-
    surface_matches(url_input, input),
    surface_matches(form_input, input),
    surface_matches(json_input, input).

test(target_surface_classification, set(Surface == [ip])) :-
    target_surface(ip(10,50,50,18), Surface).

test(target_input_surfaces) :-
    target_surface(url_param(id, query, get), url_input),
    target_surface(body_param(user, pass), form_input),
    target_surface(json_param(q, page), json_input).

test(technique_applies_to_ip_target, set(Method == [asn_range, port_scan, subdomain_discovery])) :-
    technique_applies(ip(10,50,50,18), Method).

test(technique_applies_to_domain_target, set(Method == [port_scan, subdomain_discovery])) :-
    technique_applies(domain([com, example]), Method).

test(technique_applies_to_input_targets, set(Method == [blind_sqli, sqli])) :-
    technique_applies(url_param(id, 1, get), Method),
    technique_applies(body_param(user, "' OR 1=1 --"), Method),
    technique_applies(json_param(q, "x'"), Method).

test(domain_exact_match) :-
    domain_matches([com, example], [com, example]).

test(domain_wildcard_subdomain_match) :-
    domain_matches([com, example], [com, example, www]).

test(domain_no_match) :-
    \+ domain_matches([com, example], [com, example_org]).

test(pattern_is_list_form) :-
    domain_matches([actor, starintel], [actor, starintel, api, dev]).

test(tool_assigned_goals_for_logicstrike, set(Target == [ip(10,50,50,18)])) :-
    tool_assigned_goals(logicstrike, Target).

test(tool_candidate_techniques, set(Method == [
        asn_range,
        blind_sqli,
        graphql_introspection,
        port_scan,
        shell_injection,
        sqli,
        subdomain_discovery
    ])) :-
    tool_candidate_techniques(logicstrike, ip(10,50,50,18), Method, _).

test(tool_applicable_techniques, set(Method == [asn_range, port_scan, subdomain_discovery])) :-
    tool_applicable_techniques(ip(10,50,50,18), Method).

test(tool_surface_of_ip) :-
    tool_surface_of(ip(10,50,50,18), ip).

test(tool_surface_of_unknown_fails, [fail]) :-
    tool_surface_of(email('alice@example.org'), _).

test(tool_domains_matching, [nondet]) :-
    tool_domains_matching([com, example], [com, example, www]).

:- end_tests(logicstrike).
