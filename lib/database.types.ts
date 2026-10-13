
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
                    "created_at": string,"etransfer_recipient": string | null,"fiscal_year_end_month": number,"gst_number": string | null,"gst_registered": boolean,"id": string,"legal_name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"etransfer_recipient"?: string | null,"fiscal_year_end_month"?: number,"gst_number"?: string | null,"gst_registered"?: boolean,"id"?: string,"legal_name": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"etransfer_recipient"?: string | null,"fiscal_year_end_month"?: number,"gst_number"?: string | null,"gst_registered"?: boolean,"id"?: string,"legal_name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
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
                }
          }
          Views: {
            [_ in never]: never
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
"is_admin":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"ownership_as_of":
{ Args: { "p_aircraft_id": string,"p_on": string }; Returns: {
              "member_id": string,"pct": number
            }[]
                           }
          }
          Enums: {
            "billing_basis": "flight_time"|"tach","expense_approval_rule": "any_other_owner"|"admin_only","fixed_cost_split": "ownership_pct"|"equal"|"hours_flown","hour_rounding": "round_up_tenth"|"nearest_tenth"|"exact","member_role": "pilot"|"admin"
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
            "billing_basis": ["flight_time", "tach"],"expense_approval_rule": ["any_other_owner", "admin_only"],"fixed_cost_split": ["ownership_pct", "equal", "hours_flown"],"hour_rounding": ["round_up_tenth", "nearest_tenth", "exact"],"member_role": ["pilot", "admin"]
          }
        }
} as const
