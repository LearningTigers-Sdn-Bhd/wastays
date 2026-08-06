# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Requests::Narrowing do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", guest_name: "Sena Ling") }

  # The module is written to be mixed into a board, which supplies the params
  # and calls `narrow` on its own relations. This is the smallest thing shaped
  # like one.
  let(:board_class) do
    Class.new do
      include HotelPortal::Requests::Narrowing

      attr_reader :params

      def initialize(params) = @params = params

      def narrow_requests(relation, kind: "housekeeping") = narrow(relation, kind: kind)
    end
  end

  def narrowed(params, relation: HousekeepingRequest.all, kind: "housekeeping")
    board_class.new(params).narrow_requests(relation, kind: kind)
  end

  describe "narrowing by status group" do
    it "keeps dispatched work under the pending filter" do
      dispatched = create(:housekeeping_request, booking: booking, status: "in_progress")
      finished = create(:housekeeping_request, booking: booking, status: "completed")

      expect(narrowed({ status: "pending" })).to include(dispatched)
      expect(narrowed({ status: "pending" })).not_to include(finished)
    end

    it "leaves the relation alone when nothing is asked of it" do
      request = create(:housekeeping_request, booking: booking, status: "completed")

      expect(narrowed({})).to include(request)
      expect(narrowed({ status: "all" })).to include(request)
    end
  end

  describe "narrowing by search" do
    it "finds a request by its guest" do
      mine = create(:housekeeping_request, booking: booking, status: "new")
      theirs = create(:housekeeping_request, booking: create(:booking, hotel: hotel, guest_name: "Other"), status: "new")

      expect(narrowed({ q: "sena" })).to include(mine)
      expect(narrowed({ q: "sena" })).not_to include(theirs)
    end

    it "finds a request by its details" do
      towels = create(:housekeeping_request, booking: booking, request_details: "Fresh towels", status: "new")
      soap = create(:housekeeping_request, booking: booking, request_details: "More soap", status: "new")

      expect(narrowed({ q: "towel" })).to include(towels)
      expect(narrowed({ q: "towel" })).not_to include(soap)
    end

    # A term naming the kind itself keeps everything of that kind.
    it "keeps the whole kind when the term names it" do
      request = create(:housekeeping_request, booking: booking, request_details: "Fresh towels", status: "new")

      expect(narrowed({ q: "housekeeping" })).to include(request)
    end

    # Typing "pend" has to reach work that now reads "new".
    it "reaches a status group through a partly typed term" do
      dispatched = create(:housekeeping_request, booking: booking, status: "in_progress", request_details: "Towels")

      expect(narrowed({ q: "pend" })).to include(dispatched)
    end

    it "reads a term with wildcards in it literally" do
      request = create(:housekeeping_request, booking: booking, request_details: "Fresh towels", status: "new")

      expect(narrowed({ q: "%" })).not_to include(request)
    end

    it "leaves the relation alone for a blank term" do
      request = create(:housekeeping_request, booking: booking, status: "new")

      expect(narrowed({ q: "   " })).to include(request)
    end
  end

  # Notes are read in the archive, so the board is the one that says no.
  describe "internal notes" do
    it "does not search them by default" do
      request = create(:housekeeping_request, booking: booking, status: "new", request_details: "Towels")
      request.add_internal_note("Guest was furious")
      request.save!

      expect(narrowed({ q: "furious" })).not_to include(request)
    end
  end
end
