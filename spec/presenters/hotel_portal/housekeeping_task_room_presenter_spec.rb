# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::HousekeepingTaskRoomPresenter do
  # Everything this presenter needs from the outside arrives through the view
  # context, so the whole thing can be exercised without a request.
  let(:view_context) do
    context = double("view context")
    allow(context).to receive(:display_housekeeping_datetime) { |value| "at #{value.strftime('%H:%M')}" }
    allow(context).to receive(:display_housekeeping_date) { |value| "on #{value.to_date}" }
    allow(context).to receive(:assign_hotel_housekeeping_task_path) { |_hotel, id| "/assign/housekeeping/#{id}" }
    allow(context).to receive(:status_hotel_housekeeping_task_path) { |_hotel, id| "/status/housekeeping/#{id}" }
    allow(context).to receive(:hotel_assign_checkout_request_path) { |_hotel, id| "/assign/checkout/#{id}" }
    allow(context).to receive(:hotel_checkout_request_status_path) { |_hotel, id| "/status/checkout/#{id}" }
    context
  end

  let(:hotel) { build_stubbed(:hotel) }
  let(:room_type) { build_stubbed(:room_type, name: "Ocean Suite", smoking_allowed: false, pets_allowed: true) }

  def task(id: 1, status: "assigned", source_kind: "housekeeping", metadata: {}, details: "Fresh towels")
    HousekeepingTasks::TaskRow.new(
      id: id, booking: nil, room_number: "101", request_details: details, status: status,
      metadata: metadata, created_at: Time.current, requested_at: Time.current, source_kind: source_kind
    )
  end

  def present(resolved_status: "dirty", booking: nil, tasks: [ task ])
    described_class.new(
      { room_number: "101", room_type: room_type, resolved_status: resolved_status,
        active_booking: booking, hk_requests: tasks },
      hotel: hotel,
      view_context: view_context
    )
  end

  describe "the room's own columns" do
    it "names the status the way every other page names it" do
      expect(present(resolved_status: "out_of_service").display_status).to eq("Out of Service")
      expect(present(resolved_status: "out_of_service").status_badge_variant).to eq(:destructive)
    end

    it "reads the real timestamps once the guest has arrived and left" do
      booking = build_stubbed(:booking, checked_in_at: Time.zone.local(2026, 7, 21, 14, 30),
                                        checked_out_at: Time.zone.local(2026, 7, 23, 11, 0))

      expect(present(booking: booking).arrival).to eq("at 14:30")
      expect(present(booking: booking).departure).to eq("at 11:00")
    end

    it "falls back to the booked dates while the stay has not happened yet" do
      booking = build_stubbed(:booking, checked_in_at: nil, checked_out_at: nil,
                                        check_in: Date.new(2026, 7, 21), check_out: Date.new(2026, 7, 23))

      expect(present(booking: booking).arrival).to eq("on 2026-07-21")
      expect(present(booking: booking).departure).to eq("on 2026-07-23")
    end

    it "says so plainly when no booking holds the room" do
      expect(present.arrival).to eq("-")
      expect(present.departure).to eq("-")
      expect(present.nights).to eq("-")
    end

    it "spans the room's columns across however many tasks it has" do
      expect(present(tasks: [ task(id: 1), task(id: 2) ]).row_span).to eq(2)
      expect(present(tasks: [ task ]).row_span).to eq(1)
    end
  end

  describe "a task on the row" do
    it "routes a housekeeping task to the board's own endpoints" do
      presented = present.first_task_request

      expect(presented.assign_url).to eq("/assign/housekeeping/1")
      expect(presented.status_url).to eq("/status/housekeeping/1")
    end

    it "routes a checkout cleaning to the checkout endpoints" do
      presented = present(tasks: [ task(id: 7, source_kind: "checkout") ]).first_task_request

      expect(presented.assign_url).to eq("/assign/checkout/7")
      expect(presented.status_url).to eq("/status/checkout/7")
    end

    it "offers no route at all for the stand-in row of a room with nothing to do" do
      presented = present(tasks: [ task(id: nil, status: "no_task", details: "-") ]).first_task_request

      expect(presented).not_to be_assignable
      expect(presented.assign_url).to be_nil
      expect(presented.status_url).to be_nil
      expect(presented.fallback_status_label).to eq("No Task")
    end

    it "offers the one step that is actually next" do
      expect(present(tasks: [ task(status: "assigned") ]).first_task_request.next_status_action).to eq(:start)
      expect(present(tasks: [ task(status: "in_progress") ]).first_task_request.next_status_action).to eq(:complete)
      expect(present(tasks: [ task(status: "completed") ]).first_task_request.next_status_action).to be_nil
    end

    it "lets a performer take unclaimed work and release only their own" do
      user = build_stubbed(:user, id: 42)
      colleague = build_stubbed(:user, id: 43)

      unclaimed = present(tasks: [ task(metadata: {}) ]).first_task_request
      theirs = present(tasks: [ task(metadata: { "assigned_to" => 42 }) ]).first_task_request
      colleagues = present(tasks: [ task(metadata: { "assigned_to" => 43 }) ]).first_task_request

      expect(unclaimed.take_release_action(user)).to eq(:take)
      expect(theirs.take_release_action(user)).to eq(:release)
      expect(colleagues.take_release_action(user)).to be_nil
      expect(theirs.take_release_action(colleague)).to be_nil
    end

    it "puts only a note too long for the column behind a tooltip" do
      short = present(tasks: [ task(details: "Fresh towels") ]).first_task_request
      long = present(tasks: [ task(details: "T" * 81) ]).first_task_request

      expect(short).to have_details
      expect(short).not_to be_long_details
      expect(long).to be_long_details
    end

    it "keeps its dom key unique across the two kinds of task" do
      housekeeping = present(tasks: [ task(id: 5) ]).first_task_request
      checkout = present(tasks: [ task(id: 5, source_kind: "checkout") ]).first_task_request

      expect(housekeeping.dom_key).to eq("housekeeping-5")
      expect(checkout.dom_key).to eq("checkout-5")
    end
  end
end
