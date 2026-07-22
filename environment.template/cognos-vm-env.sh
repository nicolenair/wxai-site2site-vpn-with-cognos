#!/usr/bin/env bash
# Reference values used throughout README.md. Windows steps use these as
# plain values (PowerShell has no `source`) - copy them in manually or
# adapt into a .ps1 if preferred.

# --- Content store (PostgreSQL) ---
export CM_DB_HOST=""
export CM_DB_PORT=""
export CM_DB_NAME=""
export CM_DB_SCHEMA=""
export CM_DB_USER=""
export CM_DB_PASSWORD=""

# --- Authentication (LDAP) ---
export LDAP_HOST_PORT=""
export LDAP_BASE_DN=""
export LDAP_ADMIN_DN=""
export LDAP_ADMIN_PASSWORD=""
export LDAP_ORG=""
export LDAP_DOMAIN=""
export TEST_USER_DN=""
export TEST_USER_PASSWORD=""

# --- Agentic AI ---
export WATSONX_API_KEY=""
  # your watsonx.ai project - check via GET /ml/v1/foundation_model_specs
export CA_BASE_URL=""       # the
  # agentic service runs in a container - never use "localhost" here
export AGENTIC_CONTAINER_NAME=""
export AGENTIC_NETWORK_NAME=""
export OPENSEARCH_CONTAINER_NAME=""
export INITIAL_OPENSEARCH_ADMIN_PASSWORD=""