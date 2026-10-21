package trino

# Entry point Trino queries (data.trino.allow, data.trino.batch). A user
# bound to at least one role (data.trino.bindings) gets exactly what its
# roles allow; any other authenticated user may do anything.

user := input.context.identity.user

granted_roles contains role if {
	some binding in data.trino.bindings.user_roles
	binding[0] == user
	role := binding[1]
}

restricted if count(granted_roles) > 0

default allow := false

allow if {
	user != ""
	not restricted
}

allow if {
	some role in granted_roles
	data.trino.roles[role].allow
}

# Trino's batch endpoint for Filter* ops (SHOW CATALOGS/SCHEMAS/TABLES
# etc.); without it these silently return empty results instead of
# erroring. Returns indices of the allowed filterResources - for
# FilterColumns of the columns of its single table instead.
batch contains i if {
	user != ""
	not restricted
	some i in numbers.range(0, count(input.action.filterResources) - 1)
}

batch contains i if {
	user != ""
	not restricted
	input.action.operation == "FilterColumns"
	some i in numbers.range(0, count(input.action.filterResources[0].table.columns) - 1)
}

batch contains i if {
	some role in granted_roles
	some i in data.trino.roles[role].batch
}
