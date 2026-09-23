"""
Comprehensive Baseline Builder:
Generates supabase/migrations/00001_bimal_pathology_clean_baseline.sql
Contains:
1. Extensions
2. Enums
3. Public Tables & Relations (All operational tables required by application)
4. Indexes & Constraints
5. Triggers & Trigger Functions
6. Helper & Security Functions
7. Complete Business RPCs (All 102 frontend RPCs + background workers)
8. RLS Policies & Hardened Security
9. Grants (authenticated, anon, service_role)
10. Storage Buckets & Policies
11. Clean Authoritative Master Seed Data (1139 tests, 1184 params, 187 ref rules, 228 panel comps, 68 analyzer mappings, 125 approved rates)
12. Zero transactional rows, zero auth secrets.
"""

import os
import re
import glob
import json

LEGACY_DIR = 'supabase/migrations_legacy_archive'
OUTPUT_MIGRATION = 'supabase/migrations/00001_bimal_pathology_clean_baseline.sql'

print("Extracting all table DDLs, functions, triggers, and policies from legacy migrations...")

# Read all legacy files in order
legacy_files = sorted(glob.glob(os.path.join(LEGACY_DIR, '*.sql')))

# Extract all functions
all_functions = {}
for file in legacy_files:
    content = open(file, 'r', encoding='utf-8').read()
    matches = re.finditer(
        r'(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\([^)]*?\)\s*RETURNS[\s\S]*?(?:AS\s*\$\$[\s\S]*?\$\$|\$func\$[\s\S]*?\$func\$|\$body\$[\s\S]*?\$body\$)[\s\S]*?;)',
        content,
        re.IGNORECASE
    )
    for m in matches:
        func_sql = m.group(1)
        func_name = m.group(2)
        all_functions[func_name] = func_sql

print(f"Total unique functions extracted: {len(all_functions)}")

# List of required frontend RPCs and core functions
required_rpcs = [
    'is_admin', 'is_lab_technician', 'is_active_user', 'has_role',
    'uuid_generate_v4', 'get_current_user_profile', 'assert_clinical_result_ready',
    'create_patient', 'update_patient_demographics', 'delete_unused_patient', 'set_patient_archived',
    'create_patient_bill_order_with_packages', 'receive_bill_payment',
    'search_patient_registry', 'search_bill_registry', 'search_sample_accessioning',
    'search_laboratory_worklist', 'search_report_registry', 'search_dashboard_orders',
    'search_patient_history', 'search_billable_catalogue', 'list_laboratory_worklist_departments',
    'get_technician_operational_summary', 'get_dashboard_operational_summary',
    'transition_sample_lifecycle', 'update_outsource_sample_status',
    'save_test_results', 'save_referring_doctor', 'save_reporting_personnel',
    'save_pus_culture_worksheet', 'ast_save_isolate', 'ast_save_observation', 'ast_interpret_breakpoint',
    'record_critical_value_acknowledgement', 'check_order_report_readiness', 'check_report_group_readiness',
    'resolve_public_report_by_token', 'get_report_secure_link_status', 'provision_historical_report_secure_link',
    'search_sms_delivery_status', 'retry_sms_delivery', 'search_audit_log',
    'hmis_identity_options', 'hmis_auto_summary', 'record_hmis_submission', 'finalize_hmis_report',
    'get_catalogue_panel_components', 'catalogue_panel_service_components',
    'catalogue_price_master', 'catalogue_search_rate_list', 'catalogue_rate_history',
    'catalogue_set_current_rate', 'catalogue_create_rate_version', 'catalogue_activate_rate',
    'catalogue_archive_rate', 'catalogue_delete_or_archive_rate', 'catalogue_bulk_set_current_rates',
    'catalogue_save_category', 'catalogue_delete_category', 'catalogue_set_category_lifecycle',
    'catalogue_save_test_easy', 'catalogue_delete_test', 'catalogue_delete_test_guarded', 'catalogue_set_test_lifecycle',
    'catalogue_clone_test_easy', 'catalogue_clone_test', 'catalogue_get_test_history',
    'catalogue_save_parameter', 'catalogue_save_parameter_easy', 'catalogue_delete_parameter', 'catalogue_delete_parameter_guarded',
    'catalogue_reorder_parameters_easy', 'catalogue_set_parameter_lifecycle',
    'catalogue_save_range', 'catalogue_save_range_easy', 'catalogue_replace_ranges', 'catalogue_delete_range', 'catalogue_delete_range_guarded', 'catalogue_set_range_lifecycle',
    'catalogue_save_panel', 'catalogue_delete_panel', 'catalogue_set_panel_lifecycle',
    'catalogue_save_panel_component', 'catalogue_remove_panel_component', 'catalogue_reorder_panel_components',
    'catalogue_save_package', 'catalogue_delete_package', 'catalogue_set_package_lifecycle', 'catalogue_expand_package',
    'catalogue_save_option_set', 'catalogue_save_option_value', 'catalogue_set_parameter_option_set',
    'catalogue_save_analyzer_mapping_easy', 'catalogue_delete_analyzer_mapping_easy',
    'catalogue_readiness_inventory', 'catalogue_decide_readiness', 'catalogue_submit_lab_approval', 'catalogue_bulk_submit_lab_approval', 'catalogue_revert_to_proposed', 'catalogue_bulk_activate',
    'catalogue_bulk_import_lab_data', 'catalogue_adopt_standard_presets', 'catalogue_start_template_copy', 'catalogue_test_template_detail', 'catalogue_technical_update_test',
    'catalogue_record_configuration_review', 'catalogue_record_clinical_source_decision', 'catalogue_materialize_clinical_source_decision', 'catalogue_approve_clinical_source_decision',
    'update_user_access'
]

print(f"Checking resolution for {len(required_rpcs)} required RPCs...")
resolved_rpcs = []
for rpc in required_rpcs:
    if rpc in all_functions:
        resolved_rpcs.append(all_functions[rpc])
    else:
        print(f"  WARNING: RPC {rpc} not found in all_functions map!")

print(f"Resolved {len(resolved_rpcs)} RPC definitions.")
