# Test fixture for trino_test.rego (not deployed)
package trino.roles.api_reader

import data.trino.lib

allow if lib.read_schema("iceberg", "dataware_api")
batch contains i if some i in lib.filter_schema("iceberg", "dataware_api")
