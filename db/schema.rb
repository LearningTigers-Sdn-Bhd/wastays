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

ActiveRecord::Schema[8.0].define(version: 2026_05_25_110203) do
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

  create_table "booking_folios", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.integer "folio_number"
    t.string "status", default: "open"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "hotel_id", null: false
    t.integer "invoice_number"
    t.index ["booking_id"], name: "index_booking_folios_on_booking_id", unique: true
    t.index ["hotel_id", "folio_number"], name: "index_booking_folios_on_hotel_id_and_folio_number", unique: true
    t.index ["hotel_id", "invoice_number"], name: "index_booking_folios_on_hotel_id_and_invoice_number", unique: true, where: "(invoice_number IS NOT NULL)"
    t.index ["hotel_id"], name: "index_booking_folios_on_hotel_id"
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
    t.string "display_currency"
    t.decimal "display_total_amount", precision: 10, scale: 2
    t.decimal "display_exchange_rate", precision: 18, scale: 8
    t.string "display_rate_source"
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
    t.bigint "rate_plan_id"
    t.index ["booking_id"], name: "index_booking_rooms_on_booking_id"
    t.index ["rate_plan_id"], name: "index_booking_rooms_on_rate_plan_id"
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
    t.decimal "margin_amount", precision: 15, scale: 2
    t.decimal "net_amount", precision: 15, scale: 2
    t.decimal "margin_rate", precision: 10, scale: 4
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
    t.bigint "payout_batch_id"
    t.string "source", default: "internal"
    t.string "external_reference"
    t.string "channel_manager_reference"
    t.integer "revision_number", default: 0
    t.jsonb "tax_lines", default: [], null: false
    t.integer "reservation_number"
    t.integer "receipt_number"
    t.integer "guest_registration_number"
    t.text "internal_notes"
    t.decimal "manual_rate_override"
    t.jsonb "tax_posting_snapshot", default: {}, null: false
    t.string "guest_home_address"
    t.index ["booking_quote_id"], name: "index_bookings_on_booking_quote_id_unique", unique: true, where: "(booking_quote_id IS NOT NULL)"
    t.index ["channel_manager_reference"], name: "index_bookings_on_channel_manager_reference"
    t.index ["confirmation_token"], name: "index_bookings_on_confirmation_token", unique: true
    t.index ["external_reference"], name: "index_bookings_on_external_reference"
    t.index ["hotel_id"], name: "index_bookings_on_hotel_id"
    t.index ["payment_status"], name: "index_bookings_on_payment_status"
    t.index ["payout_batch_id"], name: "index_bookings_on_payout_batch_id"
    t.index ["source"], name: "index_bookings_on_source"
    t.index ["status"], name: "index_bookings_on_status"
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

  create_table "deposits", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.bigint "booking_folio_id"
    t.bigint "user_id"
    t.string "hold_type", null: false
    t.string "status", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", null: false
    t.string "payment_method"
    t.string "external_reference"
    t.string "gl_code"
    t.datetime "collected_at"
    t.datetime "authorized_at"
    t.datetime "released_at"
    t.datetime "forfeited_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_folio_id"], name: "index_deposits_on_booking_folio_id"
    t.index ["booking_id"], name: "index_deposits_on_booking_id"
    t.index ["gl_code"], name: "index_deposits_on_gl_code"
    t.index ["hotel_id", "hold_type", "status"], name: "index_deposits_on_hotel_id_and_hold_type_and_status"
    t.index ["hotel_id"], name: "index_deposits_on_hotel_id"
    t.index ["user_id"], name: "index_deposits_on_user_id"
  end

  create_table "exchange_rates", force: :cascade do |t|
    t.string "currency_code", null: false
    t.decimal "rate", precision: 18, scale: 8, null: false
    t.datetime "effective_at", null: false
    t.boolean "active", default: true, null: false
    t.string "source", default: "manual", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "base_currency", default: "MYR", null: false
    t.index ["base_currency", "currency_code"], name: "index_exchange_rates_on_base_currency_and_currency_code", unique: true
    t.index ["created_by_id"], name: "index_exchange_rates_on_created_by_id"
    t.check_constraint "rate > 0::numeric", name: "exchange_rates_rate_positive"
  end

  create_table "financial_audit_events", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.date "business_date", null: false
    t.string "event_type", null: false
    t.bigint "actor_id"
    t.string "actor_type"
    t.string "source", null: false
    t.decimal "amount", precision: 10, scale: 2
    t.string "currency"
    t.bigint "folio_transaction_id"
    t.bigint "booking_folio_id"
    t.bigint "booking_id"
    t.bigint "payment_transaction_id"
    t.bigint "refund_request_id"
    t.bigint "night_audit_id"
    t.bigint "hotel_business_date_id"
    t.string "reason"
    t.jsonb "metadata", default: {}, null: false
    t.string "request_id"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_financial_audit_events_on_actor_id"
    t.index ["booking_folio_id"], name: "index_financial_audit_events_on_booking_folio_id"
    t.index ["booking_id"], name: "index_financial_audit_events_on_booking_id"
    t.index ["event_type", "folio_transaction_id"], name: "idx_financial_audit_events_unique_transaction_event", unique: true, where: "(folio_transaction_id IS NOT NULL)"
    t.index ["folio_transaction_id"], name: "index_financial_audit_events_on_folio_transaction_id"
    t.index ["hotel_business_date_id"], name: "index_financial_audit_events_on_hotel_business_date_id"
    t.index ["hotel_id", "business_date", "occurred_at"], name: "idx_financial_audit_events_on_hotel_date_time"
    t.index ["hotel_id", "event_type", "occurred_at"], name: "idx_financial_audit_events_on_hotel_event_time"
    t.index ["hotel_id"], name: "index_financial_audit_events_on_hotel_id"
    t.index ["night_audit_id"], name: "index_financial_audit_events_on_night_audit_id"
    t.index ["payment_transaction_id"], name: "index_financial_audit_events_on_payment_transaction_id"
    t.index ["refund_request_id"], name: "index_financial_audit_events_on_refund_request_id"
    t.index ["request_id"], name: "index_financial_audit_events_on_request_id"
  end

  create_table "folio_transactions", force: :cascade do |t|
    t.bigint "booking_folio_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "transaction_type", null: false
    t.string "category", null: false
    t.date "posting_date", null: false
    t.string "description"
    t.bigint "user_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "reversal_of_transaction_id"
    t.bigint "voided_by_transaction_id"
    t.string "correction_reason"
    t.text "correction_note"
    t.datetime "posted_at"
    t.string "currency"
    t.string "gl_code"
    t.index "booking_folio_id, ((metadata ->> 'early_checkout_charge_key'::text))", name: "index_folio_transactions_on_early_checkout_charge", unique: true, where: "(metadata ? 'early_checkout_charge_key'::text)"
    t.index "booking_folio_id, ((metadata ->> 'nightly_charge_key'::text))", name: "index_folio_transactions_on_nightly_charge", unique: true, where: "(metadata ? 'nightly_charge_key'::text)"
    t.index "booking_folio_id, ((metadata ->> 'no_show_charge_key'::text))", name: "index_folio_transactions_on_no_show_charge", unique: true, where: "(metadata ? 'no_show_charge_key'::text)"
    t.index "booking_folio_id, ((metadata ->> 'payment_transaction_id'::text))", name: "index_folio_transactions_on_gateway_payment", unique: true, where: "(metadata ? 'payment_transaction_id'::text)"
    t.index "booking_folio_id, ((metadata ->> 'refund_request_id'::text))", name: "index_folio_transactions_on_refund_request", unique: true, where: "(metadata ? 'refund_request_id'::text)"
    t.index ["booking_folio_id", "posting_date"], name: "index_folio_transactions_on_folio_and_posting_date"
    t.index ["booking_folio_id"], name: "index_folio_transactions_on_booking_folio_id"
    t.index ["category"], name: "index_folio_transactions_on_category"
    t.index ["gl_code"], name: "index_folio_transactions_on_gl_code"
    t.index ["posting_date"], name: "index_folio_transactions_on_posting_date"
    t.index ["reversal_of_transaction_id"], name: "index_folio_transactions_on_reversal_of_transaction_id"
    t.index ["transaction_type"], name: "index_folio_transactions_on_transaction_type"
    t.index ["user_id"], name: "index_folio_transactions_on_user_id"
    t.index ["voided_by_transaction_id"], name: "index_folio_transactions_on_voided_by_transaction_id"
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

  create_table "hotel_business_dates", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.date "business_date", null: false
    t.string "status", default: "open", null: false
    t.datetime "opened_at"
    t.datetime "audit_started_at"
    t.datetime "blocked_at"
    t.datetime "closed_at"
    t.jsonb "blockers_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "business_date", "status"], name: "idx_on_hotel_id_business_date_status_38d59d82f8"
    t.index ["hotel_id", "business_date"], name: "index_hotel_business_dates_on_hotel_id_and_business_date", unique: true
    t.index ["hotel_id", "status"], name: "index_hotel_business_dates_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "index_hotel_business_dates_on_hotel_id"
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

  create_table "hotel_general_ledger_maps", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "transaction_category", null: false
    t.string "gl_code", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "transaction_category"], name: "idx_hotel_gl_maps_on_hotel_and_category", unique: true
    t.index ["hotel_id"], name: "index_hotel_general_ledger_maps_on_hotel_id"
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
    t.jsonb "metadata"
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

  create_table "hotel_team_configs", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "name"
    t.text "description"
    t.text "emails"
    t.integer "frequency"
    t.string "template_type"
    t.datetime "last_alert_sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_hotel_team_configs_on_hotel_id"
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
    t.bigint "salesperson_id"
    t.date "onboarding_start_date"
    t.date "onboarding_end_date"
    t.boolean "ai_provider_enabled", default: false
    t.string "ai_provider_name"
    t.text "ai_provider_key"
    t.jsonb "amenities", default: [], null: false
    t.string "slug", null: false
    t.string "ai_concierge_tone", default: "basic", null: false
    t.jsonb "faq", default: [], null: false
    t.jsonb "policy", default: [], null: false
    t.boolean "sst_enabled", default: false, null: false
    t.string "hotel_prefix"
    t.string "time_zone"
    t.time "business_starts_at", default: "2000-01-01 08:00:00", null: false
    t.time "business_ends_at", default: "2000-01-01 02:00:00", null: false
    t.integer "arrival_grace_period", default: 7200, null: false
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

  create_table "journal_batch_entries", force: :cascade do |t|
    t.bigint "journal_batch_id", null: false
    t.string "gl_code", null: false
    t.string "transaction_type", null: false
    t.decimal "debit_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "credit_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["journal_batch_id"], name: "index_journal_batch_entries_on_journal_batch_id"
  end

  create_table "journal_batches", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.date "business_date", null: false
    t.string "status", default: "finalized", null: false
    t.datetime "finalized_at"
    t.jsonb "summary_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "business_date"], name: "index_journal_batches_on_hotel_id_and_business_date", unique: true
    t.index ["hotel_id"], name: "index_journal_batches_on_hotel_id"
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

  create_table "night_audit_financial_summaries", force: :cascade do |t|
    t.bigint "night_audit_id", null: false
    t.decimal "room_revenue", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_revenue", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "payments_total", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "refunds_total", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "no_show_charges", precision: 12, scale: 2, default: "0.0", null: false
    t.jsonb "changelog", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "adjustments_total", precision: 15, scale: 2, default: "0.0", null: false
    t.index ["night_audit_id"], name: "index_night_audit_financial_summaries_on_night_audit_id", unique: true
  end

  create_table "night_audit_logs", force: :cascade do |t|
    t.bigint "night_audit_id", null: false
    t.bigint "hotel_id", null: false
    t.bigint "user_id"
    t.string "action_type", null: false
    t.text "message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_type"], name: "index_night_audit_logs_on_action_type"
    t.index ["hotel_id"], name: "index_night_audit_logs_on_hotel_id"
    t.index ["night_audit_id"], name: "index_night_audit_logs_on_night_audit_id"
    t.index ["user_id"], name: "index_night_audit_logs_on_user_id"
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
    t.index ["booking_id"], name: "index_pre_checkins_on_booking_id", unique: true
    t.index ["token"], name: "index_pre_checkins_on_token", unique: true
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
    t.integer "lock_version", default: 0, null: false
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
    t.integer "min_stay"
    t.integer "max_stay"
    t.boolean "closed_to_arrival"
    t.boolean "closed_to_departure"
    t.boolean "stop_sell"
    t.decimal "walk_in_price", precision: 10, scale: 2
    t.decimal "ota_price", precision: 10, scale: 2
    t.string "applied_rule_type"
    t.decimal "corporate_price", precision: 10, scale: 2
    t.index ["rate_plan_id"], name: "index_room_rates_on_rate_plan_id"
    t.index ["room_type_id", "rate_plan_id", "date", "currency"], name: "index_room_rates_on_rt_rp_date_curr", unique: true
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
    t.string "room_number_mode", default: "range", null: false
    t.jsonb "amenities", default: [], null: false
    t.boolean "smoking_allowed", default: false, null: false
    t.boolean "pets_allowed", default: false, null: false
    t.index ["hotel_id"], name: "index_room_types_on_hotel_id"
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
  add_foreign_key "booking_folios", "bookings"
  add_foreign_key "booking_folios", "hotels"
  add_foreign_key "booking_guests", "bookings"
  add_foreign_key "booking_guests", "guests"
  add_foreign_key "booking_notes", "bookings"
  add_foreign_key "booking_notes", "users"
  add_foreign_key "booking_quote_items", "booking_quotes"
  add_foreign_key "booking_quote_items", "room_types"
  add_foreign_key "booking_quotes", "hotels"
  add_foreign_key "booking_rooms", "bookings"
  add_foreign_key "booking_rooms", "rate_plans"
  add_foreign_key "booking_rooms", "room_types"
  add_foreign_key "bookings", "booking_quotes"
  add_foreign_key "bookings", "hotels"
  add_foreign_key "bookings", "payout_batches"
  add_foreign_key "check_out_requests", "bookings"
  add_foreign_key "check_out_requests", "users", column: "acknowledged_by_user_id"
  add_foreign_key "complaint_requests", "bookings"
  add_foreign_key "deposits", "booking_folios"
  add_foreign_key "deposits", "bookings"
  add_foreign_key "deposits", "hotels"
  add_foreign_key "deposits", "users"
  add_foreign_key "exchange_rates", "users", column: "created_by_id"
  add_foreign_key "financial_audit_events", "booking_folios"
  add_foreign_key "financial_audit_events", "bookings"
  add_foreign_key "financial_audit_events", "folio_transactions"
  add_foreign_key "financial_audit_events", "hotel_business_dates"
  add_foreign_key "financial_audit_events", "hotels"
  add_foreign_key "financial_audit_events", "night_audits"
  add_foreign_key "financial_audit_events", "payment_transactions"
  add_foreign_key "financial_audit_events", "refund_requests"
  add_foreign_key "folio_transactions", "booking_folios"
  add_foreign_key "folio_transactions", "folio_transactions", column: "reversal_of_transaction_id"
  add_foreign_key "folio_transactions", "folio_transactions", column: "voided_by_transaction_id"
  add_foreign_key "folio_transactions", "users"
  add_foreign_key "hotel_business_dates", "hotels"
  add_foreign_key "hotel_counters", "hotels"
  add_foreign_key "hotel_general_ledger_maps", "hotels"
  add_foreign_key "hotel_pricing_rules", "hotels"
  add_foreign_key "hotel_taxes", "hotels"
  add_foreign_key "hotel_team_configs", "hotels"
  add_foreign_key "hotels", "accounts"
  add_foreign_key "hotels", "users", column: "salesperson_id"
  add_foreign_key "housekeeping_requests", "bookings"
  add_foreign_key "inventory_audit_logs", "hotels"
  add_foreign_key "inventory_audit_logs", "room_types"
  add_foreign_key "inventory_audit_logs", "users"
  add_foreign_key "journal_batch_entries", "journal_batches"
  add_foreign_key "journal_batches", "hotels"
  add_foreign_key "nearby_attractions", "hotels"
  add_foreign_key "night_audit_financial_summaries", "night_audits"
  add_foreign_key "night_audit_logs", "hotels"
  add_foreign_key "night_audit_logs", "night_audits"
  add_foreign_key "night_audit_logs", "users"
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
end
