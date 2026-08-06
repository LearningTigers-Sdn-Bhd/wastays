# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CreateStaffBooking, frozen_time: :business_day do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 5, room_numbers: [ "101" ]) }
  let(:common_params) do
    {
      guest_name: "Reserved Guest", guest_email: "reserved@example.com", guest_phone: "123456",
      check_in: Date.current, check_out: Date.current + 1.day, adults: 1
    }
  end
  let(:room_rows) { [ { room_type_id: room_type.id, room_number: "" } ] }

  def guest_advance_method
    PaymentMethods::EnsureDefaults.call(hotel)
    hotel.hotel_payment_methods.active.find_by!(guest_advance: true)
  end

  def direct_payment_method
    PaymentMethods::EnsureDefaults.call(hotel)
    hotel.hotel_payment_methods.active.find_by!(guest_advance: false)
  end

  before do
    allow(Notifications::Dispatcher).to receive(:new).and_return(instance_double(Notifications::Dispatcher, call: []))
    create(:room_rate, room_type: room_type, date: Date.current, price: 200)
  end

  it "creates an unassigned reservation and deducts room-type inventory" do
    result = described_class.new(hotel: hotel, common_params: common_params, room_rows: room_rows, user: nil).call

    expect(result.success?).to be(true)
    expect(result.booking.booking_rooms.sole).to have_attributes(room_type: room_type, room_number: nil)
    expect(room_type.room_inventories.find_by!(date: Date.current).quantity).to eq(4)
  end

  it "requires a room number for walk-in creation" do
    result = described_class.new(
      hotel: hotel, common_params: common_params, room_rows: room_rows, user: nil, booking_type: "walk_in"
    ).call

    expect(result.success?).to be(false)
    expect(result.errors).to include("Each room row requires a room category and room number.")
  end

  it "uses a reservation-specific message when room category is missing" do
    result = described_class.new(
      hotel: hotel, common_params: common_params, room_rows: [ { room_type_id: "", room_number: "" } ], user: nil
    ).call

    expect(result.success?).to be(false)
    expect(result.errors).to include("Each reservation row requires a room category.")
  end

  it "rejects an unassigned reservation when its room type is sold out" do
    create(:room_inventory, room_type: room_type, date: Date.current, quantity: 0, status: "open")

    result = described_class.new(hotel: hotel, common_params: common_params, room_rows: room_rows, user: nil).call

    expect(result.success?).to be(false)
    expect(result.errors.join).to include("Not enough inventory for #{room_type.name}")
    expect(Booking.where(hotel: hotel)).to be_empty
  end

  it "sponsors room charges to the company without hijacking the guest folio" do
    corporate_account = create(:hotel_corporate_account, hotel: hotel)
    params = common_params.merge(hotel_corporate_account_id: corporate_account.id)

    result = described_class.new(hotel: hotel, common_params: params, room_rows: room_rows, user: nil).call
    expect(result.errors).to be_empty

    booking = result.booking
    guest_folio = booking.booking_folio
    company_folio = booking.booking_folios.find_by(payer_type: "company")

    # Guest primary folio stays guest-owned; the account id never leaks onto it.
    expect(guest_folio).to have_attributes(is_primary: true, payer_type: "guest", hotel_corporate_account_id: nil)

    # A separate external company folio carries the corporate account.
    expect(company_folio).to be_present
    expect(company_folio).to have_attributes(folio_type: "external", hotel_corporate_account_id: corporate_account.id)

    # Room revenue is *routed* to the company folio, not folio-hijacked.
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    rule = booking.folio_routing_rules.active.find_by(transaction_code: room_code)
    expect(rule&.target_folio_id).to eq(company_folio.id)

    # Accommodation forecasts land on the company folio; the guest folio has none.
    expect(company_folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation")).to be_present
    expect(guest_folio.folio_forecasted_charges.forecast.where(charge_kind: "accommodation")).to be_empty
  end

  it "rolls back all rooms when cumulative unassigned reservations exceed inventory" do
    room_type.update!(quantity: 1)
    create(:room_inventory, room_type: room_type, date: Date.current, quantity: 1, status: "open")
    rows = Array.new(2) { { room_type_id: room_type.id, room_number: "" } }

    result = described_class.new(hotel: hotel, common_params: common_params, room_rows: rows, user: nil).call

    expect(result.success?).to be(false)
    expect(Booking.where(hotel: hotel)).to be_empty
    expect(room_type.room_inventories.find_by!(date: Date.current).quantity).to eq(1)
  end

  it "creates one aggregate configured prepayment and surcharge for a group reservation" do
    method = guest_advance_method
    extra_charge = create(:hotel_extra_charge, hotel: hotel)
    method.update!(surcharge_posting_type: "fixed", surcharge_value: 2, surcharge_extra_charge: extra_charge)
    params = common_params.merge(collect_payment: "1", hotel_payment_method_id: method.id)
    rows = [
      { room_type_id: room_type.id, room_number: "" },
      { room_type_id: room_type.id, room_number: "" }
    ]

    result = described_class.new(hotel: hotel, common_params: params, room_rows: rows, user: nil).call

    expect(result.success?).to be(true), result.errors.to_sentence
    expect(result.group_booking).to be_present
    deposit = result.group_booking.deposits.sole
    expect(deposit.amount).to eq(402.to_d)
    expect(deposit.metadata).to include("hotel_payment_method_id" => method.id, "payment_collected_total" => "402.0")
    expect(FolioTransaction.where(transaction_code: extra_charge.transaction_code).map(&:amount)).to eq([ 2.to_d ])
    expect(result.bookings.map(&:payment_status)).to all(eq("captured"))
    expect(result.bookings.map { |booking| booking.booking_folio.folio_transactions.payment.sum(:amount) }).to all(eq(201.to_d))
  end

  it "ignores forged legacy payment fields for a walk-in" do
    method = guest_advance_method
    params = common_params.merge(hotel_payment_method_id: method.id, payment_amount: "1")

    result = described_class.new(
      hotel: hotel, common_params: params, room_rows: [ { room_type_id: room_type.id, room_number: "101" } ],
      user: nil, booking_type: "walk_in"
    ).call

    expect(result.success?).to be(true)
    expect(result.booking).to be_checked_in
    expect(result.booking.deposits.kind_prepayment).to be_empty
  end

  it "collects the billing summary as a direct payment at walk-in check-in" do
    method = direct_payment_method
    params = common_params.merge(
      collect_payment: "1",
      hotel_payment_method_id: method.id,
      payment_reference: "WALK-IN-PAYMENT"
    )

    result = described_class.new(
      hotel: hotel, common_params: params, room_rows: [ { room_type_id: room_type.id, room_number: "101" } ],
      user: nil, booking_type: "walk_in"
    ).call

    expect(result.success?).to be(true)
    booking = result.booking.reload
    payment = booking.booking_folio.folio_transactions.payment.find_by("metadata->>'source' = ?", "check_in_payment")
    expect(booking.payment_status).to eq("captured")
    expect(payment).to have_attributes(amount: 200.to_d, description: "Payment collected at check-in")
    expect(payment.metadata).to include(
      "hotel_payment_method_id" => method.id,
      "payment_method_name" => method.name,
      "payment_method_code" => method.code,
      "reference" => "WALK-IN-PAYMENT",
      "payment_base_amount" => "200.0",
      "payment_collected_total" => "200.0"
    )
    expect(booking.deposits.kind_prepayment).to be_empty
  end

  it "collects canonical tourism tax and a configured direct security deposit for a walk-in" do
    hotel.update!(tourism_tax_enabled: true, tourism_tax_amount: 10.0)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    method = direct_payment_method
    params = common_params.merge(
      guest_country: "Singapore",
      guest_date_of_birth: "1990-01-01",
      tourism_tax_collected: "1",
      collect_security_deposit: "1",
      hotel_payment_method_id: method.id,
      security_deposit: { amount: "75.00", external_reference: "WALK-IN-1" }
    )

    result = described_class.new(
      hotel: hotel, common_params: params, room_rows: [ { room_type_id: room_type.id, room_number: "101" } ],
      user: nil, booking_type: "walk_in"
    ).call

    expect(result.success?).to be(true)
    booking = result.booking.reload
    expect(booking).to be_checked_in
    expect(booking.tourism_tax_collected?).to be(true)
    expect(booking.booking_folio.folio_transactions.payment.where("metadata->>'source' = ?", "tourism_tax_check_in").sum(:amount)).to eq(10.to_d)
    deposit = booking.deposits.kind_security.sole
    expect(deposit).to have_attributes(amount: 75.to_d, payment_method: "cash", external_reference: "WALK-IN-1")
    expect(deposit.metadata).to include("hotel_payment_method_id" => method.id)
  end

  it "rolls back walk-in creation when a guest-advance method is used for a security deposit" do
    method = guest_advance_method
    params = common_params.merge(
      collect_security_deposit: "1",
      hotel_payment_method_id: method.id,
      security_deposit: { amount: "75.00" }
    )

    expect {
      @result = described_class.new(
        hotel: hotel, common_params: params, room_rows: [ { room_type_id: room_type.id, room_number: "101" } ],
        user: nil, booking_type: "walk_in"
      ).call
    }.not_to change(Booking, :count)

    expect(@result.success?).to be(false)
    expect(@result.errors).to include("Select a valid direct payment method.")
  end

  it "requires a positive security deposit amount when collection is enabled" do
    method = direct_payment_method
    params = common_params.merge(
      collect_security_deposit: "1",
      hotel_payment_method_id: method.id,
      security_deposit: {}
    )

    result = described_class.new(
      hotel: hotel, common_params: params, room_rows: [ { room_type_id: room_type.id, room_number: "101" } ],
      user: nil, booking_type: "walk_in"
    ).call

    expect(result.success?).to be(false)
    expect(result.errors).to include("Security deposit amount must be greater than zero.")
    expect(Booking.where(hotel: hotel)).to be_empty
  end
end
