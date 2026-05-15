# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_15_001934) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_accounts_on_slug"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "amenities", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "icon"
    t.string "category"
    t.string "amenity_type"
    t.string "channex_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channex_id"], name: "index_amenities_on_channex_id"
    t.index ["slug"], name: "index_amenities_on_slug"
  end

  create_table "api_keys", force: :cascade do |t|
    t.string "token", null: false
    t.string "name"
    t.string "bearer_type"
    t.bigint "bearer_id"
    t.string "status", default: "active"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bearer_type", "bearer_id"], name: "index_api_keys_on_bearer"
    t.index ["token"], name: "index_api_keys_on_token", unique: true
  end

  create_table "app_configs", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_configs_on_key", unique: true
  end

  create_table "banking_details", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "account_holder_name", null: false
    t.string "bank_name", null: false
    t.string "account_number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_banking_details_on_account_id", unique: true
  end

  create_table "booking_audit_logs", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "auditable_type", null: false
    t.bigint "auditable_id", null: false
    t.bigint "user_id"
    t.string "action_type", null: false
    t.jsonb "old_value", default: {}, null: false
    t.jsonb "new_value", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auditable_type", "auditable_id"], name: "index_booking_audit_logs_on_auditable"
    t.index ["hotel_id"], name: "index_booking_audit_logs_on_hotel_id"
    t.index ["user_id"], name: "index_booking_audit_logs_on_user_id"
  end

  create_table "booking_guests", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "guest_id", null: false
    t.boolean "is_primary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_booking_guests_on_booking_id"
    t.index ["guest_id"], name: "index_booking_guests_on_guest_id"
  end

  create_table "booking_notes", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.text "body", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "edit_history", default: [], null: false
    t.index ["booking_id"], name: "index_booking_notes_on_booking_id"
    t.index ["user_id"], name: "index_booking_notes_on_user_id"
  end

  create_table "booking_quote_items", force: :cascade do |t|
    t.bigint "booking_quote_id", null: false
    t.bigint "room_type_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.jsonb "room_type_snapshot", default: {}, null: false
    t.jsonb "nightly_rate_snapshot", default: {}, null: false
    t.jsonb "occupancy_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_quote_id"], name: "index_booking_quote_items_on_booking_quote_id"
    t.index ["room_type_id"], name: "index_booking_quote_items_on_room_type_id"
  end

  create_table "booking_quotes", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.date "check_in", null: false
    t.date "check_out", null: false
    t.integer "adults", null: false
    t.integer "children", default: 0
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "MYR", null: false
    t.string "status", default: "pending", null: false
    t.datetime "expires_at", null: false
    t.string "token", null: false
    t.jsonb "hotel_snapshot", default: {}, null: false
    t.text "cancellation_policy_snapshot"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "guest_name"
    t.string "guest_email"
    t.string "guest_phone"
    t.index ["hotel_id"], name: "index_booking_quotes_on_hotel_id"
    t.index ["token"], name: "index_booking_quotes_on_token", unique: true
  end

  create_table "booking_rooms", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "room_type_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.jsonb "room_type_snapshot", default: {}, null: false
    t.jsonb "nightly_rate_snapshot", default: {}, null: false
    t.jsonb "occupancy_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "room_number"
    t.index ["booking_id"], name: "index_booking_rooms_on_booking_id"
    t.index ["room_type_id"], name: "index_booking_rooms_on_room_type_id"
  end

  create_table "bookings", force: :cascade do |t|
    t.bigint "booking_quote_id"
    t.bigint "hotel_id", null: false
    t.string "guest_name", null: false
    t.string "guest_email", null: false
    t.string "guest_phone", null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "MYR", null: false
    t.string "status", default: "pending", null: false
    t.string "payment_status", default: "pending", null: false
    t.string "confirmation_token", null: false
    t.date "check_in", null: false
    t.date "check_out", null: false
    t.integer "adults", null: false
    t.integer "children", default: 0
    t.jsonb "hotel_snapshot", default: {}, null: false
    t.text "cancellation_policy_snapshot"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pre_checkin_status"
    t.string "guarantee_method"
    t.string "deposit_status"
    t.decimal "margin_amount"
    t.decimal "net_amount"
    t.decimal "margin_rate"
    t.datetime "checked_in_at"
    t.datetime "checked_out_at"
    t.string "guest_gender"
    t.string "guest_country"
    t.string "guest_document_type"
    t.decimal "tourism_tax_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "tourism_tax_applied", default: false, null: false
    t.string "payout_status"
    t.datetime "payout_at"
    t.string "payout_reference"
    t.string "payout_batch_id"
    t.string "source", default: "internal"
    t.string "external_reference"
    t.string "channel_manager_reference"
    t.integer "revision_number", default: 0
    t.jsonb "tax_lines", default: [], null: false
    t.integer "reservation_number"
    t.integer "folio_number"
    t.integer "receipt_number"
    t.integer "guest_registration_number"
    t.bigint "walk_in_arrival_id"
    t.index ["booking_quote_id"], name: "index_bookings_on_booking_quote_id"
    t.index ["channel_manager_reference"], name: "index_bookings_on_channel_manager_reference"
    t.index ["confirmation_token"], name: "index_bookings_on_confirmation_token", unique: true
    t.index ["external_reference"], name: "index_bookings_on_external_reference"
    t.index ["hotel_id"], name: "index_bookings_on_hotel_id"
    t.index ["payment_status"], name: "index_bookings_on_payment_status"
    t.index ["source"], name: "index_bookings_on_source"
    t.index ["status"], name: "index_bookings_on_status"
    t.index ["walk_in_arrival_id"], name: "index_bookings_on_walk_in_arrival_id"
  end

  create_table "cancellation_policy_templates", force: :cascade do |t|
    t.string "name"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "channel_mappings", force: :cascade do |t|
    t.string "mappable_type", null: false
    t.bigint "mappable_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mappable_type", "mappable_id"], name: "index_channel_mappings_on_mappable"
    t.index ["provider", "external_id"], name: "index_channel_mappings_on_provider_and_external_id", unique: true
    t.index ["provider", "mappable_type", "mappable_id"], name: "idx_channel_mappings_provider_mappable", unique: true
  end

  create_table "check_out_requests", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "requested_at", null: false
    t.datetime "acknowledged_at"
    t.bigint "acknowledged_by_user_id"
    t.text "guest_notes"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged_by_user_id"], name: "index_check_out_requests_on_acknowledged_by_user_id"
    t.index ["booking_id", "requested_at"], name: "index_check_out_requests_on_booking_id_and_requested_at"
    t.index ["booking_id", "status"], name: "index_check_out_requests_on_booking_id_and_status"
    t.index ["booking_id"], name: "index_check_out_requests_on_booking_id"
  end

  create_table "complaint_requests", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.string "external_id"
    t.datetime "requested_at", null: false
    t.text "complaint_details", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "internal_notes", default: []
    t.string "status", default: "pending", null: false
    t.datetime "archived_at"
    t.datetime "completed_at"
    t.index ["booking_id", "archived_at"], name: "index_complaint_requests_on_booking_id_and_archived_at"
    t.index ["booking_id", "completed_at"], name: "index_complaint_requests_on_booking_id_and_completed_at"
    t.index ["booking_id", "requested_at"], name: "index_complaint_requests_on_booking_id_and_requested_at"
    t.index ["booking_id"], name: "index_complaint_requests_on_booking_id"
    t.index ["external_id"], name: "index_complaint_requests_on_external_id", unique: true
  end

  create_table "complaints", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.string "category"
    t.text "description"
    t.string "status", default: "open"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_complaints_on_booking_id"
  end

  create_table "guests", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "government_id"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "gender"
    t.string "country"
    t.string "document_type"
    t.string "otp_code_digest"
    t.datetime "otp_sent_at"
    t.string "magic_token_digest"
    t.datetime "magic_token_expires_at"
    t.datetime "last_signed_in_at"
    t.bigint "created_by_hotel_id"
    t.index ["created_by_hotel_id"], name: "index_guests_on_created_by_hotel_id"
    t.index ["magic_token_digest"], name: "index_guests_on_magic_token_digest", unique: true, where: "(magic_token_digest IS NOT NULL)"
  end

  create_table "hotel_counters", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "counter_type", null: false
    t.integer "last_value", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "counter_type"], name: "index_hotel_counters_on_hotel_id_and_counter_type", unique: true
    t.index ["hotel_id"], name: "index_hotel_counters_on_hotel_id"
  end

  create_table "hotel_pricing_rules", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "rule_type", null: false
    t.string "name"
    t.decimal "price", precision: 10, scale: 2, null: false
    t.date "start_date"
    t.date "end_date"
    t.integer "weekdays", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "rule_type"], name: "index_hotel_pricing_rules_on_hotel_and_type"
    t.index ["hotel_id", "start_date", "end_date"], name: "index_hotel_pricing_rules_on_hotel_and_dates"
    t.index ["hotel_id"], name: "index_hotel_pricing_rules_on_hotel_id"
  end

  create_table "hotel_taxes", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "name", null: false
    t.string "rate_type", default: "flat", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "foreign_guests_only", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_hotel_taxes_on_hotel_id"
  end

  create_table "hotels", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.string "city"
    t.string "country"
    t.integer "star_rating"
    t.bigint "account_id", null: false
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "default_currency", default: "MYR", null: false
    t.decimal "usd_conversion_rate", precision: 10, scale: 4, default: "4.5", null: false
    t.boolean "tourism_tax_enabled", default: false, null: false
    t.decimal "tourism_tax_amount", precision: 10, scale: 2, default: "10.0", null: false
    t.bigint "featured_photo_attachment_id"
    t.string "preferred_channel_manager"
    t.integer "salesperson_id"
    t.date "onboarding_start_date"
    t.date "onboarding_end_date"
    t.jsonb "amenities", default: [], null: false
    t.string "slug", null: false
    t.boolean "ai_provider_enabled", default: false
    t.string "ai_provider_name"
    t.text "ai_provider_key"
    t.string "ai_concierge_tone", default: "basic", null: false
    t.jsonb "faq", default: [], null: false
    t.jsonb "policy", default: [], null: false
    t.boolean "sst_enabled", default: false, null: false
    t.string "hotel_prefix"
    t.string "contact_phone"
    t.string "contact_email"
    t.string "whatsapp_number"
    t.boolean "concierge_enabled", default: true, null: false
    t.index ["account_id"], name: "index_hotels_on_account_id"
    t.index ["featured_photo_attachment_id"], name: "index_hotels_on_featured_photo_attachment_id"
    t.index ["hotel_prefix"], name: "index_hotels_on_hotel_prefix", unique: true
    t.index ["salesperson_id"], name: "index_hotels_on_salesperson_id"
    t.index ["slug"], name: "index_hotels_on_slug", unique: true
  end

  create_table "housekeeping_requests", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.string "external_id"
    t.datetime "requested_at", null: false
    t.text "request_details", null: false
    t.string "status", default: "pending", null: false
    t.datetime "completed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "internal_notes", default: []
    t.datetime "archived_at"
    t.index ["booking_id", "archived_at"], name: "index_housekeeping_requests_on_booking_id_and_archived_at"
    t.index ["booking_id", "requested_at"], name: "index_housekeeping_requests_on_booking_id_and_requested_at"
    t.index ["booking_id", "status"], name: "index_housekeeping_requests_on_booking_id_and_status"
    t.index ["booking_id"], name: "index_housekeeping_requests_on_booking_id"
    t.index ["external_id"], name: "index_housekeeping_requests_on_external_id", unique: true
  end

  create_table "inventory_audit_logs", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "room_type_id"
    t.bigint "user_id", null: false
    t.string "action_type", null: false
    t.jsonb "old_value", default: {}, null: false
    t.jsonb "new_value", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_inventory_audit_logs_on_hotel_id"
    t.index ["room_type_id"], name: "index_inventory_audit_logs_on_room_type_id"
    t.index ["user_id"], name: "index_inventory_audit_logs_on_user_id"
  end

  create_table "margin_rules", force: :cascade do |t|
    t.string "settable_type"
    t.bigint "settable_id"
    t.decimal "rate"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["settable_type", "settable_id"], name: "index_margin_rules_on_settable"
  end

  create_table "nearby_attractions", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "name", null: false
    t.text "description"
    t.text "address"
    t.string "city", null: false
    t.string "country", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_nearby_attractions_on_hotel_id"
  end

  create_table "night_audits", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.date "business_date", null: false
    t.string "status", default: "pending", null: false
    t.string "trigger_mode", default: "manual", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.jsonb "summary", default: {}, null: false
    t.jsonb "exceptions", default: {}, null: false
    t.text "notes"
    t.boolean "force_closed", default: false, null: false
    t.bigint "performed_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "blocked_details", default: {}, null: false
    t.index ["hotel_id", "business_date"], name: "index_night_audits_on_hotel_id_and_business_date", unique: true
    t.index ["hotel_id"], name: "index_night_audits_on_hotel_id"
    t.index ["performed_by_user_id"], name: "index_night_audits_on_performed_by_user_id"
    t.index ["status"], name: "index_night_audits_on_status"
  end

  create_table "notification_configs", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "notification_type", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "channels", default: [], null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "notification_type"], name: "index_notification_configs_on_hotel_id_and_notification_type", unique: true
    t.index ["hotel_id"], name: "index_notification_configs_on_hotel_id"
  end

  create_table "notification_deliveries", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.string "notification_type", null: false
    t.string "channel", null: false
    t.string "trigger_event", null: false
    t.string "status", default: "pending", null: false
    t.string "idempotency_key", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "sent_at"
    t.datetime "failed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_notification_deliveries_on_booking_id"
    t.index ["hotel_id"], name: "index_notification_deliveries_on_hotel_id"
    t.index ["idempotency_key"], name: "index_notification_deliveries_on_idempotency_key", unique: true
  end

  create_table "observation_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "entry_type", null: false
    t.string "request_id"
    t.integer "status"
    t.float "duration"
    t.string "path"
    t.jsonb "payload", default: {}
    t.jsonb "tags", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "ai_analysis"
    t.index ["created_at"], name: "index_observation_entries_on_created_at"
    t.index ["entry_type"], name: "index_observation_entries_on_entry_type"
    t.index ["request_id"], name: "index_observation_entries_on_request_id"
    t.index ["status"], name: "index_observation_entries_on_status"
    t.index ["tags"], name: "index_observation_entries_on_tags", using: :gin
  end

  create_table "onboarding_sessions", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "meeting_link"
    t.datetime "scheduled_at"
    t.datetime "completed_at"
    t.string "status", default: "scheduled", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "trainer_name", default: "", null: false
    t.index ["hotel_id"], name: "index_onboarding_sessions_on_hotel_id"
  end

  create_table "payment_settings", force: :cascade do |t|
    t.string "settable_type"
    t.bigint "settable_id"
    t.string "gateway"
    t.string "api_key"
    t.string "secret_key"
    t.string "webhook_secret"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["settable_type", "settable_id"], name: "index_payment_settings_on_settable"
  end

  create_table "payment_transactions", force: :cascade do |t|
    t.bigint "booking_quote_id"
    t.bigint "booking_id"
    t.string "gateway", null: false
    t.string "external_reference"
    t.string "gateway_order_id"
    t.string "signature"
    t.string "status", default: "pending", null: false
    t.string "payment_method"
    t.integer "amount_subunits"
    t.string "currency"
    t.string "event_source"
    t.datetime "verified_at"
    t.datetime "captured_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "gateway_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_payment_transactions_on_booking_id"
    t.index ["booking_quote_id"], name: "index_payment_transactions_on_booking_quote_id"
    t.index ["gateway", "external_reference"], name: "idx_payment_transactions_on_gateway_and_external_reference", unique: true, where: "(external_reference IS NOT NULL)"
    t.index ["gateway", "gateway_order_id"], name: "idx_payment_transactions_on_gateway_and_order_id", unique: true, where: "(gateway_order_id IS NOT NULL)"
    t.index ["status"], name: "index_payment_transactions_on_status"
  end

  create_table "payout_batches", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.decimal "amount"
    t.string "status"
    t.date "period_start"
    t.date "period_end"
    t.datetime "payout_at"
    t.string "payout_reference"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_payout_batches_on_hotel_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_permissions_on_slug", unique: true
  end

  create_table "pre_checkins", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.string "status"
    t.string "token"
    t.datetime "completed_at"
    t.string "document_status"
    t.string "signature_status"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_pre_checkins_on_booking_id"
  end

  create_table "property_policies", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "check_in_time"
    t.string "check_out_time"
    t.text "cancellation_policy"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "currency", default: "MYR", null: false
    t.decimal "usd_rate", precision: 10, scale: 4, default: "0.21", null: false
    t.index ["hotel_id"], name: "index_property_policies_on_hotel_id"
  end

  create_table "prospect_conversation_states", force: :cascade do |t|
    t.bigint "prospect_id", null: false
    t.string "active_topic"
    t.string "active_flow"
    t.string "flow_status", default: "active", null: false
    t.text "pending_question"
    t.jsonb "slots_payload", default: {}, null: false
    t.string "last_intent"
    t.string "last_action_name"
    t.datetime "last_user_message_at"
    t.datetime "last_topic_switch_at"
    t.integer "reset_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_topic"], name: "index_prospect_conversation_states_on_active_topic"
    t.index ["flow_status"], name: "index_prospect_conversation_states_on_flow_status"
    t.index ["prospect_id"], name: "index_prospect_conversation_states_on_prospect_id", unique: true
  end

  create_table "prospect_messages", force: :cascade do |t|
    t.bigint "prospect_id", null: false
    t.string "direction", null: false
    t.text "body", null: false
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prospect_id", "sent_at"], name: "index_prospect_messages_on_prospect_id_and_sent_at"
    t.index ["prospect_id"], name: "index_prospect_messages_on_prospect_id"
  end

  create_table "prospects", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "guest_id"
    t.string "phone_number", null: false
    t.string "name"
    t.string "stage", default: "cold", null: false
    t.datetime "last_contact"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "public_id", null: false
    t.index ["guest_id"], name: "index_prospects_on_guest_id"
    t.index ["hotel_id", "phone_number"], name: "index_prospects_on_hotel_id_and_phone_number", unique: true
    t.index ["hotel_id"], name: "index_prospects_on_hotel_id"
    t.index ["last_contact"], name: "index_prospects_on_last_contact"
    t.index ["public_id"], name: "index_prospects_on_public_id", unique: true
    t.index ["stage"], name: "index_prospects_on_stage"
  end

  create_table "rate_plans", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "room_type_id", null: false
    t.string "sell_mode", default: "per_room", null: false
    t.string "currency", default: "MYR", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_type_id"], name: "index_rate_plans_on_room_type_id"
  end

  create_table "refund_policies", force: :cascade do |t|
    t.integer "min_days_before_checkin", default: 0, null: false
    t.decimal "refund_percentage", precision: 5, scale: 2, default: "100.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "refund_requests", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.text "reason"
    t.string "bank_name", null: false
    t.string "account_holder_name", null: false
    t.string "account_number", null: false
    t.string "account_type", null: false
    t.string "status", default: "pending", null: false
    t.text "hotel_note"
    t.decimal "refund_amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_refund_requests_on_booking_id", unique: true
  end

  create_table "request_notes", force: :cascade do |t|
    t.string "noteable_type", null: false
    t.bigint "noteable_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["noteable_type", "noteable_id", "created_at"], name: "index_request_notes_on_noteable_and_created_at"
    t.index ["noteable_type", "noteable_id"], name: "index_request_notes_on_noteable"
  end

  create_table "role_permissions", force: :cascade do |t|
    t.bigint "role_id", null: false
    t.bigint "permission_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "index_roles_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_roles_on_account_id"
    t.index ["slug"], name: "index_roles_on_slug"
  end

  create_table "room_blocks", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "room_type_id", null: false
    t.string "room_number"
    t.date "start_date"
    t.date "end_date"
    t.string "block_type"
    t.text "reason"
    t.text "notes"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "completed_at"
    t.index ["hotel_id"], name: "index_room_blocks_on_hotel_id"
    t.index ["room_type_id"], name: "index_room_blocks_on_room_type_id"
    t.index ["user_id"], name: "index_room_blocks_on_user_id"
  end

  create_table "room_inventories", force: :cascade do |t|
    t.bigint "room_type_id", null: false
    t.date "date", null: false
    t.integer "quantity", default: 0, null: false
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "available_room_numbers"
    t.index ["room_type_id", "date"], name: "index_room_inventories_on_room_type_id_and_date", unique: true
    t.index ["room_type_id"], name: "index_room_inventories_on_room_type_id"
  end

  create_table "room_locks", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "user_id", null: false
    t.string "room_number", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "room_type_id", null: false
    t.index ["expires_at"], name: "index_room_locks_on_expires_at"
    t.index ["hotel_id", "room_type_id", "room_number"], name: "idx_room_locks_on_hotel_room_type_number", unique: true
    t.index ["hotel_id"], name: "index_room_locks_on_hotel_id"
    t.index ["room_type_id"], name: "index_room_locks_on_room_type_id"
    t.index ["user_id"], name: "index_room_locks_on_user_id"
  end

  create_table "room_operational_audit_logs", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "room_type_id"
    t.bigint "booking_id"
    t.bigint "user_id"
    t.string "room_number", null: false
    t.string "event_type", null: false
    t.string "old_status"
    t.string "new_status"
    t.text "reason"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_room_operational_audit_logs_on_booking_id"
    t.index ["created_at"], name: "index_room_operational_audit_logs_on_created_at"
    t.index ["hotel_id", "event_type"], name: "index_room_operational_audit_logs_on_hotel_id_and_event_type"
    t.index ["hotel_id", "room_number"], name: "index_room_operational_audit_logs_on_hotel_id_and_room_number"
    t.index ["hotel_id"], name: "index_room_operational_audit_logs_on_hotel_id"
    t.index ["room_type_id"], name: "index_room_operational_audit_logs_on_room_type_id"
    t.index ["user_id"], name: "index_room_operational_audit_logs_on_user_id"
  end

  create_table "room_rates", force: :cascade do |t|
    t.bigint "room_type_id", null: false
    t.date "date", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.string "currency", default: "MYR", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "rate_plan_id"
    t.index ["rate_plan_id"], name: "index_room_rates_on_rate_plan_id"
    t.index ["room_type_id", "date"], name: "index_room_rates_on_room_type_id_and_date", unique: true
    t.index ["room_type_id"], name: "index_room_rates_on_room_type_id"
  end

  create_table "room_statuses", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "room_type_id", null: false
    t.string "room_number", null: false
    t.string "status", default: "ready", null: false
    t.bigint "last_changed_by_id"
    t.datetime "last_changed_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "room_type_id", "room_number"], name: "idx_room_statuses_on_hotel_room_type_number", unique: true
    t.index ["hotel_id", "status"], name: "index_room_statuses_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "index_room_statuses_on_hotel_id"
    t.index ["last_changed_by_id"], name: "index_room_statuses_on_last_changed_by_id"
    t.index ["room_type_id"], name: "index_room_statuses_on_room_type_id"
  end

  create_table "room_types", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "name"
    t.text "description"
    t.integer "max_adults"
    t.integer "max_children"
    t.integer "quantity"
    t.decimal "base_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "room_numbers"
    t.string "room_number_mode"
    t.jsonb "amenities", default: [], null: false
    t.boolean "smoking_allowed", default: false, null: false
    t.boolean "pets_allowed", default: false, null: false
    t.index ["hotel_id"], name: "index_room_types_on_hotel_id"
  end

  create_table "salespeople", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "salesperson_hotels", force: :cascade do |t|
    t.bigint "salesperson_id", null: false
    t.bigint "hotel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_salesperson_hotels_on_hotel_id"
    t.index ["salesperson_id", "hotel_id"], name: "index_salesperson_hotels_on_salesperson_and_hotel", unique: true
    t.index ["salesperson_id"], name: "index_salesperson_hotels_on_salesperson_id"
  end

  create_table "setup_fee_rules", force: :cascade do |t|
    t.string "settable_type"
    t.bigint "settable_id"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", default: "MYR", null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["settable_type", "settable_id"], name: "index_setup_fee_rules_on_active_hotel_overrides", unique: true, where: "(((status)::text = 'active'::text) AND ((settable_type)::text = 'Hotel'::text))"
    t.index ["settable_type", "settable_id"], name: "index_setup_fee_rules_on_settable"
    t.index ["status"], name: "index_setup_fee_rules_on_active_global_default", unique: true, where: "(((status)::text = 'active'::text) AND (settable_type IS NULL) AND (settable_id IS NULL))"
  end

  create_table "staff_invitations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "hotel_id", null: false
    t.bigint "role_id", null: false
    t.bigint "invited_by_user_id", null: false
    t.string "email", null: false
    t.string "name"
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_at"], name: "index_staff_invitations_on_accepted_at"
    t.index ["account_id"], name: "index_staff_invitations_on_account_id"
    t.index ["expires_at"], name: "index_staff_invitations_on_expires_at"
    t.index ["hotel_id", "email"], name: "index_pending_staff_invites_on_hotel_and_email", unique: true, where: "(accepted_at IS NULL)"
    t.index ["hotel_id"], name: "index_staff_invitations_on_hotel_id"
    t.index ["invited_by_user_id"], name: "index_staff_invitations_on_invited_by_user_id"
    t.index ["role_id"], name: "index_staff_invitations_on_role_id"
    t.index ["token_digest"], name: "index_staff_invitations_on_token_digest", unique: true
  end

  create_table "user_hotel_accesses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "hotel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "role_id"
    t.datetime "deactivated_at"
    t.index ["deactivated_at"], name: "index_user_hotel_accesses_on_deactivated_at"
    t.index ["hotel_id"], name: "index_user_hotel_accesses_on_hotel_id"
    t.index ["role_id"], name: "index_user_hotel_accesses_on_role_id"
    t.index ["user_id"], name: "index_user_hotel_accesses_on_user_id"
  end

  create_table "user_roles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "password_digest"
    t.bigint "account_id", null: false
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "time_zone", default: "Kuala Lumpur", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email"
  end

  create_table "walk_in_arrivals", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "guest_id"
    t.bigint "booking_id"
    t.string "guest_name", null: false
    t.string "guest_email"
    t.string "guest_phone", null: false
    t.string "guest_country"
    t.string "guest_document_type"
    t.string "guest_government_id"
    t.string "estimated_arrival_time"
    t.integer "party_size_adults", default: 1, null: false
    t.integer "party_size_children", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "matched_at"
    t.bigint "matched_by_user_id"
    t.string "ip_address"
    t.string "user_agent"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_walk_in_arrivals_on_booking_id"
    t.index ["guest_id"], name: "index_walk_in_arrivals_on_guest_id"
    t.index ["hotel_id", "created_at"], name: "index_walk_in_arrivals_on_hotel_id_and_created_at"
    t.index ["hotel_id", "status"], name: "index_walk_in_arrivals_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "index_walk_in_arrivals_on_hotel_id"
    t.index ["matched_by_user_id"], name: "index_walk_in_arrivals_on_matched_by_user_id"
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.boolean "enabled"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "gateway"
    t.string "external_id"
    t.jsonb "payload"
    t.string "status"
    t.text "error_message"
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "banking_details", "accounts"
  add_foreign_key "booking_audit_logs", "hotels"
  add_foreign_key "booking_audit_logs", "users"
  add_foreign_key "booking_guests", "bookings"
  add_foreign_key "booking_guests", "guests"
  add_foreign_key "booking_notes", "bookings"
  add_foreign_key "booking_notes", "users"
  add_foreign_key "booking_quote_items", "booking_quotes"
  add_foreign_key "booking_quote_items", "room_types"
  add_foreign_key "booking_quotes", "hotels"
  add_foreign_key "booking_rooms", "bookings"
  add_foreign_key "booking_rooms", "room_types"
  add_foreign_key "bookings", "booking_quotes"
  add_foreign_key "bookings", "hotels"
  add_foreign_key "bookings", "walk_in_arrivals"
  add_foreign_key "check_out_requests", "bookings"
  add_foreign_key "check_out_requests", "users", column: "acknowledged_by_user_id"
  add_foreign_key "complaint_requests", "bookings"
  add_foreign_key "hotel_counters", "hotels"
  add_foreign_key "hotel_pricing_rules", "hotels"
  add_foreign_key "hotel_taxes", "hotels"
  add_foreign_key "hotels", "accounts"
  add_foreign_key "hotels", "users", column: "salesperson_id"
  add_foreign_key "housekeeping_requests", "bookings"
  add_foreign_key "inventory_audit_logs", "hotels"
  add_foreign_key "inventory_audit_logs", "room_types"
  add_foreign_key "inventory_audit_logs", "users"
  add_foreign_key "nearby_attractions", "hotels"
  add_foreign_key "night_audits", "hotels"
  add_foreign_key "night_audits", "users", column: "performed_by_user_id"
  add_foreign_key "notification_configs", "hotels"
  add_foreign_key "notification_deliveries", "bookings"
  add_foreign_key "notification_deliveries", "hotels"
  add_foreign_key "onboarding_sessions", "hotels"
  add_foreign_key "payment_transactions", "booking_quotes"
  add_foreign_key "payment_transactions", "bookings"
  add_foreign_key "payout_batches", "hotels"
  add_foreign_key "pre_checkins", "bookings"
  add_foreign_key "property_policies", "hotels"
  add_foreign_key "prospect_conversation_states", "prospects"
  add_foreign_key "prospect_messages", "prospects"
  add_foreign_key "prospects", "guests"
  add_foreign_key "prospects", "hotels"
  add_foreign_key "rate_plans", "room_types"
  add_foreign_key "refund_requests", "bookings"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "roles", "accounts"
  add_foreign_key "room_blocks", "hotels"
  add_foreign_key "room_blocks", "room_types"
  add_foreign_key "room_blocks", "users"
  add_foreign_key "room_inventories", "room_types"
  add_foreign_key "room_locks", "hotels"
  add_foreign_key "room_locks", "room_types"
  add_foreign_key "room_locks", "users"
  add_foreign_key "room_operational_audit_logs", "bookings"
  add_foreign_key "room_operational_audit_logs", "hotels"
  add_foreign_key "room_operational_audit_logs", "room_types"
  add_foreign_key "room_operational_audit_logs", "users"
  add_foreign_key "room_rates", "rate_plans"
  add_foreign_key "room_rates", "room_types"
  add_foreign_key "room_statuses", "hotels"
  add_foreign_key "room_statuses", "room_types"
  add_foreign_key "room_statuses", "users", column: "last_changed_by_id"
  add_foreign_key "room_types", "hotels"
  add_foreign_key "salesperson_hotels", "salespeople"
  add_foreign_key "staff_invitations", "accounts"
  add_foreign_key "staff_invitations", "hotels"
  add_foreign_key "staff_invitations", "roles"
  add_foreign_key "staff_invitations", "users", column: "invited_by_user_id"
  add_foreign_key "user_hotel_accesses", "hotels"
  add_foreign_key "user_hotel_accesses", "roles"
  add_foreign_key "user_hotel_accesses", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "accounts"
  add_foreign_key "walk_in_arrivals", "bookings"
  add_foreign_key "walk_in_arrivals", "guests"
  add_foreign_key "walk_in_arrivals", "hotels"
  add_foreign_key "walk_in_arrivals", "users", column: "matched_by_user_id"
end
