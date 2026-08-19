require "rails_helper"

RSpec.describe Reports::Bookings::GenerateBookingSummary do
  let(:hotel) { create(:hotel, name: "Seaview Hotel") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Aisha",
      confirmation_token: "WS-SUMMARY1",
      total_amount: 300.0,
      check_in: Date.new(2026, 5, 1),
      check_out: Date.new(2026, 5, 3),
      hotel_snapshot: { "property_policy" => { "check_in_time" => "3:00 PM" } })
  end

  before do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      subtotal: 300.0,
      room_type_snapshot: { "name" => "Deluxe" },
      nightly_rate_snapshot: {
        "2026-05-01" => { "price" => "150.00", "transaction_code_code" => "RM-DLX" },
        "2026-05-02" => { "price" => "150.00", "transaction_code_code" => "RM-DLX" }
      })
  end

  def pdf_text(pdf) = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

  def summary_for(booking) = pdf_text(described_class.new(booking: booking).generate)

  it "generates a valid PDF binary" do
    pdf = described_class.new(booking: booking).generate

    expect(pdf).to be_a(String)
    expect(pdf.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
  end

  # The whole risk of splitting this out is that it gets mistaken for the invoice, so the
  # qualification has to arrive before any number on the page does.
  it "opens on a band saying it is the booked position rather than the final bill" do
    text = summary_for(booking)

    expect(text).to include("BOOKED POSITION")
    # The note wraps, so the extracted text carries newlines the sentence does not.
    expect(text.squish).to include("Charges posted during the stay are billed on the invoice, which is the final bill.")
    expect(text.index("BOOKED POSITION")).to be < text.index("Total due")
  end

  it "renders the dense nightly charge breakdown from the booking snapshots" do
    booking.update!(
      total_amount: 324,
      tax_lines: [ { "name" => "SST", "amount" => 24.0 } ],
      tax_posting_snapshot: {
        "2026-05-01" => [ { "name" => "SST", "amount" => "12.00", "transaction_code_code" => "TX-SST" } ],
        "2026-05-02" => [ { "name" => "SST", "amount" => "12.00", "transaction_code_code" => "TX-SST" } ]
      }
    )

    text = summary_for(booking.reload)

    expect(text).to include(
      "Charges", "Net (MYR)", "Charges (MYR)", "Gross (MYR)",
      "RM-DLX", "Night 1 of 2", "Night 2 of 2", "TX-SST", "SST",
      "Total due", "324.00"
    )
  end

  it "renders the total paid and positive balance due from folio transactions" do
    booking.update!(total_amount: 324.0)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 100.0)

    text = summary_for(booking.reload)

    expect(text).to include("Payments", "Total payments", "(100.00)", "Balance due", "224.00")
  end

  it "omits balance due when transactions cover the total" do
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 300.0)

    text = summary_for(booking.reload)

    expect(text).to include("Total payments", "(300.00)", "Booking balance settled")
    expect(text).not_to include("Balance due")
  end

  it "shows an overpayment as a credit balance" do
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 400.0)

    text = summary_for(booking.reload)

    expect(text).to include("Total payments", "(400.00)", "Credit balance", "100.00")
    expect(text).not_to include("Booking balance settled")
  end

  it "does not count posted room charges as payments" do
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 300.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 100.0)

    text = summary_for(booking.reload)

    expect(text).to include("Total payments", "(100.00)", "Balance due", "200.00")
  end

  it "discloses tourism tax separately without including it in total due" do
    booking.update!(
      tourism_tax_amount: 20,
      tourism_tax_collected: false,
      tax_lines: [ { "name" => "Tourism tax", "type" => "tourism_tax", "amount" => "20.00" } ],
      tax_posting_snapshot: {
        "2026-05-01" => [ { "name" => "Tourism tax", "type" => "tourism_tax", "amount" => "10.00" } ],
        "2026-05-02" => [ { "name" => "Tourism tax", "type" => "tourism_tax", "amount" => "10.00" } ]
      }
    )

    text = summary_for(booking.reload)

    expect(text).to include(
      "Total due",
      "300.00",
      "Excluded from booking total: Tourism tax of MYR 20.00 is payable at the property. " \
        "A separate tourism tax voucher will be provided."
    )
    expect(text.scan("Tourism tax").size).to eq(1)
  end

  it "repeats document identity, charge headers, and numbered furniture over a long stay" do
    nights = 30
    booking.update!(check_out: booking.check_in + nights.days, total_amount: nights * 100)
    booking.booking_rooms.sole.update!(
      subtotal: nights * 100,
      nightly_rate_snapshot: nights.times.to_h do |index|
        [ (booking.check_in.to_date + index.days).iso8601, { "price" => "100.00" } ]
      end
    )

    pages = PDF::Reader.new(StringIO.new(described_class.new(booking: booking.reload).generate)).pages

    expect(pages.size).to be > 1
    expect(pages.drop(1).map(&:text).join).to include("Seaview Hotel", "Booking summary")
    expect(pages.count { |page| page.text.include?("Net (MYR)") && page.text.include?("Charges (MYR)") }).to eq(pages.size)
    pages.each_with_index do |page, index|
      expect(page.text).to include("Generated by", "Page #{index + 1} of #{pages.size}")
    end
  end

  describe "for a group" do
    let(:group_booking) { create(:group_booking, hotel: hotel, name: "Tanaka Wedding") }
    let!(:first_child) { create_child(position: 1, total: 300.0) }
    let!(:second_child) { create_child(position: 2, total: 200.0) }

    def create_child(position:, total:)
      child = create(:booking,
        hotel: hotel,
        group_booking: group_booking,
        group_position: position,
        total_amount: total,
        check_in: Date.new(2026, 5, 1),
        check_out: Date.new(2026, 5, 3))
      create(:booking_room, booking: child, room_type: room_type, subtotal: total,
        room_type_snapshot: { "name" => "Deluxe" })
      child
    end

    def group_summary = pdf_text(described_class.new(group_booking: group_booking).generate)

    it "reports one position for the whole group rather than one per room" do
      text = group_summary

      expect(text).to include("GROUP BOOKING SUMMARY", "Tanaka Wedding", "2 rooms")
      expect(text).to include("Total due", "500.00")
    end

    # Twenty rows of "Deluxe" tell an organiser nothing about which room each line is for.
    it "names the room each charge line belongs to" do
      text = group_summary

      expect(text).to include(first_child.confirmation_token, second_child.confirmation_token)
    end

    # A deposit taken against the group belongs to no child booking, so nothing in the
    # per-booking folio scope can see it. Before this, an organiser who had paid saw nothing.
    it "counts a deposit held against the group itself" do
      create(:deposit,
        hotel: hotel,
        group_booking: group_booking,
        booking: nil,
        amount: 150.0,
        currency: "MYR",
        status: "held",
        received_at: Time.zone.local(2026, 4, 1))

      text = group_summary

      expect(text).to include("DEP-GRP", "Held against the group", "(150.00)")
      expect(text).to include("Balance due", "350.00")
    end
  end
end
