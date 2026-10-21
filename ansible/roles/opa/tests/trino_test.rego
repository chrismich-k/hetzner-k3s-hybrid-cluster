# Unit tests of the Trino policy (files/*.rego) with the example roles in
# fixture_*.rego; run from roles/opa:
#   docker run --rm -v "$PWD":/w:ro openpolicyagent/opa:<opa_product_version> test -v /w/files /w/tests
package trino_test

import data.trino

ctx(u) := {"identity": {"user": u, "groups": []}}

table(op, c, s, t) := {"operation": op, "resource": {"table": {"catalogName": c, "schemaName": s, "tableName": t}}}

test_api_reader_selects_api_view if {
	trino.allow with input as {"context": ctx("svc-api-ro"), "action": table("SelectFromColumns", "iceberg", "dataware_api", "api_balancing_cost_hourly")}
}

test_api_reader_execute_query_and_catalog if {
	trino.allow with input as {"context": ctx("svc-api-ro"), "action": {"operation": "ExecuteQuery"}}
	trino.allow with input as {"context": ctx("svc-api-ro"), "action": {"operation": "AccessCatalog", "resource": {"catalog": {"name": "iceberg"}}}}
}

test_api_reader_denied_marts if {
	not trino.allow with input as {"context": ctx("svc-api-ro"), "action": table("SelectFromColumns", "iceberg", "dataware_marts", "fct_x")}
}

test_api_reader_denied_other_catalog if {
	not trino.allow with input as {"context": ctx("svc-api-ro"), "action": {"operation": "AccessCatalog", "resource": {"catalog": {"name": "system"}}}}
}

test_api_reader_denied_writes if {
	not trino.allow with input as {"context": ctx("svc-api-ro"), "action": table("CreateTable", "iceberg", "dataware_api", "x")}
	not trino.allow with input as {"context": ctx("svc-api-ro"), "action": table("DropTable", "iceberg", "dataware_api", "api_balancing_cost_hourly")}
	not trino.allow with input as {"context": ctx("svc-api-ro"), "action": table("InsertIntoTable", "iceberg", "dataware_api", "api_balancing_cost_hourly")}
}

test_api_reader_filter_schemas if {
	result := trino.batch with input as {"context": ctx("svc-api-ro"), "action": {"operation": "FilterSchemas", "filterResources": [
		{"schema": {"catalogName": "iceberg", "schemaName": "dataware_marts"}},
		{"schema": {"catalogName": "iceberg", "schemaName": "dataware_api"}},
	]}}
	result == {1}
}

test_api_reader_filter_catalogs if {
	result := trino.batch with input as {"context": ctx("svc-api-ro"), "action": {"operation": "FilterCatalogs", "filterResources": [
		{"catalog": {"name": "system"}},
		{"catalog": {"name": "iceberg"}},
	]}}
	result == {1}
}

test_api_reader_filter_columns if {
	result := trino.batch with input as {"context": ctx("svc-api-ro"), "action": {"operation": "FilterColumns", "filterResources": [{"table": {"catalogName": "iceberg", "schemaName": "dataware_api", "tableName": "v", "columns": ["a", "b", "c"]}}]}}
	result == {0, 1, 2}
	other := trino.batch with input as {"context": ctx("svc-api-ro"), "action": {"operation": "FilterColumns", "filterResources": [{"table": {"catalogName": "iceberg", "schemaName": "dataware_marts", "tableName": "v", "columns": ["a", "b"]}}]}}
	other == set()
}

test_unbound_users_keep_full_access if {
	trino.allow with input as {"context": ctx("svc-dbt"), "action": table("CreateTable", "iceberg", "dataware_marts", "x")}
	trino.allow with input as {"context": ctx("someone@example.org"), "action": table("DropTable", "iceberg", "x", "y")}
	result := trino.batch with input as {"context": ctx("svc-dbt"), "action": {"operation": "FilterColumns", "filterResources": [{"table": {"catalogName": "iceberg", "schemaName": "s", "tableName": "t", "columns": ["a", "b", "c"]}}]}}
	result == {0, 1, 2}
}

test_anonymous_denied if {
	not trino.allow with input as {"context": ctx(""), "action": {"operation": "ExecuteQuery"}}
}

test_two_roles_union if {
	trino.allow with input as {"context": ctx("two-roles"), "action": table("SelectFromColumns", "iceberg", "dataware_api", "v")}
	trino.allow with input as {"context": ctx("two-roles"), "action": table("SelectFromColumns", "iceberg", "dataware_marts", "t")}
	not trino.allow with input as {"context": ctx("two-roles"), "action": table("SelectFromColumns", "iceberg", "dataware_staging", "t")}
	result := trino.batch with input as {"context": ctx("two-roles"), "action": {"operation": "FilterSchemas", "filterResources": [
		{"schema": {"catalogName": "iceberg", "schemaName": "dataware_marts"}},
		{"schema": {"catalogName": "iceberg", "schemaName": "dataware_api"}},
		{"schema": {"catalogName": "iceberg", "schemaName": "dataware_staging"}},
	]}}
	result == {0, 1}
}

test_empty_bindings_keep_old_behaviour if {
	trino.allow with input as {"context": ctx("svc-api-ro"), "action": table("CreateTable", "iceberg", "x", "y")}
		with data.trino.bindings.user_roles as set()
}
