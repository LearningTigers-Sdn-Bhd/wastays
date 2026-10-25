require "rails_helper"
require "csv"
require "zip"

RSpec.describe EstatellExports::ExportHotel do
  let(:hotel) { create(:hotel, name: "Grand Eastern Hotel", time_zone: "Asia/Kuala_Lumpur") }
  let(:other_hotel) { create(:hotel) }
  let(:storage) { instance_double(ActiveStorage::Service::R2Service, upload: nil) }
  let(:uploads) { {} }

  before do
    allow(storage).to receive(:upload) { |key, io, **| uploads[key] = io.read }
    allow(storage).to receive(:r2_configured?).and_return(true)
  end

  def run_export(**options)
    described_class.call(hotel: hotel, storage: storage, today: Date.new(2026, 10, 22), **options)
  end

  def zip_entries(result)
    entries = {}
    Zip::File.open_buffer(StringIO.new(uploads.fetch(result.key))) do |zip|
      zip.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end
    entries
  end

  def csv_rows(entries, name)
    CSV.parse(entries.fetch(name), headers: true)
  end

  it "exports only the given hotel's rows" do
    mine = create(:booking, hotel: hotel)
    theirs = create(:booking, hotel: other_hotel)

    entries = zip_entries(run_export)

    expect(csv_rows(entries, "bookings.csv").map { |row| row["id"] }).to eq([ mine.id.to_s ])
    expect(csv_rows(entries, "bookings.csv").map { |row| row["id"] }).not_to include(theirs.id.to_s)
    expect(csv_rows(entries, "hotels.csv").map { |row| row["id"] }).to eq([ hotel.id.to_s ])
  end

  it "exports the hotel's companies with their accounts, and no other hotel's" do
    mine = create(:hotel_corporate_account, hotel: hotel)
    theirs = create(:hotel_corporate_account, hotel: other_hotel)

    entries = zip_entries(run_export)

    expect(csv_rows(entries, "hotel_corporate_accounts.csv").map { |row| row["id"] }).to eq([ mine.id.to_s ])
    expect(csv_rows(entries, "accounts.csv").map { |row| row["id"] }).to eq([ mine.corporate_account_id.to_s ])
    expect(csv_rows(entries, "accounts.csv").map { |row| row["id"] }).not_to include(theirs.corporate_account_id.to_s)
  end

  it "exports the hotel's AR invoices and payments, and no other hotel's" do
    account = create(:hotel_corporate_account, hotel: hotel)
    other_account = create(:hotel_corporate_account, hotel: other_hotel)
    mine = create(:ar_payment, hotel: hotel, hotel_corporate_account: account)
    create(:ar_payment, hotel: other_hotel, hotel_corporate_account: other_account)

    entries = zip_entries(run_export)

    expect(csv_rows(entries, "ar_payments.csv").map { |row| row["id"] }).to eq([ mine.id.to_s ])
    %w[ar_invoices ar_invoice_corrections ar_payment_allocations ar_payment_allocation_reversals ar_payment_voids].each do |table|
      expect(entries).to have_key("#{table}.csv")
    end
  end

  it "writes guest PII decrypted, never as ciphertext" do
    booking = create(:booking, hotel: hotel)
    guest = create(:guest, email: "kim@example.com", phone: "+60111222333", government_id: "A9998887", passport_number: "P1234567")
    create(:booking_guest, booking: booking, guest: guest, email_snapshot: "kim@example.com", phone_snapshot: "+60111222333")
    stranger = create(:guest, email: "other@example.com")
    create(:booking_guest, booking: create(:booking, hotel: other_hotel), guest: stranger)

    entries = zip_entries(run_export)

    guest_row = csv_rows(entries, "guests.csv").first
    expect(guest_row.to_h).to include("email" => "kim@example.com", "phone" => "+60111222333", "government_id" => "a9998887", "passport_number" => "p1234567")
    expect(csv_rows(entries, "guests.csv").size).to eq(1)
    expect(csv_rows(entries, "booking_guests.csv").first.to_h).to include("email_snapshot" => "kim@example.com", "phone_snapshot" => "+60111222333")
    expect(csv_rows(entries, "guests.csv").headers).not_to include("magic_token_digest", "otp_code_digest")
  end

  it "writes values as stored: decimals with scale, booleans, ISO dates, empty for nil" do
    create(:night_audit, hotel: hotel, business_date: Date.new(2026, 8, 13))
    create(:night_audit, hotel: hotel, business_date: Date.new(2026, 10, 21))
    create(:night_audit, hotel: other_hotel, business_date: Date.new(2020, 1, 1))
    create(:booking, hotel: hotel, total_amount: 162)

    entries = zip_entries(run_export)

    row = csv_rows(entries, "bookings.csv").first
    expect(row["total_amount"]).to match(/\A162\.0+\z/)
    expect(row["tourism_tax_applied"]).to be_in(%w[true false])
    expect(row["internal_notes"]).to be_nil
    expect(csv_rows(entries, "night_audits.csv").map { |r| r["business_date"] }).to match_array(%w[2026-08-13 2026-10-21])
  end

  it "builds a manifest whose row counts and checksums match the files" do
    create(:night_audit, hotel: hotel, business_date: Date.new(2026, 8, 13))
    create(:night_audit, hotel: hotel, business_date: Date.new(2026, 10, 21))
    create(:booking, hotel: hotel)
    create(:booking, hotel: hotel)

    result = run_export
    entries = zip_entries(result)
    manifest = JSON.parse(entries.fetch("manifest.json"))

    expect(manifest).to include(
      "format_version" => 1,
      "hotel_id" => hotel.id,
      "hotel_code" => hotel.hotel_prefix,
      "hotel_name" => "Grand Eastern Hotel",
      "first_audit_date" => "2026-08-13",
      "last_audit_date" => "2026-10-21"
    )
    expect(Time.iso8601(manifest["exported_at"]).utc_offset).to eq(8.hours.to_i)
    expect(entries.keys).to match_array([ "manifest.json" ] + manifest["files"].keys)
    expect(manifest["files"].keys).to all(end_with(".csv"))
    expect(manifest["files"]["bookings.csv"]["rows"]).to eq(2)
    manifest["files"].each do |name, info|
      expect(Digest::SHA256.hexdigest(entries.fetch(name))).to eq(info["sha256"])
      expect(CSV.parse(entries.fetch(name), headers: true).size).to eq(info["rows"])
    end
  end

  it "exports the booking audit rows the replay reads, without guest keys or guest edits" do
    booking = create(:booking, hotel: hotel)
    other = create(:booking, hotel: other_hotel)
    base = { hotel: hotel, category: "status", source: "staff", occurred_at: Time.current }
    create(:booking_audit_log, base.merge(auditable: booking, action_type: "update", new_value: { "check_out" => "2026-09-02", "guest_name" => "Invented Name", "guest_email" => "x@example.com" }, old_value: { "check_out" => "2026-09-01", "guest_phone" => "+601" }))
    create(:booking_audit_log, base.merge(auditable: booking, action_type: "check_in", new_value: { "status" => "checked_in" }))
    create(:booking_audit_log, base.merge(auditable: booking, action_type: "guest_updated", new_value: { "guest_name" => "Invented Name" }))
    create(:booking_audit_log, base.merge(auditable: booking, action_type: "room_assignment", new_value: { "room_number" => "101" }))
    create(:booking_audit_log, base.merge(auditable: other, hotel: other_hotel, action_type: "check_in"))

    entries = zip_entries(run_export)
    rows = csv_rows(entries, "booking_audit_logs.csv")

    expect(rows.map { |row| row["action_type"] }).to match_array(%w[update check_in])
    expect(entries.fetch("booking_audit_logs.csv")).not_to match(/guest_|Invented|example\.com/)
    expect(JSON.parse(rows.find { |row| row["action_type"] == "update" }["new_value"])).to eq("check_out" => "2026-09-02")
    expect(JSON.parse(entries.fetch("manifest.json"))["files"]).to have_key("booking_audit_logs.csv")
  end

  it "uploads the zip and its checksum under the hotel slug and date" do
    result = run_export

    expect(result.key).to eq("exports/grand-eastern-hotel/2026-10-22.zip")
    expect(storage).to have_received(:upload).with("exports/grand-eastern-hotel/2026-10-22.zip", anything, content_type: "application/zip")
    expect(storage).to have_received(:upload).with("exports/grand-eastern-hotel/2026-10-22.zip.sha256", anything, content_type: "text/plain")
    expect(Digest::SHA256.hexdigest(uploads.fetch(result.key))).to eq(result.sha256)
    expect(uploads.fetch("#{result.key}.sha256").strip).to eq(result.sha256)
  end

  it "saves the zip and its checksum to output_dir instead of R2" do
    Dir.mktmpdir do |dir|
      result = run_export(output_dir: dir)

      expect(result.path).to eq(File.join(dir, "exports/grand-eastern-hotel/2026-10-22.zip"))
      expect(Digest::SHA256.file(result.path).hexdigest).to eq(result.sha256)
      expect(File.read("#{result.path}.sha256").strip).to eq(result.sha256)
      expect(storage).not_to have_received(:upload)
    end
  end

  it "refuses to upload when R2 is not configured" do
    allow(storage).to receive(:r2_configured?).and_return(false)

    expect { run_export }.to raise_error(described_class::Error, /R2 is not configured/)
    expect(storage).not_to have_received(:upload)
  end

  it "does not write to any table" do
    create(:booking, hotel: hotel)

    expect { run_export }.not_to change { [ Booking.count, Guest.count, Hotel.count, FolioTransaction.count ] }
  end

  it "removes its temp files" do
    before_dirs = Dir.glob(File.join(Dir.tmpdir, "estatell-export-*"))
    run_export
    expect(Dir.glob(File.join(Dir.tmpdir, "estatell-export-*"))).to eq(before_dirs)
  end
end
