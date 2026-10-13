
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "public": {
          Tables: {
            "aircraft": {
                  Row: {
                    "billed_hour_rounding": Database["public"]['Enums']["hour_rounding"],"billing_basis": Database["public"]['Enums']["billing_basis"],"company_id": string,"created_at": string,"expected_hours_per_year": number | null,"expense_approval_rule": Database["public"]['Enums']["expense_approval_rule"],"fixed_cost_split": Database["public"]['Enums']["fixed_cost_split"],"id": string,"nickname": string | null,"place_match_radius_m": number,"registration": string,"tach_factor": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "billed_hour_rounding"?: Database["public"]['Enums']["hour_rounding"],"billing_basis"?: Database["public"]['Enums']["billing_basis"],"company_id": string,"created_at"?: string,"expected_hours_per_year"?: number | null,"expense_approval_rule"?: Database["public"]['Enums']["expense_approval_rule"],"fixed_cost_split"?: Database["public"]['Enums']["fixed_cost_split"],"id"?: string,"nickname"?: string | null,"place_match_radius_m"?: number,"registration": string,"tach_factor"?: number,"updated_at"?: string
                  }
                  Update: {
                    "billed_hour_rounding"?: Database["public"]['Enums']["hour_rounding"],"billing_basis"?: Database["public"]['Enums']["billing_basis"],"company_id"?: string,"created_at"?: string,"expected_hours_per_year"?: number | null,"expense_approval_rule"?: Database["public"]['Enums']["expense_approval_rule"],"fixed_cost_split"?: Database["public"]['Enums']["fixed_cost_split"],"id"?: string,"nickname"?: string | null,"place_match_radius_m"?: number,"registration"?: string,"tach_factor"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "aircraft_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "company"
      referencedColumns: ["id"]
    }
                  ]
                },"api_token": {
                  Row: {
                    "created_at": string,"id": string,"label": string | null,"last_used_at": string | null,"member_id": string,"revoked_at": string | null,"token_hash": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"label"?: string | null,"last_used_at"?: string | null,"member_id": string,"revoked_at"?: string | null,"token_hash": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"label"?: string | null,"last_used_at"?: string | null,"member_id"?: string,"revoked_at"?: string | null,"token_hash"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "api_token_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"company": {
                  Row: {
                    "ar_account_code": string | null,"bank_account_code": string | null,"created_at": string,"etransfer_recipient": string | null,"fiscal_year_end_month": number,"gst_number": string | null,"gst_rate": number,"gst_registered": boolean,"id": string,"legal_name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "ar_account_code"?: string | null,"bank_account_code"?: string | null,"created_at"?: string,"etransfer_recipient"?: string | null,"fiscal_year_end_month"?: number,"gst_number"?: string | null,"gst_rate"?: number,"gst_registered"?: boolean,"id"?: string,"legal_name": string,"updated_at"?: string
                  }
                  Update: {
                    "ar_account_code"?: string | null,"bank_account_code"?: string | null,"created_at"?: string,"etransfer_recipient"?: string | null,"fiscal_year_end_month"?: number,"gst_number"?: string | null,"gst_rate"?: number,"gst_registered"?: boolean,"id"?: string,"legal_name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"fixed_cost": {
                  Row: {
                    "gl_account_code": string,"id": string,"kind": Database["public"]['Enums']["ledger_entry_kind"],"monthly_amount": number,"name": string,"schedule_id": string,"sort_order": number,"tax_treatment": Database["public"]['Enums']["tax_treatment"]
                  }
                  ComputedFields: never
                  Insert: {
                    "gl_account_code": string,"id"?: string,"kind": Database["public"]['Enums']["ledger_entry_kind"],"monthly_amount": number,"name": string,"schedule_id": string,"sort_order"?: number,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"]
                  }
                  Update: {
                    "gl_account_code"?: string,"id"?: string,"kind"?: Database["public"]['Enums']["ledger_entry_kind"],"monthly_amount"?: number,"name"?: string,"schedule_id"?: string,"sort_order"?: number,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "fixed_cost_schedule_id_fkey"
      columns: ["schedule_id"]
isOneToOne: false
      referencedRelation: "fixed_cost_schedule"
      referencedColumns: ["id"]
    }
                  ]
                },"fixed_cost_schedule": {
                  Row: {
                    "aircraft_id": string,"created_at": string,"effective_from": string,"id": string,"note": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": string,"created_at"?: string,"effective_from": string,"id"?: string,"note"?: string | null
                  }
                  Update: {
                    "aircraft_id"?: string,"created_at"?: string,"effective_from"?: string,"id"?: string,"note"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "fixed_cost_schedule_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    }
                  ]
                },"flight": {
                  Row: {
                    "actual_tach_hours": number | null,"aircraft_id": string,"billed_hours": number | null,"created_at": string,"dest_place_id": string | null,"end_at": string | null,"end_fix_accuracy_m": number | null,"end_fix_at": string | null,"est_tach_hours": number | null,"flight_hours": number | null,"id": string,"invoice_id": string | null,"journey_text": string | null,"landing_place_uncertain": boolean,"notes": string | null,"origin_place_id": string | null,"pilot_member_id": string,"start_at": string,"start_fix_accuracy_m": number | null,"start_fix_at": string | null,"start_idempotency_key": string | null,"status": Database["public"]['Enums']["flight_status"],"stop_idempotency_key": string | null,"tach_factor_used": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "actual_tach_hours"?: number | null,"aircraft_id": string,"billed_hours"?: number | null,"created_at"?: string,"dest_place_id"?: string | null,"end_at"?: string | null,"end_fix_accuracy_m"?: number | null,"end_fix_at"?: string | null,"est_tach_hours"?: number | null,"flight_hours"?: never,"id"?: string,"invoice_id"?: string | null,"journey_text"?: string | null,"landing_place_uncertain"?: boolean,"notes"?: string | null,"origin_place_id"?: string | null,"pilot_member_id": string,"start_at"?: string,"start_fix_accuracy_m"?: number | null,"start_fix_at"?: string | null,"start_idempotency_key"?: string | null,"status"?: Database["public"]['Enums']["flight_status"],"stop_idempotency_key"?: string | null,"tach_factor_used": number,"updated_at"?: string
                  }
                  Update: {
                    "actual_tach_hours"?: number | null,"aircraft_id"?: string,"billed_hours"?: number | null,"created_at"?: string,"dest_place_id"?: string | null,"end_at"?: string | null,"end_fix_accuracy_m"?: number | null,"end_fix_at"?: string | null,"est_tach_hours"?: number | null,"flight_hours"?: never,"id"?: string,"invoice_id"?: string | null,"journey_text"?: string | null,"landing_place_uncertain"?: boolean,"notes"?: string | null,"origin_place_id"?: string | null,"pilot_member_id"?: string,"start_at"?: string,"start_fix_accuracy_m"?: number | null,"start_fix_at"?: string | null,"start_idempotency_key"?: string | null,"status"?: Database["public"]['Enums']["flight_status"],"stop_idempotency_key"?: string | null,"tach_factor_used"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "flight_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_dest_place_id_fkey"
      columns: ["dest_place_id"]
isOneToOne: false
      referencedRelation: "place"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_origin_place_id_fkey"
      columns: ["origin_place_id"]
isOneToOne: false
      referencedRelation: "place"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_pilot_member_id_fkey"
      columns: ["pilot_member_id"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"flight_fix": {
                  Row: {
                    "accuracy_m": number | null,"created_at": string,"flight_id": string,"lat": number,"lon": number,"source": Database["public"]['Enums']["fix_source"],"taken_at": string,"which": Database["public"]['Enums']["fix_which"]
                  }
                  ComputedFields: never
                  Insert: {
                    "accuracy_m"?: number | null,"created_at"?: string,"flight_id": string,"lat": number,"lon": number,"source"?: Database["public"]['Enums']["fix_source"],"taken_at"?: string,"which": Database["public"]['Enums']["fix_which"]
                  }
                  Update: {
                    "accuracy_m"?: number | null,"created_at"?: string,"flight_id"?: string,"lat"?: number,"lon"?: number,"source"?: Database["public"]['Enums']["fix_source"],"taken_at"?: string,"which"?: Database["public"]['Enums']["fix_which"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "flight_fix_flight_id_fkey"
      columns: ["flight_id"]
isOneToOne: false
      referencedRelation: "flight"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_fix_flight_id_fkey"
      columns: ["flight_id"]
isOneToOne: false
      referencedRelation: "flight_running"
      referencedColumns: ["id"]
    }
                  ]
                },"gl_account": {
                  Row: {
                    "code": string,"company_id": string,"created_at": string,"name": string,"type": Database["public"]['Enums']["gl_account_type"]
                  }
                  ComputedFields: never
                  Insert: {
                    "code": string,"company_id": string,"created_at"?: string,"name": string,"type": Database["public"]['Enums']["gl_account_type"]
                  }
                  Update: {
                    "code"?: string,"company_id"?: string,"created_at"?: string,"name"?: string,"type"?: Database["public"]['Enums']["gl_account_type"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "gl_account_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "company"
      referencedColumns: ["id"]
    }
                  ]
                },"invoice": {
                  Row: {
                    "company_id": string,"created_at": string,"external_ref": string | null,"id": string,"issued_at": string | null,"member_id": string,"note": string | null,"number": number | null,"period_month": string,"settled_at": string | null,"status": Database["public"]['Enums']["invoice_status"],"synced_at": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "company_id": string,"created_at"?: string,"external_ref"?: string | null,"id"?: string,"issued_at"?: string | null,"member_id": string,"note"?: string | null,"number"?: number | null,"period_month": string,"settled_at"?: string | null,"status"?: Database["public"]['Enums']["invoice_status"],"synced_at"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "company_id"?: string,"created_at"?: string,"external_ref"?: string | null,"id"?: string,"issued_at"?: string | null,"member_id"?: string,"note"?: string | null,"number"?: number | null,"period_month"?: string,"settled_at"?: string | null,"status"?: Database["public"]['Enums']["invoice_status"],"synced_at"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "invoice_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "company"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invoice_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"invoice_counter": {
                  Row: {
                    "company_id": string,"next_number": number
                  }
                  ComputedFields: never
                  Insert: {
                    "company_id": string,"next_number"?: number
                  }
                  Update: {
                    "company_id"?: string,"next_number"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "invoice_counter_company_id_fkey"
      columns: ["company_id"]
isOneToOne: true
      referencedRelation: "company"
      referencedColumns: ["id"]
    }
                  ]
                },"ledger_entry": {
                  Row: {
                    "amount": number,"company_id": string,"created_at": string,"description": string,"entry_date": string,"external_ref": string | null,"gl_account_code": string,"gst_amount": number,"id": string,"invoice_id": string | null,"kind": Database["public"]['Enums']["ledger_entry_kind"],"member_id": string,"quantity": number | null,"recorded_by": string | null,"synced_at": string | null,"tax_treatment": Database["public"]['Enums']["tax_treatment"],"unit_rate": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "amount": number,"company_id": string,"created_at"?: string,"description": string,"entry_date": string,"external_ref"?: string | null,"gl_account_code": string,"gst_amount"?: number,"id"?: string,"invoice_id"?: string | null,"kind": Database["public"]['Enums']["ledger_entry_kind"],"member_id": string,"quantity"?: number | null,"recorded_by"?: string | null,"synced_at"?: string | null,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"],"unit_rate"?: number | null
                  }
                  Update: {
                    "amount"?: number,"company_id"?: string,"created_at"?: string,"description"?: string,"entry_date"?: string,"external_ref"?: string | null,"gl_account_code"?: string,"gst_amount"?: number,"id"?: string,"invoice_id"?: string | null,"kind"?: Database["public"]['Enums']["ledger_entry_kind"],"member_id"?: string,"quantity"?: number | null,"recorded_by"?: string | null,"synced_at"?: string | null,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"],"unit_rate"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "ledger_entry_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "company"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entry_company_id_gl_account_code_fkey"
      columns: ["company_id","gl_account_code"]
isOneToOne: false
      referencedRelation: "gl_account"
      referencedColumns: ["company_id","code"]
    },{
      foreignKeyName: "ledger_entry_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entry_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entry_recorded_by_fkey"
      columns: ["recorded_by"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"maintenance_event": {
                  Row: {
                    "created_at": string,"done_by": string | null,"done_on": string,"id": string,"item_id": string,"note": string | null,"tach": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"done_by"?: string | null,"done_on"?: string,"id"?: string,"item_id": string,"note"?: string | null,"tach"?: number | null
                  }
                  Update: {
                    "created_at"?: string,"done_by"?: string | null,"done_on"?: string,"id"?: string,"item_id"?: string,"note"?: string | null,"tach"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "maintenance_event_done_by_fkey"
      columns: ["done_by"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "maintenance_event_item_id_fkey"
      columns: ["item_id"]
isOneToOne: false
      referencedRelation: "maintenance_item"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "maintenance_event_item_id_fkey"
      columns: ["item_id"]
isOneToOne: false
      referencedRelation: "maintenance_status"
      referencedColumns: ["id"]
    }
                  ]
                },"maintenance_item": {
                  Row: {
                    "aircraft_id": string,"basis": Database["public"]['Enums']["maintenance_basis"],"created_at": string,"due_date": string | null,"est_cost": number | null,"id": string,"interval_hours": number | null,"interval_months": number | null,"is_active": boolean,"kind": Database["public"]['Enums']["maintenance_kind"],"lead_days": number | null,"lead_hours": number | null,"name": string,"sort_order": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": string,"basis": Database["public"]['Enums']["maintenance_basis"],"created_at"?: string,"due_date"?: string | null,"est_cost"?: number | null,"id"?: string,"interval_hours"?: number | null,"interval_months"?: number | null,"is_active"?: boolean,"kind": Database["public"]['Enums']["maintenance_kind"],"lead_days"?: number | null,"lead_hours"?: number | null,"name": string,"sort_order"?: number,"updated_at"?: string
                  }
                  Update: {
                    "aircraft_id"?: string,"basis"?: Database["public"]['Enums']["maintenance_basis"],"created_at"?: string,"due_date"?: string | null,"est_cost"?: number | null,"id"?: string,"interval_hours"?: number | null,"interval_months"?: number | null,"is_active"?: boolean,"kind"?: Database["public"]['Enums']["maintenance_kind"],"lead_days"?: number | null,"lead_hours"?: number | null,"name"?: string,"sort_order"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "maintenance_item_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    }
                  ]
                },"member": {
                  Row: {
                    "auth_user_id": string | null,"created_at": string,"email": string,"full_name": string,"id": string,"is_active": boolean,"role": Database["public"]['Enums']["member_role"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "auth_user_id"?: string | null,"created_at"?: string,"email": string,"full_name": string,"id"?: string,"is_active"?: boolean,"role"?: Database["public"]['Enums']["member_role"],"updated_at"?: string
                  }
                  Update: {
                    "auth_user_id"?: string | null,"created_at"?: string,"email"?: string,"full_name"?: string,"id"?: string,"is_active"?: boolean,"role"?: Database["public"]['Enums']["member_role"],"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"ownership_period": {
                  Row: {
                    "aircraft_id": string,"created_at": string,"effective_from": string,"id": string,"note": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": string,"created_at"?: string,"effective_from": string,"id"?: string,"note"?: string | null
                  }
                  Update: {
                    "aircraft_id"?: string,"created_at"?: string,"effective_from"?: string,"id"?: string,"note"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "ownership_period_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    }
                  ]
                },"ownership_share": {
                  Row: {
                    "member_id": string,"pct": number,"period_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "member_id": string,"pct": number,"period_id": string
                  }
                  Update: {
                    "member_id"?: string,"pct"?: number,"period_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ownership_share_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ownership_share_period_id_fkey"
      columns: ["period_id"]
isOneToOne: false
      referencedRelation: "ownership_period"
      referencedColumns: ["id"]
    }
                  ]
                },"place": {
                  Row: {
                    "company_id": string,"created_at": string,"created_by": string | null,"external_id": string | null,"id": string,"kind": Database["public"]['Enums']["place_kind"],"lat": number,"lon": number,"name": string,"source": Database["public"]['Enums']["place_source"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "company_id": string,"created_at"?: string,"created_by"?: string | null,"external_id"?: string | null,"id"?: string,"kind"?: Database["public"]['Enums']["place_kind"],"lat": number,"lon": number,"name": string,"source"?: Database["public"]['Enums']["place_source"],"updated_at"?: string
                  }
                  Update: {
                    "company_id"?: string,"created_at"?: string,"created_by"?: string | null,"external_id"?: string | null,"id"?: string,"kind"?: Database["public"]['Enums']["place_kind"],"lat"?: number,"lon"?: number,"name"?: string,"source"?: Database["public"]['Enums']["place_source"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "place_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "company"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "place_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"rate_component": {
                  Row: {
                    "gl_account_code": string,"id": string,"kind": Database["public"]['Enums']["rate_component_kind"],"name": string,"rate_per_hour": number,"schedule_id": string,"sort_order": number,"tax_treatment": Database["public"]['Enums']["tax_treatment"]
                  }
                  ComputedFields: never
                  Insert: {
                    "gl_account_code": string,"id"?: string,"kind": Database["public"]['Enums']["rate_component_kind"],"name": string,"rate_per_hour": number,"schedule_id": string,"sort_order"?: number,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"]
                  }
                  Update: {
                    "gl_account_code"?: string,"id"?: string,"kind"?: Database["public"]['Enums']["rate_component_kind"],"name"?: string,"rate_per_hour"?: number,"schedule_id"?: string,"sort_order"?: number,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "rate_component_schedule_id_fkey"
      columns: ["schedule_id"]
isOneToOne: false
      referencedRelation: "rate_schedule"
      referencedColumns: ["id"]
    }
                  ]
                },"rate_schedule": {
                  Row: {
                    "aircraft_id": string,"created_at": string,"effective_from": string,"id": string,"note": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": string,"created_at"?: string,"effective_from": string,"id"?: string,"note"?: string | null
                  }
                  Update: {
                    "aircraft_id"?: string,"created_at"?: string,"effective_from"?: string,"id"?: string,"note"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "rate_schedule_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    }
                  ]
                },"snag": {
                  Row: {
                    "aircraft_id": string,"cleared_at": string | null,"cleared_by": string | null,"created_at": string,"flight_id": string | null,"grounding": boolean,"id": string,"notes": string | null,"recheck_item_id": string | null,"recheck_on": string | null,"recheck_tach_base": number | null,"recheck_tach_hours": number | null,"reported_at": string,"reported_by": string | null,"status": Database["public"]['Enums']["snag_status"],"title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": string,"cleared_at"?: string | null,"cleared_by"?: string | null,"created_at"?: string,"flight_id"?: string | null,"grounding"?: boolean,"id"?: string,"notes"?: string | null,"recheck_item_id"?: string | null,"recheck_on"?: string | null,"recheck_tach_base"?: number | null,"recheck_tach_hours"?: number | null,"reported_at"?: string,"reported_by"?: string | null,"status"?: Database["public"]['Enums']["snag_status"],"title": string,"updated_at"?: string
                  }
                  Update: {
                    "aircraft_id"?: string,"cleared_at"?: string | null,"cleared_by"?: string | null,"created_at"?: string,"flight_id"?: string | null,"grounding"?: boolean,"id"?: string,"notes"?: string | null,"recheck_item_id"?: string | null,"recheck_on"?: string | null,"recheck_tach_base"?: number | null,"recheck_tach_hours"?: number | null,"reported_at"?: string,"reported_by"?: string | null,"status"?: Database["public"]['Enums']["snag_status"],"title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "snag_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "snag_cleared_by_fkey"
      columns: ["cleared_by"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "snag_flight_id_fkey"
      columns: ["flight_id"]
isOneToOne: false
      referencedRelation: "flight"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "snag_flight_id_fkey"
      columns: ["flight_id"]
isOneToOne: false
      referencedRelation: "flight_running"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "snag_recheck_item_id_fkey"
      columns: ["recheck_item_id"]
isOneToOne: false
      referencedRelation: "maintenance_item"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "snag_recheck_item_id_fkey"
      columns: ["recheck_item_id"]
isOneToOne: false
      referencedRelation: "maintenance_status"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "snag_reported_by_fkey"
      columns: ["reported_by"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"tach_reading": {
                  Row: {
                    "aircraft_id": string,"created_at": string,"flight_id": string | null,"id": string,"note": string | null,"read_at": string,"read_by": string | null,"reading": number,"source": Database["public"]['Enums']["tach_reading_source"]
                  }
                  ComputedFields: never
                  Insert: {
                    "aircraft_id": string,"created_at"?: string,"flight_id"?: string | null,"id"?: string,"note"?: string | null,"read_at"?: string,"read_by"?: string | null,"reading": number,"source"?: Database["public"]['Enums']["tach_reading_source"]
                  }
                  Update: {
                    "aircraft_id"?: string,"created_at"?: string,"flight_id"?: string | null,"id"?: string,"note"?: string | null,"read_at"?: string,"read_by"?: string | null,"reading"?: number,"source"?: Database["public"]['Enums']["tach_reading_source"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "tach_reading_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tach_reading_flight_id_fkey"
      columns: ["flight_id"]
isOneToOne: false
      referencedRelation: "flight"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tach_reading_flight_id_fkey"
      columns: ["flight_id"]
isOneToOne: false
      referencedRelation: "flight_running"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tach_reading_read_by_fkey"
      columns: ["read_by"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            "flight_running": {
                  Row: {
                    "actual_tach_hours": number | null,"aircraft_id": string | null,"billed_hours": number | null,"created_at": string | null,"dest_place_id": string | null,"end_at": string | null,"end_fix_accuracy_m": number | null,"end_fix_at": string | null,"est_tach_hours": number | null,"flight_hours": number | null,"id": string | null,"invoice_id": string | null,"journey_text": string | null,"landing_place_uncertain": boolean | null,"notes": string | null,"origin_place_id": string | null,"pilot_member_id": string | null,"start_at": string | null,"start_fix_accuracy_m": number | null,"start_fix_at": string | null,"start_idempotency_key": string | null,"status": Database["public"]['Enums']["flight_status"] | null,"stop_idempotency_key": string | null,"tach_factor_used": number | null,"updated_at": string | null
                  }
                  ComputedFields: never
                  Insert: {
                           "actual_tach_hours"?: number | null,"aircraft_id"?: string | null,"billed_hours"?: number | null,"created_at"?: string | null,"dest_place_id"?: string | null,"end_at"?: string | null,"end_fix_accuracy_m"?: number | null,"end_fix_at"?: string | null,"est_tach_hours"?: number | null,"flight_hours"?: number | null,"id"?: string | null,"invoice_id"?: string | null,"journey_text"?: string | null,"landing_place_uncertain"?: boolean | null,"notes"?: string | null,"origin_place_id"?: string | null,"pilot_member_id"?: string | null,"start_at"?: string | null,"start_fix_accuracy_m"?: number | null,"start_fix_at"?: string | null,"start_idempotency_key"?: string | null,"status"?: Database["public"]['Enums']["flight_status"] | null,"stop_idempotency_key"?: string | null,"tach_factor_used"?: number | null,"updated_at"?: string | null
                         }
                        Update: {
                           "actual_tach_hours"?: number | null,"aircraft_id"?: string | null,"billed_hours"?: number | null,"created_at"?: string | null,"dest_place_id"?: string | null,"end_at"?: string | null,"end_fix_accuracy_m"?: number | null,"end_fix_at"?: string | null,"est_tach_hours"?: number | null,"flight_hours"?: number | null,"id"?: string | null,"invoice_id"?: string | null,"journey_text"?: string | null,"landing_place_uncertain"?: boolean | null,"notes"?: string | null,"origin_place_id"?: string | null,"pilot_member_id"?: string | null,"start_at"?: string | null,"start_fix_accuracy_m"?: number | null,"start_fix_at"?: string | null,"start_idempotency_key"?: string | null,"status"?: Database["public"]['Enums']["flight_status"] | null,"stop_idempotency_key"?: string | null,"tach_factor_used"?: number | null,"updated_at"?: string | null
                         }
                        Relationships: [
                    {
      foreignKeyName: "flight_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_dest_place_id_fkey"
      columns: ["dest_place_id"]
isOneToOne: false
      referencedRelation: "place"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_origin_place_id_fkey"
      columns: ["origin_place_id"]
isOneToOne: false
      referencedRelation: "place"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "flight_pilot_member_id_fkey"
      columns: ["pilot_member_id"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"gl_journal": {
                  Row: {
                    "company_id": string | null,"debit_credit": number | null,"description": string | null,"entry_date": string | null,"gl_account_code": string | null,"invoice_number": number | null,"kind": Database["public"]['Enums']["ledger_entry_kind"] | null,"ledger_entry_id": string | null,"line_no": number | null,"member_id": string | null,"tax_treatment": Database["public"]['Enums']["tax_treatment"] | null
                  }
                  ComputedFields: never
                  Relationships: [
                    
                  ]
                },"ledger_entry_posted": {
                  Row: {
                    "amount": number | null,"company_id": string | null,"created_at": string | null,"description": string | null,"entry_date": string | null,"external_ref": string | null,"gl_account_code": string | null,"gst_amount": number | null,"id": string | null,"invoice_id": string | null,"kind": Database["public"]['Enums']["ledger_entry_kind"] | null,"member_id": string | null,"quantity": number | null,"synced_at": string | null,"tax_treatment": Database["public"]['Enums']["tax_treatment"] | null,"unit_rate": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "ledger_entry_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "company"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entry_company_id_gl_account_code_fkey"
      columns: ["company_id","gl_account_code"]
isOneToOne: false
      referencedRelation: "gl_account"
      referencedColumns: ["company_id","code"]
    },{
      foreignKeyName: "ledger_entry_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entry_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "member"
      referencedColumns: ["id"]
    }
                  ]
                },"maintenance_status": {
                  Row: {
                    "aircraft_id": string | null,"basis": Database["public"]['Enums']["maintenance_basis"] | null,"days_remaining": number | null,"due_date": string | null,"est_cost": number | null,"fraction_used": number | null,"hours_remaining": number | null,"hours_used": number | null,"id": string | null,"interval_hours": number | null,"interval_months": number | null,"kind": Database["public"]['Enums']["maintenance_kind"] | null,"last_done_on": string | null,"last_done_tach": number | null,"lead_days": number | null,"lead_hours": number | null,"name": string | null,"next_due_on": string | null,"sort_order": number | null,"state": string | null,"tach_now": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "maintenance_item_aircraft_id_fkey"
      columns: ["aircraft_id"]
isOneToOne: false
      referencedRelation: "aircraft"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Functions: {
            "aircraft_date":
{ Args: { "p_at": string }; Returns: string
                           },
"aircraft_tach_estimate":
{ Args: { "p_aircraft_id": string }; Returns: number
                           },
"aircraft_today":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"claim_member_identity":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"close_month":
{ Args: { "p_aircraft_id": string,"p_month": string }; Returns: number
                           },
"current_auth_email":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"current_member_id":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"distance_m":
{ Args: { "p_lat1": number,"p_lat2": number,"p_lon1": number,"p_lon2": number }; Returns: number
                           },
"fixed_cost_share":
{ Args: { "p_aircraft_id": string,"p_member_id": string,"p_month": string }; Returns: number
                           },
"fixed_costs_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: {
              "gl_account_code": string,"kind": Database["public"]['Enums']["ledger_entry_kind"],"monthly_amount": number,"name": string,"tax_treatment": Database["public"]['Enums']["tax_treatment"]
            }[]
                           },
"invoice_total":
{ Args: { "p_invoice_id": string }; Returns: number
                           },
"is_admin":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"issue_invoice":
{ Args: { "p_invoice_id": string }; Returns: number
                           },
"journey_text_for":
{ Args: { "p_dest_id": string,"p_origin_id": string }; Returns: string
                           },
"member_balance":
{ Args: { "p_member_id": string }; Returns: number
                           },
"member_for_token_hash":
{ Args: { "p_token_hash": string }; Returns: string
                           },
"month_charges":
{ Args: { "p_aircraft_id": string,"p_member_id": string,"p_month": string }; Returns: {
              "amount": number,"description": string,"gl_account_code": string,"gst_amount": number,"kind": Database["public"]['Enums']["ledger_entry_kind"],"period_hours": number,"quantity": number,"sort_order": number,"tax_treatment": Database["public"]['Enums']["tax_treatment"],"unit_rate": number
            }[]
                           },
"month_flight_ids":
{ Args: { "p_aircraft_id": string,"p_member_id": string,"p_month": string }; Returns: string[]
                           },
"next_invoice_number":
{ Args: { "p_company_id": string }; Returns: number
                           },
"ownership_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: {
              "member_id": string,"pct": number
            }[]
                           },
"place_match":
{ Args: { "p_aircraft_id": string,"p_lat": number,"p_lon": number }; Returns: string
                           },
"place_times_used":
{ Args: { "p_place_id": string }; Returns: number
                           },
"places_near":
{ Args: { "p_lat": number,"p_limit"?: number,"p_lon": number }; Returns: {
              "distance_m": number,"id": string,"kind": Database["public"]['Enums']["place_kind"],"lat": number,"lon": number,"name": string,"source": Database["public"]['Enums']["place_source"],"times_used": number
            }[]
                           },
"places_used":
{ Args: { "p_limit"?: number }; Returns: {
              "id": string,"kind": Database["public"]['Enums']["place_kind"],"last_used_at": string,"lat": number,"lon": number,"name": string,"source": Database["public"]['Enums']["place_source"],"times_used": number
            }[]
                           },
"rate_components_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: {
              "gl_account_code": string,"kind": Database["public"]['Enums']["rate_component_kind"],"name": string,"rate_per_hour": number,"tax_treatment": Database["public"]['Enums']["tax_treatment"]
            }[]
                           },
"rate_schedule_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: string
                           },
"record_payment":
{ Args: { "p_amount": number,"p_member_id": string,"p_note"?: string,"p_paid_on": string }; Returns: string
                           },
"round_hours":
{ Args: { "p_hours": number,"p_rule": Database["public"]['Enums']["hour_rounding"] }; Returns: number
                           },
"timer_start":
{ Args: { "p_accuracy_m"?: number,"p_aircraft_id"?: string,"p_idempotency_key"?: string,"p_lat"?: number,"p_lon"?: number,"p_token_hash": string }; Returns: {
              "actual_tach_hours": number | null,
"aircraft_id": string,
"billed_hours": number | null,
"created_at": string,
"dest_place_id": string | null,
"end_at": string | null,
"end_fix_accuracy_m": number | null,
"end_fix_at": string | null,
"est_tach_hours": number | null,
"flight_hours": number | null,
"id": string,
"invoice_id": string | null,
"journey_text": string | null,
"landing_place_uncertain": boolean,
"notes": string | null,
"origin_place_id": string | null,
"pilot_member_id": string,
"start_at": string,
"start_fix_accuracy_m": number | null,
"start_fix_at": string | null,
"start_idempotency_key": string | null,
"status": Database["public"]['Enums']["flight_status"],
"stop_idempotency_key": string | null,
"tach_factor_used": number,
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "flight"
        isOneToOne: true
        isSetofReturn: false
      } },
"timer_stop":
{ Args: { "p_accuracy_m"?: number,"p_aircraft_id"?: string,"p_idempotency_key"?: string,"p_lat"?: number,"p_lon"?: number,"p_token_hash": string }; Returns: {
              "actual_tach_hours": number | null,
"aircraft_id": string,
"billed_hours": number | null,
"created_at": string,
"dest_place_id": string | null,
"end_at": string | null,
"end_fix_accuracy_m": number | null,
"end_fix_at": string | null,
"est_tach_hours": number | null,
"flight_hours": number | null,
"id": string,
"invoice_id": string | null,
"journey_text": string | null,
"landing_place_uncertain": boolean,
"notes": string | null,
"origin_place_id": string | null,
"pilot_member_id": string,
"start_at": string,
"start_fix_accuracy_m": number | null,
"start_fix_at": string | null,
"start_idempotency_key": string | null,
"status": Database["public"]['Enums']["flight_status"],
"stop_idempotency_key": string | null,
"tach_factor_used": number,
"updated_at": string
            }
                          SetofOptions: {
        from: "*"
        to: "flight"
        isOneToOne: true
        isSetofReturn: false
      } },
"wet_rate_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: number
                           }
          }
          Enums: {
            "billing_basis": "flight_time"|"tach","expense_approval_rule": "any_other_owner"|"admin_only","fix_source": "gps"|"manual","fix_which": "start"|"end","fixed_cost_split": "ownership_pct"|"equal"|"hours_flown","flight_status": "draft"|"confirmed"|"billed","gl_account_type": "asset"|"liability"|"equity"|"revenue"|"expense","hour_rounding": "round_up_tenth"|"nearest_tenth"|"exact","invoice_status": "draft"|"issued"|"settled"|"void","ledger_entry_kind": "flight_charge"|"hangarage"|"insurance"|"expense_credit"|"payment"|"payout"|"adjustment","maintenance_basis": "tach"|"calendar","maintenance_kind": "life_limit"|"recurring_inspection"|"recurring_task","member_role": "pilot"|"admin","place_kind": "airport"|"water_aerodrome"|"heliport"|"bay"|"lake"|"dock"|"other","place_source": "ourairports"|"osm"|"bcgnis"|"saved","rate_component_kind": "fuel"|"reserve"|"operating","snag_status": "open"|"watch"|"cleared","tach_reading_source": "manual"|"flight","tax_treatment": "taxable"|"zero_rated"|"exempt"|"out_of_scope"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            "billing_basis": ["flight_time", "tach"],"expense_approval_rule": ["any_other_owner", "admin_only"],"fix_source": ["gps", "manual"],"fix_which": ["start", "end"],"fixed_cost_split": ["ownership_pct", "equal", "hours_flown"],"flight_status": ["draft", "confirmed", "billed"],"gl_account_type": ["asset", "liability", "equity", "revenue", "expense"],"hour_rounding": ["round_up_tenth", "nearest_tenth", "exact"],"invoice_status": ["draft", "issued", "settled", "void"],"ledger_entry_kind": ["flight_charge", "hangarage", "insurance", "expense_credit", "payment", "payout", "adjustment"],"maintenance_basis": ["tach", "calendar"],"maintenance_kind": ["life_limit", "recurring_inspection", "recurring_task"],"member_role": ["pilot", "admin"],"place_kind": ["airport", "water_aerodrome", "heliport", "bay", "lake", "dock", "other"],"place_source": ["ourairports", "osm", "bcgnis", "saved"],"rate_component_kind": ["fuel", "reserve", "operating"],"snag_status": ["open", "watch", "cleared"],"tach_reading_source": ["manual", "flight"],"tax_treatment": ["taxable", "zero_rated", "exempt", "out_of_scope"]
          }
        }
} as const
