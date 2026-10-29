/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

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
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      acquisition_events: {
        Row: {
          app_user_id: string
          created_at: string
          id: number
          source: string
          source_detail: string | null
        }
        Insert: {
          app_user_id: string
          created_at?: string
          id?: never
          source: string
          source_detail?: string | null
        }
        Update: {
          app_user_id?: string
          created_at?: string
          id?: never
          source?: string
          source_detail?: string | null
        }
        Relationships: []
      }
      catalog_fill_state: {
        Row: {
          id: number
          pause_reason: string | null
          paused_until: string | null
          updated_at: string
        }
        Insert: {
          id: number
          pause_reason?: string | null
          paused_until?: string | null
          updated_at?: string
        }
        Update: {
          id?: number
          pause_reason?: string | null
          paused_until?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      catalog_search_cursors: {
        Row: {
          lane_key: string
          page_token: string | null
          updated_at: string
          variant: number
        }
        Insert: {
          lane_key: string
          page_token?: string | null
          updated_at?: string
          variant?: number
        }
        Update: {
          lane_key?: string
          page_token?: string | null
          updated_at?: string
          variant?: number
        }
        Relationships: []
      }
      clips: {
        Row: {
          category: string
          channel_avatar_color: string | null
          channel_name: string
          created_at: string
          difficulty: string
          duration_sec: number
          id: string
          lines: Json
          model: string | null
          prompt_version: string | null
          published: boolean
          source_start_sec: number
          thumbnail_gradient: Json | null
          timing_mode: string | null
          title: string
          video_id: string
        }
        Insert: {
          category: string
          channel_avatar_color?: string | null
          channel_name: string
          created_at?: string
          difficulty: string
          duration_sec: number
          id: string
          lines: Json
          model?: string | null
          prompt_version?: string | null
          published?: boolean
          source_start_sec?: number
          thumbnail_gradient?: Json | null
          timing_mode?: string | null
          title: string
          video_id: string
        }
        Update: {
          category?: string
          channel_avatar_color?: string | null
          channel_name?: string
          created_at?: string
          difficulty?: string
          duration_sec?: number
          id?: string
          lines?: Json
          model?: string | null
          prompt_version?: string | null
          published?: boolean
          source_start_sec?: number
          thumbnail_gradient?: Json | null
          timing_mode?: string | null
          title?: string
          video_id?: string
        }
        Relationships: []
      }
      direct_messages: {
        Row: {
          app_user_id: string
          body: string
          created_at: string
          id: number
          sender: string
        }
        Insert: {
          app_user_id: string
          body: string
          created_at?: string
          id?: never
          sender: string
        }
        Update: {
          app_user_id?: string
          body?: string
          created_at?: string
          id?: never
          sender?: string
        }
        Relationships: []
      }
      explain_ingress_buckets: {
        Row: {
          bucket_key: string
          count: number
          window_start: string
        }
        Insert: {
          bucket_key: string
          count?: number
          window_start: string
        }
        Update: {
          bucket_key?: string
          count?: number
          window_start?: string
        }
        Relationships: []
      }
      explain_rate_buckets: {
        Row: {
          app_user_id: string
          count: number
          day_utc: string
          kind: string
        }
        Insert: {
          app_user_id: string
          count?: number
          day_utc: string
          kind: string
        }
        Update: {
          app_user_id?: string
          count?: number
          day_utc?: string
          kind?: string
        }
        Relationships: []
      }
      feedback_comments: {
        Row: {
          app_user_id: string
          body: string
          created_at: string
          id: number
          post_id: number
        }
        Insert: {
          app_user_id: string
          body: string
          created_at?: string
          id?: never
          post_id: number
        }
        Update: {
          app_user_id?: string
          body?: string
          created_at?: string
          id?: never
          post_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "feedback_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "feedback_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      feedback_items: {
        Row: {
          app_user_id: string
          category: string | null
          created_at: string
          enjoyed: boolean | null
          id: number
          message: string
          status: string
        }
        Insert: {
          app_user_id: string
          category?: string | null
          created_at?: string
          enjoyed?: boolean | null
          id?: never
          message?: string
          status?: string
        }
        Update: {
          app_user_id?: string
          category?: string | null
          created_at?: string
          enjoyed?: boolean | null
          id?: never
          message?: string
          status?: string
        }
        Relationships: []
      }
      feedback_posts: {
        Row: {
          app_user_id: string
          body: string
          category: string
          comment_count: number
          created_at: string
          id: number
          status: string
          title: string
          vote_count: number
        }
        Insert: {
          app_user_id: string
          body: string
          category: string
          comment_count?: number
          created_at?: string
          id?: never
          status?: string
          title: string
          vote_count?: number
        }
        Update: {
          app_user_id?: string
          body?: string
          category?: string
          comment_count?: number
          created_at?: string
          id?: never
          status?: string
          title?: string
          vote_count?: number
        }
        Relationships: []
      }
      feedback_votes: {
        Row: {
          app_user_id: string
          created_at: string
          post_id: number
        }
        Insert: {
          app_user_id: string
          created_at?: string
          post_id: number
        }
        Update: {
          app_user_id?: string
          created_at?: string
          post_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "feedback_votes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "feedback_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      gemini_daily_usage: {
        Row: {
          count: number
          day_utc: string
        }
        Insert: {
          count?: number
          day_utc: string
        }
        Update: {
          count?: number
          day_utc?: string
        }
        Relationships: []
      }
      immersion_job_requests: {
        Row: {
          created_at: string
          job_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          job_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          job_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "immersion_job_requests_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "immersion_jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      immersion_jobs: {
        Row: {
          attempts: number
          channel_name: string | null
          clip_id: string | null
          created_at: string
          error_code: string | null
          error_message: string | null
          finished_at: string | null
          id: string
          language: string
          locked_at: string | null
          locked_by: string | null
          max_attempts: number
          model: string | null
          next_attempt_at: string
          prompt_version: string | null
          scan_offset_sec: number
          stage: string
          status: string
          timing_mode: string | null
          title: string | null
          updated_at: string
          video_duration_sec: number | null
          video_id: string
          windows_scanned: number
        }
        Insert: {
          attempts?: number
          channel_name?: string | null
          clip_id?: string | null
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          finished_at?: string | null
          id?: string
          language?: string
          locked_at?: string | null
          locked_by?: string | null
          max_attempts?: number
          model?: string | null
          next_attempt_at?: string
          prompt_version?: string | null
          scan_offset_sec?: number
          stage?: string
          status?: string
          timing_mode?: string | null
          title?: string | null
          updated_at?: string
          video_duration_sec?: number | null
          video_id: string
          windows_scanned?: number
        }
        Update: {
          attempts?: number
          channel_name?: string | null
          clip_id?: string | null
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          finished_at?: string | null
          id?: string
          language?: string
          locked_at?: string | null
          locked_by?: string | null
          max_attempts?: number
          model?: string | null
          next_attempt_at?: string
          prompt_version?: string | null
          scan_offset_sec?: number
          stage?: string
          status?: string
          timing_mode?: string | null
          title?: string | null
          updated_at?: string
          video_duration_sec?: number | null
          video_id?: string
          windows_scanned?: number
        }
        Relationships: [
          {
            foreignKeyName: "immersion_jobs_clip_id_fkey"
            columns: ["clip_id"]
            isOneToOne: false
            referencedRelation: "clips"
            referencedColumns: ["id"]
          },
        ]
      }
      insight_rate_buckets: {
        Row: {
          app_user_id: string
          count: number
          day_utc: string
          kind: string
        }
        Insert: {
          app_user_id: string
          count?: number
          day_utc: string
          kind: string
        }
        Update: {
          app_user_id?: string
          count?: number
          day_utc?: string
          kind?: string
        }
        Relationships: []
      }
      practice_attempts: {
        Row: {
          clip_id: string
          created_at: string
          id: string
          line_index: number
          locale: string
          on_device: boolean
          recognized_text: string
          scoring_method: string
          similarity: number
          target_text: string
          user_id: string
        }
        Insert: {
          clip_id: string
          created_at?: string
          id?: string
          line_index: number
          locale?: string
          on_device?: boolean
          recognized_text: string
          scoring_method?: string
          similarity: number
          target_text: string
          user_id?: string
        }
        Update: {
          clip_id?: string
          created_at?: string
          id?: string
          line_index?: number
          locale?: string
          on_device?: boolean
          recognized_text?: string
          scoring_method?: string
          similarity?: number
          target_text?: string
          user_id?: string
        }
        Relationships: []
      }
      revenuecat_entitlement_cache: {
        Row: {
          app_user_id: string
          checked_at: string
          entitled: boolean
        }
        Insert: {
          app_user_id: string
          checked_at?: string
          entitled: boolean
        }
        Update: {
          app_user_id?: string
          checked_at?: string
          entitled?: boolean
        }
        Relationships: []
      }
      sori_clips: {
        Row: {
          category: string
          channel_avatar_color: string | null
          channel_name: string
          created_at: string
          difficulty: string
          duration_sec: number
          id: string
          lines: Json
          published: boolean
          source_start_sec: number
          thumbnail_gradient: Json | null
          title: string
          video_id: string
        }
        Insert: {
          category: string
          channel_avatar_color?: string | null
          channel_name: string
          created_at?: string
          difficulty: string
          duration_sec: number
          id: string
          lines: Json
          published?: boolean
          source_start_sec?: number
          thumbnail_gradient?: Json | null
          title: string
          video_id: string
        }
        Update: {
          category?: string
          channel_avatar_color?: string | null
          channel_name?: string
          created_at?: string
          difficulty?: string
          duration_sec?: number
          id?: string
          lines?: Json
          published?: boolean
          source_start_sec?: number
          thumbnail_gradient?: Json | null
          title?: string
          video_id?: string
        }
        Relationships: []
      }
      user_vocab: {
        Row: {
          clip_id: string | null
          context_note: string | null
          context_sentence: string | null
          context_translation: string | null
          created_at: string
          definitions: Json
          encounter_count: number
          id: string
          jlpt: string | null
          line_index: number | null
          pos: string | null
          reading: string
          romaji: string | null
          srs_state: string
          surface: string | null
          term: string
          updated_at: string
          user_id: string
        }
        Insert: {
          clip_id?: string | null
          context_note?: string | null
          context_sentence?: string | null
          context_translation?: string | null
          created_at?: string
          definitions?: Json
          encounter_count?: number
          id?: string
          jlpt?: string | null
          line_index?: number | null
          pos?: string | null
          reading?: string
          romaji?: string | null
          srs_state?: string
          surface?: string | null
          term: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          clip_id?: string | null
          context_note?: string | null
          context_sentence?: string | null
          context_translation?: string | null
          created_at?: string
          definitions?: Json
          encounter_count?: number
          id?: string
          jlpt?: string | null
          line_index?: number | null
          pos?: string | null
          reading?: string
          romaji?: string | null
          srs_state?: string
          surface?: string | null
          term?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      word_explanations: {
        Row: {
          cache_key: string
          created_at: string
          kind: string
          model: string
          payload: Json
          prompt_version: string
          sentence_hash: string | null
          updated_at: string
          word: string
        }
        Insert: {
          cache_key: string
          created_at?: string
          kind: string
          model: string
          payload: Json
          prompt_version: string
          sentence_hash?: string | null
          updated_at?: string
          word: string
        }
        Update: {
          cache_key?: string
          created_at?: string
          kind?: string
          model?: string
          payload?: Json
          prompt_version?: string
          sentence_hash?: string | null
          updated_at?: string
          word?: string
        }
        Relationships: []
      }
      youtube_quota_usage: {
        Row: {
          day_utc: string
          units: number
        }
        Insert: {
          day_utc: string
          units?: number
        }
        Update: {
          day_utc?: string
          units?: number
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      claim_immersion_jobs: {
        Args: {
          p_max_concurrency?: number
          p_stale_seconds?: number
          p_worker: string
        }
        Returns: {
          attempts: number
          channel_name: string | null
          clip_id: string | null
          created_at: string
          error_code: string | null
          error_message: string | null
          finished_at: string | null
          id: string
          language: string
          locked_at: string | null
          locked_by: string | null
          max_attempts: number
          model: string | null
          next_attempt_at: string
          prompt_version: string | null
          scan_offset_sec: number
          stage: string
          status: string
          timing_mode: string | null
          title: string | null
          updated_at: string
          video_duration_sec: number | null
          video_id: string
          windows_scanned: number
        }[]
        SetofOptions: {
          from: "*"
          to: "immersion_jobs"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      consume_youtube_quota: {
        Args: { p_day_utc: string; p_limit: number; p_units: number }
        Returns: boolean
      }
      increment_explain_ingress: {
        Args: { p_bucket_key: string; p_limit: number; p_window_start: string }
        Returns: boolean
      }
      increment_explain_rate: {
        Args: {
          p_app_user_id: string
          p_day_utc: string
          p_kind: string
          p_limit: number
        }
        Returns: boolean
      }
      increment_gemini_usage: {
        Args: { p_day_utc: string; p_limit: number }
        Returns: boolean
      }
      increment_insight_rate: {
        Args: {
          p_app_user_id: string
          p_day_utc: string
          p_kind: string
          p_limit: number
        }
        Returns: boolean
      }
      upsert_vault_secret: {
        Args: { secret_name: string; secret_value: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
