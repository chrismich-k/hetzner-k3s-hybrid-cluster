package trino.lib

# Helpers for the role policies (package trino.roles.<role>).

# Read access to schema s of catalog c: run queries, open the catalog,
# list its tables and select from them. With SECURITY DEFINER views (the
# dbt-trino default) the tables behind them are checked against the view
# owner, not against this user.
read_schema(_, _) if input.action.operation == "ExecuteQuery"

read_schema(c, _) if {
	input.action.operation == "AccessCatalog"
	input.action.resource.catalog.name == c
}

read_schema(c, s) if {
	input.action.operation == "ShowTables"
	input.action.resource.schema.catalogName == c
	input.action.resource.schema.schemaName == s
}

read_schema(c, s) if {
	input.action.operation in {"SelectFromColumns", "ShowColumns"}
	input.action.resource.table.catalogName == c
	input.action.resource.table.schemaName == s
}

# Indices for the batch rule of a role: catalog c, schema s and its
# tables and columns stay visible in SHOW / information_schema listings.
# Use as: batch contains i if some i in lib.filter_schema("cat", "schema")
filter_schema(c, s) := {i | some i, _ in table.columns} if {
	input.action.operation == "FilterColumns"
	table := input.action.filterResources[0].table
	table.catalogName == c
	table.schemaName == s
}

else := {i |
	some i, resource in input.action.filterResources
	_in_schema(resource, c, s)
}

_in_schema(resource, c, _) if {
	input.action.operation == "FilterCatalogs"
	resource.catalog.name == c
}

_in_schema(resource, c, s) if {
	input.action.operation == "FilterSchemas"
	resource.schema.catalogName == c
	resource.schema.schemaName == s
}

_in_schema(resource, c, s) if {
	input.action.operation == "FilterTables"
	resource.table.catalogName == c
	resource.table.schemaName == s
}
