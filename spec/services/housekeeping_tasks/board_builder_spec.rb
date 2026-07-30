# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::BoardBuilder do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:) }

  # Two different rooms that happen to share the number 101.
  let!(:penthouse) { create(:room_type, hotel:, name: "Executive Penthouse", room_number_mode: "custom", room_numbers: %w[101]) }
  let!(:garden_suite) { create(:room_type, hotel:, name: "Garden Prestige Suite", room_number_mode: "custom", room_numbers: %w[101]) }

  def board
    described_class.new(hotel:, date: Date.current).call
  end

  def tasks_for(room_type_name)
    group = board.find { |entry| entry[:room_type].name == room_type_name }
    room = group[:rooms].find { |entry| entry[:room_number] == "101" }
    room[:hk_requests].reject { |task| task.status == "no_task" }.map(&:request_details)
  end

  def task_on(room_type, details:, status: "in_progress", archived_at: nil)
    booking = create(:booking, hotel:)
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(
      :housekeeping_request,
      booking:,
      hotel:,
      room_number: "101",
      status:,
      archived_at:,
      request_details: details
    )
  end

  describe "room identity" do
    it "keeps each room type's tasks to itself when the numbers collide" do
      task_on(penthouse, details: "Penthouse towels")
      task_on(garden_suite, details: "Garden towels")

      expect(tasks_for("Executive Penthouse")).to contain_exactly("Penthouse towels")
      expect(tasks_for("Garden Prestige Suite")).to contain_exactly("Garden towels")
    end

    it "keeps a checkout cleaning on the room that is actually checking out" do
      booking = create(:booking, hotel:)
      create(:booking_room, booking:, room_type: penthouse, room_number: "101")
      create(:check_out_request, booking:, status: "new", requested_at: Time.current)

      expect(tasks_for("Executive Penthouse")).to contain_exactly("Checkout Room Cleaning")
      expect(tasks_for("Garden Prestige Suite")).to be_empty
    end

    it "shows a room type with no tasks as empty rather than borrowing its neighbour's" do
      task_on(penthouse, details: "Penthouse towels")

      expect(tasks_for("Garden Prestige Suite")).to be_empty
    end
  end

  describe "which tasks count as open" do
    it "shows a pending task, which is work nobody has triaged yet" do
      task_on(penthouse, details: "Untriaged request", status: "pending")

      expect(tasks_for("Executive Penthouse")).to contain_exactly("Untriaged request")
    end

    it "hides an archived task" do
      task_on(penthouse, details: "Archived request", archived_at: Time.current)

      expect(tasks_for("Executive Penthouse")).to be_empty
    end

    %w[completed failed cancelled].each do |status|
      it "hides a #{status} task" do
        task_on(penthouse, details: "Closed request", status:)

        expect(tasks_for("Executive Penthouse")).to be_empty
      end
    end

    it "still shows assigned and in-progress work" do
      task_on(penthouse, details: "Towels", status: "assigned")
      task_on(penthouse, details: "Minibar", status: "in_progress")

      expect(tasks_for("Executive Penthouse")).to contain_exactly("Towels", "Minibar")
    end
  end
end
