export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      analyzers: {
        Row: {
          code: string
          created_at: string
          id: string
          laboratory_location: string | null
          lifecycle_status: Database["public"]["Enums"]["analyzer_lifecycle_enum"]
          manufacturer: string | null
          model: string | null
          name: string
          row_version: number
          serial_number: string | null
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          laboratory_location?: string | null
          lifecycle_status?: Database["public"]["Enums"]["analyzer_lifecycle_enum"]
          manufacturer?: string | null
          model?: string | null
          name: string
          row_version?: number
          serial_number?: string | null
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          laboratory_location?: string | null
          lifecycle_status?: Database["public"]["Enums"]["analyzer_lifecycle_enum"]
          manufacturer?: string | null
          model?: string | null
          name?: string
          row_version?: number
          serial_number?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      ast_antibiotics: {
        Row: {
          code: string
          created_at: string
          id: string
          is_active: boolean
          name: string
          row_version: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          row_version?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          row_version?: number
          updated_at?: string
        }
        Relationships: []
      }
      ast_breakpoint_rules: {
        Row: {
          antibiotic_id: string
          automatic_interpretation_allowed: boolean
          breakpoint_set_id: string
          created_at: string
          id: string
          intermediate_max: number | null
          intermediate_min: number | null
          intermediate_secondary_max: number | null
          intermediate_secondary_min: number | null
          intermediate_semantics: string | null
          interpretation_semantics: Json
          method: string
          metric_type: string
          notes: string | null
          organism_group_id: string
          potency: string | null
          resistant_max: number | null
          resistant_min: number | null
          resistant_secondary: number | null
          row_version: number
          susceptible_max: number | null
          susceptible_min: number | null
          susceptible_secondary: number | null
          updated_at: string
        }
        Insert: {
          antibiotic_id: string
          automatic_interpretation_allowed?: boolean
          breakpoint_set_id: string
          created_at?: string
          id?: string
          intermediate_max?: number | null
          intermediate_min?: number | null
          intermediate_secondary_max?: number | null
          intermediate_secondary_min?: number | null
          intermediate_semantics?: string | null
          interpretation_semantics?: Json
          method: string
          metric_type: string
          notes?: string | null
          organism_group_id: string
          potency?: string | null
          resistant_max?: number | null
          resistant_min?: number | null
          resistant_secondary?: number | null
          row_version?: number
          susceptible_max?: number | null
          susceptible_min?: number | null
          susceptible_secondary?: number | null
          updated_at?: string
        }
        Update: {
          antibiotic_id?: string
          automatic_interpretation_allowed?: boolean
          breakpoint_set_id?: string
          created_at?: string
          id?: string
          intermediate_max?: number | null
          intermediate_min?: number | null
          intermediate_secondary_max?: number | null
          intermediate_secondary_min?: number | null
          intermediate_semantics?: string | null
          interpretation_semantics?: Json
          method?: string
          metric_type?: string
          notes?: string | null
          organism_group_id?: string
          potency?: string | null
          resistant_max?: number | null
          resistant_min?: number | null
          resistant_secondary?: number | null
          row_version?: number
          susceptible_max?: number | null
          susceptible_min?: number | null
          susceptible_secondary?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ast_breakpoint_rules_antibiotic_id_fkey"
            columns: ["antibiotic_id"]
            isOneToOne: false
            referencedRelation: "ast_antibiotics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_breakpoint_rules_breakpoint_set_id_fkey"
            columns: ["breakpoint_set_id"]
            isOneToOne: false
            referencedRelation: "ast_breakpoint_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_breakpoint_rules_organism_group_id_fkey"
            columns: ["organism_group_id"]
            isOneToOne: false
            referencedRelation: "ast_organism_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      ast_breakpoint_sets: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string | null
          effective_date: string
          id: string
          is_active: boolean
          name: string
          provenance: string
          retired_at: string | null
          row_version: number
          status: string
          version: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          effective_date: string
          id?: string
          is_active?: boolean
          name: string
          provenance: string
          retired_at?: string | null
          row_version?: number
          status: string
          version: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          effective_date?: string
          id?: string
          is_active?: boolean
          name?: string
          provenance?: string
          retired_at?: string | null
          row_version?: number
          status?: string
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "ast_breakpoint_sets_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_breakpoint_sets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      ast_isolates: {
        Row: {
          created_at: string
          created_by: string
          growth_state: string
          id: string
          isolate_number: number
          microorganism_id: string | null
          order_item_id: string
          organism_group_id: string | null
          organism_group_snapshot: string | null
          organism_name_snapshot: string
          row_version: number
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          growth_state: string
          id?: string
          isolate_number: number
          microorganism_id?: string | null
          order_item_id: string
          organism_group_id?: string | null
          organism_group_snapshot?: string | null
          organism_name_snapshot: string
          row_version?: number
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          growth_state?: string
          id?: string
          isolate_number?: number
          microorganism_id?: string | null
          order_item_id?: string
          organism_group_id?: string | null
          organism_group_snapshot?: string | null
          organism_name_snapshot?: string
          row_version?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ast_isolates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_isolates_microorganism_id_fkey"
            columns: ["microorganism_id"]
            isOneToOne: false
            referencedRelation: "ast_microorganisms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_isolates_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "clinical_order_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_isolates_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["order_item_id"]
          },
          {
            foreignKeyName: "ast_isolates_organism_group_id_fkey"
            columns: ["organism_group_id"]
            isOneToOne: false
            referencedRelation: "ast_organism_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      ast_microorganisms: {
        Row: {
          code: string
          created_at: string
          display_name: string
          id: string
          is_active: boolean
          organism_group_id: string | null
          row_version: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          display_name: string
          id?: string
          is_active?: boolean
          organism_group_id?: string | null
          row_version?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          display_name?: string
          id?: string
          is_active?: boolean
          organism_group_id?: string | null
          row_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ast_microorganisms_organism_group_id_fkey"
            columns: ["organism_group_id"]
            isOneToOne: false
            referencedRelation: "ast_organism_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      ast_observation_audit: {
        Row: {
          action: string
          actor_id: string
          after_state: Json
          before_state: Json | null
          created_at: string
          id: string
          isolate_id: string
          observation_id: string | null
          reason: string | null
        }
        Insert: {
          action: string
          actor_id: string
          after_state: Json
          before_state?: Json | null
          created_at?: string
          id?: string
          isolate_id: string
          observation_id?: string | null
          reason?: string | null
        }
        Update: {
          action?: string
          actor_id?: string
          after_state?: Json
          before_state?: Json | null
          created_at?: string
          id?: string
          isolate_id?: string
          observation_id?: string | null
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ast_observation_audit_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_observation_audit_isolate_id_fkey"
            columns: ["isolate_id"]
            isOneToOne: false
            referencedRelation: "ast_isolates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_observation_audit_observation_id_fkey"
            columns: ["observation_id"]
            isOneToOne: false
            referencedRelation: "ast_observations"
            referencedColumns: ["id"]
          },
        ]
      }
      ast_observations: {
        Row: {
          actor_id: string
          antibiotic_code_snapshot: string
          antibiotic_id: string
          antibiotic_name_snapshot: string
          automatic_interpretation: string | null
          breakpoint_rule_id: string | null
          breakpoint_set_id: string | null
          breakpoint_set_version_snapshot: string | null
          created_at: string
          final_interpretation: string
          id: string
          isolate_id: string
          manual_override: boolean
          method: string
          metric_secondary_value: number | null
          metric_type: string
          metric_value: number
          override_reason: string | null
          row_version: number
          updated_at: string
        }
        Insert: {
          actor_id: string
          antibiotic_code_snapshot: string
          antibiotic_id: string
          antibiotic_name_snapshot: string
          automatic_interpretation?: string | null
          breakpoint_rule_id?: string | null
          breakpoint_set_id?: string | null
          breakpoint_set_version_snapshot?: string | null
          created_at?: string
          final_interpretation: string
          id?: string
          isolate_id: string
          manual_override?: boolean
          method: string
          metric_secondary_value?: number | null
          metric_type: string
          metric_value: number
          override_reason?: string | null
          row_version?: number
          updated_at?: string
        }
        Update: {
          actor_id?: string
          antibiotic_code_snapshot?: string
          antibiotic_id?: string
          antibiotic_name_snapshot?: string
          automatic_interpretation?: string | null
          breakpoint_rule_id?: string | null
          breakpoint_set_id?: string | null
          breakpoint_set_version_snapshot?: string | null
          created_at?: string
          final_interpretation?: string
          id?: string
          isolate_id?: string
          manual_override?: boolean
          method?: string
          metric_secondary_value?: number | null
          metric_type?: string
          metric_value?: number
          override_reason?: string | null
          row_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ast_observations_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_observations_antibiotic_id_fkey"
            columns: ["antibiotic_id"]
            isOneToOne: false
            referencedRelation: "ast_antibiotics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_observations_breakpoint_rule_id_fkey"
            columns: ["breakpoint_rule_id"]
            isOneToOne: false
            referencedRelation: "ast_breakpoint_rules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_observations_breakpoint_set_id_fkey"
            columns: ["breakpoint_set_id"]
            isOneToOne: false
            referencedRelation: "ast_breakpoint_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ast_observations_isolate_id_fkey"
            columns: ["isolate_id"]
            isOneToOne: false
            referencedRelation: "ast_isolates"
            referencedColumns: ["id"]
          },
        ]
      }
      ast_organism_groups: {
        Row: {
          code: string
          created_at: string
          display_name: string
          id: string
          is_active: boolean
          row_version: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          display_name: string
          id?: string
          is_active?: boolean
          row_version?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          display_name?: string
          id?: string
          is_active?: boolean
          row_version?: number
          updated_at?: string
        }
        Relationships: []
      }
      audit_logs: {
        Row: {
          action: string
          entity_id: string
          entity_type: string
          id: string
          ip_address: string | null
          new_data: Json | null
          old_data: Json | null
          timestamp: string
          user_agent: string | null
          user_id: string | null
          user_name: string | null
        }
        Insert: {
          action: string
          entity_id: string
          entity_type: string
          id?: string
          ip_address?: string | null
          new_data?: Json | null
          old_data?: Json | null
          timestamp?: string
          user_agent?: string | null
          user_id?: string | null
          user_name?: string | null
        }
        Update: {
          action?: string
          entity_id?: string
          entity_type?: string
          id?: string
          ip_address?: string | null
          new_data?: Json | null
          old_data?: Json | null
          timestamp?: string
          user_agent?: string | null
          user_id?: string | null
          user_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      bill_items: {
        Row: {
          bill_id: string
          catalogue_price_paisa_snapshot: number | null
          created_at: string
          discount_paisa: number
          id: string
          item_description: string | null
          net_price_paisa: number
          outsource_lab_name: string | null
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          test_code_snapshot: string
          test_id: string
          test_name_snapshot: string
          unit_price_paisa: number
        }
        Insert: {
          bill_id: string
          catalogue_price_paisa_snapshot?: number | null
          created_at?: string
          discount_paisa?: number
          id?: string
          item_description?: string | null
          net_price_paisa: number
          outsource_lab_name?: string | null
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          test_code_snapshot: string
          test_id: string
          test_name_snapshot: string
          unit_price_paisa: number
        }
        Update: {
          bill_id?: string
          catalogue_price_paisa_snapshot?: number | null
          created_at?: string
          discount_paisa?: number
          id?: string
          item_description?: string | null
          net_price_paisa?: number
          outsource_lab_name?: string | null
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          test_code_snapshot?: string
          test_id?: string
          test_name_snapshot?: string
          unit_price_paisa?: number
        }
        Relationships: [
          {
            foreignKeyName: "bill_items_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
        ]
      }
      bill_package_components: {
        Row: {
          bill_item_id: string
          bill_package_selection_id: string
          test_id: string
        }
        Insert: {
          bill_item_id: string
          bill_package_selection_id: string
          test_id: string
        }
        Update: {
          bill_item_id?: string
          bill_package_selection_id?: string
          test_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "bill_package_components_bill_item_id_fkey"
            columns: ["bill_item_id"]
            isOneToOne: false
            referencedRelation: "bill_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_package_components_bill_package_selection_id_fkey"
            columns: ["bill_package_selection_id"]
            isOneToOne: false
            referencedRelation: "bill_package_selections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_package_components_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "bill_package_components_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      bill_package_selections: {
        Row: {
          bill_id: string
          catalogue_package_price_paisa: number | null
          created_at: string
          id: string
          package_code_snapshot: string
          package_id: string
          package_name_snapshot: string
          package_price_paisa: number
        }
        Insert: {
          bill_id: string
          catalogue_package_price_paisa?: number | null
          created_at?: string
          id?: string
          package_code_snapshot: string
          package_id: string
          package_name_snapshot: string
          package_price_paisa: number
        }
        Update: {
          bill_id?: string
          catalogue_package_price_paisa?: number | null
          created_at?: string
          id?: string
          package_code_snapshot?: string
          package_id?: string
          package_name_snapshot?: string
          package_price_paisa?: number
        }
        Relationships: [
          {
            foreignKeyName: "bill_package_selections_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_package_selections_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "health_packages"
            referencedColumns: ["id"]
          },
        ]
      }
      bill_panel_components: {
        Row: {
          bill_item_id: string
          bill_panel_selection_id: string
          display_order: number
          test_id: string
        }
        Insert: {
          bill_item_id: string
          bill_panel_selection_id: string
          display_order: number
          test_id: string
        }
        Update: {
          bill_item_id?: string
          bill_panel_selection_id?: string
          display_order?: number
          test_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "bill_panel_components_bill_item_id_fkey"
            columns: ["bill_item_id"]
            isOneToOne: false
            referencedRelation: "bill_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_panel_components_bill_panel_selection_id_fkey"
            columns: ["bill_panel_selection_id"]
            isOneToOne: false
            referencedRelation: "bill_panel_selections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_panel_components_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "bill_panel_components_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      bill_panel_selections: {
        Row: {
          bill_id: string
          catalogue_panel_price_paisa: number | null
          component_snapshot: Json
          created_at: string
          id: string
          panel_id: string
          panel_name_snapshot: string
          panel_price_paisa: number
          panel_service_id: string
          rate_version_id: string
          service_code_snapshot: string
        }
        Insert: {
          bill_id: string
          catalogue_panel_price_paisa?: number | null
          component_snapshot: Json
          created_at?: string
          id?: string
          panel_id: string
          panel_name_snapshot: string
          panel_price_paisa: number
          panel_service_id: string
          rate_version_id: string
          service_code_snapshot: string
        }
        Update: {
          bill_id?: string
          catalogue_panel_price_paisa?: number | null
          component_snapshot?: Json
          created_at?: string
          id?: string
          panel_id?: string
          panel_name_snapshot?: string
          panel_price_paisa?: number
          panel_service_id?: string
          rate_version_id?: string
          service_code_snapshot?: string
        }
        Relationships: [
          {
            foreignKeyName: "bill_panel_selections_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_panel_selections_panel_id_fkey"
            columns: ["panel_id"]
            isOneToOne: false
            referencedRelation: "catalogue_panels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_panel_selections_panel_service_id_fkey"
            columns: ["panel_service_id"]
            isOneToOne: false
            referencedRelation: "catalogue_panel_services"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bill_panel_selections_rate_version_id_fkey"
            columns: ["rate_version_id"]
            isOneToOne: false
            referencedRelation: "catalogue_rate_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_idempotency_requests: {
        Row: {
          caller_id: string
          completed_at: string | null
          created_at: string
          idempotency_key: string
          request_hash: string
          response_json: Json | null
        }
        Insert: {
          caller_id: string
          completed_at?: string | null
          created_at?: string
          idempotency_key: string
          request_hash: string
          response_json?: Json | null
        }
        Update: {
          caller_id?: string
          completed_at?: string | null
          created_at?: string
          idempotency_key?: string
          request_hash?: string
          response_json?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "billing_idempotency_requests_caller_id_fkey"
            columns: ["caller_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      bills: {
        Row: {
          bill_number: string
          created_at: string
          created_by: string | null
          discount_amount_paisa: number
          discount_reason: string | null
          due_amount_paisa: number
          gross_amount_paisa: number
          id: string
          net_amount_paisa: number
          paid_amount_paisa: number
          patient_age_gender_snapshot: string
          patient_id: string
          patient_mobile_snapshot: string
          patient_name_snapshot: string
          patient_uhid_snapshot: string
          payment_status: Database["public"]["Enums"]["payment_status_enum"]
          referring_doctor_id: string | null
          referring_doctor_name_snapshot: string | null
          remarks: string | null
          updated_at: string
        }
        Insert: {
          bill_number: string
          created_at?: string
          created_by?: string | null
          discount_amount_paisa?: number
          discount_reason?: string | null
          due_amount_paisa?: number
          gross_amount_paisa: number
          id?: string
          net_amount_paisa: number
          paid_amount_paisa?: number
          patient_age_gender_snapshot: string
          patient_id: string
          patient_mobile_snapshot: string
          patient_name_snapshot: string
          patient_uhid_snapshot: string
          payment_status?: Database["public"]["Enums"]["payment_status_enum"]
          referring_doctor_id?: string | null
          referring_doctor_name_snapshot?: string | null
          remarks?: string | null
          updated_at?: string
        }
        Update: {
          bill_number?: string
          created_at?: string
          created_by?: string | null
          discount_amount_paisa?: number
          discount_reason?: string | null
          due_amount_paisa?: number
          gross_amount_paisa?: number
          id?: string
          net_amount_paisa?: number
          paid_amount_paisa?: number
          patient_age_gender_snapshot?: string
          patient_id?: string
          patient_mobile_snapshot?: string
          patient_name_snapshot?: string
          patient_uhid_snapshot?: string
          payment_status?: Database["public"]["Enums"]["payment_status_enum"]
          referring_doctor_id?: string | null
          referring_doctor_name_snapshot?: string | null
          remarks?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bills_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bills_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bills_referring_doctor_id_fkey"
            columns: ["referring_doctor_id"]
            isOneToOne: false
            referencedRelation: "referring_doctors"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_calculation_definitions: {
        Row: {
          identifier: string
          implementation_note: string
          is_active: boolean
          parameter_code: string
          server_authoritative: boolean
        }
        Insert: {
          identifier: string
          implementation_note: string
          is_active?: boolean
          parameter_code: string
          server_authoritative?: boolean
        }
        Update: {
          identifier?: string
          implementation_note?: string
          is_active?: boolean
          parameter_code?: string
          server_authoritative?: boolean
        }
        Relationships: []
      }
      catalogue_configuration_evidence: {
        Row: {
          actor_id: string
          actor_role: string
          category: string
          configuration_version: number
          created_at: string
          id: string
          new_state: Json
          previous_state: Json | null
          reason: string
          source_metadata: Json
          status: Database["public"]["Enums"]["catalogue_decision_status_enum"]
          test_id: string
        }
        Insert: {
          actor_id: string
          actor_role: string
          category: string
          configuration_version: number
          created_at?: string
          id?: string
          new_state?: Json
          previous_state?: Json | null
          reason: string
          source_metadata?: Json
          status: Database["public"]["Enums"]["catalogue_decision_status_enum"]
          test_id: string
        }
        Update: {
          actor_id?: string
          actor_role?: string
          category?: string
          configuration_version?: number
          created_at?: string
          id?: string
          new_state?: Json
          previous_state?: Json | null
          reason?: string
          source_metadata?: Json
          status?: Database["public"]["Enums"]["catalogue_decision_status_enum"]
          test_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_configuration_evidence_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_configuration_evidence_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_configuration_evidence_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_identity_conflicts: {
        Row: {
          canonical_code: string | null
          conflict_key: string
          created_at: string
          id: string
          recommendation: string
          resolution: Json | null
          resolved_at: string | null
          resolved_by: string | null
          source_numbers: number[]
          status: string
          title: string
        }
        Insert: {
          canonical_code?: string | null
          conflict_key: string
          created_at?: string
          id?: string
          recommendation: string
          resolution?: Json | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_numbers: number[]
          status?: string
          title: string
        }
        Update: {
          canonical_code?: string | null
          conflict_key?: string
          created_at?: string
          id?: string
          recommendation?: string
          resolution?: Json | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_numbers?: number[]
          status?: string
          title?: string
        }
        Relationships: []
      }
      catalogue_master_source_rows: {
        Row: {
          canonical_code: string | null
          canonical_department: string
          canonical_parameter_id: string | null
          canonical_test_id: string | null
          conflict_id: string | null
          disposition: Database["public"]["Enums"]["catalogue_source_disposition_enum"]
          provenance: Json
          reporting_model: Database["public"]["Enums"]["catalogue_reporting_model_enum"]
          source_alias: string | null
          source_department: string
          source_id: string
          source_name: string
          source_number: number
          source_type: string
        }
        Insert: {
          canonical_code?: string | null
          canonical_department: string
          canonical_parameter_id?: string | null
          canonical_test_id?: string | null
          conflict_id?: string | null
          disposition: Database["public"]["Enums"]["catalogue_source_disposition_enum"]
          provenance: Json
          reporting_model: Database["public"]["Enums"]["catalogue_reporting_model_enum"]
          source_alias?: string | null
          source_department: string
          source_id: string
          source_name: string
          source_number: number
          source_type: string
        }
        Update: {
          canonical_code?: string | null
          canonical_department?: string
          canonical_parameter_id?: string | null
          canonical_test_id?: string | null
          conflict_id?: string | null
          disposition?: Database["public"]["Enums"]["catalogue_source_disposition_enum"]
          provenance?: Json
          reporting_model?: Database["public"]["Enums"]["catalogue_reporting_model_enum"]
          source_alias?: string | null
          source_department?: string
          source_id?: string
          source_name?: string
          source_number?: number
          source_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_master_source_rows_canonical_parameter_id_fkey"
            columns: ["canonical_parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "catalogue_master_source_rows_canonical_parameter_id_fkey"
            columns: ["canonical_parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_master_source_rows_canonical_test_id_fkey"
            columns: ["canonical_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_master_source_rows_canonical_test_id_fkey"
            columns: ["canonical_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_master_source_rows_conflict_id_fkey"
            columns: ["conflict_id"]
            isOneToOne: false
            referencedRelation: "catalogue_identity_conflicts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_master_source_rows_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "catalogue_master_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_master_sources: {
        Row: {
          id: string
          imported_at: string
          source_name: string
          source_row_count: number
          source_sha256: string
          source_version: string
        }
        Insert: {
          id: string
          imported_at?: string
          source_name: string
          source_row_count: number
          source_sha256: string
          source_version: string
        }
        Update: {
          id?: string
          imported_at?: string
          source_name?: string
          source_row_count?: number
          source_sha256?: string
          source_version?: string
        }
        Relationships: []
      }
      catalogue_option_sets: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          code: string
          created_at: string
          id: string
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          row_version: number
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          code: string
          created_at?: string
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          row_version?: number
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          code?: string
          created_at?: string
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name?: string
          row_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_option_sets_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_option_values: {
        Row: {
          created_at: string
          display_order: number
          id: string
          is_active: boolean
          label: string
          option_set_id: string
          row_version: number
          updated_at: string
          value_code: string
        }
        Insert: {
          created_at?: string
          display_order: number
          id?: string
          is_active?: boolean
          label: string
          option_set_id: string
          row_version?: number
          updated_at?: string
          value_code: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          label?: string
          option_set_id?: string
          row_version?: number
          updated_at?: string
          value_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_option_values_option_set_id_fkey"
            columns: ["option_set_id"]
            isOneToOne: false
            referencedRelation: "catalogue_option_sets"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_panel_components: {
        Row: {
          component_parameter_id: string | null
          component_test_id: string | null
          display_name: string
          display_order: number
          panel_id: string
          unresolved_reason: string | null
        }
        Insert: {
          component_parameter_id?: string | null
          component_test_id?: string | null
          display_name: string
          display_order: number
          panel_id: string
          unresolved_reason?: string | null
        }
        Update: {
          component_parameter_id?: string | null
          component_test_id?: string | null
          display_name?: string
          display_order?: number
          panel_id?: string
          unresolved_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_panel_components_component_parameter_id_fkey"
            columns: ["component_parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "catalogue_panel_components_component_parameter_id_fkey"
            columns: ["component_parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_components_component_test_id_fkey"
            columns: ["component_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_panel_components_component_test_id_fkey"
            columns: ["component_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_components_panel_id_fkey"
            columns: ["panel_id"]
            isOneToOne: false
            referencedRelation: "catalogue_panels"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_panel_identity_resolution: {
        Row: {
          canonical_test_id: string | null
          identity_kind: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          package_id: string | null
          panel_id: string
          panel_service_id: string | null
        }
        Insert: {
          canonical_test_id?: string | null
          identity_kind: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          package_id?: string | null
          panel_id: string
          panel_service_id?: string | null
        }
        Update: {
          canonical_test_id?: string | null
          identity_kind?: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          package_id?: string | null
          panel_id?: string
          panel_service_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_panel_identity_resolution_canonical_test_id_fkey"
            columns: ["canonical_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_panel_identity_resolution_canonical_test_id_fkey"
            columns: ["canonical_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_identity_resolution_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "health_packages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_identity_resolution_panel_id_fkey"
            columns: ["panel_id"]
            isOneToOne: true
            referencedRelation: "catalogue_panels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_identity_resolution_panel_service_id_fkey"
            columns: ["panel_service_id"]
            isOneToOne: false
            referencedRelation: "catalogue_panel_services"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_panel_ratelist_links: {
        Row: {
          health_package_id: string | null
          operator_rate_npr: number | null
          panel_id: string
          ratelist_name: string
        }
        Insert: {
          health_package_id?: string | null
          operator_rate_npr?: number | null
          panel_id: string
          ratelist_name: string
        }
        Update: {
          health_package_id?: string | null
          operator_rate_npr?: number | null
          panel_id?: string
          ratelist_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_panel_ratelist_links_health_package_id_fkey"
            columns: ["health_package_id"]
            isOneToOne: false
            referencedRelation: "health_packages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_ratelist_links_panel_id_fkey"
            columns: ["panel_id"]
            isOneToOne: false
            referencedRelation: "catalogue_panels"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_panel_services: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          category_id: string
          code: string
          collection_required: boolean
          container: string | null
          created_at: string
          id: string
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          panel_id: string
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          row_version: number
          specimen: string | null
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          category_id: string
          code: string
          collection_required?: boolean
          container?: string | null
          created_at?: string
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          panel_id: string
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          row_version?: number
          specimen?: string | null
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          category_id?: string
          code?: string
          collection_required?: boolean
          container?: string | null
          created_at?: string
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name?: string
          panel_id?: string
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          row_version?: number
          specimen?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_panel_services_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_services_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "test_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panel_services_panel_id_fkey"
            columns: ["panel_id"]
            isOneToOne: true
            referencedRelation: "catalogue_panels"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_panels: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          category_id: string
          clinical_notes: string | null
          clinical_reporting_enabled: boolean
          code: string
          created_at: string
          display_order: number
          hide_component_interpretation: boolean
          id: string
          interpretation_notes: string[]
          interpretation_rows: Json
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          row_version: number
          show_component_method_instrument: boolean
          updated_at: string
          workflow_supported: boolean
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          category_id: string
          clinical_notes?: string | null
          clinical_reporting_enabled?: boolean
          code: string
          created_at?: string
          display_order?: number
          hide_component_interpretation?: boolean
          id?: string
          interpretation_notes?: string[]
          interpretation_rows?: Json
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          row_version?: number
          show_component_method_instrument?: boolean
          updated_at?: string
          workflow_supported?: boolean
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          category_id?: string
          clinical_notes?: string | null
          clinical_reporting_enabled?: boolean
          code?: string
          created_at?: string
          display_order?: number
          hide_component_interpretation?: boolean
          id?: string
          interpretation_notes?: string[]
          interpretation_rows?: Json
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name?: string
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          row_version?: number
          show_component_method_instrument?: boolean
          updated_at?: string
          workflow_supported?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_panels_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_panels_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "test_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_profile_components: {
        Row: {
          component_parameter_id: string | null
          component_role: string
          component_test_id: string | null
          display_order: number
          is_required: boolean
          profile_test_id: string
          source_numbers: number[]
        }
        Insert: {
          component_parameter_id?: string | null
          component_role: string
          component_test_id?: string | null
          display_order: number
          is_required?: boolean
          profile_test_id: string
          source_numbers?: number[]
        }
        Update: {
          component_parameter_id?: string | null
          component_role?: string
          component_test_id?: string | null
          display_order?: number
          is_required?: boolean
          profile_test_id?: string
          source_numbers?: number[]
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_profile_components_component_parameter_id_fkey"
            columns: ["component_parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "catalogue_profile_components_component_parameter_id_fkey"
            columns: ["component_parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_profile_components_component_test_id_fkey"
            columns: ["component_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_profile_components_component_test_id_fkey"
            columns: ["component_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_profile_components_profile_test_id_fkey"
            columns: ["profile_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_profile_components_profile_test_id_fkey"
            columns: ["profile_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_rate_versions: {
        Row: {
          created_at: string
          created_by: string | null
          effective_from: string | null
          effective_to: string | null
          entity_type: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          id: string
          other_service_code: string | null
          package_id: string | null
          panel_service_id: string | null
          price_paisa: number | null
          row_version: number
          status: Database["public"]["Enums"]["catalogue_rate_status_enum"]
          test_id: string | null
          updated_at: string
          version_number: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_to?: string | null
          entity_type: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          id?: string
          other_service_code?: string | null
          package_id?: string | null
          panel_service_id?: string | null
          price_paisa?: number | null
          row_version?: number
          status?: Database["public"]["Enums"]["catalogue_rate_status_enum"]
          test_id?: string | null
          updated_at?: string
          version_number: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_to?: string | null
          entity_type?: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          id?: string
          other_service_code?: string | null
          package_id?: string | null
          panel_service_id?: string | null
          price_paisa?: number | null
          row_version?: number
          status?: Database["public"]["Enums"]["catalogue_rate_status_enum"]
          test_id?: string | null
          updated_at?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_rate_versions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_rate_versions_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "health_packages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_rate_versions_panel_service_id_fkey"
            columns: ["panel_service_id"]
            isOneToOne: false
            referencedRelation: "catalogue_panel_services"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_rate_versions_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_rate_versions_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_result_structure_reconciliation: {
        Row: {
          action_code: string
          created_at: string
          final_readiness: Database["public"]["Enums"]["catalogue_result_readiness_enum"]
          historical_zero_parameter_inventory: boolean
          notes: string
          parameters_materialized: number
          source_evidence: string
          test_id: string
        }
        Insert: {
          action_code: string
          created_at?: string
          final_readiness: Database["public"]["Enums"]["catalogue_result_readiness_enum"]
          historical_zero_parameter_inventory: boolean
          notes: string
          parameters_materialized?: number
          source_evidence: string
          test_id: string
        }
        Update: {
          action_code?: string
          created_at?: string
          final_readiness?: Database["public"]["Enums"]["catalogue_result_readiness_enum"]
          historical_zero_parameter_inventory?: boolean
          notes?: string
          parameters_materialized?: number
          source_evidence?: string
          test_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_result_structure_reconciliation_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: true
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_result_structure_reconciliation_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: true
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_service_readiness: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          configuration_version: number
          created_at: string
          decision_reason: string | null
          state: Database["public"]["Enums"]["catalogue_readiness_state_enum"]
          submitted_at: string | null
          submitted_by: string | null
          suspended_at: string | null
          suspended_by: string | null
          test_id: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          configuration_version?: number
          created_at?: string
          decision_reason?: string | null
          state?: Database["public"]["Enums"]["catalogue_readiness_state_enum"]
          submitted_at?: string | null
          submitted_by?: string | null
          suspended_at?: string | null
          suspended_by?: string | null
          test_id: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          configuration_version?: number
          created_at?: string
          decision_reason?: string | null
          state?: Database["public"]["Enums"]["catalogue_readiness_state_enum"]
          submitted_at?: string | null
          submitted_by?: string | null
          suspended_at?: string | null
          suspended_by?: string | null
          test_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_service_readiness_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_service_readiness_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_service_readiness_suspended_by_fkey"
            columns: ["suspended_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_service_readiness_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: true
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_service_readiness_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: true
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_test_database_entries: {
        Row: {
          canonical_parameter_id: string | null
          category_id: string
          configuration_test_id: string
          created_at: string
          is_operator_approved: boolean
          operator_category: string
          short_name: string | null
          source_order: number
          test_name: string
          test_type: string
        }
        Insert: {
          canonical_parameter_id?: string | null
          category_id: string
          configuration_test_id: string
          created_at?: string
          is_operator_approved?: boolean
          operator_category: string
          short_name?: string | null
          source_order: number
          test_name: string
          test_type: string
        }
        Update: {
          canonical_parameter_id?: string | null
          category_id?: string
          configuration_test_id?: string
          created_at?: string
          is_operator_approved?: boolean
          operator_category?: string
          short_name?: string | null
          source_order?: number
          test_name?: string
          test_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_test_database_entries_canonical_parameter_id_fkey"
            columns: ["canonical_parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "catalogue_test_database_entries_canonical_parameter_id_fkey"
            columns: ["canonical_parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_test_database_entries_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "test_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_test_database_entries_configuration_test_id_fkey"
            columns: ["configuration_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_test_database_entries_configuration_test_id_fkey"
            columns: ["configuration_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogue_test_template_drafts: {
        Row: {
          created_at: string
          created_by: string
          id: string
          proposed_code: string | null
          proposed_name: string | null
          revision: number
          technical_configuration: Json
          template_source_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          proposed_code?: string | null
          proposed_name?: string | null
          revision?: number
          technical_configuration?: Json
          template_source_order: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          proposed_code?: string | null
          proposed_name?: string | null
          revision?: number
          technical_configuration?: Json
          template_source_order?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_test_template_drafts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_test_template_drafts_template_source_order_fkey"
            columns: ["template_source_order"]
            isOneToOne: false
            referencedRelation: "catalogue_test_templates"
            referencedColumns: ["source_order"]
          },
        ]
      }
      catalogue_test_templates: {
        Row: {
          canonical_parameter_id: string | null
          configuration_test_id: string
          created_at: string
          is_operator_approved: boolean
          source_order: number
          supplied_name: string
          test_database_source_order: number
        }
        Insert: {
          canonical_parameter_id?: string | null
          configuration_test_id: string
          created_at?: string
          is_operator_approved?: boolean
          source_order: number
          supplied_name: string
          test_database_source_order: number
        }
        Update: {
          canonical_parameter_id?: string | null
          configuration_test_id?: string
          created_at?: string
          is_operator_approved?: boolean
          source_order?: number
          supplied_name?: string
          test_database_source_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "catalogue_test_templates_canonical_parameter_id_fkey"
            columns: ["canonical_parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "catalogue_test_templates_canonical_parameter_id_fkey"
            columns: ["canonical_parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_test_templates_configuration_test_id_fkey"
            columns: ["configuration_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "catalogue_test_templates_configuration_test_id_fkey"
            columns: ["configuration_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "catalogue_test_templates_test_database_source_order_fkey"
            columns: ["test_database_source_order"]
            isOneToOne: true
            referencedRelation: "catalogue_test_database_entries"
            referencedColumns: ["source_order"]
          },
        ]
      }
      clinical_calculation_consistency_checks: {
        Row: {
          absolute_difference: number
          calculated_expected_value: number
          calculated_unit: string
          calculation_run_id: string
          checked_at: string
          disposition: string
          id: string
          measured_result_id: string
          measured_unit: string
          measured_value: number
          percent_difference: number | null
          tolerance_version_id: string | null
        }
        Insert: {
          absolute_difference: number
          calculated_expected_value: number
          calculated_unit: string
          calculation_run_id: string
          checked_at?: string
          disposition: string
          id?: string
          measured_result_id: string
          measured_unit: string
          measured_value: number
          percent_difference?: number | null
          tolerance_version_id?: string | null
        }
        Update: {
          absolute_difference?: number
          calculated_expected_value?: number
          calculated_unit?: string
          calculation_run_id?: string
          checked_at?: string
          disposition?: string
          id?: string
          measured_result_id?: string
          measured_unit?: string
          measured_value?: number
          percent_difference?: number | null
          tolerance_version_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clinical_calculation_consistency_chec_tolerance_version_id_fkey"
            columns: ["tolerance_version_id"]
            isOneToOne: false
            referencedRelation: "clinical_calculation_tolerance_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_consistency_checks_calculation_run_id_fkey"
            columns: ["calculation_run_id"]
            isOneToOne: true
            referencedRelation: "clinical_calculation_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_consistency_checks_measured_result_id_fkey"
            columns: ["measured_result_id"]
            isOneToOne: false
            referencedRelation: "test_results"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_calculation_formula_inputs: {
        Row: {
          canonical_unit: string
          compatibility_rule: Json
          formula_version_id: string
          input_key: string
          is_required: boolean
          missing_input_behavior: string
          ordinal: number
          parameter_code: string
          parameter_id: string | null
          source_identifier: string | null
          source_type: string
        }
        Insert: {
          canonical_unit: string
          compatibility_rule?: Json
          formula_version_id: string
          input_key: string
          is_required?: boolean
          missing_input_behavior?: string
          ordinal: number
          parameter_code: string
          parameter_id?: string | null
          source_identifier?: string | null
          source_type?: string
        }
        Update: {
          canonical_unit?: string
          compatibility_rule?: Json
          formula_version_id?: string
          input_key?: string
          is_required?: boolean
          missing_input_behavior?: string
          ordinal?: number
          parameter_code?: string
          parameter_id?: string | null
          source_identifier?: string | null
          source_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "clinical_calculation_formula_inputs_formula_version_id_fkey"
            columns: ["formula_version_id"]
            isOneToOne: false
            referencedRelation: "clinical_calculation_formula_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_formula_inputs_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "clinical_calculation_formula_inputs_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_calculation_formula_versions: {
        Row: {
          approval_authority: string
          approval_reason: string | null
          approved_at: string | null
          approved_by: string | null
          calculation_mode: string
          catalogue_configuration_version: number | null
          created_at: string
          definition_hash: string
          effective_from: string | null
          effective_to: string | null
          execution_order: number
          formula_expression: string
          formula_identifier: string
          formula_key: string
          formula_version: number
          id: string
          lifecycle_status: string
          output_parameter_code: string
          output_parameter_id: string | null
          output_unit: string
          rounding_mode: string | null
          rounding_scale: number | null
          scope_test_id: string | null
          source_provenance: string
        }
        Insert: {
          approval_authority?: string
          approval_reason?: string | null
          approved_at?: string | null
          approved_by?: string | null
          calculation_mode: string
          catalogue_configuration_version?: number | null
          created_at?: string
          definition_hash: string
          effective_from?: string | null
          effective_to?: string | null
          execution_order?: number
          formula_expression: string
          formula_identifier: string
          formula_key: string
          formula_version: number
          id?: string
          lifecycle_status?: string
          output_parameter_code: string
          output_parameter_id?: string | null
          output_unit: string
          rounding_mode?: string | null
          rounding_scale?: number | null
          scope_test_id?: string | null
          source_provenance: string
        }
        Update: {
          approval_authority?: string
          approval_reason?: string | null
          approved_at?: string | null
          approved_by?: string | null
          calculation_mode?: string
          catalogue_configuration_version?: number | null
          created_at?: string
          definition_hash?: string
          effective_from?: string | null
          effective_to?: string | null
          execution_order?: number
          formula_expression?: string
          formula_identifier?: string
          formula_key?: string
          formula_version?: number
          id?: string
          lifecycle_status?: string
          output_parameter_code?: string
          output_parameter_id?: string | null
          output_unit?: string
          rounding_mode?: string | null
          rounding_scale?: number | null
          scope_test_id?: string | null
          source_provenance?: string
        }
        Relationships: [
          {
            foreignKeyName: "clinical_calculation_formula_versions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_formula_versions_output_parameter_id_fkey"
            columns: ["output_parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "clinical_calculation_formula_versions_output_parameter_id_fkey"
            columns: ["output_parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_formula_versions_scope_test_id_fkey"
            columns: ["scope_test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "clinical_calculation_formula_versions_scope_test_id_fkey"
            columns: ["scope_test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_calculation_runs: {
        Row: {
          calculated_at: string
          calculated_raw_value: number | null
          calculation_status: string
          dependency_revision_hash: string | null
          displayed_value: string | null
          error_code: string | null
          formula_snapshot: Json
          formula_version_id: string
          id: string
          input_snapshot: Json
          order_item_id: string
          output_result_id: string | null
          output_unit: string
          rounding_rule: Json
          source_result_revision: number
        }
        Insert: {
          calculated_at?: string
          calculated_raw_value?: number | null
          calculation_status: string
          dependency_revision_hash?: string | null
          displayed_value?: string | null
          error_code?: string | null
          formula_snapshot: Json
          formula_version_id: string
          id?: string
          input_snapshot: Json
          order_item_id: string
          output_result_id?: string | null
          output_unit: string
          rounding_rule: Json
          source_result_revision: number
        }
        Update: {
          calculated_at?: string
          calculated_raw_value?: number | null
          calculation_status?: string
          dependency_revision_hash?: string | null
          displayed_value?: string | null
          error_code?: string | null
          formula_snapshot?: Json
          formula_version_id?: string
          id?: string
          input_snapshot?: Json
          order_item_id?: string
          output_result_id?: string | null
          output_unit?: string
          rounding_rule?: Json
          source_result_revision?: number
        }
        Relationships: [
          {
            foreignKeyName: "clinical_calculation_runs_formula_version_id_fkey"
            columns: ["formula_version_id"]
            isOneToOne: false
            referencedRelation: "clinical_calculation_formula_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_runs_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "clinical_order_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_runs_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["order_item_id"]
          },
          {
            foreignKeyName: "clinical_calculation_runs_output_result_id_fkey"
            columns: ["output_result_id"]
            isOneToOne: false
            referencedRelation: "test_results"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_calculation_tolerance_versions: {
        Row: {
          approved_at: string
          approved_by: string
          behavior: string
          effective_from: string
          effective_to: string | null
          formula_version_id: string
          id: string
          reason: string
          tolerance_kind: string
          tolerance_value: number
          version: number
        }
        Insert: {
          approved_at: string
          approved_by: string
          behavior: string
          effective_from: string
          effective_to?: string | null
          formula_version_id: string
          id?: string
          reason: string
          tolerance_kind: string
          tolerance_value: number
          version: number
        }
        Update: {
          approved_at?: string
          approved_by?: string
          behavior?: string
          effective_from?: string
          effective_to?: string | null
          formula_version_id?: string
          id?: string
          reason?: string
          tolerance_kind?: string
          tolerance_value?: number
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "clinical_calculation_tolerance_versions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_calculation_tolerance_versions_formula_version_id_fkey"
            columns: ["formula_version_id"]
            isOneToOne: false
            referencedRelation: "clinical_calculation_formula_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_order_items: {
        Row: {
          bill_item_id: string
          clinical_reporting_enabled: boolean
          collection_required: boolean
          container_type: string
          created_at: string
          department: string
          execution_route: Database["public"]["Enums"]["clinical_execution_route_enum"]
          id: string
          order_id: string
          outsource_external_reference: string | null
          outsource_interpretation: string | null
          outsource_lab_name: string | null
          outsource_method: string | null
          outsource_result_payload: Json | null
          outsource_result_received_at: string | null
          outsource_result_received_by: string | null
          outsource_reviewed_at: string | null
          outsource_reviewed_by: string | null
          outsource_source_report_reference: string | null
          outsource_state:
            | Database["public"]["Enums"]["outsource_item_state_enum"]
            | null
          reference_laboratory_id: string | null
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          result_revision: number
          sample_id: string | null
          specimen_type: string
          status: string
          test_id: string
          test_name: string
          updated_at: string
          workflow_type: Database["public"]["Enums"]["clinical_workflow_type_enum"]
        }
        Insert: {
          bill_item_id: string
          clinical_reporting_enabled?: boolean
          collection_required?: boolean
          container_type: string
          created_at?: string
          department: string
          execution_route: Database["public"]["Enums"]["clinical_execution_route_enum"]
          id?: string
          order_id: string
          outsource_external_reference?: string | null
          outsource_interpretation?: string | null
          outsource_lab_name?: string | null
          outsource_method?: string | null
          outsource_result_payload?: Json | null
          outsource_result_received_at?: string | null
          outsource_result_received_by?: string | null
          outsource_reviewed_at?: string | null
          outsource_reviewed_by?: string | null
          outsource_source_report_reference?: string | null
          outsource_state?:
            | Database["public"]["Enums"]["outsource_item_state_enum"]
            | null
          reference_laboratory_id?: string | null
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          result_revision?: number
          sample_id?: string | null
          specimen_type: string
          status?: string
          test_id: string
          test_name: string
          updated_at?: string
          workflow_type?: Database["public"]["Enums"]["clinical_workflow_type_enum"]
        }
        Update: {
          bill_item_id?: string
          clinical_reporting_enabled?: boolean
          collection_required?: boolean
          container_type?: string
          created_at?: string
          department?: string
          execution_route?: Database["public"]["Enums"]["clinical_execution_route_enum"]
          id?: string
          order_id?: string
          outsource_external_reference?: string | null
          outsource_interpretation?: string | null
          outsource_lab_name?: string | null
          outsource_method?: string | null
          outsource_result_payload?: Json | null
          outsource_result_received_at?: string | null
          outsource_result_received_by?: string | null
          outsource_reviewed_at?: string | null
          outsource_reviewed_by?: string | null
          outsource_source_report_reference?: string | null
          outsource_state?:
            | Database["public"]["Enums"]["outsource_item_state_enum"]
            | null
          reference_laboratory_id?: string | null
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          result_revision?: number
          sample_id?: string | null
          specimen_type?: string
          status?: string
          test_id?: string
          test_name?: string
          updated_at?: string
          workflow_type?: Database["public"]["Enums"]["clinical_workflow_type_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "clinical_order_items_bill_item_id_fkey"
            columns: ["bill_item_id"]
            isOneToOne: false
            referencedRelation: "bill_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_order_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "clinical_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_order_items_reference_laboratory_id_fkey"
            columns: ["reference_laboratory_id"]
            isOneToOne: false
            referencedRelation: "reference_laboratories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_order_items_sample_id_fkey"
            columns: ["sample_id"]
            isOneToOne: false
            referencedRelation: "samples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_order_items_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "clinical_order_items_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_orders: {
        Row: {
          bill_id: string
          created_at: string
          id: string
          order_date_ad: string
          order_date_bs: string
          order_number: string
          patient_id: string
          status: string
          updated_at: string
        }
        Insert: {
          bill_id: string
          created_at?: string
          id?: string
          order_date_ad?: string
          order_date_bs: string
          order_number: string
          patient_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          bill_id?: string
          created_at?: string
          id?: string
          order_date_ad?: string
          order_date_bs?: string
          order_number?: string
          patient_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clinical_orders_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_orders_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_report_group_items: {
        Row: {
          created_at: string
          created_by: string
          display_order: number
          execution_route: Database["public"]["Enums"]["clinical_execution_route_enum"]
          frozen_reference_laboratory_id: string | null
          frozen_test_code: string
          frozen_test_name: string
          order_item_id: string
          report_group_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          display_order: number
          execution_route: Database["public"]["Enums"]["clinical_execution_route_enum"]
          frozen_reference_laboratory_id?: string | null
          frozen_test_code: string
          frozen_test_name: string
          order_item_id: string
          report_group_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          display_order?: number
          execution_route?: Database["public"]["Enums"]["clinical_execution_route_enum"]
          frozen_reference_laboratory_id?: string | null
          frozen_test_code?: string
          frozen_test_name?: string
          order_item_id?: string
          report_group_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "clinical_report_group_items_frozen_reference_laboratory_id_fkey"
            columns: ["frozen_reference_laboratory_id"]
            isOneToOne: false
            referencedRelation: "reference_laboratories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_report_group_items_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: true
            referencedRelation: "clinical_order_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_report_group_items_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: true
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["order_item_id"]
          },
          {
            foreignKeyName: "clinical_report_group_items_report_group_id_fkey"
            columns: ["report_group_id"]
            isOneToOne: false
            referencedRelation: "clinical_report_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_report_group_items_report_group_id_fkey"
            columns: ["report_group_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["report_group_id"]
          },
        ]
      }
      clinical_report_groups: {
        Row: {
          clinical_section: string
          configuration_version: number
          created_at: string
          created_by: string
          display_order: number
          group_key: string
          id: string
          lifecycle_state: string
          order_id: string
          row_version: number
          title: string
          updated_at: string
        }
        Insert: {
          clinical_section: string
          configuration_version: number
          created_at?: string
          created_by: string
          display_order: number
          group_key: string
          id?: string
          lifecycle_state?: string
          order_id: string
          row_version?: number
          title: string
          updated_at?: string
        }
        Update: {
          clinical_section?: string
          configuration_version?: number
          created_at?: string
          created_by?: string
          display_order?: number
          group_key?: string
          id?: string
          lifecycle_state?: string
          order_id?: string
          row_version?: number
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clinical_report_groups_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "clinical_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      clinical_source_decisions: {
        Row: {
          action: string
          approved_at: string | null
          approved_by: string | null
          decision_version: number
          id: string
          materialized_range_id: string | null
          reason: string
          reviewed_at: string
          reviewer_id: string
          row_version: number
          selected_policy: Json
          source_item_id: string
          status: string
        }
        Insert: {
          action: string
          approved_at?: string | null
          approved_by?: string | null
          decision_version: number
          id?: string
          materialized_range_id?: string | null
          reason: string
          reviewed_at?: string
          reviewer_id: string
          row_version?: number
          selected_policy?: Json
          source_item_id: string
          status?: string
        }
        Update: {
          action?: string
          approved_at?: string | null
          approved_by?: string | null
          decision_version?: number
          id?: string
          materialized_range_id?: string | null
          reason?: string
          reviewed_at?: string
          reviewer_id?: string
          row_version?: number
          selected_policy?: Json
          source_item_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "clinical_source_decisions_materialized_range_id_fkey"
            columns: ["materialized_range_id"]
            isOneToOne: false
            referencedRelation: "reference_ranges"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_source_decisions_source_item_id_fkey"
            columns: ["source_item_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_source_decisions_source_item_id_fkey"
            columns: ["source_item_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["source_item_id"]
          },
        ]
      }
      clinical_source_imports: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          provenance: string
          source_name: string
          source_received_on: string
          source_sha256: string
          source_version: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          provenance: string
          source_name: string
          source_received_on: string
          source_sha256: string
          source_version: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          provenance?: string
          source_name?: string
          source_received_on?: string
          source_sha256?: string
          source_version?: string
        }
        Relationships: []
      }
      clinical_source_items: {
        Row: {
          canonical_parameter: string
          conflict_key: string | null
          created_at: string
          id: string
          import_id: string
          normalized_representation: Json | null
          review_state: string
          row_version: number
          source_classification: string
          source_key: string
          source_note: string | null
          supplied_context: string
          supplied_unit: string | null
          supplied_value: string
          target_parameter_code: string | null
          target_test_code: string | null
        }
        Insert: {
          canonical_parameter: string
          conflict_key?: string | null
          created_at?: string
          id?: string
          import_id: string
          normalized_representation?: Json | null
          review_state?: string
          row_version?: number
          source_classification: string
          source_key: string
          source_note?: string | null
          supplied_context?: string
          supplied_unit?: string | null
          supplied_value: string
          target_parameter_code?: string | null
          target_test_code?: string | null
        }
        Update: {
          canonical_parameter?: string
          conflict_key?: string | null
          created_at?: string
          id?: string
          import_id?: string
          normalized_representation?: Json | null
          review_state?: string
          row_version?: number
          source_classification?: string
          source_key?: string
          source_note?: string | null
          supplied_context?: string
          supplied_unit?: string | null
          supplied_value?: string
          target_parameter_code?: string | null
          target_test_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clinical_source_items_import_id_fkey"
            columns: ["import_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_imports"
            referencedColumns: ["id"]
          },
        ]
      }
      diagnostic_reports: {
        Row: {
          amended_from_report_id: string | null
          amendment_reason: string | null
          clinical_snapshot_json: Json
          created_at: string
          id: string
          integrity_hash: string
          is_amendment: boolean
          order_id: string
          patient_id: string
          pdf_storage_path: string | null
          performed_by_personnel_id: string | null
          performed_by_personnel_name: string
          report_group_id: string | null
          report_number: string
          signed_at: string
          signed_by_personnel_id: string | null
          signed_by_personnel_name: string | null
          status: string
          updated_at: string
          verified_by_personnel_id: string | null
          verified_by_personnel_name: string | null
          version: number
        }
        Insert: {
          amended_from_report_id?: string | null
          amendment_reason?: string | null
          clinical_snapshot_json: Json
          created_at?: string
          id?: string
          integrity_hash: string
          is_amendment?: boolean
          order_id: string
          patient_id: string
          pdf_storage_path?: string | null
          performed_by_personnel_id?: string | null
          performed_by_personnel_name: string
          report_group_id?: string | null
          report_number: string
          signed_at?: string
          signed_by_personnel_id?: string | null
          signed_by_personnel_name?: string | null
          status?: string
          updated_at?: string
          verified_by_personnel_id?: string | null
          verified_by_personnel_name?: string | null
          version?: number
        }
        Update: {
          amended_from_report_id?: string | null
          amendment_reason?: string | null
          clinical_snapshot_json?: Json
          created_at?: string
          id?: string
          integrity_hash?: string
          is_amendment?: boolean
          order_id?: string
          patient_id?: string
          pdf_storage_path?: string | null
          performed_by_personnel_id?: string | null
          performed_by_personnel_name?: string
          report_group_id?: string | null
          report_number?: string
          signed_at?: string
          signed_by_personnel_id?: string | null
          signed_by_personnel_name?: string | null
          status?: string
          updated_at?: string
          verified_by_personnel_id?: string | null
          verified_by_personnel_name?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "diagnostic_reports_amended_from_report_id_fkey"
            columns: ["amended_from_report_id"]
            isOneToOne: false
            referencedRelation: "diagnostic_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnostic_reports_amended_from_report_id_fkey"
            columns: ["amended_from_report_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["latest_report_id"]
          },
          {
            foreignKeyName: "diagnostic_reports_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "clinical_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnostic_reports_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnostic_reports_performed_by_personnel_id_fkey"
            columns: ["performed_by_personnel_id"]
            isOneToOne: false
            referencedRelation: "reporting_personnel"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnostic_reports_report_group_id_fkey"
            columns: ["report_group_id"]
            isOneToOne: false
            referencedRelation: "clinical_report_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnostic_reports_report_group_id_fkey"
            columns: ["report_group_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["report_group_id"]
          },
          {
            foreignKeyName: "diagnostic_reports_signed_by_personnel_id_fkey"
            columns: ["signed_by_personnel_id"]
            isOneToOne: false
            referencedRelation: "reporting_personnel"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "diagnostic_reports_verified_by_personnel_id_fkey"
            columns: ["verified_by_personnel_id"]
            isOneToOne: false
            referencedRelation: "reporting_personnel"
            referencedColumns: ["id"]
          },
        ]
      }
      health_package_components: {
        Row: {
          display_order: number
          package_id: string
          test_id: string
        }
        Insert: {
          display_order?: number
          package_id: string
          test_id: string
        }
        Update: {
          display_order?: number
          package_id?: string
          test_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "health_package_components_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "health_packages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "health_package_components_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "health_package_components_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      health_packages: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          code: string
          created_at: string
          description: string | null
          id: string
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          price_paisa: number
          pricing_policy: Database["public"]["Enums"]["catalogue_pricing_policy_enum"]
          row_version: number
          search_aliases: string[]
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          code: string
          created_at?: string
          description?: string | null
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          price_paisa?: number
          pricing_policy?: Database["public"]["Enums"]["catalogue_pricing_policy_enum"]
          row_version?: number
          search_aliases?: string[]
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name?: string
          price_paisa?: number
          pricing_policy?: Database["public"]["Enums"]["catalogue_pricing_policy_enum"]
          row_version?: number
          search_aliases?: string[]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "health_packages_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hmis_facility_configuration: {
        Row: {
          configuration: Json
          created_at: string
          facility_key: string
          id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          configuration?: Json
          created_at?: string
          facility_key?: string
          id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          configuration?: Json
          created_at?: string
          facility_key?: string
          id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hmis_facility_configuration_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hmis_monthly_manual_values: {
        Row: {
          report_id: string
          updated_at: string
          updated_by: string
          values_json: Json
        }
        Insert: {
          report_id: string
          updated_at?: string
          updated_by: string
          values_json?: Json
        }
        Update: {
          report_id?: string
          updated_at?: string
          updated_by?: string
          values_json?: Json
        }
        Relationships: [
          {
            foreignKeyName: "hmis_monthly_manual_values_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: true
            referencedRelation: "hmis_monthly_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hmis_monthly_manual_values_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hmis_monthly_report_versions: {
        Row: {
          created_at: string
          finalized_at: string
          finalized_by: string
          generated_by: string
          id: string
          parent_version: number | null
          report_id: string
          revision_reason: string | null
          sha256: string
          snapshot_json: Json
          version: number
        }
        Insert: {
          created_at?: string
          finalized_at?: string
          finalized_by: string
          generated_by: string
          id?: string
          parent_version?: number | null
          report_id: string
          revision_reason?: string | null
          sha256: string
          snapshot_json: Json
          version: number
        }
        Update: {
          created_at?: string
          finalized_at?: string
          finalized_by?: string
          generated_by?: string
          id?: string
          parent_version?: number | null
          report_id?: string
          revision_reason?: string | null
          sha256?: string
          snapshot_json?: Json
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "hmis_monthly_report_versions_finalized_by_fkey"
            columns: ["finalized_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hmis_monthly_report_versions_generated_by_fkey"
            columns: ["generated_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hmis_monthly_report_versions_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "hmis_monthly_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hmis_version_parent_fk"
            columns: ["report_id", "parent_version"]
            isOneToOne: false
            referencedRelation: "hmis_monthly_report_versions"
            referencedColumns: ["report_id", "version"]
          },
        ]
      }
      hmis_monthly_reports: {
        Row: {
          created_at: string
          created_by: string
          current_version: number
          finalized_at: string | null
          finalized_by: string | null
          fiscal_year: string
          id: string
          reference_no: string | null
          report_month: string
          status: string
          submitted_at: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          current_version?: number
          finalized_at?: string | null
          finalized_by?: string | null
          fiscal_year: string
          id?: string
          reference_no?: string | null
          report_month: string
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          current_version?: number
          finalized_at?: string | null
          finalized_by?: string | null
          fiscal_year?: string
          id?: string
          reference_no?: string | null
          report_month?: string
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hmis_monthly_reports_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hmis_monthly_reports_finalized_by_fkey"
            columns: ["finalized_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hmis_submission_events: {
        Row: {
          attachment_path: string | null
          created_at: string
          id: string
          method: string
          recorded_by: string
          reference_receipt_no: string | null
          remarks: string | null
          report_id: string
          report_version: number
          submission_date: string
          submitted: boolean
          submitted_to: string
        }
        Insert: {
          attachment_path?: string | null
          created_at?: string
          id?: string
          method: string
          recorded_by: string
          reference_receipt_no?: string | null
          remarks?: string | null
          report_id: string
          report_version: number
          submission_date: string
          submitted?: boolean
          submitted_to: string
        }
        Update: {
          attachment_path?: string | null
          created_at?: string
          id?: string
          method?: string
          recorded_by?: string
          reference_receipt_no?: string | null
          remarks?: string | null
          report_id?: string
          report_version?: number
          submission_date?: string
          submitted?: boolean
          submitted_to?: string
        }
        Relationships: [
          {
            foreignKeyName: "hmis_submission_events_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hmis_submission_events_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "hmis_monthly_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hmis_submission_events_report_id_report_version_fkey"
            columns: ["report_id", "report_version"]
            isOneToOne: false
            referencedRelation: "hmis_monthly_report_versions"
            referencedColumns: ["report_id", "version"]
          },
        ]
      }
      lab_number_registry: {
        Row: {
          assigned_at: string | null
          lab_no: string
          order_id: string | null
          reserved_at: string
        }
        Insert: {
          assigned_at?: string | null
          lab_no: string
          order_id?: string | null
          reserved_at?: string
        }
        Update: {
          assigned_at?: string | null
          lab_no?: string
          order_id?: string | null
          reserved_at?: string
        }
        Relationships: []
      }
      order_report_delivery_entitlements: {
        Row: {
          created_at: string
          order_token_id: string
          report_group_id: string
        }
        Insert: {
          created_at?: string
          order_token_id: string
          report_group_id: string
        }
        Update: {
          created_at?: string
          order_token_id?: string
          report_group_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "order_report_delivery_entitlements_order_token_id_fkey"
            columns: ["order_token_id"]
            isOneToOne: false
            referencedRelation: "order_report_delivery_tokens"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_report_delivery_entitlements_report_group_id_fkey"
            columns: ["report_group_id"]
            isOneToOne: false
            referencedRelation: "clinical_report_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_report_delivery_entitlements_report_group_id_fkey"
            columns: ["report_group_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["report_group_id"]
          },
        ]
      }
      order_report_delivery_tokens: {
        Row: {
          access_count: number
          created_at: string
          created_by: string
          expires_at: string
          id: string
          is_active: boolean
          last_accessed_at: string | null
          order_id: string
          revoked_at: string | null
          token_hash: string
        }
        Insert: {
          access_count?: number
          created_at?: string
          created_by: string
          expires_at: string
          id?: string
          is_active?: boolean
          last_accessed_at?: string | null
          order_id: string
          revoked_at?: string | null
          token_hash: string
        }
        Update: {
          access_count?: number
          created_at?: string
          created_by?: string
          expires_at?: string
          id?: string
          is_active?: boolean
          last_accessed_at?: string | null
          order_id?: string
          revoked_at?: string | null
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "order_report_delivery_tokens_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "clinical_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      order_report_notification_generations: {
        Row: {
          created_at: string
          generation: number
          id: string
          order_id: string
          reason: string
          requested_by: string
          sms_queue_item_id: string | null
        }
        Insert: {
          created_at?: string
          generation: number
          id?: string
          order_id: string
          reason: string
          requested_by: string
          sms_queue_item_id?: string | null
        }
        Update: {
          created_at?: string
          generation?: number
          id?: string
          order_id?: string
          reason?: string
          requested_by?: string
          sms_queue_item_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "order_report_notification_generations_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "clinical_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_report_notification_generations_sms_queue_item_id_fkey"
            columns: ["sms_queue_item_id"]
            isOneToOne: true
            referencedRelation: "sms_queue_items"
            referencedColumns: ["id"]
          },
        ]
      }
      outsource_sample_events: {
        Row: {
          created_at: string
          event_type: string
          from_status:
            | Database["public"]["Enums"]["outsource_sample_status_enum"]
            | null
          id: string
          meta: Json | null
          notes: string | null
          outsource_sample_id: string
          performed_by: string | null
          performed_by_name: string | null
          to_status: Database["public"]["Enums"]["outsource_sample_status_enum"]
        }
        Insert: {
          created_at?: string
          event_type: string
          from_status?:
            | Database["public"]["Enums"]["outsource_sample_status_enum"]
            | null
          id?: string
          meta?: Json | null
          notes?: string | null
          outsource_sample_id: string
          performed_by?: string | null
          performed_by_name?: string | null
          to_status: Database["public"]["Enums"]["outsource_sample_status_enum"]
        }
        Update: {
          created_at?: string
          event_type?: string
          from_status?:
            | Database["public"]["Enums"]["outsource_sample_status_enum"]
            | null
          id?: string
          meta?: Json | null
          notes?: string | null
          outsource_sample_id?: string
          performed_by?: string | null
          performed_by_name?: string | null
          to_status?: Database["public"]["Enums"]["outsource_sample_status_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "outsource_sample_events_outsource_sample_id_fkey"
            columns: ["outsource_sample_id"]
            isOneToOne: false
            referencedRelation: "outsource_samples"
            referencedColumns: ["id"]
          },
        ]
      }
      outsource_samples: {
        Row: {
          bill_id: string
          bill_item_id: string
          blocks_returned_count: number | null
          completed_at: string | null
          courier_name: string | null
          courier_tracking_no: string | null
          created_at: string
          dispatch_notes: string | null
          dispatched_at: string | null
          dispatched_by: string | null
          dispatched_by_name: string | null
          external_report_date: string | null
          external_report_received: boolean
          id: string
          items_sent_count: string | null
          material_received_by: string | null
          material_received_by_name: string | null
          material_returned: boolean
          material_returned_at: string | null
          order_item_id: string | null
          patient_id: string
          quantity_received: string
          received_at: string
          received_by: string | null
          received_by_name: string | null
          recollects_outsource_sample_id: string | null
          reference_lab_name: string | null
          reference_lab_report_no: string | null
          reference_laboratory_id: string | null
          result_notes: string | null
          result_received_at: string | null
          result_received_by: string | null
          result_received_by_name: string | null
          return_notes: string | null
          service_description: string
          slides_returned_count: number | null
          specimen_description: string | null
          specimen_type: string
          status: Database["public"]["Enums"]["outsource_sample_status_enum"]
          test_id: string
          tracking_number: string
          updated_at: string
        }
        Insert: {
          bill_id: string
          bill_item_id: string
          blocks_returned_count?: number | null
          completed_at?: string | null
          courier_name?: string | null
          courier_tracking_no?: string | null
          created_at?: string
          dispatch_notes?: string | null
          dispatched_at?: string | null
          dispatched_by?: string | null
          dispatched_by_name?: string | null
          external_report_date?: string | null
          external_report_received?: boolean
          id?: string
          items_sent_count?: string | null
          material_received_by?: string | null
          material_received_by_name?: string | null
          material_returned?: boolean
          material_returned_at?: string | null
          order_item_id?: string | null
          patient_id: string
          quantity_received?: string
          received_at?: string
          received_by?: string | null
          received_by_name?: string | null
          recollects_outsource_sample_id?: string | null
          reference_lab_name?: string | null
          reference_lab_report_no?: string | null
          reference_laboratory_id?: string | null
          result_notes?: string | null
          result_received_at?: string | null
          result_received_by?: string | null
          result_received_by_name?: string | null
          return_notes?: string | null
          service_description: string
          slides_returned_count?: number | null
          specimen_description?: string | null
          specimen_type?: string
          status?: Database["public"]["Enums"]["outsource_sample_status_enum"]
          test_id: string
          tracking_number: string
          updated_at?: string
        }
        Update: {
          bill_id?: string
          bill_item_id?: string
          blocks_returned_count?: number | null
          completed_at?: string | null
          courier_name?: string | null
          courier_tracking_no?: string | null
          created_at?: string
          dispatch_notes?: string | null
          dispatched_at?: string | null
          dispatched_by?: string | null
          dispatched_by_name?: string | null
          external_report_date?: string | null
          external_report_received?: boolean
          id?: string
          items_sent_count?: string | null
          material_received_by?: string | null
          material_received_by_name?: string | null
          material_returned?: boolean
          material_returned_at?: string | null
          order_item_id?: string | null
          patient_id?: string
          quantity_received?: string
          received_at?: string
          received_by?: string | null
          received_by_name?: string | null
          recollects_outsource_sample_id?: string | null
          reference_lab_name?: string | null
          reference_lab_report_no?: string | null
          reference_laboratory_id?: string | null
          result_notes?: string | null
          result_received_at?: string | null
          result_received_by?: string | null
          result_received_by_name?: string | null
          return_notes?: string | null
          service_description?: string
          slides_returned_count?: number | null
          specimen_description?: string | null
          specimen_type?: string
          status?: Database["public"]["Enums"]["outsource_sample_status_enum"]
          test_id?: string
          tracking_number?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "outsource_samples_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_samples_bill_item_id_fkey"
            columns: ["bill_item_id"]
            isOneToOne: false
            referencedRelation: "bill_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_samples_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "clinical_order_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_samples_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["order_item_id"]
          },
          {
            foreignKeyName: "outsource_samples_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_samples_recollects_outsource_sample_id_fkey"
            columns: ["recollects_outsource_sample_id"]
            isOneToOne: false
            referencedRelation: "outsource_samples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_samples_reference_laboratory_id_fkey"
            columns: ["reference_laboratory_id"]
            isOneToOne: false
            referencedRelation: "reference_laboratories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outsource_samples_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "outsource_samples_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      parameters: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          calculation_identifier: string | null
          calculation_reporting_mode: Database["public"]["Enums"]["calculation_reporting_mode_enum"]
          clinical_class: Database["public"]["Enums"]["parameter_clinical_class_enum"]
          clinical_configuration_status: Database["public"]["Enums"]["clinical_configuration_status_enum"]
          code: string
          created_at: string
          decimal_precision: number | null
          display_order: number
          formula: string | null
          formula_dependencies: string[] | null
          id: string
          interpretation_config: Json | null
          is_active: boolean
          is_mandatory: boolean
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method_validation_required: boolean
          name: string
          option_set_id: string | null
          options: Json | null
          parent_parameter_id: string | null
          range_validation_required: boolean
          row_version: number
          test_id: string
          unit: string | null
          unit_validation_required: boolean
          updated_at: string
          value_type: Database["public"]["Enums"]["parameter_value_type_enum"]
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          calculation_identifier?: string | null
          calculation_reporting_mode?: Database["public"]["Enums"]["calculation_reporting_mode_enum"]
          clinical_class?: Database["public"]["Enums"]["parameter_clinical_class_enum"]
          clinical_configuration_status?: Database["public"]["Enums"]["clinical_configuration_status_enum"]
          code: string
          created_at?: string
          decimal_precision?: number | null
          display_order?: number
          formula?: string | null
          formula_dependencies?: string[] | null
          id?: string
          interpretation_config?: Json | null
          is_active?: boolean
          is_mandatory?: boolean
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method_validation_required?: boolean
          name: string
          option_set_id?: string | null
          options?: Json | null
          parent_parameter_id?: string | null
          range_validation_required?: boolean
          row_version?: number
          test_id: string
          unit?: string | null
          unit_validation_required?: boolean
          updated_at?: string
          value_type?: Database["public"]["Enums"]["parameter_value_type_enum"]
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          calculation_identifier?: string | null
          calculation_reporting_mode?: Database["public"]["Enums"]["calculation_reporting_mode_enum"]
          clinical_class?: Database["public"]["Enums"]["parameter_clinical_class_enum"]
          clinical_configuration_status?: Database["public"]["Enums"]["clinical_configuration_status_enum"]
          code?: string
          created_at?: string
          decimal_precision?: number | null
          display_order?: number
          formula?: string | null
          formula_dependencies?: string[] | null
          id?: string
          interpretation_config?: Json | null
          is_active?: boolean
          is_mandatory?: boolean
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method_validation_required?: boolean
          name?: string
          option_set_id?: string | null
          options?: Json | null
          parent_parameter_id?: string | null
          range_validation_required?: boolean
          row_version?: number
          test_id?: string
          unit?: string | null
          unit_validation_required?: boolean
          updated_at?: string
          value_type?: Database["public"]["Enums"]["parameter_value_type_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "parameters_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parameters_option_set_id_fkey"
            columns: ["option_set_id"]
            isOneToOne: false
            referencedRelation: "catalogue_option_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parameters_parent_parameter_id_fkey"
            columns: ["parent_parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "parameters_parent_parameter_id_fkey"
            columns: ["parent_parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parameters_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "parameters_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      patients: {
        Row: {
          address: string
          age_days: number | null
          age_months: number | null
          age_years: number | null
          archived_at: string | null
          archived_by: string | null
          created_at: string
          dob: string | null
          email: string | null
          full_name: string
          gender: string
          id: string
          identification_no: string | null
          is_active: boolean
          mobile: string
          title: string | null
          uhid: string
          updated_at: string
        }
        Insert: {
          address: string
          age_days?: number | null
          age_months?: number | null
          age_years?: number | null
          archived_at?: string | null
          archived_by?: string | null
          created_at?: string
          dob?: string | null
          email?: string | null
          full_name: string
          gender: string
          id?: string
          identification_no?: string | null
          is_active?: boolean
          mobile: string
          title?: string | null
          uhid: string
          updated_at?: string
        }
        Update: {
          address?: string
          age_days?: number | null
          age_months?: number | null
          age_years?: number | null
          archived_at?: string | null
          archived_by?: string | null
          created_at?: string
          dob?: string | null
          email?: string | null
          full_name?: string
          gender?: string
          id?: string
          identification_no?: string | null
          is_active?: boolean
          mobile?: string
          title?: string | null
          uhid?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "patients_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_idempotency_requests: {
        Row: {
          caller_id: string
          completed_at: string | null
          created_at: string
          idempotency_key: string
          request_hash: string
          response_json: Json | null
        }
        Insert: {
          caller_id: string
          completed_at?: string | null
          created_at?: string
          idempotency_key: string
          request_hash: string
          response_json?: Json | null
        }
        Update: {
          caller_id?: string
          completed_at?: string | null
          created_at?: string
          idempotency_key?: string
          request_hash?: string
          response_json?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_idempotency_requests_caller_id_fkey"
            columns: ["caller_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_transactions: {
        Row: {
          amount_paisa: number
          bill_id: string
          created_at: string
          id: string
          payment_mode: Database["public"]["Enums"]["payment_mode_enum"]
          receipt_number: string
          received_by: string | null
          received_by_name: string
          remarks: string | null
          transaction_reference: string | null
        }
        Insert: {
          amount_paisa: number
          bill_id: string
          created_at?: string
          id?: string
          payment_mode: Database["public"]["Enums"]["payment_mode_enum"]
          receipt_number: string
          received_by?: string | null
          received_by_name: string
          remarks?: string | null
          transaction_reference?: string | null
        }
        Update: {
          amount_paisa?: number
          bill_id?: string
          created_at?: string
          id?: string
          payment_mode?: Database["public"]["Enums"]["payment_mode_enum"]
          receipt_number?: string
          received_by?: string | null
          received_by_name?: string
          remarks?: string | null
          transaction_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_transactions_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_transactions_received_by_fkey"
            columns: ["received_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      public_report_tokens: {
        Row: {
          access_count: number
          created_at: string
          created_by: string | null
          diagnostic_report_id: string
          expires_at: string
          id: string
          is_active: boolean
          last_accessed_at: string | null
          revoked_at: string | null
          token_hash: string
          updated_at: string
        }
        Insert: {
          access_count?: number
          created_at?: string
          created_by?: string | null
          diagnostic_report_id: string
          expires_at: string
          id?: string
          is_active?: boolean
          last_accessed_at?: string | null
          revoked_at?: string | null
          token_hash: string
          updated_at?: string
        }
        Update: {
          access_count?: number
          created_at?: string
          created_by?: string | null
          diagnostic_report_id?: string
          expires_at?: string
          id?: string
          is_active?: boolean
          last_accessed_at?: string | null
          revoked_at?: string | null
          token_hash?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "public_report_tokens_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "public_report_tokens_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: false
            referencedRelation: "diagnostic_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "public_report_tokens_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["latest_report_id"]
          },
        ]
      }
      pus_culture_worksheets: {
        Row: {
          created_at: string
          created_by: string
          culture_status: string
          direct_smear_organisms: string
          final_remarks: string
          gram_stain_pus_cells: string
          id: string
          order_item_id: string
          row_version: number
          specimen_source: string
          specimen_source_other: string | null
          status: string
          updated_at: string
          updated_by: string
        }
        Insert: {
          created_at?: string
          created_by: string
          culture_status: string
          direct_smear_organisms?: string
          final_remarks?: string
          gram_stain_pus_cells: string
          id?: string
          order_item_id: string
          row_version?: number
          specimen_source: string
          specimen_source_other?: string | null
          status?: string
          updated_at?: string
          updated_by: string
        }
        Update: {
          created_at?: string
          created_by?: string
          culture_status?: string
          direct_smear_organisms?: string
          final_remarks?: string
          gram_stain_pus_cells?: string
          id?: string
          order_item_id?: string
          row_version?: number
          specimen_source?: string
          specimen_source_other?: string | null
          status?: string
          updated_at?: string
          updated_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "pus_culture_worksheets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pus_culture_worksheets_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: true
            referencedRelation: "clinical_order_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pus_culture_worksheets_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: true
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["order_item_id"]
          },
          {
            foreignKeyName: "pus_culture_worksheets_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      reference_laboratories: {
        Row: {
          code: string
          contact_details: string | null
          created_at: string
          created_by: string
          external_code: string | null
          id: string
          is_active: boolean
          name: string
          row_version: number
          tat_hours: number | null
          updated_at: string
        }
        Insert: {
          code: string
          contact_details?: string | null
          created_at?: string
          created_by: string
          external_code?: string | null
          id?: string
          is_active?: boolean
          name: string
          row_version?: number
          tat_hours?: number | null
          updated_at?: string
        }
        Update: {
          code?: string
          contact_details?: string | null
          created_at?: string
          created_by?: string
          external_code?: string | null
          id?: string
          is_active?: boolean
          name?: string
          row_version?: number
          tat_hours?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      reference_ranges: {
        Row: {
          age_max_days: number
          age_min_days: number
          approved_at: string | null
          approved_by: string | null
          archived_at: string | null
          archived_by: string | null
          created_at: string
          critical_high: number | null
          critical_low: number | null
          effective_from: string | null
          effective_to: string | null
          gender: string
          id: string
          is_active: boolean
          is_approved: boolean
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method: string | null
          normal_max: number | null
          normal_min: number | null
          normal_text: string | null
          normalized_source_snapshot: Json | null
          parameter_id: string
          policy_version: number | null
          reference_text: string | null
          row_version: number
          source_decision_id: string | null
          supplied_unit_snapshot: string | null
          supplied_value_snapshot: string | null
          unit: string | null
          updated_at: string
          validation_source: string | null
          validation_state: Database["public"]["Enums"]["reference_range_validation_state_enum"]
        }
        Insert: {
          age_max_days?: number
          age_min_days?: number
          approved_at?: string | null
          approved_by?: string | null
          archived_at?: string | null
          archived_by?: string | null
          created_at?: string
          critical_high?: number | null
          critical_low?: number | null
          effective_from?: string | null
          effective_to?: string | null
          gender?: string
          id?: string
          is_active?: boolean
          is_approved?: boolean
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method?: string | null
          normal_max?: number | null
          normal_min?: number | null
          normal_text?: string | null
          normalized_source_snapshot?: Json | null
          parameter_id: string
          policy_version?: number | null
          reference_text?: string | null
          row_version?: number
          source_decision_id?: string | null
          supplied_unit_snapshot?: string | null
          supplied_value_snapshot?: string | null
          unit?: string | null
          updated_at?: string
          validation_source?: string | null
          validation_state?: Database["public"]["Enums"]["reference_range_validation_state_enum"]
        }
        Update: {
          age_max_days?: number
          age_min_days?: number
          approved_at?: string | null
          approved_by?: string | null
          archived_at?: string | null
          archived_by?: string | null
          created_at?: string
          critical_high?: number | null
          critical_low?: number | null
          effective_from?: string | null
          effective_to?: string | null
          gender?: string
          id?: string
          is_active?: boolean
          is_approved?: boolean
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method?: string | null
          normal_max?: number | null
          normal_min?: number | null
          normal_text?: string | null
          normalized_source_snapshot?: Json | null
          parameter_id?: string
          policy_version?: number | null
          reference_text?: string | null
          row_version?: number
          source_decision_id?: string | null
          supplied_unit_snapshot?: string | null
          supplied_value_snapshot?: string | null
          unit?: string | null
          updated_at?: string
          validation_source?: string | null
          validation_state?: Database["public"]["Enums"]["reference_range_validation_state_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "reference_ranges_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reference_ranges_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reference_ranges_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "reference_ranges_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reference_ranges_source_decision_id_fkey"
            columns: ["source_decision_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_decisions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reference_ranges_source_decision_id_fkey"
            columns: ["source_decision_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["decision_id"]
          },
        ]
      }
      referring_doctors: {
        Row: {
          address: string | null
          code: string | null
          created_at: string
          degree: string | null
          email: string | null
          full_name: string
          id: string
          institution: string | null
          is_active: boolean
          phone: string | null
          updated_at: string
        }
        Insert: {
          address?: string | null
          code?: string | null
          created_at?: string
          degree?: string | null
          email?: string | null
          full_name: string
          id?: string
          institution?: string | null
          is_active?: boolean
          phone?: string | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          code?: string | null
          created_at?: string
          degree?: string | null
          email?: string | null
          full_name?: string
          id?: string
          institution?: string | null
          is_active?: boolean
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      report_artifact_worker_identities: {
        Row: {
          auth_user_id: string
          created_at: string
          created_by: string
          is_enabled: boolean
          updated_at: string
          worker_name: string
        }
        Insert: {
          auth_user_id: string
          created_at?: string
          created_by: string
          is_enabled?: boolean
          updated_at?: string
          worker_name: string
        }
        Update: {
          auth_user_id?: string
          created_at?: string
          created_by?: string
          is_enabled?: boolean
          updated_at?: string
          worker_name?: string
        }
        Relationships: []
      }
      report_calculation_provenance: {
        Row: {
          calculated_raw_value: number | null
          calculation_run_id: string
          calculation_status: string
          captured_at: string
          displayed_value: string | null
          formula_snapshot: Json
          input_snapshot: Json
          output_unit: string
          provenance_hash: string
          report_id: string
          report_version: number
        }
        Insert: {
          calculated_raw_value?: number | null
          calculation_run_id: string
          calculation_status: string
          captured_at?: string
          displayed_value?: string | null
          formula_snapshot: Json
          input_snapshot: Json
          output_unit: string
          provenance_hash: string
          report_id: string
          report_version: number
        }
        Update: {
          calculated_raw_value?: number | null
          calculation_run_id?: string
          calculation_status?: string
          captured_at?: string
          displayed_value?: string | null
          formula_snapshot?: Json
          input_snapshot?: Json
          output_unit?: string
          provenance_hash?: string
          report_id?: string
          report_version?: number
        }
        Relationships: [
          {
            foreignKeyName: "report_calculation_provenance_calculation_run_id_fkey"
            columns: ["calculation_run_id"]
            isOneToOne: false
            referencedRelation: "clinical_calculation_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_calculation_provenance_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "diagnostic_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_calculation_provenance_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["latest_report_id"]
          },
        ]
      }
      report_pdf_artifacts: {
        Row: {
          attempt_count: number
          byte_size: number | null
          created_at: string
          diagnostic_report_id: string
          failure_code: string | null
          frozen_snapshot_sha256: string
          generated_at: string | null
          generation_status: Database["public"]["Enums"]["report_artifact_status_enum"]
          generator_name: string | null
          generator_version: string | null
          id: string
          lease_expires_at: string | null
          lease_owner: string | null
          mime_type: string | null
          object_key: string | null
          pdf_sha256: string | null
          report_integrity_hash: string
          report_version: number
          updated_at: string
        }
        Insert: {
          attempt_count?: number
          byte_size?: number | null
          created_at?: string
          diagnostic_report_id: string
          failure_code?: string | null
          frozen_snapshot_sha256: string
          generated_at?: string | null
          generation_status?: Database["public"]["Enums"]["report_artifact_status_enum"]
          generator_name?: string | null
          generator_version?: string | null
          id?: string
          lease_expires_at?: string | null
          lease_owner?: string | null
          mime_type?: string | null
          object_key?: string | null
          pdf_sha256?: string | null
          report_integrity_hash: string
          report_version: number
          updated_at?: string
        }
        Update: {
          attempt_count?: number
          byte_size?: number | null
          created_at?: string
          diagnostic_report_id?: string
          failure_code?: string | null
          frozen_snapshot_sha256?: string
          generated_at?: string | null
          generation_status?: Database["public"]["Enums"]["report_artifact_status_enum"]
          generator_name?: string | null
          generator_version?: string | null
          id?: string
          lease_expires_at?: string | null
          lease_owner?: string | null
          mime_type?: string | null
          object_key?: string | null
          pdf_sha256?: string | null
          report_integrity_hash?: string
          report_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "report_pdf_artifacts_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: false
            referencedRelation: "diagnostic_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_pdf_artifacts_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["latest_report_id"]
          },
        ]
      }
      report_pdf_delivery_intents: {
        Row: {
          created_at: string
          diagnostic_report_id: string
          order_token_id: string | null
          public_url: string
          queued_at: string | null
          queued_sms_id: string | null
          report_token_id: string | null
          status: string
        }
        Insert: {
          created_at?: string
          diagnostic_report_id: string
          order_token_id?: string | null
          public_url: string
          queued_at?: string | null
          queued_sms_id?: string | null
          report_token_id?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          diagnostic_report_id?: string
          order_token_id?: string | null
          public_url?: string
          queued_at?: string | null
          queued_sms_id?: string | null
          report_token_id?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "report_pdf_delivery_intents_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: true
            referencedRelation: "diagnostic_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_pdf_delivery_intents_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: true
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["latest_report_id"]
          },
          {
            foreignKeyName: "report_pdf_delivery_intents_order_token_id_fkey"
            columns: ["order_token_id"]
            isOneToOne: false
            referencedRelation: "order_report_delivery_tokens"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_pdf_delivery_intents_queued_sms_id_fkey"
            columns: ["queued_sms_id"]
            isOneToOne: true
            referencedRelation: "sms_queue_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "report_pdf_delivery_intents_report_token_id_fkey"
            columns: ["report_token_id"]
            isOneToOne: true
            referencedRelation: "public_report_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      report_secure_link_presentations: {
        Row: {
          created_at: string
          public_url: string
          report_token_id: string
        }
        Insert: {
          created_at?: string
          public_url: string
          report_token_id: string
        }
        Update: {
          created_at?: string
          public_url?: string
          report_token_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "report_secure_link_presentations_report_token_id_fkey"
            columns: ["report_token_id"]
            isOneToOne: true
            referencedRelation: "public_report_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      reporting_personnel: {
        Row: {
          can_acknowledge_critical: boolean
          can_enter_results: boolean
          can_sign_reports: boolean
          can_verify_results: boolean
          created_at: string
          display_order: number
          email: string | null
          full_name: string
          id: string
          is_active: boolean
          phone: string | null
          professional_type: Database["public"]["Enums"]["professional_type_enum"]
          qualification: string
          registration_council: string
          registration_number: string
          signature_url: string | null
          specialization: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          can_acknowledge_critical?: boolean
          can_enter_results?: boolean
          can_sign_reports?: boolean
          can_verify_results?: boolean
          created_at?: string
          display_order?: number
          email?: string | null
          full_name: string
          id?: string
          is_active?: boolean
          phone?: string | null
          professional_type: Database["public"]["Enums"]["professional_type_enum"]
          qualification: string
          registration_council: string
          registration_number: string
          signature_url?: string | null
          specialization?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          can_acknowledge_critical?: boolean
          can_enter_results?: boolean
          can_sign_reports?: boolean
          can_verify_results?: boolean
          created_at?: string
          display_order?: number
          email?: string | null
          full_name?: string
          id?: string
          is_active?: boolean
          phone?: string | null
          professional_type?: Database["public"]["Enums"]["professional_type_enum"]
          qualification?: string
          registration_council?: string
          registration_number?: string
          signature_url?: string | null
          specialization?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "reporting_personnel_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          id: string
          permission_key: string
          role_id: string
        }
        Insert: {
          id?: string
          permission_key: string
          role_id: string
        }
        Update: {
          id?: string
          permission_key?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_system: boolean
          name: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          name: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          name?: string
        }
        Relationships: []
      }
      sample_lifecycle_events: {
        Row: {
          from_status: Database["public"]["Enums"]["sample_status_enum"]
          id: string
          performed_by: string | null
          performed_by_name: string
          reason: string | null
          sample_id: string
          timestamp: string
          to_status: Database["public"]["Enums"]["sample_status_enum"]
        }
        Insert: {
          from_status: Database["public"]["Enums"]["sample_status_enum"]
          id?: string
          performed_by?: string | null
          performed_by_name: string
          reason?: string | null
          sample_id: string
          timestamp?: string
          to_status: Database["public"]["Enums"]["sample_status_enum"]
        }
        Update: {
          from_status?: Database["public"]["Enums"]["sample_status_enum"]
          id?: string
          performed_by?: string | null
          performed_by_name?: string
          reason?: string | null
          sample_id?: string
          timestamp?: string
          to_status?: Database["public"]["Enums"]["sample_status_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "sample_lifecycle_events_performed_by_fkey"
            columns: ["performed_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sample_lifecycle_events_sample_id_fkey"
            columns: ["sample_id"]
            isOneToOne: false
            referencedRelation: "samples"
            referencedColumns: ["id"]
          },
        ]
      }
      samples: {
        Row: {
          barcode: string
          collected_at: string | null
          collected_by: string | null
          collected_by_name: string | null
          container_type: string
          created_at: string
          id: string
          order_id: string
          patient_id: string
          received_at: string | null
          received_by: string | null
          received_by_name: string | null
          recollected_from_sample_id: string | null
          rejected_at: string | null
          rejected_by: string | null
          rejected_by_name: string | null
          rejection_reason: string | null
          specimen_requirement_key: string
          specimen_type: string
          status: Database["public"]["Enums"]["sample_status_enum"]
          updated_at: string
        }
        Insert: {
          barcode: string
          collected_at?: string | null
          collected_by?: string | null
          collected_by_name?: string | null
          container_type: string
          created_at?: string
          id?: string
          order_id: string
          patient_id: string
          received_at?: string | null
          received_by?: string | null
          received_by_name?: string | null
          recollected_from_sample_id?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          rejected_by_name?: string | null
          rejection_reason?: string | null
          specimen_requirement_key: string
          specimen_type: string
          status?: Database["public"]["Enums"]["sample_status_enum"]
          updated_at?: string
        }
        Update: {
          barcode?: string
          collected_at?: string | null
          collected_by?: string | null
          collected_by_name?: string | null
          container_type?: string
          created_at?: string
          id?: string
          order_id?: string
          patient_id?: string
          received_at?: string | null
          received_by?: string | null
          received_by_name?: string | null
          recollected_from_sample_id?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          rejected_by_name?: string | null
          rejection_reason?: string | null
          specimen_requirement_key?: string
          specimen_type?: string
          status?: Database["public"]["Enums"]["sample_status_enum"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "samples_collected_by_fkey"
            columns: ["collected_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "samples_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "clinical_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "samples_patient_id_fkey"
            columns: ["patient_id"]
            isOneToOne: false
            referencedRelation: "patients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "samples_received_by_fkey"
            columns: ["received_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "samples_recollected_from_sample_id_fkey"
            columns: ["recollected_from_sample_id"]
            isOneToOne: false
            referencedRelation: "samples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "samples_rejected_by_fkey"
            columns: ["rejected_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_gateway_instances: {
        Row: {
          active_job_count: number
          auth_user_id: string
          claiming_enabled: boolean
          created_at: string
          gateway_version: string
          hostname: string
          instance_id: string
          is_enabled: boolean
          last_heartbeat_at: string | null
          last_provider_success_at: string | null
          last_successful_queue_access_at: string | null
          provider_health: string
          provider_name: string
          safe_last_error_code: string | null
          service_started_at: string | null
          updated_at: string
        }
        Insert: {
          active_job_count?: number
          auth_user_id: string
          claiming_enabled?: boolean
          created_at?: string
          gateway_version: string
          hostname: string
          instance_id: string
          is_enabled?: boolean
          last_heartbeat_at?: string | null
          last_provider_success_at?: string | null
          last_successful_queue_access_at?: string | null
          provider_health?: string
          provider_name: string
          safe_last_error_code?: string | null
          service_started_at?: string | null
          updated_at?: string
        }
        Update: {
          active_job_count?: number
          auth_user_id?: string
          claiming_enabled?: boolean
          created_at?: string
          gateway_version?: string
          hostname?: string
          instance_id?: string
          is_enabled?: boolean
          last_heartbeat_at?: string | null
          last_provider_success_at?: string | null
          last_successful_queue_access_at?: string | null
          provider_health?: string
          provider_name?: string
          safe_last_error_code?: string | null
          service_started_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      sms_queue_items: {
        Row: {
          bill_id: string | null
          created_at: string
          delivery_attempt_count: number
          diagnostic_report_id: string | null
          error_classification: string | null
          error_message: string | null
          final_state_at: string | null
          id: string
          idempotency_key: string
          last_manual_retry_at: string | null
          last_manual_retry_by: string | null
          lease_expires_at: string | null
          lease_instance_id: string | null
          lease_owner: string | null
          manual_retry_count: number
          max_attempts: number
          message_body: string
          provider_call_started_at: string | null
          provider_message_id: string | null
          provider_response_code: string | null
          provider_response_json: Json | null
          recipient_name: string
          recipient_phone: string
          retry_count: number
          scheduled_at: string
          sent_at: string | null
          sms_type: string
          status: string
          updated_at: string
        }
        Insert: {
          bill_id?: string | null
          created_at?: string
          delivery_attempt_count?: number
          diagnostic_report_id?: string | null
          error_classification?: string | null
          error_message?: string | null
          final_state_at?: string | null
          id?: string
          idempotency_key: string
          last_manual_retry_at?: string | null
          last_manual_retry_by?: string | null
          lease_expires_at?: string | null
          lease_instance_id?: string | null
          lease_owner?: string | null
          manual_retry_count?: number
          max_attempts?: number
          message_body: string
          provider_call_started_at?: string | null
          provider_message_id?: string | null
          provider_response_code?: string | null
          provider_response_json?: Json | null
          recipient_name: string
          recipient_phone: string
          retry_count?: number
          scheduled_at?: string
          sent_at?: string | null
          sms_type: string
          status?: string
          updated_at?: string
        }
        Update: {
          bill_id?: string | null
          created_at?: string
          delivery_attempt_count?: number
          diagnostic_report_id?: string | null
          error_classification?: string | null
          error_message?: string | null
          final_state_at?: string | null
          id?: string
          idempotency_key?: string
          last_manual_retry_at?: string | null
          last_manual_retry_by?: string | null
          lease_expires_at?: string | null
          lease_instance_id?: string | null
          lease_owner?: string | null
          manual_retry_count?: number
          max_attempts?: number
          message_body?: string
          provider_call_started_at?: string | null
          provider_message_id?: string | null
          provider_response_code?: string | null
          provider_response_json?: Json | null
          recipient_name?: string
          recipient_phone?: string
          retry_count?: number
          scheduled_at?: string
          sent_at?: string | null
          sms_type?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sms_queue_items_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_queue_items_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: false
            referencedRelation: "diagnostic_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_queue_items_diagnostic_report_id_fkey"
            columns: ["diagnostic_report_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["latest_report_id"]
          },
          {
            foreignKeyName: "sms_queue_items_last_manual_retry_by_fkey"
            columns: ["last_manual_retry_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_queue_items_lease_instance_id_fkey"
            columns: ["lease_instance_id"]
            isOneToOne: false
            referencedRelation: "sms_gateway_instances"
            referencedColumns: ["instance_id"]
          },
        ]
      }
      test_analyzer_configurations: {
        Row: {
          analyzer_id: string
          approved_at: string | null
          approved_by: string | null
          assay_identifier: string | null
          configuration_version: string
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          is_clinically_approved: boolean
          lifecycle_status: Database["public"]["Enums"]["analyzer_lifecycle_enum"]
          method: string
          parameter_id: string | null
          row_version: number
          test_id: string
          updated_at: string
          validation_source: string | null
          validation_state: Database["public"]["Enums"]["reference_range_validation_state_enum"]
        }
        Insert: {
          analyzer_id: string
          approved_at?: string | null
          approved_by?: string | null
          assay_identifier?: string | null
          configuration_version: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_clinically_approved?: boolean
          lifecycle_status?: Database["public"]["Enums"]["analyzer_lifecycle_enum"]
          method: string
          parameter_id?: string | null
          row_version?: number
          test_id: string
          updated_at?: string
          validation_source?: string | null
          validation_state?: Database["public"]["Enums"]["reference_range_validation_state_enum"]
        }
        Update: {
          analyzer_id?: string
          approved_at?: string | null
          approved_by?: string | null
          assay_identifier?: string | null
          configuration_version?: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          is_clinically_approved?: boolean
          lifecycle_status?: Database["public"]["Enums"]["analyzer_lifecycle_enum"]
          method?: string
          parameter_id?: string | null
          row_version?: number
          test_id?: string
          updated_at?: string
          validation_source?: string | null
          validation_state?: Database["public"]["Enums"]["reference_range_validation_state_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "test_analyzer_configurations_analyzer_id_fkey"
            columns: ["analyzer_id"]
            isOneToOne: false
            referencedRelation: "analyzers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_analyzer_configurations_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_analyzer_configurations_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "test_analyzer_configurations_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_analyzer_configurations_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "test_analyzer_configurations_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      test_categories: {
        Row: {
          code: string
          created_at: string
          description: string | null
          display_order: number
          id: string
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          row_version: number
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name: string
          row_version?: number
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          display_order?: number
          id?: string
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          name?: string
          row_version?: number
          updated_at?: string
        }
        Relationships: []
      }
      test_category_aliases: {
        Row: {
          canonical_category_id: string
          created_at: string
          legacy_category_id: string | null
          normalized_alias: string
        }
        Insert: {
          canonical_category_id: string
          created_at?: string
          legacy_category_id?: string | null
          normalized_alias: string
        }
        Update: {
          canonical_category_id?: string
          created_at?: string
          legacy_category_id?: string | null
          normalized_alias?: string
        }
        Relationships: [
          {
            foreignKeyName: "test_category_aliases_canonical_category_id_fkey"
            columns: ["canonical_category_id"]
            isOneToOne: false
            referencedRelation: "test_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_category_aliases_legacy_category_id_fkey"
            columns: ["legacy_category_id"]
            isOneToOne: false
            referencedRelation: "test_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      test_results: {
        Row: {
          created_at: string
          critical_acknowledged: boolean
          critical_acknowledged_at: string | null
          critical_acknowledged_by: string | null
          critical_high: number | null
          critical_low: number | null
          display_value: string
          entered_at: string | null
          entered_by: string | null
          entered_by_name: string | null
          flag: Database["public"]["Enums"]["result_flag_enum"]
          id: string
          is_critical: boolean
          normal_max: number | null
          normal_min: number | null
          normal_range_text: string | null
          numeric_value: number | null
          order_item_id: string
          parameter_id: string
          parameter_name: string
          signed_off_at: string | null
          signed_off_by: string | null
          signed_off_name: string | null
          status: Database["public"]["Enums"]["result_status_enum"]
          text_value: string | null
          unit: string | null
          updated_at: string
          value_type: Database["public"]["Enums"]["parameter_value_type_enum"]
          verified_at: string | null
          verified_by: string | null
          verified_by_name: string | null
        }
        Insert: {
          created_at?: string
          critical_acknowledged?: boolean
          critical_acknowledged_at?: string | null
          critical_acknowledged_by?: string | null
          critical_high?: number | null
          critical_low?: number | null
          display_value: string
          entered_at?: string | null
          entered_by?: string | null
          entered_by_name?: string | null
          flag?: Database["public"]["Enums"]["result_flag_enum"]
          id?: string
          is_critical?: boolean
          normal_max?: number | null
          normal_min?: number | null
          normal_range_text?: string | null
          numeric_value?: number | null
          order_item_id: string
          parameter_id: string
          parameter_name: string
          signed_off_at?: string | null
          signed_off_by?: string | null
          signed_off_name?: string | null
          status?: Database["public"]["Enums"]["result_status_enum"]
          text_value?: string | null
          unit?: string | null
          updated_at?: string
          value_type: Database["public"]["Enums"]["parameter_value_type_enum"]
          verified_at?: string | null
          verified_by?: string | null
          verified_by_name?: string | null
        }
        Update: {
          created_at?: string
          critical_acknowledged?: boolean
          critical_acknowledged_at?: string | null
          critical_acknowledged_by?: string | null
          critical_high?: number | null
          critical_low?: number | null
          display_value?: string
          entered_at?: string | null
          entered_by?: string | null
          entered_by_name?: string | null
          flag?: Database["public"]["Enums"]["result_flag_enum"]
          id?: string
          is_critical?: boolean
          normal_max?: number | null
          normal_min?: number | null
          normal_range_text?: string | null
          numeric_value?: number | null
          order_item_id?: string
          parameter_id?: string
          parameter_name?: string
          signed_off_at?: string | null
          signed_off_by?: string | null
          signed_off_name?: string | null
          status?: Database["public"]["Enums"]["result_status_enum"]
          text_value?: string | null
          unit?: string | null
          updated_at?: string
          value_type?: Database["public"]["Enums"]["parameter_value_type_enum"]
          verified_at?: string | null
          verified_by?: string | null
          verified_by_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "test_results_critical_acknowledged_by_fkey"
            columns: ["critical_acknowledged_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_results_entered_by_fkey"
            columns: ["entered_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_results_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "clinical_order_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_results_order_item_id_fkey"
            columns: ["order_item_id"]
            isOneToOne: false
            referencedRelation: "order_report_group_workspace"
            referencedColumns: ["order_item_id"]
          },
          {
            foreignKeyName: "test_results_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "clinical_source_review_matrix"
            referencedColumns: ["current_parameter_id"]
          },
          {
            foreignKeyName: "test_results_parameter_id_fkey"
            columns: ["parameter_id"]
            isOneToOne: false
            referencedRelation: "parameters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_results_signed_off_by_fkey"
            columns: ["signed_off_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "test_results_verified_by_fkey"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      tests: {
        Row: {
          activated_at: string | null
          activated_by: string | null
          allow_manual_price: boolean
          allow_zero_price_billing: boolean
          analyzer_configuration_required: boolean
          archived_at: string | null
          archived_by: string | null
          billing_enabled: boolean
          catalogue_approved: boolean
          category: string
          category_id: string | null
          clinical_configuration_status: Database["public"]["Enums"]["clinical_configuration_status_enum"]
          clinical_reporting_enabled: boolean
          code: string
          collection_required: boolean
          configuration_notes: string | null
          container: string
          created_at: string
          default_reference_laboratory_id: string | null
          department: string
          description: string | null
          display_order: number
          execution_route: Database["public"]["Enums"]["clinical_execution_route_enum"]
          id: string
          interpretation_template: string | null
          is_active: boolean
          lifecycle_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method: string | null
          name: string
          normalized_name_collision_exempt: boolean
          outsource_lab_name: string | null
          price_configured: boolean
          price_paisa: number
          pricing_policy: Database["public"]["Enums"]["catalogue_pricing_policy_enum"]
          report_group_key: string
          report_group_sort_order: number
          report_group_title: string
          report_section: string
          reporting_model: Database["public"]["Enums"]["catalogue_reporting_model_enum"]
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          requires_sample_tracking: boolean
          retired_duplicate_of: string | null
          retirement_reason: string | null
          row_version: number
          sample_type: string
          sample_volume: string | null
          search_aliases: string[]
          short_name: string | null
          specimen_requirement_key: string
          tat_hours: number | null
          test_kind: Database["public"]["Enums"]["catalogue_test_kind_enum"]
          updated_at: string
          workflow_supported: boolean
          workflow_type: Database["public"]["Enums"]["clinical_workflow_type_enum"]
        }
        Insert: {
          activated_at?: string | null
          activated_by?: string | null
          allow_manual_price?: boolean
          allow_zero_price_billing?: boolean
          analyzer_configuration_required?: boolean
          archived_at?: string | null
          archived_by?: string | null
          billing_enabled?: boolean
          catalogue_approved?: boolean
          category: string
          category_id?: string | null
          clinical_configuration_status?: Database["public"]["Enums"]["clinical_configuration_status_enum"]
          clinical_reporting_enabled?: boolean
          code: string
          collection_required?: boolean
          configuration_notes?: string | null
          container: string
          created_at?: string
          default_reference_laboratory_id?: string | null
          department: string
          description?: string | null
          display_order?: number
          execution_route?: Database["public"]["Enums"]["clinical_execution_route_enum"]
          id?: string
          interpretation_template?: string | null
          is_active?: boolean
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method?: string | null
          name: string
          normalized_name_collision_exempt?: boolean
          outsource_lab_name?: string | null
          price_configured?: boolean
          price_paisa: number
          pricing_policy?: Database["public"]["Enums"]["catalogue_pricing_policy_enum"]
          report_group_key?: string
          report_group_sort_order?: number
          report_group_title?: string
          report_section?: string
          reporting_model?: Database["public"]["Enums"]["catalogue_reporting_model_enum"]
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          requires_sample_tracking?: boolean
          retired_duplicate_of?: string | null
          retirement_reason?: string | null
          row_version?: number
          sample_type: string
          sample_volume?: string | null
          search_aliases?: string[]
          short_name?: string | null
          specimen_requirement_key?: string
          tat_hours?: number | null
          test_kind?: Database["public"]["Enums"]["catalogue_test_kind_enum"]
          updated_at?: string
          workflow_supported?: boolean
          workflow_type?: Database["public"]["Enums"]["clinical_workflow_type_enum"]
        }
        Update: {
          activated_at?: string | null
          activated_by?: string | null
          allow_manual_price?: boolean
          allow_zero_price_billing?: boolean
          analyzer_configuration_required?: boolean
          archived_at?: string | null
          archived_by?: string | null
          billing_enabled?: boolean
          catalogue_approved?: boolean
          category?: string
          category_id?: string | null
          clinical_configuration_status?: Database["public"]["Enums"]["clinical_configuration_status_enum"]
          clinical_reporting_enabled?: boolean
          code?: string
          collection_required?: boolean
          configuration_notes?: string | null
          container?: string
          created_at?: string
          default_reference_laboratory_id?: string | null
          department?: string
          description?: string | null
          display_order?: number
          execution_route?: Database["public"]["Enums"]["clinical_execution_route_enum"]
          id?: string
          interpretation_template?: string | null
          is_active?: boolean
          lifecycle_status?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          method?: string | null
          name?: string
          normalized_name_collision_exempt?: boolean
          outsource_lab_name?: string | null
          price_configured?: boolean
          price_paisa?: number
          pricing_policy?: Database["public"]["Enums"]["catalogue_pricing_policy_enum"]
          report_group_key?: string
          report_group_sort_order?: number
          report_group_title?: string
          report_section?: string
          reporting_model?: Database["public"]["Enums"]["catalogue_reporting_model_enum"]
          reporting_type?: Database["public"]["Enums"]["reporting_type_enum"]
          requires_sample_tracking?: boolean
          retired_duplicate_of?: string | null
          retirement_reason?: string | null
          row_version?: number
          sample_type?: string
          sample_volume?: string | null
          search_aliases?: string[]
          short_name?: string | null
          specimen_requirement_key?: string
          tat_hours?: number | null
          test_kind?: Database["public"]["Enums"]["catalogue_test_kind_enum"]
          updated_at?: string
          workflow_supported?: boolean
          workflow_type?: Database["public"]["Enums"]["clinical_workflow_type_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "tests_activated_by_fkey"
            columns: ["activated_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tests_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tests_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "test_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tests_default_reference_laboratory_id_fkey"
            columns: ["default_reference_laboratory_id"]
            isOneToOne: false
            referencedRelation: "reference_laboratories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tests_retired_duplicate_of_fkey"
            columns: ["retired_duplicate_of"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "tests_retired_duplicate_of_fkey"
            columns: ["retired_duplicate_of"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
        ]
      }
      user_direct_permissions: {
        Row: {
          is_granted: boolean
          permission_key: string
          user_id: string
        }
        Insert: {
          is_granted?: boolean
          permission_key: string
          user_id: string
        }
        Update: {
          is_granted?: boolean
          permission_key?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_direct_permissions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_profiles: {
        Row: {
          created_at: string
          email: string
          full_name: string
          id: string
          is_active: boolean
          is_super_admin: boolean
          phone: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          full_name: string
          id: string
          is_active?: boolean
          is_super_admin?: boolean
          phone?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          is_active?: boolean
          is_super_admin?: boolean
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          role_id: string
          user_id: string
        }
        Insert: {
          role_id: string
          user_id: string
        }
        Update: {
          role_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "user_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      catalogue_test_operational_state: {
        Row: {
          operational_state: string | null
          readiness:
            | Database["public"]["Enums"]["catalogue_result_readiness_enum"]
            | null
          test_id: string | null
        }
        Insert: {
          operational_state?: never
          readiness?: never
          test_id?: string | null
        }
        Update: {
          operational_state?: never
          readiness?: never
          test_id?: string | null
        }
        Relationships: []
      }
      cbc_source_version_conflict_matrix: {
        Row: {
          approved_by: string | null
          canonical_parameter: string | null
          conflict_key: string | null
          decision_status: string | null
          normalized_representation: Json | null
          reason: string | null
          review_state: string | null
          selected_action: string | null
          source_classification: string | null
          source_key: string | null
          source_version: string | null
          supplied_context: string | null
          supplied_unit: string | null
          supplied_value: string | null
        }
        Relationships: []
      }
      clinical_source_review_matrix: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          canonical_parameter: string | null
          conflict_key: string | null
          current_lis_policies: Json | null
          current_parameter_id: string | null
          decision_id: string | null
          decision_row_version: number | null
          decision_status: string | null
          decision_version: number | null
          materialized_range_id: string | null
          normalized_representation: Json | null
          reason: string | null
          review_state: string | null
          reviewed_at: string | null
          reviewer_id: string | null
          row_version: number | null
          selected_action: string | null
          selected_policy: Json | null
          source_classification: string | null
          source_item_id: string | null
          source_key: string | null
          source_name: string | null
          source_note: string | null
          source_version: string | null
          supplied_context: string | null
          supplied_unit: string | null
          supplied_value: string | null
          target_parameter_code: string | null
          target_test_code: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clinical_source_decisions_materialized_range_id_fkey"
            columns: ["materialized_range_id"]
            isOneToOne: false
            referencedRelation: "reference_ranges"
            referencedColumns: ["id"]
          },
        ]
      }
      order_report_group_workspace: {
        Row: {
          clinical_section: string | null
          display_order: number | null
          execution_route:
            | Database["public"]["Enums"]["clinical_execution_route_enum"]
            | null
          frozen_test_code: string | null
          frozen_test_name: string | null
          group_key: string | null
          item_display_order: number | null
          latest_report_id: string | null
          latest_report_version: number | null
          lifecycle_state: string | null
          order_id: string | null
          order_item_id: string | null
          outsource_lab_name: string | null
          outsource_state:
            | Database["public"]["Enums"]["outsource_item_state_enum"]
            | null
          pdf_state:
            | Database["public"]["Enums"]["report_artifact_status_enum"]
            | null
          report_group_id: string | null
          report_state: string | null
          result_state: string | null
          row_version: number | null
          sample_id: string | null
          sample_state: Database["public"]["Enums"]["sample_status_enum"] | null
          test_id: string | null
          title: string | null
        }
        Relationships: [
          {
            foreignKeyName: "clinical_order_items_sample_id_fkey"
            columns: ["sample_id"]
            isOneToOne: false
            referencedRelation: "samples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_order_items_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "catalogue_test_operational_state"
            referencedColumns: ["test_id"]
          },
          {
            foreignKeyName: "clinical_order_items_test_id_fkey"
            columns: ["test_id"]
            isOneToOne: false
            referencedRelation: "tests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "clinical_report_groups_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "clinical_orders"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      allocate_patient_uhid: {
        Args: { p_normalized_mobile: string; p_registered_at: string }
        Returns: string
      }
      assert_clinical_result_ready: {
        Args: { p_order_item_id: string }
        Returns: undefined
      }
      assert_sms_gateway_v2_identity: {
        Args: { p_instance_id: string }
        Returns: undefined
      }
      ast_activate_breakpoint_set: {
        Args: { p_expected_revision: number; p_set_id: string }
        Returns: Json
      }
      ast_clone_breakpoint_set: {
        Args: {
          p_effective_date: string
          p_new_version: string
          p_source_id: string
        }
        Returns: Json
      }
      ast_interpret_breakpoint: {
        Args: {
          p_antibiotic_code: string
          p_breakpoint_set_id?: string
          p_method: string
          p_metric_secondary_value?: number
          p_metric_value: number
          p_organism_group_code: string
        }
        Returns: Json
      }
      ast_retire_breakpoint_set: {
        Args: { p_expected_revision: number; p_set_id: string }
        Returns: Json
      }
      ast_save_breakpoint_rule: {
        Args: { p_expected_revision?: number; p_payload: Json }
        Returns: Json
      }
      ast_save_breakpoint_set: {
        Args: { p_expected_revision?: number; p_payload: Json }
        Returns: Json
      }
      ast_save_isolate: {
        Args: {
          p_expected_revision?: number
          p_growth_state: string
          p_isolate_number: number
          p_microorganism_id: string
          p_order_item_id: string
        }
        Returns: Json
      }
      ast_save_microorganism_mapping: {
        Args: {
          p_code: string
          p_display_name: string
          p_expected_revision?: number
          p_group_id: string
        }
        Returns: Json
      }
      ast_save_observation: {
        Args: {
          p_antibiotic_id: string
          p_expected_revision?: number
          p_final_interpretation: string
          p_isolate_id: string
          p_method: string
          p_metric_secondary_value: number
          p_metric_value: number
          p_override_reason: string
        }
        Returns: Json
      }
      authorize_order_report_delivery: {
        Args: { p_token_hash: string }
        Returns: Json
      }
      authorize_order_report_pdf_artifact: {
        Args: { p_report_id: string; p_token_hash: string }
        Returns: Json
      }
      authorize_report_pdf_artifact: {
        Args: { p_token_hash: string }
        Returns: Json
      }
      bootstrap_first_admin: { Args: never; Returns: Json }
      calculation_dependency_blockers: {
        Args: { p_order_item_id: string }
        Returns: Json
      }
      catalogue_activate_rate: {
        Args: { p_expected_version: number; p_rate_id: string }
        Returns: undefined
      }
      catalogue_actor_name: { Args: never; Returns: string }
      catalogue_approve_calculation_formula: {
        Args: {
          p_effective_from: string
          p_expected_identifier: string
          p_expected_version: number
          p_formula_id: string
          p_reason: string
          p_rounding_scale: number
        }
        Returns: undefined
      }
      catalogue_approve_clinical_source_decision: {
        Args: { p_decision_id: string; p_expected_version: number }
        Returns: undefined
      }
      catalogue_archive_option_set: {
        Args: { p_expected_version: number; p_option_set_id: string }
        Returns: undefined
      }
      catalogue_archive_rate: {
        Args: { p_expected_version: number; p_rate_id: string }
        Returns: undefined
      }
      catalogue_booking_readiness: {
        Args: { p_test_ids: string[] }
        Returns: {
          approval_state: string
          classification: string
          test_id: string
        }[]
      }
      catalogue_bulk_set_current_rates: {
        Args: { p_changes: Json }
        Returns: Json
      }
      catalogue_cbc_source_completeness: {
        Args: never
        Returns: {
          blocker: string
          current_validated_policy: boolean
          mandatory: boolean
          parameter_code: string
          technical_decision_status: string
          v3_source_status: string
        }[]
      }
      catalogue_cbc_v4_completeness: {
        Args: never
        Returns: {
          age_coverage: string
          conflict_status: string
          formula_status: string
          method_analyzer_status: string
          parameter_code: string
          selected_source_candidate: string
          sex_coverage: string
          technical_decision_required: string
        }[]
      }
      catalogue_classification: {
        Args: { p_test: Database["public"]["Tables"]["tests"]["Row"] }
        Returns: string
      }
      catalogue_clinical_missing_configuration: {
        Args: { p_test_id: string }
        Returns: string[]
      }
      catalogue_clone_test: {
        Args: { p_code: string; p_name: string; p_test_id: string }
        Returns: string
      }
      catalogue_configuration_history: {
        Args: { p_test_id: string }
        Returns: {
          action_at: string
          actor_role: string
          category: string
          configuration_version: number
          reason: string
          status: string
        }[]
      }
      catalogue_create_rate_version: {
        Args: {
          p_effective_from?: string
          p_entity_id: string
          p_entity_type: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          p_other_service_code: string
          p_price_paisa: number
        }
        Returns: string
      }
      catalogue_decide_readiness: {
        Args: {
          p_decision: string
          p_expected_version: number
          p_reason: string
          p_test_id: string
        }
        Returns: number
      }
      catalogue_delete_category: {
        Args: { p_category_id: string; p_expected_version: number }
        Returns: undefined
      }
      catalogue_delete_or_archive_rate: {
        Args: { p_expected_version: number; p_rate_id: string }
        Returns: string
      }
      catalogue_delete_package: {
        Args: { p_expected_version: number; p_package_id: string }
        Returns: undefined
      }
      catalogue_delete_panel: {
        Args: { p_expected_version: number; p_panel_id: string }
        Returns: string
      }
      catalogue_delete_parameter: {
        Args: { p_expected_version: number; p_parameter_id: string }
        Returns: undefined
      }
      catalogue_delete_range: {
        Args: { p_expected_version: number; p_range_id: string }
        Returns: undefined
      }
      catalogue_delete_test: {
        Args: { p_expected_version: number; p_test_id: string }
        Returns: undefined
      }
      catalogue_expand_package: {
        Args: { p_package_id: string }
        Returns: {
          display_order: number
          package_code: string
          package_id: string
          package_name: string
          package_price_paisa: number
          test_code: string
          test_id: string
          test_name: string
        }[]
      }
      catalogue_expand_profile: {
        Args: { p_profile_test_id: string }
        Returns: {
          component_parameter_id: string
          component_role: string
          component_test_id: string
          display_order: number
          is_required: boolean
        }[]
      }
      catalogue_master_acceptance_summary: { Args: never; Returns: Json }
      catalogue_materialize_clinical_source_decision: {
        Args: { p_decision_id: string; p_expected_version: number }
        Returns: string
      }
      catalogue_panel_service_components: {
        Args: { p_service_id: string }
        Returns: {
          display_order: number
          panel_id: string
          panel_service_id: string
          readiness: Database["public"]["Enums"]["catalogue_result_readiness_enum"]
          test_code: string
          test_id: string
          test_name: string
        }[]
      }
      catalogue_price_master: {
        Args: never
        Returns: {
          item: Json
        }[]
      }
      catalogue_rate_history: {
        Args: {
          p_entity_id: string
          p_entity_type: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          p_other_service_code?: string
        }
        Returns: {
          item: Json
        }[]
      }
      catalogue_readiness_actor_role: { Args: never; Returns: string }
      catalogue_readiness_inventory: {
        Args: { p_query?: string; p_state?: string }
        Returns: Json[]
      }
      catalogue_record_clinical_source_decision: {
        Args: {
          p_action: string
          p_expected_item_version: number
          p_reason: string
          p_selected_policy: Json
          p_source_item_id: string
        }
        Returns: string
      }
      catalogue_record_configuration_review: {
        Args: {
          p_category: string
          p_expected_version: number
          p_reason: string
          p_source_metadata: Json
          p_test_id: string
        }
        Returns: number
      }
      catalogue_remove_panel_component: {
        Args: {
          p_display_order: number
          p_expected_panel_version: number
          p_panel_id: string
        }
        Returns: undefined
      }
      catalogue_reorder_panel_components: {
        Args: {
          p_component_ids: string[]
          p_expected_panel_version: number
          p_panel_id: string
        }
        Returns: undefined
      }
      catalogue_replace_ranges: {
        Args: { p_parameter_ids: string[]; p_ranges: Json }
        Returns: number
      }
      catalogue_require_manager: { Args: never; Returns: undefined }
      catalogue_require_readiness_staff: { Args: never; Returns: undefined }
      catalogue_require_technical: { Args: never; Returns: undefined }
      catalogue_save_analyzer: {
        Args: { p_analyzer: Json; p_expected_version?: number }
        Returns: string
      }
      catalogue_save_category: {
        Args: { p_category: Json; p_expected_version?: number }
        Returns: string
      }
      catalogue_save_option_set: {
        Args: { p_expected_version?: number; p_payload: Json }
        Returns: string
      }
      catalogue_save_option_value: {
        Args: { p_expected_version?: number; p_payload: Json }
        Returns: string
      }
      catalogue_save_package: {
        Args: {
          p_components: string[]
          p_expected_version?: number
          p_package: Json
        }
        Returns: string
      }
      catalogue_save_panel: {
        Args: { p_expected_version?: number; p_payload: Json }
        Returns: string
      }
      catalogue_save_panel_component: {
        Args: {
          p_component_parameter_id: string
          p_component_test_id: string
          p_display_name: string
          p_display_order: number
          p_expected_panel_version: number
          p_panel_id: string
        }
        Returns: undefined
      }
      catalogue_save_parameter: {
        Args: { p_expected_version?: number; p_parameter: Json }
        Returns: string
      }
      catalogue_save_range: {
        Args: { p_expected_version?: number; p_range: Json }
        Returns: string
      }
      catalogue_save_test: {
        Args: { p_expected_version?: number; p_test: Json }
        Returns: Json
      }
      catalogue_save_test_analyzer_configuration: {
        Args: { p_configuration: Json; p_expected_version?: number }
        Returns: string
      }
      catalogue_save_test_conservative_00089: {
        Args: { p_expected_version?: number; p_test: Json }
        Returns: Json
      }
      catalogue_search_rate_list: {
        Args: {
          p_category_id?: string
          p_desc?: boolean
          p_entity_type?: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          p_lifecycle?: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          p_limit?: number
          p_offset?: number
          p_priced?: boolean
          p_query?: string
          p_sort?: string
        }
        Returns: {
          item: Json
          total_count: number
        }[]
      }
      catalogue_service_readiness_checklist: {
        Args: { p_test_id: string }
        Returns: Json
      }
      catalogue_set_category_lifecycle: {
        Args: {
          p_category_id: string
          p_expected_version: number
          p_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
        }
        Returns: undefined
      }
      catalogue_set_current_rate: {
        Args: {
          p_entity_id: string
          p_entity_type: Database["public"]["Enums"]["catalogue_billable_entity_enum"]
          p_expected_rate_id?: string
          p_expected_rate_version?: number
          p_price_paisa: number
          p_reason?: string
        }
        Returns: Json
      }
      catalogue_set_package_lifecycle: {
        Args: {
          p_expected_version: number
          p_package_id: string
          p_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
        }
        Returns: undefined
      }
      catalogue_set_panel_lifecycle: {
        Args: {
          p_expected_version: number
          p_panel_id: string
          p_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
        }
        Returns: undefined
      }
      catalogue_set_parameter_calculation_reporting_mode: {
        Args: {
          p_mode: Database["public"]["Enums"]["calculation_reporting_mode_enum"]
          p_parameter_id: string
          p_reason: string
        }
        Returns: undefined
      }
      catalogue_set_parameter_lifecycle: {
        Args: {
          p_expected_version: number
          p_parameter_id: string
          p_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
        }
        Returns: undefined
      }
      catalogue_set_parameter_option_set: {
        Args: {
          p_expected_version: number
          p_option_set_id: string
          p_parameter_id: string
        }
        Returns: undefined
      }
      catalogue_set_range_lifecycle: {
        Args: {
          p_expected_version: number
          p_range_id: string
          p_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
        }
        Returns: undefined
      }
      catalogue_set_test_lifecycle: {
        Args: {
          p_expected_version: number
          p_status: Database["public"]["Enums"]["catalogue_lifecycle_enum"]
          p_test_id: string
        }
        Returns: Json
      }
      catalogue_set_test_operational_gates: {
        Args: {
          p_billing_enabled: boolean
          p_clinical_reporting_enabled: boolean
          p_collection_required: boolean
          p_expected_version: number
          p_test_id: string
        }
        Returns: Json
      }
      catalogue_start_template_copy: {
        Args: {
          p_proposed_code: string
          p_proposed_name: string
          p_source_order: number
        }
        Returns: string
      }
      catalogue_submit_for_review: {
        Args: {
          p_expected_version: number
          p_reason: string
          p_test_id: string
        }
        Returns: number
      }
      catalogue_technical_save_range: {
        Args: { p_expected_version: number; p_range: Json; p_reason: string }
        Returns: string
      }
      catalogue_technical_update_parameter: {
        Args: {
          p_expected_version: number
          p_parameter_id: string
          p_patch: Json
          p_reason: string
        }
        Returns: number
      }
      catalogue_technical_update_test: {
        Args: {
          p_expected_version: number
          p_patch: Json
          p_reason: string
          p_test_id: string
        }
        Returns: number
      }
      catalogue_test_missing_configuration: {
        Args: { p_test_id: string }
        Returns: string[]
      }
      catalogue_test_operational_label: {
        Args: { p_test_id: string }
        Returns: string
      }
      catalogue_test_result_readiness: {
        Args: { p_test_id: string }
        Returns: Database["public"]["Enums"]["catalogue_result_readiness_enum"]
      }
      catalogue_test_template_detail: {
        Args: { p_source_order: number }
        Returns: Json
      }
      catalogue_update_test_price: {
        Args: {
          p_acknowledge_zero_price?: boolean
          p_price_paisa: number
          p_test_id: string
        }
        Returns: undefined
      }
      check_order_report_readiness: {
        Args: { p_order_id: string }
        Returns: Json
      }
      check_report_group_readiness: {
        Args: { p_report_group_id: string }
        Returns: Json
      }
      claim_next_sms_gateway_item: {
        Args: { p_lease_seconds?: number; p_worker_id: string }
        Returns: {
          id: string
          idempotency_key: string
          lease_owner: string
          max_attempts: number
          message_body: string
          recipient_phone: string
          retry_count: number
          sms_type: string
        }[]
      }
      claim_report_pdf_artifact: {
        Args: { p_lease_seconds?: number }
        Returns: {
          artifact_created_at: string
          artifact_id: string
          lease_owner: string
          public_url: string
          report_id: string
          report_integrity_hash: string
          report_version: number
          snapshot: Json
          snapshot_sha256: string
        }[]
      }
      claim_report_pdf_artifact_v2: {
        Args: { p_lease_seconds?: number }
        Returns: {
          artifact_created_at: string
          artifact_id: string
          lease_owner: string
          public_url: string
          report_id: string
          report_integrity_hash: string
          report_number: string
          report_version: number
          snapshot: Json
          snapshot_sha256: string
        }[]
      }
      claim_sms_batch: {
        Args: { p_batch_size?: number }
        Returns: {
          id: string
          max_attempts: number
          message_body: string
          recipient_name: string
          recipient_phone: string
          retry_count: number
          sms_type: string
        }[]
      }
      claim_sms_gateway_item: {
        Args: { p_sms_id: string }
        Returns: {
          id: string
          idempotency_key: string
          max_attempts: number
          message_body: string
          recipient_phone: string
          retry_count: number
          sms_type: string
        }[]
      }
      claim_sms_gateway_v2_batch: {
        Args: {
          p_batch_size?: number
          p_instance_id: string
          p_lease_seconds?: number
          p_worker_id: string
        }
        Returns: {
          id: string
          idempotency_key: string
          lease_owner: string
          max_attempts: number
          message_body: string
          recipient_phone: string
          retry_count: number
          sms_type: string
        }[]
      }
      clinical_result_collection_readiness: {
        Args: { p_order_item_id: string }
        Returns: Json
      }
      complete_report_pdf_artifact: {
        Args: {
          p_artifact_id: string
          p_byte_size?: number
          p_failure_code?: string
          p_generator_name?: string
          p_generator_version?: string
          p_lease_owner: string
          p_pdf_sha256?: string
          p_ready: boolean
        }
        Returns: Json
      }
      complete_report_pdf_artifact_v2: {
        Args: {
          p_artifact_id: string
          p_byte_size?: number
          p_failure_code?: string
          p_generator_name?: string
          p_generator_version?: string
          p_lease_owner: string
          p_pdf_sha256?: string
          p_ready: boolean
        }
        Returns: Json
      }
      complete_sms_gateway_item: {
        Args: {
          p_accepted: boolean
          p_error_classification?: string
          p_error_msg?: string
          p_provider_msg_id?: string
          p_provider_response?: Json
          p_provider_response_code?: string
          p_retryable?: boolean
          p_sms_id: string
          p_worker_id: string
        }
        Returns: Json
      }
      complete_sms_gateway_v2_item: {
        Args: {
          p_accepted: boolean
          p_error_classification?: string
          p_error_msg?: string
          p_instance_id: string
          p_provider_msg_id?: string
          p_provider_response?: Json
          p_provider_response_code?: string
          p_retryable?: boolean
          p_sms_id: string
          p_worker_id: string
        }
        Returns: Json
      }
      configure_reference_laboratory: {
        Args: { p_expected_version?: number; p_payload: Json }
        Returns: Json
      }
      create_patient: {
        Args: { p_patient_data: Json }
        Returns: {
          address: string
          age_days: number | null
          age_months: number | null
          age_years: number | null
          archived_at: string | null
          archived_by: string | null
          created_at: string
          dob: string | null
          email: string | null
          full_name: string
          gender: string
          id: string
          identification_no: string | null
          is_active: boolean
          mobile: string
          title: string | null
          uhid: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "patients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_patient_bill_and_order:
        | {
            Args: {
              p_bill_data: Json
              p_items_data: Json[]
              p_patient_data: Json
              p_payment_data?: Json
            }
            Returns: Json
          }
        | {
            Args: {
              p_bill_data: Json
              p_idempotency_key: string
              p_items_data: Json[]
              p_patient_data: Json
              p_payment_data: Json
            }
            Returns: Json
          }
      create_patient_bill_order_mixed_catalogue: {
        Args: {
          p_agreed_panel_price_paisa?: number
          p_bill_data: Json
          p_expected_panel_version?: number
          p_idempotency_key: string
          p_items_data: Json[]
          p_packages?: Json
          p_panel_service_id?: string
          p_patient_data: Json
          p_payment_data: Json
        }
        Returns: Json
      }
      create_patient_bill_order_with_packages: {
        Args: {
          p_bill_data: Json
          p_idempotency_key: string
          p_items_data: Json[]
          p_packages?: Json
          p_patient_data: Json
          p_payment_data: Json
        }
        Returns: Json
      }
      create_patient_bill_order_with_panel_service:
        | {
            Args: {
              p_bill_data: Json
              p_expected_panel_version: number
              p_idempotency_key: string
              p_panel_service_id: string
              p_patient_data: Json
              p_payment_data: Json
            }
            Returns: Json
          }
        | {
            Args: {
              p_agreed_panel_price_paisa: number
              p_bill_data: Json
              p_expected_panel_version: number
              p_idempotency_key: string
              p_panel_service_id: string
              p_patient_data: Json
              p_payment_data: Json
            }
            Returns: Json
          }
      create_public_report_token: {
        Args: {
          p_expiry_days?: number
          p_public_url_base?: string
          p_report_id: string
          p_token_hash: string
        }
        Returns: Json
      }
      delete_unused_patient: { Args: { p_patient_id: string }; Returns: Json }
      derive_order_reporting_state: {
        Args: { p_order_id: string }
        Returns: string
      }
      enqueue_missing_report_pdf_artifacts: {
        Args: { p_limit?: number }
        Returns: number
      }
      ensure_bill_collection_traceability: {
        Args: { p_bill_id: string }
        Returns: Json
      }
      evaluate_governed_formula: {
        Args: { p_formula_key: string; p_inputs: Json }
        Returns: number
      }
      finalize_hmis_report: {
        Args: {
          p_report_id: string
          p_revision_reason?: string
          p_snapshot: Json
        }
        Returns: {
          created_at: string
          finalized_at: string
          finalized_by: string
          generated_by: string
          id: string
          parent_version: number | null
          report_id: string
          revision_reason: string | null
          sha256: string
          snapshot_json: Json
          version: number
        }
        SetofOptions: {
          from: "*"
          to: "hmis_monthly_report_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_dashboard_collection_summary: {
        Args: never
        Returns: {
          month_collection_paisa: number
          month_count: number
          month_label: string
          today_collection_paisa: number
          today_count: number
          total_collection_paisa: number
          total_count: number
        }[]
      }
      get_dashboard_operational_summary: { Args: never; Returns: Json }
      get_report_pdf_delivery_acceptance_candidate: {
        Args: never
        Returns: Json
      }
      get_report_secure_link_status: {
        Args: { p_report_id: string }
        Returns: Json
      }
      get_sms_delivery_status: {
        Args: { p_limit?: number }
        Returns: {
          created_at: string
          estimated_segments: number
          event_type: string
          id: string
          lab_no: string
          manual_retry_count: number
          mobile: string
          provider_message_id: string
          provider_status: string
          retry_count: number
          sent_at: string
          status: string
        }[]
      }
      get_sms_gateway_v2_health: { Args: never; Returns: Json }
      get_technician_operational_summary: { Args: never; Returns: Json }
      has_permission: { Args: { p_permission_key: string }; Returns: boolean }
      heartbeat_sms_gateway_v2: {
        Args: {
          p_active_job_count: number
          p_gateway_version: string
          p_hostname: string
          p_instance_id: string
          p_last_provider_success_at: string
          p_last_successful_queue_access_at: string
          p_provider_health: string
          p_provider_name: string
          p_safe_last_error_code: string
          p_service_started_at: string
        }
        Returns: Json
      }
      hmis_auto_summary: { Args: { p_month: string }; Returns: Json }
      hmis_identity_options: { Args: never; Returns: Json }
      is_active_user: { Args: never; Returns: boolean }
      is_report_artifact_worker: { Args: never; Returns: boolean }
      is_super_admin: { Args: never; Returns: boolean }
      list_laboratory_worklist_departments: {
        Args: never
        Returns: {
          department: string
        }[]
      }
      mark_sms_gateway_v2_provider_call_started: {
        Args: { p_instance_id: string; p_sms_id: string; p_worker_id: string }
        Returns: boolean
      }
      mark_sms_provider_call_started: {
        Args: { p_sms_id: string; p_worker_id: string }
        Returns: boolean
      }
      normalize_clinical_calculation_input: {
        Args: {
          p_canonical_unit: string
          p_supplied_unit: string
          p_value: number
        }
        Returns: number
      }
      normalize_nepal_sms_mobile: {
        Args: { p_mobile: string }
        Returns: string
      }
      notify_updated_order_reports: {
        Args: {
          p_expected_generation: number
          p_order_id: string
          p_reason: string
        }
        Returns: Json
      }
      patient_actor_name: { Args: never; Returns: string }
      patient_clean_text: { Args: { p_value: string }; Returns: string }
      patient_normalize_mobile: { Args: { p_mobile: string }; Returns: string }
      provision_historical_report_secure_link: {
        Args: {
          p_expiry_days?: number
          p_public_url: string
          p_report_id: string
          p_token_hash: string
        }
        Returns: Json
      }
      queue_bill_sms: { Args: { p_bill_id: string }; Returns: Json }
      receive_bill_payment: {
        Args: {
          p_amount_paisa: number
          p_bill_id: string
          p_idempotency_key: string
          p_payment_mode: Database["public"]["Enums"]["payment_mode_enum"]
          p_remarks: string
          p_transaction_reference: string
        }
        Returns: Json
      }
      recompute_order_item_calculated_results: {
        Args: { p_order_item_id: string }
        Returns: undefined
      }
      record_critical_value_acknowledgement: {
        Args: {
          p_comment?: string
          p_notification_method: string
          p_notified_person: string
          p_order_item_id: string
        }
        Returns: Json
      }
      record_hmis_submission: {
        Args: {
          p_attachment_path?: string
          p_method: string
          p_reference?: string
          p_remarks?: string
          p_report_id: string
          p_submission_date: string
          p_submitted_to: string
        }
        Returns: {
          attachment_path: string | null
          created_at: string
          id: string
          method: string
          recorded_by: string
          reference_receipt_no: string | null
          remarks: string | null
          report_id: string
          report_version: number
          submission_date: string
          submitted: boolean
          submitted_to: string
        }
        SetofOptions: {
          from: "*"
          to: "hmis_submission_events"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      recover_stale_sms_gateway_items: {
        Args: { p_stale_after_seconds?: number }
        Returns: Json
      }
      recover_stale_sms_gateway_v2_items: {
        Args: { p_instance_id: string; p_stale_after_seconds?: number }
        Returns: Json
      }
      register_report_artifact_worker: {
        Args: {
          p_auth_user_id: string
          p_confirmation: string
          p_worker_name: string
        }
        Returns: undefined
      }
      register_sms_gateway_v2_instance: {
        Args: {
          p_auth_user_id: string
          p_gateway_version: string
          p_hostname: string
          p_instance_id: string
          p_provider_name: string
        }
        Returns: Json
      }
      reject_sms_gateway_v2_local_validation: {
        Args: {
          p_error_code: string
          p_instance_id: string
          p_sms_id: string
          p_worker_id: string
        }
        Returns: boolean
      }
      replace_role_permission_matrix: {
        Args: { p_matrix: Json }
        Returns: number
      }
      report_artifact_public_url: {
        Args: { p_report_id: string }
        Returns: string
      }
      require_outsource_tracking_permission: { Args: never; Returns: undefined }
      resolve_public_report_by_token: {
        Args: { p_token_hash: string }
        Returns: Json
      }
      retry_sms_delivery: {
        Args: { p_reason: string; p_sms_id: string }
        Returns: Json
      }
      revoke_public_report_token: {
        Args: { p_reason?: string; p_token_id: string }
        Returns: Json
      }
      run_governed_order_item_calculations: {
        Args: { p_order_item_id: string }
        Returns: undefined
      }
      save_pus_culture_worksheet: {
        Args: {
          p_expected_revision: number
          p_order_item_id: string
          p_payload: Json
        }
        Returns: Json
      }
      save_referring_doctor: { Args: { p_doctor: Json }; Returns: string }
      save_reporting_personnel: { Args: { p_personnel: Json }; Returns: string }
      save_test_results: {
        Args: {
          p_amended_from_report_id: string
          p_amendment_reason: string
          p_expected_revision: number
          p_order_item_id: string
          p_results: Json
          p_target_status: Database["public"]["Enums"]["result_status_enum"]
        }
        Returns: Json
      }
      save_test_results_revision_internal: {
        Args: {
          p_amended_from_report_id: string
          p_amendment_reason: string
          p_expected_revision: number
          p_order_item_id: string
          p_results: Json
          p_target_status: Database["public"]["Enums"]["result_status_enum"]
        }
        Returns: Json
      }
      save_test_results_scoping_internal_00090: {
        Args: {
          p_amended_from_report_id: string
          p_amendment_reason: string
          p_expected_revision: number
          p_order_item_id: string
          p_results: Json
          p_target_status: Database["public"]["Enums"]["result_status_enum"]
        }
        Returns: Json
      }
      save_test_results_unversioned_internal: {
        Args: {
          p_amended_from_report_id?: string
          p_amendment_reason?: string
          p_order_item_id: string
          p_results: Json
          p_target_status: Database["public"]["Enums"]["result_status_enum"]
        }
        Returns: Json
      }
      search_audit_log: {
        Args: {
          p_action?: string
          p_actor?: string
          p_cursor_id?: string
          p_cursor_timestamp?: string
          p_date_from?: string
          p_date_to?: string
          p_entity?: string
          p_exact_id?: string
          p_limit?: number
        }
        Returns: {
          item: Json
          sort_id: string
          sort_timestamp: string
        }[]
      }
      search_bill_registry: {
        Args: {
          p_cursor_created_at?: string
          p_cursor_id?: string
          p_date?: string
          p_limit?: number
          p_payment_status?: string
          p_search?: string
        }
        Returns: {
          item: Json
        }[]
      }
      search_billable_catalogue: {
        Args: { p_limit?: number; p_query: string }
        Returns: {
          allow_zero_price_billing: boolean
          category: string
          code: string
          container: string
          entity_id: string
          entity_type: string
          name: string
          price_configured: boolean
          price_paisa: number
          pricing_policy: Database["public"]["Enums"]["catalogue_pricing_policy_enum"]
          rank_score: number
          reporting_type: Database["public"]["Enums"]["reporting_type_enum"]
          short_name: string
          specimen: string
        }[]
      }
      search_dashboard_orders: {
        Args: {
          p_cursor_created_at?: string
          p_cursor_id?: string
          p_limit?: number
          p_search?: string
          p_workflow?: string
        }
        Returns: {
          item: Json
        }[]
      }
      search_laboratory_worklist: {
        Args: {
          p_cursor_created_at?: string
          p_cursor_id?: string
          p_department?: string
          p_limit?: number
          p_order_date?: string
          p_sample_status?: string
          p_search?: string
          p_view?: string
        }
        Returns: {
          item: Json
        }[]
      }
      search_patient_history: {
        Args: {
          p_cursor_id?: string
          p_cursor_timestamp?: string
          p_limit?: number
          p_patient_id: string
          p_section: string
        }
        Returns: {
          item: Json
          sort_id: string
          sort_timestamp: string
        }[]
      }
      search_patient_registry: {
        Args: {
          p_active_state?: string
          p_cursor_created_at?: string
          p_cursor_id?: string
          p_limit?: number
          p_search?: string
        }
        Returns: {
          item: Json
        }[]
      }
      search_report_registry: {
        Args: {
          p_amendment_state?: string
          p_cursor_id?: string
          p_cursor_signed_at?: string
          p_date?: string
          p_limit?: number
          p_search?: string
          p_status?: string
        }
        Returns: {
          item: Json
        }[]
      }
      search_sample_accessioning: {
        Args: {
          p_cursor_created_at?: string
          p_cursor_id?: string
          p_date?: string
          p_limit?: number
          p_search?: string
          p_specimen?: string
          p_status?: string
        }
        Returns: {
          item: Json
        }[]
      }
      search_sms_delivery_status: {
        Args: {
          p_cursor_created_at?: string
          p_cursor_id?: string
          p_date?: string
          p_event_type?: string
          p_limit?: number
          p_search?: string
          p_status?: string
        }
        Returns: {
          item: Json
          sort_created_at: string
          sort_id: string
        }[]
      }
      set_patient_archived: {
        Args: { p_archived: boolean; p_patient_id: string }
        Returns: {
          address: string
          age_days: number | null
          age_months: number | null
          age_years: number | null
          archived_at: string | null
          archived_by: string | null
          created_at: string
          dob: string | null
          email: string | null
          full_name: string
          gender: string
          id: string
          identification_no: string | null
          is_active: boolean
          mobile: string
          title: string | null
          uhid: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "patients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_sms_gateway_v2_claiming: {
        Args: {
          p_confirmation: string
          p_enabled: boolean
          p_instance_id: string
        }
        Returns: Json
      }
      set_sms_gateway_v2_enabled: {
        Args: {
          p_confirmation: string
          p_enabled: boolean
          p_instance_id: string
        }
        Returns: Json
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      sign_and_freeze_diagnostic_report: {
        Args: {
          p_amended_from_report_id?: string
          p_amendment_reason?: string
          p_order_id: string
          p_performed_by_id: string
          p_signed_by_id: string
        }
        Returns: Json
      }
      sign_and_queue_diagnostic_report: {
        Args: {
          p_amended_from_report_id: string
          p_amendment_reason: string
          p_order_id: string
          p_performed_by_id: string
          p_public_report_url: string
          p_signed_by_id: string
          p_token_hash: string
        }
        Returns: Json
      }
      sign_and_queue_report_group: {
        Args: {
          p_amended_from_report_id: string
          p_amendment_reason: string
          p_order_public_url: string
          p_performed_by_id: string
          p_report_group_id: string
          p_signed_by_id: string
          p_token_hash: string
        }
        Returns: Json
      }
      sign_report_group: {
        Args: {
          p_amended_from_report_id?: string
          p_amendment_reason?: string
          p_performed_by_id: string
          p_report_group_id: string
          p_signed_by_id?: string
        }
        Returns: Json
      }
      sms_gateway_v2_preflight: {
        Args: { p_instance_id: string }
        Returns: Json
      }
      transition_outsource_order_item: {
        Args: {
          p_destination_id?: string
          p_external_reference?: string
          p_order_item_id: string
          p_payload?: Json
          p_reason?: string
          p_to_state: Database["public"]["Enums"]["outsource_item_state_enum"]
        }
        Returns: Json
      }
      transition_sample_lifecycle: {
        Args: {
          p_reason?: string
          p_sample_id: string
          p_to_status: Database["public"]["Enums"]["sample_status_enum"]
        }
        Returns: Json
      }
      update_outsource_sample_status: {
        Args: {
          p_meta?: Json
          p_notes?: string
          p_sample_id: string
          p_to_status: Database["public"]["Enums"]["outsource_sample_status_enum"]
        }
        Returns: Json
      }
      update_patient_demographics: {
        Args: { p_patient_data: Json; p_patient_id: string }
        Returns: {
          address: string
          age_days: number | null
          age_months: number | null
          age_years: number | null
          archived_at: string | null
          archived_by: string | null
          created_at: string
          dob: string | null
          email: string | null
          full_name: string
          gender: string
          id: string
          identification_no: string | null
          is_active: boolean
          mobile: string
          title: string | null
          uhid: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "patients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_sms_status: {
        Args: {
          p_error_msg?: string
          p_is_permanent_failure?: boolean
          p_provider_msg_id?: string
          p_provider_response?: Json
          p_sms_id: string
          p_status: string
        }
        Returns: Json
      }
      update_user_access: {
        Args: {
          p_is_active: boolean
          p_is_super_admin: boolean
          p_role_ids?: string[]
          p_user_id: string
        }
        Returns: Json
      }
      uuid_generate_v4: { Args: never; Returns: string }
    }
    Enums: {
      analyzer_lifecycle_enum: "Draft" | "Active" | "Archived"
      calculation_reporting_mode_enum:
        | "Measured"
        | "Calculated"
        | "MeasuredWithCalculatedConsistencyCheck"
      catalogue_billable_entity_enum: "Test" | "Panel" | "Package" | "Other"
      catalogue_decision_status_enum:
        | "Configured"
        | "Reviewed"
        | "Approved"
        | "Rejected"
      catalogue_lifecycle_enum: "Draft" | "Active" | "Archived"
      catalogue_pricing_policy_enum:
        | "Fixed"
        | "Negotiable"
        | "PricePending"
        | "Manual"
      catalogue_rate_status_enum: "Draft" | "Active" | "Inactive" | "Archived"
      catalogue_readiness_state_enum:
        | "Draft"
        | "NeedsConfiguration"
        | "ReadyForReview"
        | "Approved"
        | "Suspended"
      catalogue_reporting_model_enum:
        | "NumericSingle"
        | "NumericMultiParameter"
        | "Qualitative"
        | "MixedTyped"
        | "StructuredNested"
        | "NarrativeDocument"
        | "Calculated"
        | "Profile"
        | "MicrobiologyWorkflow"
        | "CytologyWorkflow"
        | "MolecularWorkflow"
      catalogue_result_readiness_enum:
        | "Ready"
        | "Incomplete"
        | "SpecialistWorkflow"
        | "DocumentWorkflow"
        | "NoReporting"
        | "Inactive"
      catalogue_source_disposition_enum:
        | "CanonicalStandaloneTest"
        | "CanonicalProfile"
        | "ProfileComponentOnly"
        | "AliasOnly"
        | "DuplicateDoNotCreate"
        | "DraftNewIdentity"
        | "SpecialistWorkflow"
        | "ConflictNeedsOperatorDecision"
        | "RetireCandidate"
      catalogue_test_kind_enum: "Individual" | "Profile"
      clinical_configuration_status_enum:
        | "Configured"
        | "Requires Clinical Validation"
        | "Ready for Activation"
        | "Workflow Not Supported"
      clinical_execution_route_enum: "INTERNAL" | "OUTSOURCE"
      clinical_workflow_type_enum:
        | "Routine"
        | "MicrobiologyCulture"
        | "MicrobiologyMicroscopy"
        | "Cytology"
        | "Histopathology"
        | "Molecular"
        | "Outsource"
        | "NoClinicalReport"
      outsource_item_state_enum:
        | "AwaitingDispatch"
        | "Dispatched"
        | "AwaitingExternalResult"
        | "ResultReceived"
        | "InternalReview"
        | "Verified"
        | "Signed"
        | "Rejected"
        | "RecollectionRequired"
        | "Cancelled"
        | "UnableToPerform"
      outsource_sample_status_enum:
        | "ReceivedAtBimal"
        | "PreparedForDispatch"
        | "DispatchedToReferenceLab"
        | "ReceivedByReferenceLab"
        | "ProcessingAtReferenceLab"
        | "ResultReceived"
        | "MaterialReturned"
        | "Completed"
        | "Rejected"
        | "Cancelled"
        | "LostInTransit"
      parameter_clinical_class_enum:
        | "Measured"
        | "Calculated"
        | "DerivedInterpretation"
        | "ReferencePolicy"
      parameter_value_type_enum:
        | "Numeric"
        | "Text"
        | "Select"
        | "Boolean"
        | "Heading"
        | "Calculated"
      payment_mode_enum:
        | "Cash"
        | "Fonepay"
        | "eSewa"
        | "Khalti"
        | "Card"
        | "Bank"
        | "Credit"
        | "Other"
      payment_status_enum: "Paid" | "Partial" | "Due"
      professional_type_enum:
        | "Pathologist"
        | "Lab Technologist"
        | "Lab Technician"
        | "Lab Assistant"
        | "Receptionist"
        | "Admin"
      reference_range_validation_state_enum:
        | "Unclassified"
        | "ClinicallyValidated"
        | "LegacyDefaultRequiresValidation"
      report_artifact_status_enum:
        | "Pending"
        | "Generating"
        | "GenerationFailed"
        | "UploadFailed"
        | "Ready"
      reporting_type_enum:
        | "InHouse"
        | "OutsourceWithBimalReport"
        | "NoReporting"
      result_flag_enum:
        | "Normal"
        | "Low"
        | "High"
        | "CriticalLow"
        | "CriticalHigh"
        | "Abnormal"
        | "NoRange"
      result_status_enum:
        | "Draft"
        | "SubmittedForVerification"
        | "Verified"
        | "SignedOff"
        | "ReturnedForCorrection"
      sample_status_enum:
        | "Pending"
        | "Collected"
        | "Received"
        | "Rejected"
        | "Recollected"
        | "Processing"
        | "Completed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      analyzer_lifecycle_enum: ["Draft", "Active", "Archived"],
      calculation_reporting_mode_enum: [
        "Measured",
        "Calculated",
        "MeasuredWithCalculatedConsistencyCheck",
      ],
      catalogue_billable_entity_enum: ["Test", "Panel", "Package", "Other"],
      catalogue_decision_status_enum: [
        "Configured",
        "Reviewed",
        "Approved",
        "Rejected",
      ],
      catalogue_lifecycle_enum: ["Draft", "Active", "Archived"],
      catalogue_pricing_policy_enum: [
        "Fixed",
        "Negotiable",
        "PricePending",
        "Manual",
      ],
      catalogue_rate_status_enum: ["Draft", "Active", "Inactive", "Archived"],
      catalogue_readiness_state_enum: [
        "Draft",
        "NeedsConfiguration",
        "ReadyForReview",
        "Approved",
        "Suspended",
      ],
      catalogue_reporting_model_enum: [
        "NumericSingle",
        "NumericMultiParameter",
        "Qualitative",
        "MixedTyped",
        "StructuredNested",
        "NarrativeDocument",
        "Calculated",
        "Profile",
        "MicrobiologyWorkflow",
        "CytologyWorkflow",
        "MolecularWorkflow",
      ],
      catalogue_result_readiness_enum: [
        "Ready",
        "Incomplete",
        "SpecialistWorkflow",
        "DocumentWorkflow",
        "NoReporting",
        "Inactive",
      ],
      catalogue_source_disposition_enum: [
        "CanonicalStandaloneTest",
        "CanonicalProfile",
        "ProfileComponentOnly",
        "AliasOnly",
        "DuplicateDoNotCreate",
        "DraftNewIdentity",
        "SpecialistWorkflow",
        "ConflictNeedsOperatorDecision",
        "RetireCandidate",
      ],
      catalogue_test_kind_enum: ["Individual", "Profile"],
      clinical_configuration_status_enum: [
        "Configured",
        "Requires Clinical Validation",
        "Ready for Activation",
        "Workflow Not Supported",
      ],
      clinical_execution_route_enum: ["INTERNAL", "OUTSOURCE"],
      clinical_workflow_type_enum: [
        "Routine",
        "MicrobiologyCulture",
        "MicrobiologyMicroscopy",
        "Cytology",
        "Histopathology",
        "Molecular",
        "Outsource",
        "NoClinicalReport",
      ],
      outsource_item_state_enum: [
        "AwaitingDispatch",
        "Dispatched",
        "AwaitingExternalResult",
        "ResultReceived",
        "InternalReview",
        "Verified",
        "Signed",
        "Rejected",
        "RecollectionRequired",
        "Cancelled",
        "UnableToPerform",
      ],
      outsource_sample_status_enum: [
        "ReceivedAtBimal",
        "PreparedForDispatch",
        "DispatchedToReferenceLab",
        "ReceivedByReferenceLab",
        "ProcessingAtReferenceLab",
        "ResultReceived",
        "MaterialReturned",
        "Completed",
        "Rejected",
        "Cancelled",
        "LostInTransit",
      ],
      parameter_clinical_class_enum: [
        "Measured",
        "Calculated",
        "DerivedInterpretation",
        "ReferencePolicy",
      ],
      parameter_value_type_enum: [
        "Numeric",
        "Text",
        "Select",
        "Boolean",
        "Heading",
        "Calculated",
      ],
      payment_mode_enum: [
        "Cash",
        "Fonepay",
        "eSewa",
        "Khalti",
        "Card",
        "Bank",
        "Credit",
        "Other",
      ],
      payment_status_enum: ["Paid", "Partial", "Due"],
      professional_type_enum: [
        "Pathologist",
        "Lab Technologist",
        "Lab Technician",
        "Lab Assistant",
        "Receptionist",
        "Admin",
      ],
      reference_range_validation_state_enum: [
        "Unclassified",
        "ClinicallyValidated",
        "LegacyDefaultRequiresValidation",
      ],
      report_artifact_status_enum: [
        "Pending",
        "Generating",
        "GenerationFailed",
        "UploadFailed",
        "Ready",
      ],
      reporting_type_enum: [
        "InHouse",
        "OutsourceWithBimalReport",
        "NoReporting",
      ],
      result_flag_enum: [
        "Normal",
        "Low",
        "High",
        "CriticalLow",
        "CriticalHigh",
        "Abnormal",
        "NoRange",
      ],
      result_status_enum: [
        "Draft",
        "SubmittedForVerification",
        "Verified",
        "SignedOff",
        "ReturnedForCorrection",
      ],
      sample_status_enum: [
        "Pending",
        "Collected",
        "Received",
        "Rejected",
        "Recollected",
        "Processing",
        "Completed",
      ],
    },
  },
} as const
