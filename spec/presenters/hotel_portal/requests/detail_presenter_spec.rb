require "rails_helper"

RSpec.describe HotelPortal::Requests::DetailPresenter do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisyah", confirmation_token: "WS-1") }

  def presenter_for(record, kind)
    described_class.new(request: record, kind: kind, hotel: hotel)
  end

  describe "reading the title each kind keeps under its own name" do
    it "reads a housekeeping request's details" do
      record = create(:housekeeping_request, booking: booking, request_details: "Fresh towels")
      expect(presenter_for(record, "housekeeping").title).to eq("Fresh towels")
    end

    it "reads a complaint's details" do
      record = create(:complaint_request, booking: booking, complaint_details: "Noisy")
      expect(presenter_for(record, "complaint").title).to eq("Noisy")
    end

    it "reads a checkout's guest notes, and names it when there are none" do
      with_note = create(:check_out_request, booking: booking, guest_notes: "Leaving early")
      without = create(:check_out_request, booking: booking, guest_notes: nil)

      expect(presenter_for(with_note, "checkout").title).to eq("Leaving early")
      expect(presenter_for(without, "checkout").title).to eq("Checkout requested")
    end
  end

  describe "the columns a checkout does not have" do
    it "reads when a checkout finished from its own column" do
      finished_at = 2.days.ago
      record = create(:check_out_request, booking: booking, status: "completed", completed_at: finished_at)

      expect(presenter_for(record, "checkout").completed_at).to be_within(1.second).of(finished_at)
    end

    it "reports no finish for a checkout still open" do
      record = create(:check_out_request, booking: booking, status: "pending")

      expect(presenter_for(record, "checkout").completed_at).to be_nil
    end

    it "reads a checkout's archiving out of its metadata" do
      archived_at = 2.days.ago
      record = create(:check_out_request, booking: booking, status: "completed",
                      metadata: { "archived_at" => archived_at.iso8601 })

      subject = presenter_for(record, "checkout")

      expect(subject).to be_archived
      expect(subject.archived_at).to be_within(1.second).of(archived_at)
    end

    it "survives an unreadable archived_at rather than raising" do
      record = create(:check_out_request, booking: booking, metadata: { "archived_at" => "not a time" })

      expect(presenter_for(record, "checkout").archived_at).to be_nil
    end

    it "reports no internal notes for a kind that keeps none" do
      record = create(:check_out_request, booking: booking)

      expect(presenter_for(record, "checkout").internal_notes).to eq([])
      expect(presenter_for(record, "checkout")).not_to be_internal_notes
    end
  end

  describe "where the request came from" do
    it "names the concierge page a guest raised it on" do
      record = create(:housekeeping_request, booking: booking, metadata: { "source" => "concierge_page" })

      subject = presenter_for(record, "housekeeping")

      expect(subject).to be_guest_raised
      expect(subject.source_label).to eq("Guest, via concierge page")
    end

    it "names the desk otherwise" do
      record = create(:housekeeping_request, booking: booking, metadata: {})

      expect(presenter_for(record, "housekeeping").source_label).to eq("Front desk")
    end
  end

  describe "the room" do
    it "prefers the request's own room number" do
      record = create(:housekeeping_request, booking: booking, room_number: "101")

      expect(presenter_for(record, "housekeeping").room_number).to eq("101")
    end

    it "falls back to the one a checkout carries in metadata" do
      record = create(:check_out_request, booking: booking, metadata: { "room_number" => "205" })

      expect(presenter_for(record, "checkout").room_number).to eq("205")
    end
  end

  it "labels each kind for a reader" do
    record = create(:housekeeping_request, booking: booking)

    expect(presenter_for(record, "housekeeping").kind_label).to eq("Housekeeping")
    expect(presenter_for(record, "complaint").kind_label).to eq("Complaint")
    expect(presenter_for(record, "checkout").kind_label).to eq("Checkout")
  end
end
