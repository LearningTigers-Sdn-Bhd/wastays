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
      expect(result.booking.hotel_snapshot["room_number"]).to eq("101")
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

  it "blocks manual booking creation while night audit is running" do
    hotel.current_business_date_record.update!(status: "audit_running")

    expect { subject.call }.not_to change(Booking, :count)
    expect(subject.call.errors).to include(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
  end

  it "allows a manually recorded partial payment" do
    params.merge!(
      record_payment: "1",
      payment_amount: "25.00",
      payment_method: "cash"
    )

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.payment_status).to eq("partial")
    expect(result.booking.payment_transactions.first.amount_subunits).to eq(2_500)
  end

  it "rejects non-positive manual payment amounts" do
    params.merge!(record_payment: "1", payment_amount: "0")

    result = subject.call

    expect(result.success?).to be false
    expect(result.errors).to include("Payment amount must be greater than 0.")
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
    expect(guest.document_type).to eq("passport")
    expect(guest.government_id).to eq("new-passport")
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

  it "matches manual guest details by email instead of creating a duplicate" do
    guest = create(:guest, created_by_hotel: hotel, name: "Repeat Guest", email: "repeat@example.com", phone: "+60222222222")
    params.merge!(
      guest_name: "Repeat Guest Updated",
      guest_email: "repeat@example.com",
      guest_phone: "+60333333333",
      guest_country: "Thailand",
      guest_gender: "other",
      guest_document_type: "passport",
      guest_government_id: "repeat-passport"
    )

    expect {
      result = subject.call

      expect(result.success?).to be true
      expect(result.booking.guests).to contain_exactly(guest)
    }.not_to change(Guest, :count)

    guest.reload
    expect(guest.name).to eq("Repeat Guest Updated")
    expect(guest.phone).to eq("+60222222222")
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
      guest_government_id: "new-id"
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
      guest_government_id: "A987654"
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
    expect(snapshot[(Date.current + 1.day).iso8601]["source"]).to eq("base_price_fallback")
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

  it "posts custom flat hotel tax once in the tax posting snapshot" do
    HotelTax.create!(hotel: hotel, name: "Admin Levy", rate_type: "flat", amount: 12)
    create(:room_rate, room_type: room_type, date: Date.current + 1.day, price: 220)
    params.merge!(check_in: Date.current, check_out: Date.current + 2.days)

    result = subject.call

    expect(result.success?).to be true
    expect(result.booking.tax_lines.find { |line| line["name"] == "Admin Levy" }["amount"]).to eq("12.0")
    expect(result.booking.tax_posting_snapshot[Date.current.iso8601].count { |tax| tax["name"] == "Admin Levy" }).to eq(1)
    expect(result.booking.tax_posting_snapshot[(Date.current + 1.day).iso8601].to_a).to be_empty
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
