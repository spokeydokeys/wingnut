
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
                },"company": {
                  Row: {
                    "ar_account_code": string | null,"bank_account_code": string | null,"created_at": string,"etransfer_recipient": string | null,"fiscal_year_end_month": number,"gst_number": string | null,"gst_registered": boolean,"id": string,"legal_name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "ar_account_code"?: string | null,"bank_account_code"?: string | null,"created_at"?: string,"etransfer_recipient"?: string | null,"fiscal_year_end_month"?: number,"gst_number"?: string | null,"gst_registered"?: boolean,"id"?: string,"legal_name": string,"updated_at"?: string
                  }
                  Update: {
                    "ar_account_code"?: string | null,"bank_account_code"?: string | null,"created_at"?: string,"etransfer_recipient"?: string | null,"fiscal_year_end_month"?: number,"gst_number"?: string | null,"gst_registered"?: boolean,"id"?: string,"legal_name"?: string,"updated_at"?: string
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
                    "amount": number,"company_id": string,"created_at": string,"description": string,"entry_date": string,"external_ref": string | null,"gl_account_code": string,"gst_amount": number,"id": string,"invoice_id": string | null,"kind": Database["public"]['Enums']["ledger_entry_kind"],"member_id": string,"quantity": number | null,"synced_at": string | null,"tax_treatment": Database["public"]['Enums']["tax_treatment"],"unit_rate": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "amount": number,"company_id": string,"created_at"?: string,"description": string,"entry_date": string,"external_ref"?: string | null,"gl_account_code": string,"gst_amount"?: number,"id"?: string,"invoice_id"?: string | null,"kind": Database["public"]['Enums']["ledger_entry_kind"],"member_id": string,"quantity"?: number | null,"synced_at"?: string | null,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"],"unit_rate"?: number | null
                  }
                  Update: {
                    "amount"?: number,"company_id"?: string,"created_at"?: string,"description"?: string,"entry_date"?: string,"external_ref"?: string | null,"gl_account_code"?: string,"gst_amount"?: number,"id"?: string,"invoice_id"?: string | null,"kind"?: Database["public"]['Enums']["ledger_entry_kind"],"member_id"?: string,"quantity"?: number | null,"synced_at"?: string | null,"tax_treatment"?: Database["public"]['Enums']["tax_treatment"],"unit_rate"?: number | null
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
                }
          }
          Views: {
            "gl_journal": {
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
                }
          }
          Functions: {
            "claim_member_identity":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"current_auth_email":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"current_member_id":
{ Args: Record<PropertyKey, never>; Returns: string
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
"member_balance":
{ Args: { "p_member_id": string }; Returns: number
                           },
"next_invoice_number":
{ Args: { "p_company_id": string }; Returns: number
                           },
"ownership_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: {
              "member_id": string,"pct": number
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
"wet_rate_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: number
                           }
          }
          Enums: {
            "billing_basis": "flight_time"|"tach","expense_approval_rule": "any_other_owner"|"admin_only","fixed_cost_split": "ownership_pct"|"equal"|"hours_flown","gl_account_type": "asset"|"liability"|"equity"|"revenue"|"expense","hour_rounding": "round_up_tenth"|"nearest_tenth"|"exact","invoice_status": "draft"|"issued"|"settled"|"void","ledger_entry_kind": "flight_charge"|"hangarage"|"insurance"|"expense_credit"|"payment"|"payout"|"adjustment","member_role": "pilot"|"admin","rate_component_kind": "fuel"|"reserve"|"operating","tax_treatment": "taxable"|"zero_rated"|"exempt"|"out_of_scope"
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
            "billing_basis": ["flight_time", "tach"],"expense_approval_rule": ["any_other_owner", "admin_only"],"fixed_cost_split": ["ownership_pct", "equal", "hours_flown"],"gl_account_type": ["asset", "liability", "equity", "revenue", "expense"],"hour_rounding": ["round_up_tenth", "nearest_tenth", "exact"],"invoice_status": ["draft", "issued", "settled", "void"],"ledger_entry_kind": ["flight_charge", "hangarage", "insurance", "expense_credit", "payment", "payout", "adjustment"],"member_role": ["pilot", "admin"],"rate_component_kind": ["fuel", "reserve", "operating"],"tax_treatment": ["taxable", "zero_rated", "exempt", "out_of_scope"]
          }
        }
} as const
