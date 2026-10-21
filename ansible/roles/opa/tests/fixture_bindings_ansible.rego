# Test fixture for trino_test.rego (not deployed)
package trino.bindings

user_roles contains binding if some binding in [["svc-api-ro", "api_reader"], ["two-roles", "api_reader"], ["two-roles", "marts_reader"]]
