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

ActiveRecord::Schema[8.0].define(version: 2026_07_21_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pre_suspension_status"
    t.string "account_kind", default: "hotel", null: false
    t.index ["account_kind"], name: "index_accounts_on_account_kind"
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
    t.check_constraint "account_kind::text = ANY (ARRAY['hotel'::character varying, 'corporate'::character varying]::text[])", name: "accounts_account_kind_allowed"
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

  create_table "ar_invoices", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_folio_id", null: false
    t.bigint "hotel_corporate_account_id", null: false
    t.integer "invoice_number", null: false
    t.string "status", default: "open", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", null: false
    t.date "issued_on", null: false
    t.date "due_on", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "paid_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "outstanding_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["booking_folio_id"], name: "index_ar_invoices_on_booking_folio_id", unique: true
    t.index ["hotel_corporate_account_id", "status"], name: "index_ar_invoices_on_hotel_corporate_account_id_and_status"
    t.index ["hotel_corporate_account_id"], name: "index_ar_invoices_on_hotel_corporate_account_id"
    t.index ["hotel_id", "invoice_number"], name: "index_ar_invoices_on_hotel_id_and_invoice_number", unique: true
    t.index ["hotel_id", "status", "due_on"], name: "index_ar_invoices_on_hotel_id_and_status_and_due_on"
    t.index ["hotel_id"], name: "index_ar_invoices_on_hotel_id"
    t.check_constraint "amount > 0::numeric", name: "ar_invoices_amount_positive"
    t.check_constraint "outstanding_amount >= 0::numeric", name: "ar_invoices_outstanding_amount_nonnegative"
    t.check_constraint "paid_amount >= 0::numeric", name: "ar_invoices_paid_amount_nonnegative"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying, 'partially_paid'::character varying, 'paid'::character varying, 'overdue'::character varying, 'void'::character varying]::text[])", name: "ar_invoices_status_allowed"
  end

  create_table "ar_payment_allocation_reversals", force: :cascade do |t|
    t.bigint "ar_payment_allocation_id", null: false
    t.bigint "reversed_by_id", null: false
    t.text "reason", null: false
    t.datetime "reversed_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ar_payment_allocation_id"], name: "idx_ar_allocation_reversals_unique", unique: true
    t.index ["reversed_by_id"], name: "index_ar_payment_allocation_reversals_on_reversed_by_id"
  end

  create_table "ar_payment_allocations", force: :cascade do |t|
    t.bigint "ar_payment_id", null: false
    t.bigint "ar_invoice_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ar_invoice_id", "created_at"], name: "idx_ar_allocations_on_invoice_created_at"
    t.index ["ar_invoice_id"], name: "index_ar_payment_allocations_on_ar_invoice_id"
    t.index ["ar_payment_id", "ar_invoice_id"], name: "idx_ar_allocations_on_payment_invoice"
    t.index ["ar_payment_id"], name: "index_ar_payment_allocations_on_ar_payment_id"
    t.check_constraint "amount > 0::numeric", name: "ar_payment_allocations_amount_positive"
  end

  create_table "ar_payment_submission_allocations", force: :cascade do |t|
    t.bigint "ar_payment_submission_id", null: false
    t.bigint "ar_invoice_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ar_invoice_id"], name: "index_ar_payment_submission_allocations_on_ar_invoice_id"
    t.index ["ar_payment_submission_id", "ar_invoice_id"], name: "index_submission_allocations_on_submission_and_invoice", unique: true
    t.index ["ar_payment_submission_id"], name: "idx_on_ar_payment_submission_id_60deb1a492"
    t.check_constraint "amount > 0::numeric", name: "ar_payment_submission_allocations_amount_positive"
  end

  create_table "ar_payment_submissions", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "hotel_corporate_account_id", null: false
    t.bigint "submitted_by_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", null: false
    t.string "reference_number", null: false
    t.date "received_at", null: false
    t.string "payment_method", default: "bank_transfer", null: false
    t.text "notes"
    t.string "status", default: "pending", null: false
    t.text "rejection_reason"
    t.bigint "ar_payment_id"
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ar_payment_id"], name: "index_ar_payment_submissions_on_ar_payment_id"
    t.index ["hotel_corporate_account_id"], name: "index_ar_payment_submissions_on_hotel_corporate_account_id"
    t.index ["hotel_id"], name: "index_ar_payment_submissions_on_hotel_id"
    t.index ["reviewed_by_id"], name: "index_ar_payment_submissions_on_reviewed_by_id"
    t.index ["submitted_by_id"], name: "index_ar_payment_submissions_on_submitted_by_id"
    t.check_constraint "amount > 0::numeric", name: "ar_payment_submissions_amount_positive"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying]::text[])", name: "ar_payment_submissions_status_allowed"
  end

  create_table "ar_payments", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "hotel_corporate_account_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", null: false
    t.string "reference_number", null: false
    t.date "received_at", null: false
    t.string "payment_method", default: "bank_transfer", null: false
    t.text "notes"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_corporate_account_id", "received_at"], name: "idx_ar_payments_on_account_received_at"
    t.index ["hotel_corporate_account_id"], name: "index_ar_payments_on_hotel_corporate_account_id"
    t.index ["hotel_id", "received_at"], name: "index_ar_payments_on_hotel_id_and_received_at"
    t.index ["hotel_id", "reference_number"], name: "index_ar_payments_on_hotel_id_and_reference_number"
    t.index ["hotel_id"], name: "index_ar_payments_on_hotel_id"
    t.check_constraint "amount > 0::numeric", name: "ar_payments_amount_positive"
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

  create_table "billing_route_batches", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.bigint "actor_id"
    t.string "idempotency_key", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_billing_route_batches_on_actor_id"
    t.index ["booking_id", "idempotency_key"], name: "idx_billing_route_batches_idempotency", unique: true
    t.index ["booking_id"], name: "index_billing_route_batches_on_booking_id"
    t.index ["hotel_id"], name: "index_billing_route_batches_on_hotel_id"
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
    t.string "category", null: false
    t.string "source", null: false
    t.string "request_id"
    t.datetime "occurred_at", null: false
    t.index ["auditable_type", "auditable_id", "occurred_at"], name: "idx_booking_audit_logs_on_auditable_time"
    t.index ["auditable_type", "auditable_id"], name: "index_booking_audit_logs_on_auditable"
    t.index ["hotel_id", "category", "occurred_at"], name: "idx_booking_audit_logs_on_hotel_category_time"
    t.index ["hotel_id", "occurred_at"], name: "idx_booking_audit_logs_on_hotel_time"
    t.index ["hotel_id"], name: "index_booking_audit_logs_on_hotel_id"
    t.index ["request_id"], name: "index_booking_audit_logs_on_request_id"
    t.index ["source"], name: "index_booking_audit_logs_on_source"
    t.index ["user_id"], name: "index_booking_audit_logs_on_user_id"
  end

  create_table "booking_billing_parties", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.string "party_kind", null: false
    t.bigint "booking_guest_id"
    t.bigint "hotel_corporate_account_id"
    t.bigint "created_by_id"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "account_type"
    t.index ["booking_guest_id"], name: "idx_booking_billing_parties_unique_guest", unique: true, where: "(booking_guest_id IS NOT NULL)"
    t.index ["booking_guest_id"], name: "index_booking_billing_parties_on_booking_guest_id"
    t.index ["booking_id", "hotel_corporate_account_id"], name: "idx_booking_billing_parties_unique_company", unique: true, where: "(hotel_corporate_account_id IS NOT NULL)"
    t.index ["booking_id", "party_kind"], name: "index_booking_billing_parties_on_booking_id_and_party_kind"
    t.index ["booking_id"], name: "index_booking_billing_parties_on_booking_id"
    t.index ["created_by_id"], name: "index_booking_billing_parties_on_created_by_id"
    t.index ["hotel_corporate_account_id"], name: "index_booking_billing_parties_on_hotel_corporate_account_id"
    t.index ["hotel_id", "archived_at"], name: "index_booking_billing_parties_on_hotel_id_and_archived_at"
    t.index ["hotel_id"], name: "index_booking_billing_parties_on_hotel_id"
    t.check_constraint "((booking_guest_id IS NOT NULL)::integer + (hotel_corporate_account_id IS NOT NULL)::integer) = 1", name: "booking_billing_parties_one_identity"
    t.check_constraint "account_type IS NULL OR (account_type::text = ANY (ARRAY['company'::text, 'government'::text, 'travel_agent'::text, 'airline'::text]))", name: "booking_billing_parties_account_type_allowed"
    t.check_constraint "party_kind::text = ANY (ARRAY['guest'::character varying, 'company'::character varying]::text[])", name: "booking_billing_parties_kind_allowed"
  end

  create_table "booking_billing_terms", force: :cascade do |t|
    t.bigint "booking_billing_party_id", null: false
    t.string "settlement_type", default: "cash_bank", null: false
    t.string "purchase_order_reference"
    t.string "authorization_reference"
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_billing_party_id"], name: "index_booking_billing_terms_on_booking_billing_party_id", unique: true
    t.index ["created_by_id"], name: "index_booking_billing_terms_on_created_by_id"
    t.index ["updated_by_id"], name: "index_booking_billing_terms_on_updated_by_id"
    t.check_constraint "settlement_type::text = ANY (ARRAY['cash_bank'::character varying, 'city_ledger'::character varying]::text[])", name: "booking_billing_terms_settlement_allowed"
  end

  create_table "booking_folios", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.integer "folio_number"
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "hotel_id", null: false
    t.integer "invoice_number"
    t.string "name", null: false
    t.string "folio_type", default: "guest", null: false
    t.string "payer_type", default: "guest", null: false
    t.bigint "payer_id"
    t.boolean "is_primary", default: false, null: false
    t.string "currency", null: false
    t.datetime "opened_at", null: false
    t.datetime "closed_at"
    t.bigint "created_by_id"
    t.bigint "closed_by_id"
    t.integer "folio_sequence"
    t.bigint "hotel_corporate_account_id"
    t.bigint "booking_room_id"
    t.bigint "booking_billing_party_id"
    t.index ["booking_billing_party_id"], name: "index_booking_folios_on_booking_billing_party_id"
    t.index ["booking_id", "booking_room_id"], name: "idx_booking_folios_primary_per_room", unique: true, where: "(is_primary AND (booking_room_id IS NOT NULL))"
    t.index ["booking_id", "folio_sequence"], name: "idx_booking_folios_on_booking_folio_sequence", unique: true, where: "(folio_sequence IS NOT NULL)"
    t.index ["booking_id"], name: "idx_booking_folios_primary_at_booking_level", unique: true, where: "(is_primary AND (booking_room_id IS NULL))"
    t.index ["booking_id"], name: "index_booking_folios_on_booking_id"
    t.index ["booking_room_id"], name: "index_booking_folios_on_booking_room_id"
    t.index ["closed_by_id"], name: "index_booking_folios_on_closed_by_id"
    t.index ["created_by_id"], name: "index_booking_folios_on_created_by_id"
    t.index ["hotel_corporate_account_id"], name: "index_booking_folios_on_hotel_corporate_account_id"
    t.index ["hotel_id", "folio_number"], name: "index_booking_folios_on_hotel_id_and_folio_number", unique: true
    t.index ["hotel_id", "folio_type"], name: "index_booking_folios_on_hotel_id_and_folio_type"
    t.index ["hotel_id", "invoice_number"], name: "index_booking_folios_on_hotel_id_and_invoice_number", unique: true, where: "(invoice_number IS NOT NULL)"
    t.index ["hotel_id", "status"], name: "index_booking_folios_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "index_booking_folios_on_hotel_id"
    t.check_constraint "folio_type::text <> 'guest'::text OR payer_type::text = 'guest'::text", name: "booking_folios_guest_type_is_guest_payer"
    t.check_constraint "folio_type::text = ANY (ARRAY['guest'::character varying, 'external'::character varying, 'house'::character varying]::text[])", name: "booking_folios_folio_type_allowed"
    t.check_constraint "payer_type::text = ANY (ARRAY['guest'::character varying, 'company'::character varying, 'agent'::character varying, 'hotel'::character varying, 'custom'::character varying]::text[])", name: "booking_folios_payer_type_allowed"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying, 'closed'::character varying, 'voided'::character varying]::text[])", name: "booking_folios_status_allowed"
  end

  create_table "booking_guests", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "guest_id", null: false
    t.boolean "is_primary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "additional", null: false
    t.string "name_snapshot"
    t.string "email_snapshot"
    t.string "phone_snapshot"
    t.string "government_id_snapshot"
    t.string "gender_snapshot"
    t.string "country_snapshot"
    t.string "document_type_snapshot"
    t.date "date_of_birth_snapshot"
    t.datetime "boat_in_at"
    t.datetime "boat_out_at"
    t.index ["boat_in_at"], name: "index_booking_guests_on_boat_in_at"
    t.index ["boat_out_at"], name: "index_booking_guests_on_boat_out_at"
    t.index ["booking_id", "guest_id"], name: "index_booking_guests_on_booking_id_and_guest_id", unique: true
    t.index ["booking_id"], name: "idx_booking_guests_one_primary_per_booking", unique: true, where: "((role)::text = 'primary'::text)"
    t.index ["booking_id"], name: "index_booking_guests_on_booking_id"
    t.index ["guest_id"], name: "index_booking_guests_on_guest_id"
    t.check_constraint "role::text = ANY (ARRAY['primary'::character varying, 'additional'::character varying]::text[])", name: "booking_guests_role_allowed"
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
    t.text "special_requests"
    t.bigint "hotel_corporate_account_id"
    t.index ["hotel_corporate_account_id"], name: "index_booking_quotes_on_hotel_corporate_account_id"
    t.index ["hotel_id"], name: "index_booking_quotes_on_hotel_id"
    t.index ["token"], name: "index_booking_quotes_on_token", unique: true
  end

  create_table "booking_rooms", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "room_type_id", null: false
    t.decimal "subtotal", precision: 10, scale: 2, null: false
    t.jsonb "room_type_snapshot", default: {}, null: false
    t.jsonb "nightly_rate_snapshot", default: {}, null: false
    t.jsonb "occupancy_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "room_number"
    t.bigint "rate_plan_id"
    t.index ["booking_id"], name: "idx_booking_rooms_unique_booking", unique: true
    t.index ["booking_id"], name: "index_booking_rooms_on_booking_id"
    t.index ["rate_plan_id"], name: "index_booking_rooms_on_rate_plan_id"
    t.index ["room_type_id"], name: "index_booking_rooms_on_room_type_id"
  end

  create_table "booking_tax_inclusion_overrides", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.bigint "transaction_code_id", null: false
    t.bigint "hotel_tax_id"
    t.string "primary_tax_key"
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_booking_tax_inclusion_overrides_on_actor_id"
    t.index ["booking_id", "transaction_code_id", "hotel_tax_id"], name: "idx_booking_tax_overrides_hotel_tax", unique: true, where: "(hotel_tax_id IS NOT NULL)"
    t.index ["booking_id", "transaction_code_id", "primary_tax_key"], name: "idx_booking_tax_overrides_primary", unique: true, where: "(primary_tax_key IS NOT NULL)"
    t.index ["booking_id"], name: "index_booking_tax_inclusion_overrides_on_booking_id"
    t.index ["hotel_id"], name: "index_booking_tax_inclusion_overrides_on_hotel_id"
    t.index ["hotel_tax_id"], name: "index_booking_tax_inclusion_overrides_on_hotel_tax_id"
    t.index ["transaction_code_id"], name: "index_booking_tax_inclusion_overrides_on_transaction_code_id"
    t.check_constraint "((hotel_tax_id IS NOT NULL)::integer + (primary_tax_key IS NOT NULL)::integer) = 1", name: "booking_tax_overrides_one_tax_source"
    t.check_constraint "action::text = ANY (ARRAY['include'::character varying, 'exclude'::character varying]::text[])", name: "booking_tax_overrides_action_allowed"
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
    t.datetime "check_in", null: false
    t.datetime "check_out", null: false
    t.date "no_show_review_business_date"
    t.boolean "tourism_tax_collected", default: false, null: false
    t.text "special_requests"
    t.string "folio_account_reference"
    t.bigint "group_booking_id"
    t.integer "group_position"
    t.boolean "vip", default: false, null: false
    t.integer "tourism_tax_voucher_number"
    t.bigint "hotel_corporate_account_id"
    t.index ["booking_quote_id"], name: "index_bookings_on_booking_quote_id"
    t.index ["channel_manager_reference"], name: "index_bookings_on_channel_manager_reference"
    t.index ["check_in"], name: "index_bookings_on_check_in"
    t.index ["check_out"], name: "index_bookings_on_check_out"
    t.index ["confirmation_token"], name: "index_bookings_on_confirmation_token", unique: true
    t.index ["external_reference"], name: "index_bookings_on_external_reference"
    t.index ["group_booking_id", "group_position"], name: "idx_bookings_group_position", unique: true, where: "(group_booking_id IS NOT NULL)"
    t.index ["group_booking_id"], name: "index_bookings_on_group_booking_id"
    t.index ["hotel_corporate_account_id"], name: "index_bookings_on_hotel_corporate_account_id"
    t.index ["hotel_id", "folio_account_reference"], name: "idx_bookings_on_hotel_folio_account_reference", unique: true, where: "(folio_account_reference IS NOT NULL)"
    t.index ["hotel_id", "receipt_number"], name: "idx_bookings_on_hotel_receipt_number", unique: true, where: "(receipt_number IS NOT NULL)"
    t.index ["hotel_id", "reservation_number"], name: "idx_bookings_on_hotel_reservation_number", unique: true, where: "(reservation_number IS NOT NULL)"
    t.index ["hotel_id", "status", "no_show_review_business_date"], name: "index_bookings_on_hotel_status_no_show_review_date"
    t.index ["hotel_id", "tourism_tax_voucher_number"], name: "idx_bookings_on_hotel_tourism_tax_voucher_number", unique: true, where: "(tourism_tax_voucher_number IS NOT NULL)"
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

  create_table "channel_availability_rules", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "external_id"
    t.string "title"
    t.date "start_date", null: false
    t.date "end_date"
    t.string "rule_type", null: false
    t.integer "value"
    t.string "days"
    t.json "affected_channels"
    t.json "affected_room_types"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_channel_availability_rules_on_hotel_id"
  end

  create_table "channel_derived_settings", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "channel_id", null: false
    t.string "pricing_mode", default: "same", null: false
    t.decimal "pricing_value", precision: 10, scale: 2
    t.string "room_allocation_mode", default: "shared", null: false
    t.integer "room_allocation_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "channel_id"], name: "index_channel_derived_settings_on_hotel_id_and_channel_id", unique: true
    t.index ["hotel_id"], name: "index_channel_derived_settings_on_hotel_id"
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

  create_table "channel_room_rates", force: :cascade do |t|
    t.bigint "room_type_id", null: false
    t.bigint "rate_plan_id"
    t.string "channel_id", null: false
    t.string "channel_rate_plan_id"
    t.date "date", null: false
    t.decimal "price", precision: 10, scale: 2
    t.integer "min_stay"
    t.integer "max_stay"
    t.boolean "closed_to_arrival"
    t.boolean "closed_to_departure"
    t.boolean "stop_sell"
    t.integer "availability"
    t.string "currency", default: "MYR", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rate_plan_id"], name: "index_channel_room_rates_on_rate_plan_id"
    t.index ["room_type_id", "rate_plan_id", "channel_rate_plan_id", "date", "currency"], name: "idx_channel_room_rates_uniqueness", unique: true
    t.index ["room_type_id"], name: "index_channel_room_rates_on_room_type_id"
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

  create_table "corporate_ar_payment_intents", force: :cascade do |t|
    t.bigint "corporate_account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "hotel_id", null: false
    t.bigint "hotel_corporate_account_id", null: false
    t.bigint "ar_payment_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", null: false
    t.string "gateway", null: false
    t.string "gateway_order_id"
    t.string "external_reference"
    t.string "status", default: "pending", null: false
    t.datetime "expires_at", null: false
    t.datetime "verified_at"
    t.datetime "captured_at"
    t.text "error_message"
    t.jsonb "invoice_snapshots", default: [], null: false
    t.jsonb "remittance_suggestions", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ar_payment_id"], name: "index_corporate_ar_payment_intents_on_ar_payment_id"
    t.index ["corporate_account_id", "created_at"], name: "idx_corp_ar_intents_on_account_created_at"
    t.index ["corporate_account_id"], name: "index_corporate_ar_payment_intents_on_corporate_account_id"
    t.index ["gateway", "external_reference"], name: "idx_corp_ar_intents_on_gateway_external_ref", unique: true, where: "(external_reference IS NOT NULL)"
    t.index ["gateway", "gateway_order_id"], name: "idx_corp_ar_intents_on_gateway_order", unique: true, where: "(gateway_order_id IS NOT NULL)"
    t.index ["hotel_corporate_account_id", "status"], name: "idx_corp_ar_intents_on_relationship_status"
    t.index ["hotel_corporate_account_id"], name: "idx_on_hotel_corporate_account_id_95207673f7"
    t.index ["hotel_id"], name: "index_corporate_ar_payment_intents_on_hotel_id"
    t.index ["user_id"], name: "index_corporate_ar_payment_intents_on_user_id"
    t.check_constraint "amount > 0::numeric", name: "corporate_ar_payment_intents_amount_positive"
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
    t.bigint "transaction_code_id", null: false
    t.index ["booking_folio_id"], name: "index_deposits_on_booking_folio_id"
    t.index ["booking_id"], name: "index_deposits_on_booking_id"
    t.index ["gl_code"], name: "index_deposits_on_gl_code"
    t.index ["hotel_id", "hold_type", "status"], name: "index_deposits_on_hotel_id_and_hold_type_and_status"
    t.index ["hotel_id"], name: "index_deposits_on_hotel_id"
    t.index ["transaction_code_id"], name: "index_deposits_on_transaction_code_id"
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

  create_table "feature_groups", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_feature_groups_on_slug", unique: true
  end

  create_table "features", force: :cascade do |t|
    t.bigint "feature_group_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.boolean "leveled", default: false, null: false
    t.boolean "addon", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_group_id"], name: "index_features_on_feature_group_id"
    t.index ["slug"], name: "index_features_on_slug", unique: true
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

  create_table "folio_forecasted_charges", force: :cascade do |t|
    t.bigint "booking_folio_id", null: false
    t.date "stay_date", null: false
    t.string "charge_kind", null: false
    t.string "identity", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description", null: false
    t.string "status", default: "forecast", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "actualizing_transaction_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actualizing_transaction_id"], name: "index_folio_forecasted_charges_on_actualizing_transaction_id"
    t.index ["booking_folio_id", "charge_kind", "identity", "stay_date"], name: "idx_forecasted_charges_on_unique_forecast", unique: true, where: "((status)::text = 'forecast'::text)"
    t.index ["booking_folio_id", "status"], name: "index_folio_forecasted_charges_on_booking_folio_id_and_status"
    t.index ["booking_folio_id", "stay_date"], name: "idx_on_booking_folio_id_stay_date_5ee8190530"
    t.index ["booking_folio_id"], name: "index_folio_forecasted_charges_on_booking_folio_id"
  end

  create_table "folio_operation_logs", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.bigint "actor_id"
    t.string "operation_type", null: false
    t.bigint "source_folio_id"
    t.bigint "target_folio_id"
    t.bigint "source_transaction_id"
    t.bigint "target_transaction_id"
    t.decimal "amount", precision: 10, scale: 2
    t.string "currency"
    t.string "operation_key"
    t.text "reason"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_folio_operation_logs_on_actor_id"
    t.index ["booking_id"], name: "index_folio_operation_logs_on_booking_id"
    t.index ["hotel_id", "booking_id", "created_at"], name: "idx_folio_operation_logs_on_booking_time"
    t.index ["hotel_id"], name: "index_folio_operation_logs_on_hotel_id"
    t.index ["operation_key"], name: "index_folio_operation_logs_on_operation_key"
    t.index ["operation_type"], name: "index_folio_operation_logs_on_operation_type"
    t.index ["source_folio_id"], name: "index_folio_operation_logs_on_source_folio_id"
    t.index ["source_transaction_id"], name: "index_folio_operation_logs_on_source_transaction_id"
    t.index ["target_folio_id"], name: "index_folio_operation_logs_on_target_folio_id"
    t.index ["target_transaction_id"], name: "index_folio_operation_logs_on_target_transaction_id"
  end

  create_table "folio_routing_rules", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.bigint "transaction_code_id", null: false
    t.bigint "target_folio_id", null: false
    t.boolean "active", default: true, null: false
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_type", default: "booking", null: false
    t.date "effective_from"
    t.date "effective_until"
    t.decimal "coverage_percentage", precision: 5, scale: 2, default: "100.0", null: false
    t.index ["booking_id", "transaction_code_id"], name: "idx_folio_routing_rules_one_active_per_code", unique: true, where: "active"
    t.index ["booking_id"], name: "index_folio_routing_rules_on_booking_id"
    t.index ["created_by_id"], name: "index_folio_routing_rules_on_created_by_id"
    t.index ["hotel_id"], name: "index_folio_routing_rules_on_hotel_id"
    t.index ["target_folio_id"], name: "index_folio_routing_rules_on_target_folio_id"
    t.index ["transaction_code_id"], name: "index_folio_routing_rules_on_transaction_code_id"
    t.index ["updated_by_id"], name: "index_folio_routing_rules_on_updated_by_id"
    t.check_constraint "coverage_percentage > 0::numeric AND coverage_percentage <= 100::numeric", name: "folio_routing_rules_coverage_percentage"
    t.check_constraint "source_type::text = ANY (ARRAY['booking'::character varying, 'group'::character varying]::text[])", name: "folio_routing_rules_source_allowed"
  end

  create_table "folio_transactions", force: :cascade do |t|
    t.bigint "booking_folio_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "transaction_type", null: false
    t.string "category", null: false
    t.date "posting_date", null: false
    t.string "description", null: false
    t.bigint "user_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "reversal_of_transaction_id"
    t.bigint "voided_by_transaction_id"
    t.string "correction_reason"
    t.text "correction_note"
    t.datetime "posted_at"
    t.string "currency", null: false
    t.string "gl_code"
    t.bigint "night_audit_id"
    t.string "catch_up_key"
    t.bigint "transaction_code_id"
    t.bigint "parent_transaction_id"
    t.bigint "split_from_transaction_id"
    t.bigint "moved_from_transaction_id"
    t.string "transfer_group_id"
    t.string "operation_key"
    t.index "booking_folio_id, ((metadata ->> 'early_checkout_charge_key'::text))", name: "index_folio_transactions_on_early_checkout_charge", unique: true, where: "(metadata ? 'early_checkout_charge_key'::text)"
    t.index "booking_folio_id, ((metadata ->> 'nightly_charge_key'::text))", name: "index_folio_transactions_on_nightly_charge", unique: true, where: "(metadata ? 'nightly_charge_key'::text)"
    t.index "booking_folio_id, ((metadata ->> 'no_show_charge_key'::text))", name: "index_folio_transactions_on_no_show_charge", unique: true, where: "(metadata ? 'no_show_charge_key'::text)"
    t.index "booking_folio_id, ((metadata ->> 'payment_transaction_id'::text))", name: "index_folio_transactions_on_gateway_payment", unique: true, where: "(metadata ? 'payment_transaction_id'::text)"
    t.index "booking_folio_id, ((metadata ->> 'refund_request_id'::text))", name: "index_folio_transactions_on_refund_request", unique: true, where: "(metadata ? 'refund_request_id'::text)"
    t.index ["booking_folio_id", "catch_up_key"], name: "index_folio_transactions_on_folio_and_catch_up_key", unique: true, where: "(catch_up_key IS NOT NULL)"
    t.index ["booking_folio_id", "posting_date"], name: "index_folio_transactions_on_folio_and_posting_date"
    t.index ["booking_folio_id"], name: "index_folio_transactions_on_booking_folio_id"
    t.index ["category"], name: "index_folio_transactions_on_category"
    t.index ["gl_code"], name: "index_folio_transactions_on_gl_code"
    t.index ["moved_from_transaction_id"], name: "index_folio_transactions_on_moved_from_transaction_id"
    t.index ["night_audit_id"], name: "index_folio_transactions_on_night_audit_id"
    t.index ["operation_key"], name: "index_folio_transactions_on_operation_key"
    t.index ["parent_transaction_id"], name: "index_folio_transactions_on_parent_transaction_id"
    t.index ["posting_date"], name: "index_folio_transactions_on_posting_date"
    t.index ["reversal_of_transaction_id"], name: "index_folio_transactions_on_reversal_of_transaction_id"
    t.index ["split_from_transaction_id"], name: "index_folio_transactions_on_split_from_transaction_id"
    t.index ["transaction_code_id"], name: "index_folio_transactions_on_transaction_code_id"
    t.index ["transaction_type"], name: "index_folio_transactions_on_transaction_type"
    t.index ["transfer_group_id"], name: "index_folio_transactions_on_transfer_group_id"
    t.index ["user_id"], name: "index_folio_transactions_on_user_id"
    t.index ["voided_by_transaction_id"], name: "index_folio_transactions_on_voided_by_transaction_id"
  end

  create_table "group_billing_change_batches", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "group_booking_id", null: false
    t.bigint "actor_id"
    t.string "idempotency_key", null: false
    t.string "payload_digest", null: false
    t.string "status", default: "pending", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_group_billing_change_batches_on_actor_id"
    t.index ["group_booking_id", "idempotency_key"], name: "idx_group_billing_change_batches_idempotency", unique: true
    t.index ["group_booking_id"], name: "index_group_billing_change_batches_on_group_booking_id"
    t.index ["hotel_id"], name: "index_group_billing_change_batches_on_hotel_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'completed'::character varying]::text[])", name: "group_billing_change_batches_status_allowed"
  end

  create_table "group_bookings", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "organizer_guest_id"
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.string "source"
    t.string "external_reference"
    t.date "default_check_in"
    t.date "default_check_out"
    t.text "notes"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "confirmation_token", null: false
    t.integer "reservation_number", null: false
    t.integer "receipt_number", null: false
    t.string "channel_manager_reference"
    t.integer "revision_number", default: 0, null: false
    t.index ["confirmation_token"], name: "index_group_bookings_on_confirmation_token", unique: true
    t.index ["hotel_id", "channel_manager_reference"], name: "idx_group_bookings_channel_identity", unique: true, where: "((channel_manager_reference IS NOT NULL) AND ((channel_manager_reference)::text <> ''::text))"
    t.index ["hotel_id", "external_reference"], name: "idx_group_bookings_external_identity", unique: true, where: "((external_reference IS NOT NULL) AND ((external_reference)::text <> ''::text))"
    t.index ["hotel_id", "receipt_number"], name: "idx_group_bookings_on_hotel_receipt_number", unique: true
    t.index ["hotel_id", "reservation_number"], name: "idx_group_bookings_on_hotel_reservation_number", unique: true
    t.index ["hotel_id", "status"], name: "index_group_bookings_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "index_group_bookings_on_hotel_id"
    t.index ["organizer_guest_id"], name: "index_group_bookings_on_organizer_guest_id"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'active'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])", name: "group_bookings_status_allowed"
  end

  create_table "group_deposit_allocations", force: :cascade do |t|
    t.bigint "group_deposit_id", null: false
    t.bigint "booking_id", null: false
    t.bigint "booking_folio_id", null: false
    t.bigint "folio_transaction_id"
    t.bigint "allocated_by_id"
    t.bigint "reversal_of_id"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "status", default: "active", null: false
    t.datetime "allocated_at", null: false
    t.datetime "reversed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["allocated_by_id"], name: "index_group_deposit_allocations_on_allocated_by_id"
    t.index ["booking_folio_id"], name: "index_group_deposit_allocations_on_booking_folio_id"
    t.index ["booking_id"], name: "index_group_deposit_allocations_on_booking_id"
    t.index ["folio_transaction_id"], name: "index_group_deposit_allocations_on_folio_transaction_id"
    t.index ["group_deposit_id"], name: "index_group_deposit_allocations_on_group_deposit_id"
    t.index ["reversal_of_id"], name: "idx_group_deposit_allocations_one_reversal", unique: true, where: "(reversal_of_id IS NOT NULL)"
    t.index ["reversal_of_id"], name: "index_group_deposit_allocations_on_reversal_of_id"
    t.check_constraint "amount > 0::numeric", name: "group_deposit_allocations_amount_positive"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'reversed'::character varying]::text[])", name: "group_deposit_allocations_status_allowed"
  end

  create_table "group_deposits", force: :cascade do |t|
    t.bigint "group_booking_id", null: false
    t.bigint "hotel_id", null: false
    t.bigint "hotel_corporate_account_id"
    t.bigint "received_by_id"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", null: false
    t.string "payment_method", null: false
    t.string "external_reference"
    t.string "status", default: "received", null: false
    t.datetime "received_at", null: false
    t.datetime "refunded_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "refunded_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.index ["group_booking_id"], name: "index_group_deposits_on_group_booking_id"
    t.index ["hotel_corporate_account_id"], name: "index_group_deposits_on_hotel_corporate_account_id"
    t.index ["hotel_id", "external_reference"], name: "index_group_deposits_on_hotel_id_and_external_reference", unique: true, where: "(external_reference IS NOT NULL)"
    t.index ["hotel_id"], name: "index_group_deposits_on_hotel_id"
    t.index ["received_by_id"], name: "index_group_deposits_on_received_by_id"
    t.check_constraint "amount > 0::numeric", name: "group_deposits_amount_positive"
    t.check_constraint "refunded_amount >= 0::numeric AND refunded_amount <= amount", name: "group_deposits_refunded_amount_valid"
    t.check_constraint "status::text = ANY (ARRAY['received'::character varying, 'partially_allocated'::character varying, 'allocated'::character varying, 'partially_refunded'::character varying, 'refunded'::character varying, 'cancelled'::character varying]::text[])", name: "group_deposits_status_allowed"
  end

  create_table "guest_registration_cards", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "booking_id", null: false
    t.string "status", default: "draft", null: false
    t.string "signer_name"
    t.text "signature_data_url"
    t.jsonb "terms_snapshot", default: {}, null: false
    t.datetime "signed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "display_fields_snapshot"
    t.index ["booking_id"], name: "index_guest_registration_cards_on_booking_id", unique: true
    t.index ["hotel_id"], name: "index_guest_registration_cards_on_hotel_id"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'signed'::character varying]::text[])", name: "guest_registration_cards_status_allowed"
  end

  create_table "guest_registration_note_templates", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "title"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_guest_registration_note_templates_on_hotel_id"
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
    t.datetime "discarded_at"
    t.date "date_of_birth"
    t.boolean "vip", default: false, null: false
    t.boolean "blacklisted", default: false, null: false
    t.index ["blacklisted"], name: "index_guests_on_blacklisted"
    t.index ["created_by_hotel_id"], name: "index_guests_on_created_by_hotel_id"
    t.index ["discarded_at"], name: "index_guests_on_discarded_at"
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
    t.bigint "force_closed_by_id"
    t.datetime "force_closed_at"
    t.text "force_close_reason"
    t.index ["force_closed_by_id"], name: "index_hotel_business_dates_on_force_closed_by_id"
    t.index ["hotel_id", "business_date", "status"], name: "idx_on_hotel_id_business_date_status_38d59d82f8"
    t.index ["hotel_id", "business_date"], name: "index_hotel_business_dates_on_hotel_id_and_business_date", unique: true
    t.index ["hotel_id", "status"], name: "index_hotel_business_dates_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "idx_one_current_business_date_per_hotel", unique: true, where: "((status)::text = ANY ((ARRAY['open'::character varying, 'audit_running'::character varying, 'audit_blocked'::character varying])::text[]))"
    t.index ["hotel_id"], name: "index_hotel_business_dates_on_hotel_id"
  end

  create_table "hotel_corporate_accounts", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "corporate_account_id", null: false
    t.string "relationship_type", default: "standard", null: false
    t.boolean "direct_bill_enabled", default: false, null: false
    t.decimal "credit_limit", precision: 12, scale: 2
    t.string "credit_currency", null: false
    t.integer "payment_terms_days"
    t.string "status", default: "active", null: false
    t.datetime "suspended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "account_type", default: "company", null: false
    t.string "agent_code"
    t.string "contact_email"
    t.string "contact_phone"
    t.boolean "auto_allocate_payments", default: false, null: false
    t.index ["corporate_account_id", "status"], name: "idx_hotel_corporate_accounts_on_account_and_status"
    t.index ["corporate_account_id"], name: "index_hotel_corporate_accounts_on_corporate_account_id"
    t.index ["hotel_id", "agent_code"], name: "index_hotel_corporate_accounts_on_hotel_id_and_agent_code", unique: true
    t.index ["hotel_id", "corporate_account_id"], name: "idx_hotel_corporate_accounts_unique_relationship", unique: true
    t.index ["hotel_id", "status"], name: "idx_hotel_corporate_accounts_on_hotel_and_status"
    t.index ["hotel_id"], name: "index_hotel_corporate_accounts_on_hotel_id"
    t.check_constraint "account_type::text = ANY (ARRAY['company'::character varying, 'government'::character varying, 'travel_agent'::character varying, 'airline'::character varying]::text[])", name: "hotel_corporate_accounts_account_type_allowed"
    t.check_constraint "credit_limit IS NULL OR credit_limit >= 0::numeric", name: "hotel_corporate_accounts_credit_limit_nonnegative"
    t.check_constraint "payment_terms_days IS NULL OR payment_terms_days >= 0", name: "hotel_corporate_accounts_payment_terms_nonnegative"
    t.check_constraint "relationship_type::text = ANY (ARRAY['standard'::character varying, 'direct_bill'::character varying]::text[])", name: "hotel_corporate_accounts_relationship_type_allowed"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'suspended'::character varying]::text[])", name: "hotel_corporate_accounts_status_allowed"
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

  create_table "hotel_knowledge_chunks", force: :cascade do |t|
    t.bigint "hotel_knowledge_document_id", null: false
    t.text "content", null: false
    t.vector "embedding", limit: 1536
    t.integer "chunk_index", null: false
    t.integer "token_count"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_hotel_knowledge_chunks_on_embedding", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["hotel_knowledge_document_id", "chunk_index"], name: "idx_knowledge_chunks_on_document_and_index", unique: true
    t.index ["hotel_knowledge_document_id"], name: "index_hotel_knowledge_chunks_on_hotel_knowledge_document_id"
  end

  create_table "hotel_knowledge_diagnostics", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "prospect_id"
    t.bigint "prospect_message_id"
    t.text "question", null: false
    t.string "intent", null: false
    t.string "topic"
    t.string "answer_mode"
    t.text "answer"
    t.boolean "success", default: false, null: false
    t.string "source"
    t.string "diagnostic_status", default: "open", null: false
    t.string "suggested_category"
    t.text "routed_categories", default: [], null: false, array: true
    t.text "fallback_categories", default: [], null: false, array: true
    t.jsonb "knowledge_matches", default: [], null: false
    t.integer "match_count", default: 0, null: false
    t.decimal "best_distance", precision: 8, scale: 6
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["answer_mode"], name: "index_hotel_knowledge_diagnostics_on_answer_mode"
    t.index ["created_at"], name: "index_hotel_knowledge_diagnostics_on_created_at"
    t.index ["diagnostic_status"], name: "index_hotel_knowledge_diagnostics_on_diagnostic_status"
    t.index ["hotel_id"], name: "index_hotel_knowledge_diagnostics_on_hotel_id"
    t.index ["prospect_id"], name: "index_hotel_knowledge_diagnostics_on_prospect_id"
    t.index ["prospect_message_id"], name: "index_hotel_knowledge_diagnostics_on_prospect_message_id"
    t.index ["suggested_category"], name: "index_hotel_knowledge_diagnostics_on_suggested_category"
  end

  create_table "hotel_knowledge_documents", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "title", null: false
    t.string "source_type", null: false
    t.string "category", null: false
    t.string "language", default: "en", null: false
    t.string "embedding_status", default: "pending", null: false
    t.text "tags", default: [], array: true
    t.integer "version", default: 1, null: false
    t.date "effective_date"
    t.text "content"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "category"], name: "index_hotel_knowledge_documents_on_hotel_id_and_category"
    t.index ["hotel_id"], name: "index_hotel_knowledge_documents_on_hotel_id"
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
    t.bigint "transaction_code_id"
    t.string "code"
    t.string "charge_type", default: "tax", null: false
    t.index ["hotel_id", "code"], name: "index_hotel_taxes_on_hotel_id_and_code", unique: true, where: "(code IS NOT NULL)"
    t.index ["hotel_id"], name: "index_hotel_taxes_on_hotel_id"
    t.index ["transaction_code_id"], name: "index_hotel_taxes_on_transaction_code_id"
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

  create_table "hotel_transaction_configurations", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "room_revenue_tax_rule_application", default: "new_bookings_only", null: false
    t.index ["hotel_id"], name: "index_hotel_transaction_configurations_on_hotel_id", unique: true
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
    t.string "pre_suspension_status"
    t.bigint "plan_id"
    t.string "google_map_link"
    t.boolean "geolocation_enabled", default: true, null: false
    t.boolean "pax_pricing_only", default: false, null: false
    t.boolean "allow_pax_pricing", default: false, null: false
    t.jsonb "guest_registration_card_fields"
    t.text "description"
    t.boolean "allow_boat_information", default: true, null: false
    t.jsonb "boat_in_times", default: [], null: false
    t.jsonb "boat_out_times", default: [], null: false
    t.index ["account_id"], name: "index_hotels_on_account_id"
    t.index ["featured_photo_attachment_id"], name: "index_hotels_on_featured_photo_attachment_id"
    t.index ["hotel_prefix"], name: "index_hotels_on_hotel_prefix", unique: true
    t.index ["plan_id"], name: "index_hotels_on_plan_id"
    t.index ["salesperson_id"], name: "index_hotels_on_salesperson_id"
    t.index ["slug"], name: "index_hotels_on_slug", unique: true
  end

  create_table "housekeeping_requests", force: :cascade do |t|
    t.bigint "booking_id"
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
    t.bigint "hotel_id"
    t.bigint "room_type_id"
    t.string "room_number"
    t.index ["booking_id", "archived_at"], name: "index_housekeeping_requests_on_booking_id_and_archived_at"
    t.index ["booking_id", "requested_at"], name: "index_housekeeping_requests_on_booking_id_and_requested_at"
    t.index ["booking_id", "status"], name: "index_housekeeping_requests_on_booking_id_and_status"
    t.index ["booking_id"], name: "index_housekeeping_requests_on_booking_id"
    t.index ["external_id"], name: "index_housekeeping_requests_on_external_id", unique: true
    t.index ["hotel_id", "room_number"], name: "index_housekeeping_requests_on_hotel_id_and_room_number"
    t.index ["hotel_id", "status"], name: "index_housekeeping_requests_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "index_housekeeping_requests_on_hotel_id"
    t.index ["room_type_id"], name: "index_housekeeping_requests_on_room_type_id"
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

  create_table "invitations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "hotel_id", null: false
    t.bigint "role_id"
    t.bigint "invited_by_user_id", null: false
    t.string "email", null: false
    t.string "name"
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kind", default: "staff", null: false
    t.jsonb "metadata", default: {}, null: false
    t.index ["accepted_at"], name: "index_invitations_on_accepted_at"
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["expires_at"], name: "index_invitations_on_expires_at"
    t.index ["hotel_id", "email"], name: "index_pending_staff_invites_on_hotel_and_email", unique: true, where: "(accepted_at IS NULL)"
    t.index ["hotel_id"], name: "index_invitations_on_hotel_id"
    t.index ["invited_by_user_id"], name: "index_invitations_on_invited_by_user_id"
    t.index ["kind"], name: "index_invitations_on_kind"
    t.index ["role_id"], name: "index_invitations_on_role_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
    t.check_constraint "kind::text <> 'corporate'::text OR metadata ? 'relationship_type'::text AND ((metadata ->> 'relationship_type'::text) = ANY (ARRAY['standard'::text, 'direct_bill'::text]))", name: "invitations_corporate_fields_required"
    t.check_constraint "kind::text <> 'staff'::text OR role_id IS NOT NULL", name: "invitations_staff_role_required"
    t.check_constraint "kind::text = ANY (ARRAY['staff'::character varying, 'corporate'::character varying]::text[])", name: "invitations_kind_allowed"
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

  create_table "legacy_booking_split_lineages", force: :cascade do |t|
    t.bigint "legacy_booking_id", null: false
    t.bigint "group_booking_id", null: false
    t.bigint "child_booking_id", null: false
    t.bigint "booking_room_id", null: false
    t.boolean "anchor", default: false, null: false
    t.string "review_status", default: "approved", null: false
    t.text "review_reason"
    t.uuid "batch_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_legacy_booking_split_lineages_on_batch_id"
    t.index ["booking_room_id"], name: "idx_legacy_split_lineages_unique_room", unique: true
    t.index ["booking_room_id"], name: "index_legacy_booking_split_lineages_on_booking_room_id"
    t.index ["child_booking_id"], name: "idx_legacy_split_lineages_unique_child", unique: true
    t.index ["child_booking_id"], name: "index_legacy_booking_split_lineages_on_child_booking_id"
    t.index ["group_booking_id"], name: "index_legacy_booking_split_lineages_on_group_booking_id"
    t.index ["legacy_booking_id", "batch_id"], name: "idx_legacy_split_lineages_booking_batch"
    t.index ["legacy_booking_id"], name: "idx_legacy_split_lineages_unique_anchor", unique: true, where: "(anchor = true)"
    t.index ["legacy_booking_id"], name: "index_legacy_booking_split_lineages_on_legacy_booking_id"
    t.check_constraint "review_status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying]::text[])", name: "legacy_split_lineages_review_status_allowed"
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
    t.bigint "corporate_ar_payment_intent_id"
    t.bigint "ar_payment_id"
    t.index ["ar_payment_id"], name: "index_payment_transactions_on_ar_payment_id"
    t.index ["booking_id"], name: "index_payment_transactions_on_booking_id"
    t.index ["booking_quote_id"], name: "index_payment_transactions_on_booking_quote_id"
    t.index ["corporate_ar_payment_intent_id"], name: "idx_payment_transactions_on_corp_ar_intent_id"
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

  create_table "plan_features", force: :cascade do |t|
    t.bigint "plan_id", null: false
    t.bigint "feature_id", null: false
    t.boolean "enabled", default: false, null: false
    t.string "level"
    t.boolean "addon", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_id"], name: "index_plan_features_on_feature_id"
    t.index ["plan_id", "feature_id"], name: "index_plan_features_on_plan_id_and_feature_id", unique: true
    t.index ["plan_id"], name: "index_plan_features_on_plan_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.boolean "most_popular", default: false, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_plans_on_slug", unique: true
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

  create_table "rate_plan_age_bands", force: :cascade do |t|
    t.bigint "rate_plan_id", null: false
    t.integer "min_age", null: false
    t.integer "max_age", null: false
    t.decimal "price_value", precision: 10, scale: 2, default: "100.0", null: false
    t.string "label"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pricing_mode", default: "multiplier", null: false
    t.index ["rate_plan_id", "position"], name: "index_rate_plan_age_bands_on_rate_plan_id_and_position"
    t.index ["rate_plan_id"], name: "index_rate_plan_age_bands_on_rate_plan_id"
  end

  create_table "rate_plans", force: :cascade do |t|
    t.string "name", null: false
    t.string "sell_mode", default: "per_room", null: false
    t.string "currency", default: "MYR", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "single_supplement", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "child_price_multiplier", precision: 3, scale: 2, default: "1.0", null: false
    t.integer "base_occupancy", default: 2, null: false
    t.decimal "extra_pax_charge", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "hotel_id", null: false
    t.text "description"
    t.datetime "archived_at"
    t.index ["archived_at"], name: "index_rate_plans_on_archived_at"
    t.index ["hotel_id"], name: "index_rate_plans_on_hotel_id"
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

  create_table "room_groups", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_room_groups_on_hotel_id"
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
    t.string "applied_rule_type"
    t.decimal "corporate_price", precision: 10, scale: 2
    t.decimal "single_supplement", precision: 10, scale: 2
    t.integer "base_occupancy"
    t.decimal "extra_pax_charge", precision: 10, scale: 2
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
    t.boolean "priority", default: false, null: false
    t.boolean "dnd", default: false, null: false
    t.date "dnd_date"
    t.text "priority_note"
    t.index ["hotel_id", "dnd", "dnd_date"], name: "index_room_statuses_on_hotel_id_and_dnd_and_dnd_date"
    t.index ["hotel_id", "priority"], name: "index_room_statuses_on_hotel_id_and_priority"
    t.index ["hotel_id", "room_type_id", "room_number"], name: "idx_room_statuses_on_hotel_room_type_number", unique: true
    t.index ["hotel_id", "status"], name: "index_room_statuses_on_hotel_id_and_status"
    t.index ["hotel_id"], name: "index_room_statuses_on_hotel_id"
    t.index ["last_changed_by_id"], name: "index_room_statuses_on_last_changed_by_id"
    t.index ["room_type_id"], name: "index_room_statuses_on_room_type_id"
  end

  create_table "room_type_rate_plans", force: :cascade do |t|
    t.bigint "room_type_id", null: false
    t.bigint "rate_plan_id", null: false
    t.string "pricing_mode", default: "fixed", null: false
    t.decimal "pricing_value", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rate_plan_id"], name: "index_room_type_rate_plans_on_rate_plan_id"
    t.index ["room_type_id"], name: "index_room_type_rate_plans_on_room_type_id"
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
    t.bigint "room_group_id"
    t.index ["hotel_id"], name: "index_room_types_on_hotel_id"
    t.index ["room_group_id"], name: "index_room_types_on_room_group_id"
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

  create_table "transaction_code_taxes", force: :cascade do |t|
    t.bigint "transaction_code_id", null: false
    t.bigint "hotel_tax_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "primary_tax_key"
    t.index ["hotel_tax_id"], name: "index_transaction_code_taxes_on_hotel_tax_id"
    t.index ["transaction_code_id", "hotel_tax_id"], name: "idx_transaction_code_taxes_on_custom_tax", unique: true, where: "(hotel_tax_id IS NOT NULL)"
    t.index ["transaction_code_id", "primary_tax_key"], name: "idx_transaction_code_taxes_on_primary_tax", unique: true, where: "(primary_tax_key IS NOT NULL)"
    t.index ["transaction_code_id"], name: "index_transaction_code_taxes_on_transaction_code_id"
  end

  create_table "transaction_codes", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.string "system_key", null: false
    t.string "code", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "category", null: false
    t.boolean "active", default: true, null: false
    t.boolean "system_required", default: false, null: false
    t.string "gl_account_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_taxable", default: false, null: false
    t.index ["hotel_id", "code"], name: "index_transaction_codes_on_hotel_id_and_code", unique: true
    t.index ["hotel_id", "kind", "category"], name: "index_transaction_codes_on_hotel_id_and_kind_and_category"
    t.index ["hotel_id", "system_key"], name: "index_transaction_codes_on_hotel_id_and_system_key", unique: true
    t.index ["hotel_id"], name: "index_transaction_codes_on_hotel_id"
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
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["account_id"], name: "index_users_on_unique_corporate_account", unique: true, where: "((role)::text = 'corporate'::text)"
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
  add_foreign_key "ar_invoices", "booking_folios"
  add_foreign_key "ar_invoices", "hotel_corporate_accounts"
  add_foreign_key "ar_invoices", "hotels"
  add_foreign_key "ar_payment_allocation_reversals", "ar_payment_allocations"
  add_foreign_key "ar_payment_allocation_reversals", "users", column: "reversed_by_id"
  add_foreign_key "ar_payment_allocations", "ar_invoices"
  add_foreign_key "ar_payment_allocations", "ar_payments"
  add_foreign_key "ar_payment_submission_allocations", "ar_invoices"
  add_foreign_key "ar_payment_submission_allocations", "ar_payment_submissions"
  add_foreign_key "ar_payment_submissions", "ar_payments"
  add_foreign_key "ar_payment_submissions", "hotel_corporate_accounts"
  add_foreign_key "ar_payment_submissions", "hotels"
  add_foreign_key "ar_payment_submissions", "users", column: "reviewed_by_id"
  add_foreign_key "ar_payment_submissions", "users", column: "submitted_by_id"
  add_foreign_key "ar_payments", "hotel_corporate_accounts"
  add_foreign_key "ar_payments", "hotels"
  add_foreign_key "banking_details", "accounts"
  add_foreign_key "billing_route_batches", "bookings"
  add_foreign_key "billing_route_batches", "hotels"
  add_foreign_key "billing_route_batches", "users", column: "actor_id"
  add_foreign_key "booking_audit_logs", "hotels"
  add_foreign_key "booking_audit_logs", "users"
  add_foreign_key "booking_billing_parties", "booking_guests"
  add_foreign_key "booking_billing_parties", "bookings"
  add_foreign_key "booking_billing_parties", "hotel_corporate_accounts"
  add_foreign_key "booking_billing_parties", "hotels"
  add_foreign_key "booking_billing_parties", "users", column: "created_by_id"
  add_foreign_key "booking_billing_terms", "booking_billing_parties"
  add_foreign_key "booking_billing_terms", "users", column: "created_by_id"
  add_foreign_key "booking_billing_terms", "users", column: "updated_by_id"
  add_foreign_key "booking_folios", "booking_billing_parties"
  add_foreign_key "booking_folios", "booking_rooms", on_delete: :restrict
  add_foreign_key "booking_folios", "bookings"
  add_foreign_key "booking_folios", "hotel_corporate_accounts"
  add_foreign_key "booking_folios", "hotels"
  add_foreign_key "booking_folios", "users", column: "closed_by_id"
  add_foreign_key "booking_folios", "users", column: "created_by_id"
  add_foreign_key "booking_guests", "bookings"
  add_foreign_key "booking_guests", "guests"
  add_foreign_key "booking_notes", "bookings"
  add_foreign_key "booking_notes", "users"
  add_foreign_key "booking_quote_items", "booking_quotes"
  add_foreign_key "booking_quote_items", "room_types"
  add_foreign_key "booking_quotes", "hotel_corporate_accounts"
  add_foreign_key "booking_quotes", "hotels"
  add_foreign_key "booking_rooms", "bookings"
  add_foreign_key "booking_rooms", "rate_plans"
  add_foreign_key "booking_rooms", "room_types"
  add_foreign_key "booking_tax_inclusion_overrides", "bookings"
  add_foreign_key "booking_tax_inclusion_overrides", "hotel_taxes"
  add_foreign_key "booking_tax_inclusion_overrides", "hotels"
  add_foreign_key "booking_tax_inclusion_overrides", "transaction_codes"
  add_foreign_key "booking_tax_inclusion_overrides", "users", column: "actor_id"
  add_foreign_key "bookings", "booking_quotes"
  add_foreign_key "bookings", "group_bookings"
  add_foreign_key "bookings", "hotel_corporate_accounts"
  add_foreign_key "bookings", "hotels"
  add_foreign_key "bookings", "payout_batches"
  add_foreign_key "channel_availability_rules", "hotels"
  add_foreign_key "channel_derived_settings", "hotels"
  add_foreign_key "channel_room_rates", "rate_plans"
  add_foreign_key "channel_room_rates", "room_types"
  add_foreign_key "check_out_requests", "bookings"
  add_foreign_key "check_out_requests", "users", column: "acknowledged_by_user_id"
  add_foreign_key "complaint_requests", "bookings"
  add_foreign_key "corporate_ar_payment_intents", "accounts", column: "corporate_account_id"
  add_foreign_key "corporate_ar_payment_intents", "ar_payments"
  add_foreign_key "corporate_ar_payment_intents", "hotel_corporate_accounts"
  add_foreign_key "corporate_ar_payment_intents", "hotels"
  add_foreign_key "corporate_ar_payment_intents", "users"
  add_foreign_key "deposits", "booking_folios"
  add_foreign_key "deposits", "bookings"
  add_foreign_key "deposits", "hotels"
  add_foreign_key "deposits", "transaction_codes"
  add_foreign_key "deposits", "users"
  add_foreign_key "exchange_rates", "users", column: "created_by_id"
  add_foreign_key "features", "feature_groups"
  add_foreign_key "financial_audit_events", "booking_folios"
  add_foreign_key "financial_audit_events", "bookings"
  add_foreign_key "financial_audit_events", "folio_transactions"
  add_foreign_key "financial_audit_events", "hotel_business_dates"
  add_foreign_key "financial_audit_events", "hotels"
  add_foreign_key "financial_audit_events", "night_audits"
  add_foreign_key "financial_audit_events", "payment_transactions"
  add_foreign_key "financial_audit_events", "refund_requests"
  add_foreign_key "folio_forecasted_charges", "booking_folios"
  add_foreign_key "folio_forecasted_charges", "folio_transactions", column: "actualizing_transaction_id"
  add_foreign_key "folio_operation_logs", "booking_folios", column: "source_folio_id"
  add_foreign_key "folio_operation_logs", "booking_folios", column: "target_folio_id"
  add_foreign_key "folio_operation_logs", "bookings"
  add_foreign_key "folio_operation_logs", "folio_transactions", column: "source_transaction_id"
  add_foreign_key "folio_operation_logs", "folio_transactions", column: "target_transaction_id"
  add_foreign_key "folio_operation_logs", "hotels"
  add_foreign_key "folio_operation_logs", "users", column: "actor_id"
  add_foreign_key "folio_routing_rules", "booking_folios", column: "target_folio_id"
  add_foreign_key "folio_routing_rules", "bookings"
  add_foreign_key "folio_routing_rules", "hotels"
  add_foreign_key "folio_routing_rules", "transaction_codes"
  add_foreign_key "folio_routing_rules", "users", column: "created_by_id"
  add_foreign_key "folio_routing_rules", "users", column: "updated_by_id"
  add_foreign_key "folio_transactions", "booking_folios"
  add_foreign_key "folio_transactions", "folio_transactions", column: "moved_from_transaction_id"
  add_foreign_key "folio_transactions", "folio_transactions", column: "parent_transaction_id"
  add_foreign_key "folio_transactions", "folio_transactions", column: "reversal_of_transaction_id"
  add_foreign_key "folio_transactions", "folio_transactions", column: "split_from_transaction_id"
  add_foreign_key "folio_transactions", "folio_transactions", column: "voided_by_transaction_id"
  add_foreign_key "folio_transactions", "night_audits", on_delete: :restrict
  add_foreign_key "folio_transactions", "transaction_codes"
  add_foreign_key "folio_transactions", "users"
  add_foreign_key "group_billing_change_batches", "group_bookings"
  add_foreign_key "group_billing_change_batches", "hotels"
  add_foreign_key "group_billing_change_batches", "users", column: "actor_id"
  add_foreign_key "group_bookings", "guests", column: "organizer_guest_id"
  add_foreign_key "group_bookings", "hotels"
  add_foreign_key "group_deposit_allocations", "booking_folios"
  add_foreign_key "group_deposit_allocations", "bookings"
  add_foreign_key "group_deposit_allocations", "folio_transactions"
  add_foreign_key "group_deposit_allocations", "group_deposit_allocations", column: "reversal_of_id"
  add_foreign_key "group_deposit_allocations", "group_deposits"
  add_foreign_key "group_deposit_allocations", "users", column: "allocated_by_id"
  add_foreign_key "group_deposits", "group_bookings"
  add_foreign_key "group_deposits", "hotel_corporate_accounts"
  add_foreign_key "group_deposits", "hotels"
  add_foreign_key "group_deposits", "users", column: "received_by_id"
  add_foreign_key "guest_registration_cards", "bookings"
  add_foreign_key "guest_registration_cards", "hotels"
  add_foreign_key "guest_registration_note_templates", "hotels"
  add_foreign_key "hotel_business_dates", "hotels"
  add_foreign_key "hotel_business_dates", "users", column: "force_closed_by_id", on_delete: :nullify
  add_foreign_key "hotel_corporate_accounts", "accounts", column: "corporate_account_id"
  add_foreign_key "hotel_corporate_accounts", "hotels"
  add_foreign_key "hotel_counters", "hotels"
  add_foreign_key "hotel_general_ledger_maps", "hotels"
  add_foreign_key "hotel_knowledge_chunks", "hotel_knowledge_documents"
  add_foreign_key "hotel_knowledge_diagnostics", "hotels"
  add_foreign_key "hotel_knowledge_diagnostics", "prospect_messages"
  add_foreign_key "hotel_knowledge_diagnostics", "prospects"
  add_foreign_key "hotel_knowledge_documents", "hotels"
  add_foreign_key "hotel_pricing_rules", "hotels"
  add_foreign_key "hotel_taxes", "hotels"
  add_foreign_key "hotel_taxes", "transaction_codes"
  add_foreign_key "hotel_team_configs", "hotels"
  add_foreign_key "hotel_transaction_configurations", "hotels"
  add_foreign_key "hotels", "accounts"
  add_foreign_key "hotels", "plans"
  add_foreign_key "hotels", "users", column: "salesperson_id"
  add_foreign_key "housekeeping_requests", "bookings"
  add_foreign_key "housekeeping_requests", "hotels"
  add_foreign_key "housekeeping_requests", "room_types"
  add_foreign_key "inventory_audit_logs", "hotels"
  add_foreign_key "inventory_audit_logs", "room_types"
  add_foreign_key "inventory_audit_logs", "users"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "hotels"
  add_foreign_key "invitations", "roles"
  add_foreign_key "invitations", "users", column: "invited_by_user_id"
  add_foreign_key "journal_batch_entries", "journal_batches"
  add_foreign_key "journal_batches", "hotels"
  add_foreign_key "legacy_booking_split_lineages", "booking_rooms"
  add_foreign_key "legacy_booking_split_lineages", "bookings", column: "child_booking_id"
  add_foreign_key "legacy_booking_split_lineages", "bookings", column: "legacy_booking_id"
  add_foreign_key "legacy_booking_split_lineages", "group_bookings"
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
  add_foreign_key "payment_transactions", "ar_payments"
  add_foreign_key "payment_transactions", "booking_quotes"
  add_foreign_key "payment_transactions", "bookings"
  add_foreign_key "payment_transactions", "corporate_ar_payment_intents"
  add_foreign_key "payout_batches", "hotels"
  add_foreign_key "plan_features", "features"
  add_foreign_key "plan_features", "plans"
  add_foreign_key "pre_checkins", "bookings"
  add_foreign_key "property_policies", "hotels"
  add_foreign_key "prospect_conversation_states", "prospects"
  add_foreign_key "prospect_messages", "prospects"
  add_foreign_key "prospects", "guests"
  add_foreign_key "prospects", "hotels"
  add_foreign_key "rate_plan_age_bands", "rate_plans"
  add_foreign_key "rate_plans", "hotels"
  add_foreign_key "refund_requests", "bookings"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "roles", "accounts"
  add_foreign_key "room_blocks", "hotels"
  add_foreign_key "room_blocks", "room_types"
  add_foreign_key "room_blocks", "users"
  add_foreign_key "room_groups", "hotels"
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
  add_foreign_key "room_type_rate_plans", "rate_plans"
  add_foreign_key "room_type_rate_plans", "room_types"
  add_foreign_key "room_types", "hotels"
  add_foreign_key "room_types", "room_groups"
  add_foreign_key "transaction_code_taxes", "hotel_taxes"
  add_foreign_key "transaction_code_taxes", "transaction_codes"
  add_foreign_key "transaction_codes", "hotels"
  add_foreign_key "user_hotel_accesses", "hotels"
  add_foreign_key "user_hotel_accesses", "roles"
  add_foreign_key "user_hotel_accesses", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "accounts"
end
