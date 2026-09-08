require "rails_helper"

RSpec.describe BookingEngine::ConfirmGroupBooking do
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:quote) do
    create(
      :booking_quote,
      hotel: hotel,
      total_amount: 400,
      adults: 2,
      children: 0,
      hotel_snapshot: { "name" => hotel.name },
      cancellation_policy_snapshot: "Free cancellation",
      cancellation_policy_snapshot_data: {
        "tiers" => [ { "days_before_arrival" => 14, "window" => "14+ days before arrival", "charge" => "No charge" } ]
      }
    )
  end
  let!(:quote_item) do
    create(
      :booking_quote_item,
      booking_quote: quote,
      room_type: room_type,
      quantity: 2,
      subtotal: 400
    )
  end
  let(:payment_details) do
    {
      guest_name: "Jane Doe",
      guest_email: "jane@example.com",
      guest_phone: "+60123456789",
      country: "Singapore",
      date_of_birth: "1990-05-20"
    }
  end

  before do
    allow(Notifications::Dispatcher).to receive(:new).and_return(instance_double(Notifications::Dispatcher, call: []))
  end

  it "creates one child booking with one booking room for each quoted room" do
    result = described_class.call(quote: quote, payment_details: payment_details)

    expect(result).to be_success
    expect(result.group_booking.bookings).to contain_exactly(*result.bookings)
    expect(result.bookings.size).to eq(2)
    expect(result.bookings.map { |booking| booking.booking_rooms.sole.room_type }).to all(eq(room_type))
  end

  it "calculates each child's commission from its room subtotal before SST" do
    hotel.update!(sst_enabled: true)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    create(:margin_rule, settable: hotel, rate: 10)
    quote.update!(total_amount: 200)
    quote_item.update!(
      subtotal: 200,
      nightly_rate_snapshot: { quote.check_in.to_date.iso8601 => 100 }
    )

    result = described_class.call(quote: quote, payment_details: payment_details)

    expect(result).to be_success
    expect(result.bookings.size).to eq(2)
    expect(result.bookings.map(&:total_amount)).to all(eq(108.to_d))
    expect(result.bookings.map(&:margin_amount)).to all(eq(10.to_d))
    expect(result.bookings.map(&:net_amount)).to all(eq(98.to_d))
    expect(result.bookings.map(&:tax_total)).to all(eq(8.to_d))
    expect(result.group_booking.deposits.sole.amount).to eq(216.to_d)
  end

  it "copies the quote's cancellation terms onto every child booking" do
    result = described_class.call(quote: quote, payment_details: payment_details)

    expect(result.bookings.map(&:cancellation_policy_snapshot_data)).to all(eq(quote.cancellation_policy_snapshot_data))
    expect(result.bookings.map(&:cancellation_policy_snapshot)).to all(eq("Free cancellation"))
  end

  # Folio creation itself is no longer what blocks this path — Folios::Lifecycle::InitializeForBooking
  # allows any system initialization during an audit. What blocks it is the group deposit,
  # a real posting into an audited business date, which FinancialControls::PostingGuard
  # rejects by design. Single confirmation reaches the audit with no posting to make, so it
  # succeeds; group confirmation always posts a deposit, so it cannot.
  it "is blocked by the deposit posting guard, not the folio guard, during a night audit" do
    hotel.current_business_date_record.update!(status: "audit_running")

    result = described_class.call(quote: quote, payment_details: payment_details)

    expect(result).not_to be_success
    expect(result.message).to include("Only night audit postings are allowed")
    expect(GroupBooking.count).to eq(0)
  end

  it "returns the existing group and child bookings when called again" do
    first_result = described_class.call(quote: quote, payment_details: payment_details)
    counts = [ GroupBooking.count, Booking.count, BookingRoom.count ]

    second_result = described_class.call(quote: quote.reload, payment_details: payment_details)

    expect([ GroupBooking.count, Booking.count, BookingRoom.count ]).to eq(counts)
    expect(second_result).to be_success
    expect(second_result.group_booking).to eq(first_result.group_booking)
    expect(second_result.bookings).to match_array(first_result.bookings)
  end
end
