# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::BuildImportRows do
  let(:hotel) { create(:hotel, status: "live") }
  let(:fixture) { Rails.root.join("spec/fixtures/files/ezee_reservation_list_sample.xls") }
  let(:import) { hotel.reservation_imports.create!(user: create(:user, account: hotel.account), status: "draft") }

  before do
    import.file.attach(io: File.open(fixture), filename: "Reservation List.xls")
    # The fixture carries the property's real inventory; only DLX is set up
    # here, so every other category's rows are expected to land as blocked.
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "DLX", room_number_mode: "custom", quantity: 4, base_price: 305.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[A1 A2 A3 A4] }
    )
  end

  it "writes one ReservationImportRow per parsed reservation" do
    result = described_class.call(import: import)

    expect(result).to be_success
    expect(result.rows_written).to eq(70)
    expect(import.rows.count).to eq(70)
  end

  it "resolves each row against the property before writing it down" do
    described_class.call(import: import)

    dlx_row = import.rows.find_by(room_type_name: "DLX")
    expect(dlx_row.status).to eq("importable")
    expect(dlx_row.room_type_id).to eq(hotel.room_types.find_by(name: "DLX").id)

    unresolved_row = import.rows.where.not(room_type_name: "DLX").first
    expect(unresolved_row.status).to eq("blocked")
    expect(unresolved_row.issues).to be_present
  end

  it "sets the import's total_rows to the importable count, not every row" do
    described_class.call(import: import)

    expect(import.reload.total_rows).to eq(import.rows.importable.count)
    expect(import.total_rows).to be < import.rows.count
  end

  it "parses the file once, on write, and does not duplicate rows on a second call" do
    described_class.call(import: import)
    expect {
      described_class.call(import: import)
    }.not_to change(import.rows, :count)
  end

  it "fails without writing rows when the file cannot be read" do
    not_a_spreadsheet = Rails.root.join("spec/fixtures/files/sample_image.jpg")
    import.file.attach(io: File.open(not_a_spreadsheet), filename: "notes.jpg")

    result = described_class.call(import: import)

    expect(result).not_to be_success
    expect(result.error).to be_present
    expect(import.rows.count).to eq(0)
  end
end
