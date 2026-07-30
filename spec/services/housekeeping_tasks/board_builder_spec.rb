# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::BoardBuilder do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:) }

  # Two different rooms that happen to share the number 101.
  let!(:penthouse) { create(:room_type, hotel:, name: "Executive Penthouse", room_number_mode: "custom", room_numbers: %w[101]) }
  let!(:garden_suite) { create(:room_type, hotel:, name: "Garden Prestige Suite", room_number_mode: "custom", room_numbers: %w[101]) }

  def board(date: Date.current)
    described_class.new(hotel:, date:).call
  end

  def tasks_for(room_type_name, date: Date.current)
    group = board(date:).find { |entry| entry[:room_type].name == room_type_name }
    room = group[:rooms].find { |entry| entry[:room_number] == "101" }
    room[:hk_requests].reject { |task| task.status == "no_task" }.map(&:request_details)
  end

  def task_on(room_type, details:, status: "in_progress", archived_at: nil, requested_at: Time.current)
    booking = create(:booking, hotel:)
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(
      :housekeeping_request,
      booking:,
      hotel:,
      room_number: "101",
      status:,
      archived_at:,
      requested_at:,
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

    it "leaves out work that had not been asked for yet on the selected date" do
      task_on(penthouse, details: "Raised today")
      task_on(penthouse, details: "Raised last week", requested_at: 7.days.ago)

      expect(tasks_for("Executive Penthouse", date: 3.days.ago.to_date)).to contain_exactly("Raised last week")
      expect(tasks_for("Executive Penthouse")).to contain_exactly("Raised today", "Raised last week")
    end

    it "counts a task raised later the same day as open on that day" do
      task_on(penthouse, details: "Raised this evening", requested_at: Date.current.end_of_day - 1.minute)

      expect(tasks_for("Executive Penthouse")).to contain_exactly("Raised this evening")
    end

    it "still shows assigned and in-progress work" do
      task_on(penthouse, details: "Towels", status: "assigned")
      task_on(penthouse, details: "Minibar", status: "in_progress")

      expect(tasks_for("Executive Penthouse")).to contain_exactly("Towels", "Minibar")
    end
  end

  describe "narrowing the board" do
    def room_types_on(**filters)
      described_class.new(hotel:, date: Date.current, **filters).call.map { |group| group[:room_type].name }
    end

    it "keeps every room type when nothing was asked for" do
      expect(room_types_on).to contain_exactly("Executive Penthouse", "Garden Prestige Suite")
    end

    it "keeps only the rooms holding the named housekeeper's work" do
      staff = create(:user, account:)
      request = task_on(penthouse, details: "Towels")
      request.update!(metadata: { "assigned_to" => staff.id, "assigned_to_name" => staff.name })
      task_on(garden_suite, details: "Somebody else's towels")

      expect(room_types_on(assigned_to: staff.id.to_s)).to contain_exactly("Executive Penthouse")
    end

    it "keeps only the rooms in the named condition" do
      create(:room_status, hotel:, room_type: penthouse, room_number: "101", status: "dirty")

      expect(room_types_on(room_status: "dirty")).to contain_exactly("Executive Penthouse")
      expect(room_types_on(room_status: "cleaning")).to be_empty
    end

    it "searches the room type, the task note and the guest, case-insensitively" do
      booking = create(:booking, hotel:, guest_name: "Ada Lovelace", confirmation_token: "WS-ADA1", status: "checked_in")
      create(:booking_room, booking:, room_type: penthouse, room_number: "101")
      create(:housekeeping_request, booking:, hotel:, room_number: "101", status: "new", request_details: "Extra pillows", requested_at: Time.current)

      expect(room_types_on(query: "penthouse")).to contain_exactly("Executive Penthouse")
      expect(room_types_on(query: "PILLOWS")).to contain_exactly("Executive Penthouse")
      expect(room_types_on(query: "ada lovelace")).to contain_exactly("Executive Penthouse")
      expect(room_types_on(query: "ws-ada1")).to contain_exactly("Executive Penthouse")
      expect(room_types_on(query: "101")).to contain_exactly("Executive Penthouse", "Garden Prestige Suite")
      expect(room_types_on(query: "nothing here")).to be_empty
    end

    it "asks every filter of the same room, not each of a different one" do
      staff = create(:user, account:)
      request = task_on(penthouse, details: "Towels")
      request.update!(metadata: { "assigned_to" => staff.id })
      create(:room_status, hotel:, room_type: garden_suite, room_number: "101", status: "dirty")

      # The penthouse holds their work but is not dirty; the garden suite is
      # dirty but holds nobody's work. Neither room answers both.
      expect(room_types_on(assigned_to: staff.id.to_s, room_status: "dirty")).to be_empty
    end

    it "treats a blank filter as no filter at all" do
      task_on(penthouse, details: "Towels")

      expect(room_types_on(query: "", assigned_to: "", room_status: "")).to contain_exactly(
        "Executive Penthouse", "Garden Prestige Suite"
      )
    end
  end
end
