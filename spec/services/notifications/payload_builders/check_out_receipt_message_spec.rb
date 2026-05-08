require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::CheckOutReceiptMessage do
  let(:hotel) { create(:hotel) }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      status: "completed",
      check_in: Date.new(2026, 5, 5),
      check_out: Date.new(2026, 5, 8),
      checked_out_at: Time.zone.local(2026, 5, 8, 11, 0),
      total_amount: 330.0,
      tourism_tax_applied: true,
      tourism_tax_amount: 10.0
    )
  end

  before do
    room_type = create(:room_type, hotel: hotel, name: "Executive King")
    create(
      :booking_room,
      booking: booking,
      room_type: room_type,
      quantity: 1,
      subtotal: 320.0,
      room_number: "104",
      room_type_snapshot: { "name" => "Executive King" }
    )

    allow(Rails.application.config.action_mailer).to receive(:default_url_options)
      .and_return({ host: "example.com", protocol: "https" })
  end

  it "builds folio-style checkout receipt payload with totals and invoice link" do
    payload = described_class.new(booking: booking).call

    expect(payload[:notification_type]).to eq("check_out_receipt_message")
    expect(payload[:trigger_event]).to eq("booking_completed")
    expect(payload[:line_items]).to contain_exactly(
      {
        description: "Executive King",
        quantity: 1,
        amount: 320.0,
        room_number: "104"
      }
    )
    expect(payload[:tax_line]).to eq({ description: "Tourism tax", quantity: 1, amount: 10.0 })
    expect(payload[:line_items_total]).to eq(320.0)
    expect(payload[:tax_total]).to eq(10.0)
    expect(payload[:derived_grand_total]).to eq(330.0)
    expect(payload[:booking_total]).to eq(330.0)
    expect(payload[:totals_mismatch]).to be(false)
    expect(payload[:totals_mismatch_amount]).to eq(0.0)
    expect(payload[:invoice_url]).to eq("https://example.com/bookings/#{booking.confirmation_token}/invoice")
  end

  it "flags totals mismatch when booking total differs from derived totals" do
    booking.update!(total_amount: 340.0)

    payload = described_class.new(booking: booking).call

    expect(payload[:derived_grand_total]).to eq(330.0)
    expect(payload[:booking_total]).to eq(340.0)
    expect(payload[:totals_mismatch]).to be(true)
    expect(payload[:totals_mismatch_amount]).to eq(10.0)
  end
end
