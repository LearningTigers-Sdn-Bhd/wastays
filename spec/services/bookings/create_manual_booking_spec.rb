# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CreateManualBooking do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 5, room_numbers: [ "101", "102", "103", "104", "105" ]) }
  let(:params) do
    {
      guest_name: "Test Guest",
      guest_email: "test@example.com",
      guest_phone: "123456",
      check_in: Date.current,
      check_out: Date.current + 1.day,
      room_type_id: room_type.id,
      room_number: "101",
      adults: 2
    }
  end

  subject { described_class.new(hotel: hotel, params: params) }

  def room_revenue_code
    hotel.transaction_codes.find_by!(system_key: "room_revenue")
  end

  def guest_advance_method
    PaymentMethods::EnsureDefaults.call(hotel)
    hotel.hotel_payment_methods.active.find_by!(guest_advance: true)
  end

  before do
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)
    create(:room_rate, room_type: room_type, date: Date.current, price: 200)
  end

  it "creates a booking and deducts inventory" do
    expect {
      result = subject.call
      expect(result.success?).to be true
      expect(result.booking).to be_persisted
      expect(result.booking.reservation_number).to be_present
      expect(result.booking.receipt_number).to be_nil
      expect(result.booking.hotel_snapshot["room_number"]).to eq("101")
      expect(result.booking.booking_folio).to be_present
      expect(result.booking.booking_folio).to be_open
    }.to have_enqueued_job(WebhookBroadcastJob).with('booking_confirmed', anything)

    inventory = room_type.room_inventories.find_by(date: Date.current)
    expect(inventory.quantity).to eq(4)
    expect(Notifications::Dispatcher).to have_received(:new).with(event: :booking_confirmed, booking: kind_of(Booking))
  end

  it "returns errors when booking fails" do
    params[:guest_name] = nil
    result = subject.call
    expect(result.success?).to be false
    expect(result.errors).to include("Guest name can't be blank")
  end

  it "rolls back booking creation when folio initialization fails" do
    allow(Folios::Lifecycle::InitializeForBooking).to receive(:call).and_raise("folio initialization failed")

    expect { @result = subject.call }.not_to change(Booking, :count)

    expect(@result.success?).to be(false)
    expect(@result.errors).to include("folio initialization failed")
  end

  it "blocks manual booking creation while night audit is running" do
    hotel.current_business_date_record.update!(status: "audit_running")

    expect { subject.call }.not_to change(Booking, :count)
    expect(subject.call.errors).to include(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
  end

  it "collects the exact billing summary and ignores a forged payment amount" do
    method = guest_advance_method
    params.merge!(
      record_payment: "1",
      payment_amount: "25.00",
      hotel_payment_method_id: method.id
    )

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.payment_status).to eq("captured")
    expect(result.booking.payment_transactions).to be_empty
    expect(result.booking.deposits.sole).to have_attributes(kind: "prepayment", amount: 200.to_d, status: "settled")
    expect(result.booking.deposits.sole.transaction_code).to eq(method.transaction_code)
    payment = result.booking.booking_folio.folio_transactions.payment.sole
    expect(payment.amount).to eq(200.to_d)
    expect(payment.metadata).to include(
      "hotel_payment_method_id" => method.id,
      "payment_method_name" => method.name,
      "payment_method_code" => method.code,
      "payment_method_type" => method.payment_method_type,
      "payment_base_amount" => "200.0",
      "payment_collected_total" => "200.0"
    )
    expect(result.booking.deposits.sole.metadata).to include(
      "hotel_payment_method_id" => method.id,
      "payment_method_name" => method.name,
      "payment_method_code" => method.code,
      "payment_method_type" => method.payment_method_type,
      "payment_base_amount" => "200.0",
      "payment_collected_total" => "200.0"
    )
  end

  it "defaults manual payment to the stay total excluding tourism tax" do
    method = guest_advance_method
    hotel.update!(tourism_tax_enabled: true, tourism_tax_amount: 10.0)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    params.merge!(record_payment: "1", hotel_payment_method_id: method.id, guest_country: "Singapore", guest_date_of_birth: "1990-01-01")

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.total_amount).to eq(200.to_d)
    expect(result.booking.tourism_tax_amount).to eq(10.to_d)
    expect(result.booking.payment_status).to eq("captured")
    expect(result.booking.payment_transactions).to be_empty
    expect(result.booking.deposits.sole).to have_attributes(kind: "prepayment", amount: 200.to_d, status: "settled")
    expect(result.booking.booking_folio.folio_transactions.payment.sole.amount).to eq(200.to_d)
  end

  it "requires a configured guest-advance payment method" do
    params.merge!(record_payment: "1", payment_amount: "0")

    result = subject.call

    expect(result.success?).to be false
    expect(result.errors).to include("Select a valid guest advance payment method.")
  end

  it "collects configured reservation surcharges and surcharge taxes" do
    method = guest_advance_method
    tax = create(:hotel_tax, hotel: hotel, name: "Service Tax", rate_type: "percentage", amount: 6, enabled: true)
    extra_charge = create(:hotel_extra_charge, hotel: hotel)
    extra_charge.transaction_code.update!(is_taxable: true)
    extra_charge.transaction_code.taxes = [ tax ]
    method.update!(surcharge_posting_type: "fixed", surcharge_value: 2, surcharge_extra_charge: extra_charge)
    params.merge!(record_payment: "1", hotel_payment_method_id: method.id)

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.deposits.sole.amount).to eq(202.12.to_d)
    expect(result.booking.booking_folio.folio_transactions.charge.map(&:amount)).to include(2.to_d, 0.12.to_d)
    expect(result.booking.deposits.sole.metadata).to include(
      "payment_surcharge_amount" => "2.0",
      "payment_surcharge_tax_amount" => "0.12",
      "payment_collected_total" => "202.12"
    )
  end

  it "collects a percentage reservation surcharge and surcharge tax" do
    method = guest_advance_method
    tax = create(:hotel_tax, hotel: hotel, name: "Service Tax", rate_type: "percentage", amount: 6, enabled: true)
    extra_charge = create(:hotel_extra_charge, hotel: hotel)
    extra_charge.transaction_code.update!(is_taxable: true)
    extra_charge.transaction_code.taxes = [ tax ]
    method.update!(surcharge_posting_type: "percentage", surcharge_value: 2, surcharge_extra_charge: extra_charge)
    params.merge!(record_payment: "1", hotel_payment_method_id: method.id)

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.deposits.sole.amount).to eq(204.24.to_d)
    expect(result.booking.deposits.sole.metadata).to include(
      "payment_surcharge_amount" => "4.0",
      "payment_surcharge_tax_amount" => "0.24",
      "payment_collected_total" => "204.24"
    )
  end

  it "associates a selected hotel guest without creating a duplicate" do
    guest = create(
      :guest,
      created_by_hotel: hotel,
      name: "Existing Guest",
      email: "existing@example.com",
      phone: "+60111111111",
      country: "Malaysia",
      gender: "male",
      document_type: "ic",
      government_id: "old-ic"
    )
    params.merge!(
      existing_guest_id: guest.id,
      guest_name: "Typed Over Name",
      guest_email: "typed@example.com",
      guest_phone: "+60999999999",
      guest_country: "Singapore",
      guest_gender: "female",
      guest_document_type: "passport",
      guest_government_id: "new-passport",
      guest_date_of_birth: "1990-05-06",
      guest_update_intent: "update_existing"
    )

    expect {
      result = subject.call

      expect(result.success?).to be true
      expect(result.booking.guests).to contain_exactly(guest)
      expect(result.booking.guest_name).to eq("Typed Over Name")
      expect(result.booking.guest_email).to eq("typed@example.com")
      expect(result.booking.guest_phone).to eq("+60999999999")
      expect(result.booking.guest_country).to eq("Singapore")
      expect(result.booking.guest_gender).to eq("female")
      expect(result.booking.guest_document_type).to eq("passport")
    }.not_to change(Guest, :count)

    guest.reload
    expect(guest.name).to eq("Typed Over Name")
    expect(guest.email).to eq("typed@example.com")
    expect(guest.phone).to eq("+60999999999")
    expect(guest.country).to eq("Singapore")
    expect(guest.gender).to eq("female")
    expect(guest.document_type).to eq("ic")
    expect(guest.government_id).to eq("old-ic")
  end

  it "rejects a selected guest that is not visible to the hotel" do
    other_hotel = create(:hotel)
    guest = create(:guest, created_by_hotel: other_hotel)
    params[:existing_guest_id] = guest.id

    expect {
      result = subject.call

      expect(result.success?).to be false
      expect(result.errors).to include("Selected guest could not be found for this hotel.")
    }.not_to change(Booking, :count)
  end

  it "matches manual guest details by email without changing the guest profile" do
    guest = create(:guest, created_by_hotel: hotel, name: "Repeat Guest", email: "repeat@example.com", phone: "+60222222222")
    params.merge!(
      guest_name: "Repeat Guest Updated",
      guest_email: "repeat@example.com",
      guest_phone: "+60333333333",
      guest_country: "Thailand",
      guest_gender: "other",
      guest_document_type: "passport",
      guest_government_id: "repeat-passport",
      guest_date_of_birth: "1989-07-08"
    )

    expect {
      result = subject.call

      expect(result.success?).to be true
      expect(result.booking.guests).to contain_exactly(guest)
    }.not_to change(Guest, :count)

    guest.reload
    expect(guest.name).to eq("Repeat Guest")
    expect(guest.phone).to eq("+60222222222")
  end

  it "matches manual guest details by phone without changing the guest profile" do
    guest = create(:guest, created_by_hotel: hotel, name: "Repeat Guest", email: "repeat@example.com", phone: "+60222222222")
    params.merge!(
      guest_name: "Booking Snapshot Name",
      guest_email: "different@example.com",
      guest_phone: "+60222222222",
      guest_update_intent: "update_existing"
    )

    expect {
      result = subject.call
      expect(result.success?).to be true
      expect(result.booking.guests).to contain_exactly(guest)
    }.not_to change(Guest, :count)

    expect(guest.reload.attributes.slice("name", "email", "phone")).to eq(
      "name" => "Repeat Guest",
      "email" => "repeat@example.com",
      "phone" => "+60222222222"
    )
  end

  it "does not match a guest by name alone" do
    existing = create(:guest, created_by_hotel: hotel, name: "Shared Name", email: "old@example.com", phone: "+60111111111")
    params.merge!(guest_name: "Shared Name", guest_email: "new@example.com", guest_phone: "+60222222222")

    expect {
      result = subject.call
      expect(result.success?).to be true
      expect(result.booking.guests).not_to include(existing)
    }.to change(Guest, :count).by(1)
  end

  it "persists date of birth when creating a matched guest from manual booking details" do
    params.merge!(
      guest_email: "dated@example.com",
      guest_document_type: "passport",
      guest_date_of_birth: "1991-02-03"
    )

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.primary_guest.date_of_birth).to eq(Date.new(1991, 2, 3))
  end

  it "keeps selected guest unchanged while booking stores edited guest fields" do
    guest = create(:guest, created_by_hotel: hotel, name: "Existing Guest", email: "existing@example.com", phone: "+60111111111")
    params.merge!(
      existing_guest_id: guest.id,
      guest_name: "Edited Booking Name",
      guest_email: "edited@example.com",
      guest_phone: "+60999999999",
      guest_update_intent: "keep_existing"
    )

    expect {
      result = subject.call

      expect(result.success?).to be true
      expect(result.booking.guests).to contain_exactly(guest)
      expect(result.booking.guest_name).to eq("Edited Booking Name")
      expect(result.booking.guest_email).to eq("edited@example.com")
      expect(result.booking.guest_phone).to eq("+60999999999")
    }.not_to change(Guest, :count)

    guest.reload
    expect(guest.name).to eq("Existing Guest")
    expect(guest.email).to eq("existing@example.com")
    expect(guest.phone).to eq("+60111111111")
  end

  it "updates a selected guest date of birth from manual booking details" do
    guest = create(
      :guest,
      created_by_hotel: hotel,
      name: "Existing Guest",
      email: "existing@example.com",
      phone: "+60111111111",
      country: "Malaysia",
      document_type: "passport",
      date_of_birth: Date.new(1980, 1, 1)
    )
    params.merge!(
      existing_guest_id: guest.id,
      guest_document_type: "passport",
      guest_date_of_birth: "1992-04-05",
      guest_update_intent: "update_existing"
    )

    result = subject.call

    expect(result.success?).to be true
    expect(guest.reload.date_of_birth).to eq(Date.new(1992, 4, 5))
  end

  it "does not erase selected guest profile values when submitted values are blank" do
    guest = create(
      :guest,
      created_by_hotel: hotel,
      name: "Existing Guest",
      email: "existing@example.com",
      phone: "+60111111111",
      country: "Malaysia",
      gender: "female",
      date_of_birth: Date.new(1990, 1, 2)
    )
    params.merge!(
      existing_guest_id: guest.id,
      guest_update_intent: "update_existing",
      guest_name: "",
      guest_email: "",
      guest_phone: "",
      guest_country: "",
      guest_gender: "",
      guest_date_of_birth: ""
    )

    result = subject.call

    expect(result.success?).to be true
    expect(guest.reload.attributes.slice("name", "email", "phone", "country", "gender", "date_of_birth")).to eq(
      "name" => "Existing Guest",
      "email" => "existing@example.com",
      "phone" => "+60111111111",
      "country" => "Malaysia",
      "gender" => "female",
      "date_of_birth" => Date.new(1990, 1, 2)
    )
  end

  it "defaults selected guest changes to keep existing when intent is blank" do
    guest = create(:guest, created_by_hotel: hotel, name: "Existing Guest", email: "existing@example.com", phone: "+60111111111")
    params.merge!(existing_guest_id: guest.id, guest_email: "edited@example.com")

    result = subject.call

    expect(result.success?).to be true
    expect(guest.reload.email).to eq("existing@example.com")
    expect(result.booking.guest_email).to eq("edited@example.com")
  end

  it "creates a new guest for create-new intent when identity fields differ" do
    selected_guest = create(:guest, created_by_hotel: hotel, name: "Same Name", email: "old@example.com", phone: "+60111111111", government_id: "old-id")
    params.merge!(
      existing_guest_id: selected_guest.id,
      guest_update_intent: "create_new",
      guest_name: "Same Name",
      guest_email: "new@example.com",
      guest_phone: "+60222222222",
      guest_country: "Malaysia",
      guest_gender: "male",
      guest_document_type: "passport",
      guest_government_id: "new-id",
      guest_date_of_birth: "1991-09-10"
    )

    expect {
      result = subject.call

      expect(result.success?).to be true
      expect(result.booking.guests).not_to include(selected_guest)
      expect(result.booking.guests.first.email).to eq("new@example.com")
    }.to change(Guest, :count).by(1)

    expect(selected_guest.reload.email).to eq("old@example.com")
  end

  it "rejects create-new intent when submitted email matches selected guest" do
    selected_guest = create(:guest, created_by_hotel: hotel, email: "same@example.com", phone: "+60111111111", government_id: "old-id")
    params.merge!(existing_guest_id: selected_guest.id, guest_update_intent: "create_new", guest_email: "same@example.com", guest_phone: "+60222222222", guest_government_id: "new-id")

    expect {
      result = subject.call

      expect(result.success?).to be false
      expect(result.errors).to include("This guest has the same email, phone, or IC/passport number as the selected guest. Update the existing guest information instead.")
    }.not_to change(Guest, :count)
  end

  it "rejects create-new intent when submitted identity matches another guest" do
    selected_guest = create(:guest, created_by_hotel: hotel, email: "selected@example.com", phone: "+60111111111", government_id: "selected-id")
    create(:guest, created_by_hotel: hotel, email: "other@example.com", phone: "+60222222222", government_id: "other-id")
    params.merge!(existing_guest_id: selected_guest.id, guest_update_intent: "create_new", guest_email: "other@example.com", guest_phone: "+60333333333", guest_government_id: "new-id")

    expect {
      result = subject.call

      expect(result.success?).to be false
      expect(result.errors).to include("Another guest already exists with this email, phone, or IC/passport number. Select that guest instead.")
    }.not_to change(Guest, :count)
  end

  it "creates a new guest with identity fields" do
    params.merge!(
      guest_country: "Indonesia",
      guest_gender: "female",
      guest_document_type: "passport",
      guest_government_id: "A987654",
      guest_date_of_birth: "1995-11-12"
    )

    result = subject.call

    expect(result.success?).to be true
    guest = result.booking.guests.first
    expect(guest.country).to eq("Indonesia")
    expect(guest.gender).to eq("female")
    expect(guest.document_type).to eq("passport")
    expect(guest.government_id).to eq("a987654")
    expect(result.booking.guest_country).to eq("Indonesia")
    expect(result.booking.guest_gender).to eq("female")
    expect(result.booking.guest_document_type).to eq("passport")
  end

  it "stores a nightly rate snapshot and tax posting snapshot" do
    hotel.update!(sst_enabled: true)
    room_revenue_code.update!(is_taxable: true)
    room_revenue_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

    result = subject.call

    expect(result.success?).to be true
    booking_room = result.booking.booking_rooms.first
    expect(booking_room.nightly_rate_snapshot[Date.current.iso8601]["price"]).to eq("200.0")
    expect(result.booking.tax_lines.find { |line| line["type"] == "sst" }["amount"]).to eq("16.0")
    expect(result.booking.tax_posting_snapshot[Date.current.iso8601].first["amount"]).to eq("16.0")
  end

  it "persists the selected rate plan and requires complete room rates" do
    room_type.update!(base_price: 80)
    rate_plan = create(:rate_plan, room_type: room_type)
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 120)
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current + 1.day, price: 130)
    params.merge!(
      rate_plan_id: rate_plan.id,
      check_in: Date.current,
      check_out: Date.current + 2.days
    )

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.total_amount).to eq(250.to_d)
    expect(result.booking.booking_rooms.first.rate_plan).to eq(rate_plan)
  end

  it "falls back to base_price when no room rate exists for a date" do
    params.merge!(check_in: Date.current, check_out: Date.current + 2.days)

    result = subject.call

    expect(result.success?).to be true
    snapshot = result.booking.booking_rooms.first.nightly_rate_snapshot
    expect(snapshot[(Date.current + 1.day).iso8601]["source"]).to eq("room_category_default")
    expect(snapshot[(Date.current + 1.day).iso8601]["price"]).to eq(room_type.base_price.to_d.to_s("F"))
  end

  it "distributes a manual override total across the nightly snapshot" do
    params.merge!(manual_rate_override: 333.33, check_in: Date.current, check_out: Date.current + 3.days)

    result = subject.call

    expect(result.success?).to be true

    snapshot = result.booking.booking_rooms.first.nightly_rate_snapshot
    expect(snapshot[Date.current.iso8601]["price"]).to eq("111.11")
    expect(snapshot[(Date.current + 2.days).iso8601]["price"]).to eq("111.11")
    expect(result.booking.total_amount).to eq(333.33.to_d)
  end

  it "posts custom flat hotel tax nightly through the room revenue tax rule" do
    hotel_tax = HotelTax.create!(hotel: hotel, name: "Admin Levy", rate_type: "flat", amount: 12)
    room_revenue_code.update!(is_taxable: true)
    room_revenue_code.transaction_code_taxes.create!(hotel_tax: hotel_tax)
    create(:room_rate, room_type: room_type, date: Date.current + 1.day, price: 220)
    params.merge!(check_in: Date.current, check_out: Date.current + 2.days)

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.tax_lines.find { |line| line["name"] == "Admin Levy" }["amount"]).to eq("24.0")
    expect(result.booking.tax_posting_snapshot[Date.current.iso8601].count { |tax| tax["name"] == "Admin Levy" }).to eq(1)
    expect(result.booking.tax_posting_snapshot[(Date.current + 1.day).iso8601].count { |tax| tax["name"] == "Admin Levy" }).to eq(1)
  end

  it "rejects a selected rate plan from another room category" do
    other_room_type = create(:room_type, hotel: hotel)
    rate_plan = create(:rate_plan, room_type: other_room_type)
    params[:rate_plan_id] = rate_plan.id

    result = subject.call

    expect(result.success?).to be false
    expect(result.errors).to include("Selected rate plan could not be found for this room category.")
  end

  it "ignores stop-sell restrictions unless staff chooses to respect them" do
    rate_plan = create(:rate_plan, room_type: room_type)
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 120, stop_sell: true)
    params[:rate_plan_id] = rate_plan.id

    result = subject.call
    expect(result.success?).to be true

    params[:room_number] = "102"
    params[:apply_stop_sell_restriction] = "1"
    result = described_class.new(hotel: hotel, params: params).call

    expect(result.success?).to be false
    expect(result.errors).to include("Selected rate plan is restricted for these stay dates.")
  end
end
