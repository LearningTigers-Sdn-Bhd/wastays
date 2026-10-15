# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::ImportReservations do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account, name: "Priya Staff") }
  let(:fixture) { Rails.root.join("spec/fixtures/files/ezee_reservation_list_sample.xls") }
  let(:import) { hotel.reservation_imports.create!(user: user, status: "draft") }

  before do
    import.file.attach(io: File.open(fixture), filename: "Reservation List.xls")
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "DLX", room_number_mode: "custom", quantity: 4, base_price: 305.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[A1 A2 A3 A4] }
    )
    Ezee::BuildImportRows.call(import: import)
  end

  it "attempts every importable row, creating a booking for each one that succeeds" do
    importable_count = import.rows.importable.count

    result = described_class.call(import: import)

    # Not every importable row is guaranteed to succeed -- two rows can
    # legitimately compete for the same room on overlapping dates, same as a
    # booking created any other way -- so the guarantee is that every row was
    # attempted and accounted for, not that all of them landed.
    expect(result.created.size + result.failed.size).to eq(importable_count)
    expect(result.created).to all(be_a(Booking))
    expect(result.created).not_to be_empty
    expect(import.rows.where(status: "created").count).to eq(result.created.size)
  end

  it "leaves a row that could not be created as failed, with the reason recorded" do
    row = import.rows.importable.first
    allow(Bookings::CreateManualBooking).to receive(:new).and_call_original
    allow(Bookings::CreateManualBooking).to receive(:new)
      .with(hotel: hotel, params: hash_including(external_reference: row.reservation_number), user: user)
      .and_raise(StandardError, "room already occupied")

    result = described_class.call(import: import)

    expect(result.failed).to include(row)
    row.reload
    expect(row.status).to eq("failed")
    expect(row.issues.last["message"]).to eq("room already occupied")
  end

  it "records who ran the import on each created booking's internal notes" do
    described_class.call(import: import)

    booking = import.rows.where(status: "created").first.booking
    expect(booking.internal_notes).to include("Imported from eZee reservation")
    expect(booking.internal_notes).to include("by Priya Staff")
  end

  it "is safe to re-run the whole file: a row already imported is matched and skipped, not duplicated" do
    described_class.call(import: import)
    created_count = import.rows.where(status: "created").count

    # A second run reads the same export into a fresh import, the way an
    # operator re-uploading the file after a partial commit actually would --
    # BuildImportRows is what marks a row "imported" by matching it on
    # external_reference, not ImportReservations itself.
    second_import = hotel.reservation_imports.create!(user: user, status: "draft")
    second_import.file.attach(io: File.open(fixture), filename: "Reservation List.xls")
    Ezee::BuildImportRows.call(import: second_import)

    result = described_class.call(import: second_import)

    expect(result.created).to be_empty
    expect(result.skipped).to eq(created_count)
    expect(Booking.where.not(external_reference: nil).count).to eq(created_count)
  end

  it "reports progress as it works" do
    steps = []
    progress = ->(step: nil, **) { steps << step if step }

    described_class.call(import: import, progress: progress)

    expect(steps.first).to eq("Creating bookings")
    expect(steps.last).to eq("Finishing up")
  end
end
