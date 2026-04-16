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

ActiveRecord::Schema[8.0].define(version: 2026_04_16_000000) do
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

  create_table "banking_details", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "account_holder_name", null: false
    t.string "bank_name", null: false
    t.string "account_number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_banking_details_on_account_id", unique: true
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
    t.index ["booking_quote_id"], name: "index_bookings_on_booking_quote_id"
    t.index ["confirmation_token"], name: "index_bookings_on_confirmation_token", unique: true
    t.index ["hotel_id"], name: "index_bookings_on_hotel_id"
    t.index ["payment_status"], name: "index_bookings_on_payment_status"
    t.index ["status"], name: "index_bookings_on_status"
  end

  create_table "cancellation_policy_templates", force: :cascade do |t|
    t.string "name"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.datetime "completed_at"
    t.index ["booking_id", "completed_at"], name: "index_complaint_requests_on_booking_id_and_completed_at"
    t.index ["booking_id", "requested_at"], name: "index_complaint_requests_on_booking_id_and_requested_at"
    t.index ["booking_id"], name: "index_complaint_requests_on_booking_id"
    t.index ["external_id"], name: "index_complaint_requests_on_external_id", unique: true
  end

  create_table "complaints", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.string "external_id"
    t.datetime "reported_at"
    t.text "issue_details"
    t.datetime "resolved_at"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_complaints_on_booking_id"
    t.index ["external_id"], name: "index_complaints_on_external_id"
    t.index ["reported_at"], name: "index_complaints_on_reported_at"
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
    t.index ["account_id"], name: "index_hotels_on_account_id"
    t.index ["featured_photo_attachment_id"], name: "index_hotels_on_featured_photo_attachment_id"
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
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "signature_status"
    t.string "document_status"
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

  create_table "room_inventories", force: :cascade do |t|
    t.bigint "room_type_id", null: false
    t.date "date", null: false
    t.integer "quantity", default: 0, null: false
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_type_id", "date"], name: "index_room_inventories_on_room_type_id_and_date", unique: true
    t.index ["room_type_id"], name: "index_room_inventories_on_room_type_id"
  end

  create_table "room_rates", force: :cascade do |t|
    t.bigint "room_type_id", null: false
    t.date "date", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.string "currency", default: "MYR", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["room_type_id", "date"], name: "index_room_rates_on_room_type_id_and_date", unique: true
    t.index ["room_type_id"], name: "index_room_rates_on_room_type_id"
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
    t.index ["hotel_id"], name: "index_room_types_on_hotel_id"
  end

  create_table "user_hotel_accesses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "hotel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "role_id"
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
  add_foreign_key "complaint_requests", "bookings"
  add_foreign_key "complaints", "bookings"
  add_foreign_key "hotels", "accounts"
  add_foreign_key "housekeeping_requests", "bookings"
  add_foreign_key "inventory_audit_logs", "hotels"
  add_foreign_key "inventory_audit_logs", "room_types"
  add_foreign_key "inventory_audit_logs", "users"
  add_foreign_key "pre_checkins", "bookings"
  add_foreign_key "property_policies", "hotels"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "roles", "accounts"
  add_foreign_key "room_inventories", "room_types"
  add_foreign_key "room_rates", "room_types"
  add_foreign_key "room_types", "hotels"
  add_foreign_key "user_hotel_accesses", "hotels"
  add_foreign_key "user_hotel_accesses", "roles"
  add_foreign_key "user_hotel_accesses", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "accounts"
end
