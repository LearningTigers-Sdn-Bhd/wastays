# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::HousekeepingTaskRoomPresenter do
  let(:selected_date) { Date.new(2026, 8, 15) }
  let(:hotel) { build_stubbed(:hotel) }
  let(:room_type) { build_stubbed(:room_type, name: "Ocean Suite", smoking_allowed: false, pets_allowed: true) }
  let(:view_context) do
    context = double("view context")
    allow(context).to receive(:display_housekeeping_datetime) { |value| "at #{value.strftime('%H:%M')}" }
    allow(context).to receive(:display_housekeeping_date) { |value| "on #{value.to_date}" }
    allow(context).to receive(:hotel_housekeeping_room_status_path) { "/rooms/status" }
    allow(context).to receive(:hotel_housekeeping_room_assignment_path) { "/rooms/assignment" }
    allow(context).to receive(:hotel_housekeeping_room_remarks_path) { "/rooms/remarks" }
    allow(context).to receive(:hotel_edit_housekeeping_room_remarks_path) { "/rooms/remarks/edit" }
    context
  end

  before do
    allow(hotel).to receive(:current_business_date).and_return(selected_date)
  end

  def present(
    resolved_status: "dirty",
    booking: nil,
    booking_status: "vacant",
    booking_status_label: "Vacant",
    notes: nil,
    assigned_to: nil,
    assigned_to_id: nil,
    late_checkout_eligible: false,
    date: selected_date
  )
    described_class.new(
      {
        room_number: "101",
        room_type:,
        resolved_status:,
        booking:,
        booking_status:,
        booking_status_label:,
        notes:,
        assigned_to:,
        assigned_to_id:,
        late_checkout_eligible:,
        pax: booking ? "#{booking.adults}/#{booking.children}" : "—"
      },
      hotel:,
      view_context:,
      selected_date: date
    )
  end

  it "uses housekeeping-specific room labels without changing shared Ready terminology" do
    expect(present(resolved_status: "ready").display_status).to eq("Cleaned")
    expect(present(resolved_status: "out_of_service").display_status).to eq("Out of service")
    expect(present(resolved_status: "out_of_service").status_badge_variant).to eq(:destructive)
  end

  it "hides inspection actions before cleaning and disables an ineligible late checkout" do
    choices = present(resolved_status: "dirty").status_choices.index_by { |choice| choice[:value] }

    expect(choices.keys).to eq(RoomStatus::STATUSES - described_class::INSPECTION_STATUSES)
    expect(choices.fetch("cleaning")[:disabled]).to be(false)
    expect(choices.fetch("dirty")[:disabled]).to be(false)
    expect(choices.fetch("late_checkout_detected")[:disabled]).to be(true)
  end

  it "reveals inspection actions during cleaning and enables an eligible late checkout" do
    cleaning_choices = present(resolved_status: "cleaning").status_choices.index_by { |choice| choice[:value] }
    eligible_choices = present(resolved_status: "dirty", late_checkout_eligible: true)
      .status_choices.index_by { |choice| choice[:value] }

    expect(cleaning_choices.keys).to eq(RoomStatus::STATUSES)
    expect(cleaning_choices.fetch("awaiting_inspection")[:disabled]).to be(false)
    expect(cleaning_choices.fetch("inspection_failed")[:disabled]).to be(false)
    expect(eligible_choices.fetch("late_checkout_detected")[:disabled]).to be(false)
  end

  it "explains that remarks are required before selecting Cleaned" do
    without_remarks = present(resolved_status: "cleaning").status_choices.index_by { |choice| choice[:value] }
    with_remarks = present(resolved_status: "cleaning", notes: "Inspection complete")
      .status_choices.index_by { |choice| choice[:value] }

    expect(without_remarks.fetch("ready")).to include(label: "Cleaned — add remarks first", disabled: true)
    expect(with_remarks.fetch("ready")).to include(label: "Cleaned", disabled: false)
  end

  it "is writable only on the current hotel business date" do
    expect(present).to be_writable
    expect(present(date: selected_date - 1.day)).not_to be_writable
  end

  it "builds room-keyed status, assignment, and remark routes" do
    presented = present

    expect(presented.status_url).to eq("/rooms/status")
    expect(presented.assignment_url).to eq("/rooms/assignment")
    expect(presented.remarks_url).to eq("/rooms/remarks")
    expect(presented.edit_remarks_url(return_to: "/board")).to eq("/rooms/remarks/edit")
    expect(view_context).to have_received(:hotel_housekeeping_room_status_path).with(
      hotel,
      room_type_id: room_type.id,
      room_number: "101"
    )
  end

  it "shows actual stay timestamps and falls back to scheduled dates" do
    actual = build_stubbed(
      :booking,
      checked_in_at: Time.zone.local(2026, 8, 15, 14, 30),
      checked_out_at: Time.zone.local(2026, 8, 17, 11),
      check_in: selected_date,
      check_out: selected_date + 2.days
    )
    scheduled = build_stubbed(
      :booking,
      checked_in_at: nil,
      checked_out_at: nil,
      check_in: selected_date,
      check_out: selected_date + 2.days
    )

    expect(present(booking: actual).arrival).to eq("at 14:30")
    expect(present(booking: actual).departure).to eq("at 11:00")
    expect(present(booking: scheduled).arrival).to eq("on 2026-08-15")
    expect(present(booking: scheduled).departure).to eq("at #{scheduled.check_out.strftime('%H:%M')}")
    expect(present.arrival).to eq("—")
  end

  it "presents room-level remarks and assignment" do
    housekeeper = build_stubbed(:user, name: "Ari Housekeeper")
    presented = present(notes: "Inspect the balcony", assigned_to: housekeeper, assigned_to_id: housekeeper.id)

    expect(presented).to have_remarks
    expect(presented.remarks).to eq("Inspect the balcony")
    expect(presented.assigned_to_name).to eq("Ari Housekeeper")
    expect(presented.assigned_to_value).to eq(housekeeper.id.to_s)
  end
end
