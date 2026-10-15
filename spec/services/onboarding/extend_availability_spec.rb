# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::ExtendAvailability do
  let(:hotel) { create(:hotel) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:room) { create(:room_type, hotel:, quantity: 3) }
  let(:submitted_end) { Date.current + 363.days }
  let(:submission) do
    create(:onboarding_submission, hotel:, snapshot: {
      "rates" => { "coverage" => { "start_date" => (submitted_end - 364.days).to_s, "end_date" => submitted_end.to_s } }
    })
  end

  def extend(today: Date.current)
    described_class.call(hotel:, submission:, actor:, today:)
  end

  it "copies reduced and closed inventory without changing prices or existing future dates" do
    create(:room_inventory, room_type: room, date: submitted_end, quantity: 2, status: "closed")
    existing = create(:room_inventory, room_type: room, date: submitted_end + 2.days, quantity: 1, status: "open")
    price = create(:room_rate, room_type: room, rate_plan: room.standard_rate_plan, date: submitted_end + 1.day, price: 180)

    result = extend(today: Date.current + 2.days)

    expect(result).to have_attributes(success?: true, start_date: submitted_end + 1.day, end_date: submitted_end + 3.days, record_count: 2)
    expect(room.room_inventories.find_by!(date: submitted_end + 1.day)).to have_attributes(quantity: 2, status: "closed", available_room_numbers: [])
    expect(room.room_inventories.find_by!(date: submitted_end + 3.days)).to have_attributes(quantity: 2, status: "closed")
    expect(existing.reload).to have_attributes(quantity: 1, status: "open")
    expect(price.reload.price).to eq(180)
    expect { extend(today: Date.current + 2.days) }.not_to change(InventoryAuditLog, :count)
    expect(hotel.inventory_audit_logs.last.metadata).to include("record_count" => 2, "submission_id" => submission.id)
  end

  it "reports only the range of appended records when earlier future dates exist" do
    create(:room_inventory, room_type: room, date: submitted_end, quantity: 2)
    create(:room_inventory, room_type: room, date: submitted_end + 1.day, quantity: 1)

    expect(extend(today: Date.current + 1.day)).to have_attributes(
      success?: true, start_date: submitted_end + 2.days, end_date: submitted_end + 2.days, record_count: 1
    )
  end

  it "does not repair missing dates within the submitted horizon" do
    create(:room_inventory, room_type: room, date: submitted_end, quantity: 3)
    extend
    expect(room.room_inventories.where(date: Date.current...submitted_end)).to be_empty
  end

  it "rolls back all rooms when source inventory is missing or exceeds room quantity" do
    create(:room_inventory, room_type: room, date: submitted_end, quantity: 2)
    other_room = create(:room_type, hotel:, quantity: 1)
    expect { extend }.not_to change(RoomInventory, :count)
    expect(hotel.inventory_audit_logs.reload).to be_empty
    create(:room_inventory, room_type: other_room, date: submitted_end, quantity: 2)
    expect(extend).not_to be_success
    expect(room.room_inventories.find_by(date: submitted_end + 1.day)).to be_nil
  end

  it "does nothing when all required future dates exist" do
    create(:room_inventory, room_type: room, date: submitted_end + 1.day, quantity: 1)
    expect(extend).to have_attributes(success?: true, record_count: 0, start_date: nil, end_date: nil)
    expect(hotel.inventory_audit_logs.reload).to be_empty
  end

  it "rejects missing coverage dates without writes" do
    allow(submission).to receive(:snapshot).and_return({})
    expect { expect(extend).not_to be_success }.not_to change(RoomInventory, :count)
  end

  it "queues one availability sync after commit" do
    create(:room_inventory, room_type: room, date: submitted_end, quantity: 2)
    hotel.update!(preferred_channel_manager: "channex")
    allow(ChannelManagers::SyncJob).to receive(:perform_later)

    callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| callbacks << callback }
    extend
    expect(ChannelManagers::SyncJob).not_to have_received(:perform_later)
    callbacks.each(&:call)
    expect(ChannelManagers::SyncJob).to have_received(:perform_later).with(
      hotel.id, submitted_end + 1.day, submitted_end + 1.day,
      sync_availability: true, sync_rates: false, sync_restrictions: false,
      room_type_ids: [ room.id ], rate_plan_ids: []
    ).once
  end
end
