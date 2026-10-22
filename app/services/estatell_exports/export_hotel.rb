# frozen_string_literal: true

require "csv"
require "digest"
require "json"
require "tmpdir"
require "zip"

module EstatellExports
  # Read-only export of one hotel for the estatell importer.
  #
  # Writes one CSV per table plus manifest.json into a zip, then uploads the
  # zip and a .sha256 file to the R2 Active Storage service. The CSVs hold
  # decrypted guest data, so every temp file lives in a Dir.mktmpdir that is
  # removed when the export ends.
  #
  # Nothing is written to a wastays table. Rows are read through anonymous
  # models (no callbacks, no default scopes) inside a read-only transaction.
  class ExportHotel
    FORMAT_VERSION = 1
    STORAGE_SERVICE = :r2

    Result = Struct.new(:key, :sha256, :manifest, :path, keyword_init: true)

    class Error < StandardError; end

    # Every query is scoped to the hotel (:h). Child tables go through the parent.
    HOTEL_BOOKINGS = "SELECT id FROM bookings WHERE hotel_id = :h"
    HOTEL_FOLIOS = "SELECT id FROM booking_folios WHERE hotel_id = :h"
    HOTEL_ROOM_TYPES = "SELECT id FROM room_types WHERE hotel_id = :h"
    HOTEL_RATE_PLANS = "SELECT id FROM rate_plans WHERE hotel_id = :h"
    HOTEL_RTRPS = "SELECT id FROM room_type_rate_plans WHERE room_type_id IN (#{HOTEL_ROOM_TYPES})"

    TABLES = {
      "hotels" => "id = :h",
      "hotel_transaction_configurations" => "hotel_id = :h",
      "hotel_business_dates" => "hotel_id = :h",
      "hotel_counters" => "hotel_id = :h",
      "hotel_prefix_histories" => "hotel_id = :h",
      "hotel_taxes" => "hotel_id = :h",
      "hotel_extra_charges" => "hotel_id = :h",
      "hotel_payment_methods" => "hotel_id = :h",
      "hotel_discounts" => "hotel_id = :h",
      "hotel_discount_transaction_codes" => "hotel_discount_id IN (SELECT id FROM hotel_discounts WHERE hotel_id = :h)",
      "hotel_reservation_policies" => "hotel_id = :h",
      "hotel_cancellation_policy_tiers" => "hotel_reservation_policy_id IN (SELECT id FROM hotel_reservation_policies WHERE hotel_id = :h)",
      "transaction_codes" => "hotel_id = :h",
      "transaction_code_taxes" => "transaction_code_id IN (SELECT id FROM transaction_codes WHERE hotel_id = :h)",
      "room_types" => "hotel_id = :h",
      "rooms" => "hotel_id = :h",
      "rate_plans" => "hotel_id = :h",
      "room_type_rate_plans" => "room_type_id IN (#{HOTEL_ROOM_TYPES})",
      "room_type_rate_plan_occupancy_prices" => "room_type_rate_plan_id IN (#{HOTEL_RTRPS})",
      "room_type_rate_plan_age_band_prices" => "room_type_rate_plan_id IN (#{HOTEL_RTRPS})",
      "rate_plan_age_bands" => "rate_plan_id IN (#{HOTEL_RATE_PLANS})",
      "rate_plan_stay_discounts" => "rate_plan_id IN (#{HOTEL_RATE_PLANS})",
      "rate_plan_agency_rules" => "rate_plan_id IN (#{HOTEL_RATE_PLANS})",
      "guests" => "id IN (SELECT guest_id FROM booking_guests WHERE guest_id IS NOT NULL AND booking_id IN (#{HOTEL_BOOKINGS})) " \
                  "OR id IN (SELECT organizer_guest_id FROM group_bookings WHERE organizer_guest_id IS NOT NULL AND hotel_id = :h) " \
                  "OR created_by_hotel_id = :h",
      "group_bookings" => "hotel_id = :h",
      "bookings" => "hotel_id = :h",
      "booking_rooms" => "booking_id IN (#{HOTEL_BOOKINGS})",
      "booking_guests" => "booking_id IN (#{HOTEL_BOOKINGS})",
      "booking_sources" => "id IN (SELECT booking_source_id FROM booking_billing_parties WHERE booking_source_id IS NOT NULL AND hotel_id = :h)",
      "booking_billing_parties" => "hotel_id = :h",
      "booking_folios" => "hotel_id = :h",
      "folio_transactions" => "booking_folio_id IN (#{HOTEL_FOLIOS})",
      "folio_operation_logs" => "hotel_id = :h",
      "folio_transfer_batches" => "hotel_id = :h",
      "payment_transactions" => "booking_id IN (#{HOTEL_BOOKINGS})",
      "refund_requests" => "booking_id IN (#{HOTEL_BOOKINGS})",
      "deposits" => "hotel_id = :h",
      "deposit_movements" => "deposit_id IN (SELECT id FROM deposits WHERE hotel_id = :h)",
      "invoices" => "hotel_id = :h",
      "invoice_revisions" => "hotel_id = :h",
      "receipts" => "hotel_id = :h",
      "night_audits" => "hotel_id = :h",
      "night_audit_financial_summaries" => "night_audit_id IN (SELECT id FROM night_audits WHERE hotel_id = :h)",
      "night_audit_logs" => "hotel_id = :h"
    }.freeze

    # Secrets and login tokens the importer does not need.
    EXCLUDED_COLUMNS = {
      "hotels" => %w[ai_provider_key],
      "guests" => %w[magic_token_digest otp_code_digest],
      "bookings" => %w[confirmation_token],
      "group_bookings" => %w[confirmation_token],
      "receipts" => %w[access_token],
      "payment_transactions" => %w[signature]
    }.freeze

    # Tables whose columns are Active Record encrypted. The attribute list is
    # read from the real model so the two cannot drift apart.
    ENCRYPTED_MODELS = { "guests" => "Guest", "booking_guests" => "BookingGuest" }.freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(hotel:, storage: nil, today: nil, output_dir: nil)
      @hotel = hotel
      @storage = storage
      @output_dir = output_dir.presence
      @zone = Time.find_zone(hotel.time_zone) || Time.zone
      @now = Time.current.in_time_zone(@zone)
      @today = today || @now.to_date
    end

    def call
      Dir.mktmpdir("estatell-export-") do |dir|
        files = {}
        read_only { write_csvs(dir, files) }
        manifest = build_manifest(files)
        File.write(File.join(dir, "manifest.json"), JSON.pretty_generate(manifest))

        zip_path = File.join(dir, "bundle.zip")
        write_zip(zip_path, dir, files.keys)
        sha256 = Digest::SHA256.file(zip_path).hexdigest
        path = @output_dir ? save_locally(zip_path, sha256) : upload(zip_path, sha256)

        Result.new(key: key, sha256: sha256, manifest: manifest, path: path)
      end
    end

    def key
      "exports/#{@hotel.name.parameterize}/#{@today.iso8601}.zip"
    end

    private

    def read_only(&block)
      connection = ActiveRecord::Base.connection
      ActiveRecord::Base.while_preventing_writes do
        if connection.open_transactions.zero?
          connection.transaction(isolation: :repeatable_read) do
            connection.execute("SET TRANSACTION READ ONLY")
            block.call
          end
        else
          block.call
        end
      end
    end

    def write_csvs(dir, files)
      TABLES.each do |table, condition|
        path = File.join(dir, "#{table}.csv")
        rows = write_csv(table, condition, path)
        files["#{table}.csv"] = { "rows" => rows, "sha256" => Digest::SHA256.file(path).hexdigest }
      end
    end

    def write_csv(table, condition, path)
      model = model_for(table)
      columns = model.column_names - EXCLUDED_COLUMNS.fetch(table, [])
      scope = model.where(ActiveRecord::Base.sanitize_sql_array([ condition, { h: @hotel.id } ]))
      count = 0

      CSV.open(path, "w") do |csv|
        csv << columns
        scope.find_each do |record|
          csv << columns.map { |column| cell(model, column, record[column]) }
          count += 1
        end
      end
      count
    end

    def model_for(table)
      encrypted = ENCRYPTED_MODELS[table]&.constantize&.encrypted_attributes.to_a

      Class.new(ActiveRecord::Base) do
        self.table_name = table
        self.inheritance_column = nil
        encrypts(*encrypted, deterministic: true) if encrypted.any?
      end
    end

    def cell(model, column, value)
      case value
      when nil then nil
      when true, false then value.to_s
      when BigDecimal then decimal(model, column, value)
      when Time, ActiveSupport::TimeWithZone, DateTime then time(model, column, value)
      when Date then value.iso8601
      when Hash, Array then JSON.generate(value)
      else value.to_s
      end
    end

    def decimal(model, column, value)
      scale = model.type_for_attribute(column).scale
      scale ? format("%.#{scale}f", value) : value.to_s("F")
    end

    def time(model, column, value)
      if model.type_for_attribute(column).type == :time
        value.strftime("%H:%M:%S")
      else
        value.utc.iso8601(6)
      end
    end

    def build_manifest(files)
      dates = NightAudit.unscoped.where(hotel_id: @hotel.id)
      {
        "format_version" => FORMAT_VERSION,
        "hotel_id" => @hotel.id,
        "hotel_code" => @hotel.hotel_prefix,
        "hotel_name" => @hotel.name,
        "exported_at" => @now.iso8601,
        "first_audit_date" => dates.minimum(:business_date)&.iso8601,
        "last_audit_date" => dates.maximum(:business_date)&.iso8601,
        "files" => files
      }
    end

    def write_zip(zip_path, dir, csv_names)
      Zip::OutputStream.open(zip_path) do |zip|
        (%w[manifest.json] + csv_names).each do |name|
          zip.put_next_entry(name)
          zip.write(File.binread(File.join(dir, name)))
        end
      end
    end

    def upload(zip_path, sha256)
      raise Error, "R2 is not configured (AppConfig r2_* keys); refusing to write to local disk" unless r2_ready?

      File.open(zip_path, "rb") do |io|
        storage.upload(key, io, content_type: "application/zip")
      end
      storage.upload("#{key}.sha256", StringIO.new("#{sha256}\n"), content_type: "text/plain")
      nil
    end

    def save_locally(zip_path, sha256)
      path = File.join(File.expand_path(@output_dir), key)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(zip_path, path)
      File.write("#{path}.sha256", "#{sha256}\n")
      path
    end

    def r2_ready?
      return true unless storage.respond_to?(:r2_configured?, true)

      storage.send(:r2_configured?)
    end

    def storage
      @storage ||= ActiveStorage::Blob.services.fetch(STORAGE_SERVICE)
    end
  end
end
