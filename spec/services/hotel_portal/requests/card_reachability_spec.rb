require 'rails_helper'

# Every card the board draws has to be reachable by the actions it offers. The
# guest-facing checkout parent and its linked turnover child are deliberately
# separate: only the parent is a Request Board card, while the child is the
# Housekeeping Tasks card.
RSpec.describe "board cards are reachable", type: :model do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", guest_name: "Sena") }

  def board = HotelPortal::RequestsBoard.new(hotel, {})

  def card_in(lane)
    board.board_columns[lane].first
  end

  # A bare controller has no request, and a path helper asked for one without a
  # host raises rather than returning a path.
  def view_context
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.view_context
  end

  # The paths a card's actions post to are built here now, not by the board, so
  # this is where a card's reachability by URL has to be asked.
  def presenter
    board_now = board
    HotelPortal::RequestsBoardPresenter.new(
      pages: board_now.pages, board_counts: board_now.board_counts, current_hotel: hotel,
      view_context: view_context, date_window: board_now.date_window
    )
  end

  def draggable?(card, lane)
    presenter.card_draggable?(card, HotelPortal::Requests::Column.find(lane))
  end

  # The card names the table it is in, so a lookup made from it finds it.
  def reachable?(card)
    HotelPortal::Requests::Finder.new(
      hotel: hotel, kind: card.record_kind, request_id: card.request_id
    ).call.present?
  end

  describe "the checkout lane" do
    let!(:checkout) do
      create(:check_out_request, booking: booking, status: "pending")
    end

    # Raised by the same room's departure, and answered on the other board. The
    # two records do not reference each other.
    let!(:turnover) do
      create(:housekeeping_request, booking: booking, work_context: "checkout_turnover",
             status: "new", request_details: "Checkout turnover", archived_at: nil)
    end

    it "shows the message the guest sent" do
      card = card_in(:checkout)

      expect(card.kind).to eq("checkout")
      expect(card.record_kind).to eq("checkout")
      expect(card.request_id).to eq(checkout.id)
    end

    it "keeps the room's turnover off the Request Board" do
      expect(board.board_columns.values.flatten.map { |card| card[:request_id] }).not_to include(turnover.id)
    end

    it "can be found from its own card" do
      expect(reachable?(card_in(:checkout))).to be(true)
    end

    it "can be archived from its own card" do
      card = card_in(:checkout)

      result = HotelPortal::Requests::Move.new(
        hotel: hotel, kind: card.record_kind, display_kind: card.kind,
        request_id: card.request_id, to: :archived
      ).call

      expect(result).to be_ok
      expect(checkout.reload.metadata["archived_at"]).to be_present
    end

    it "is draggable" do
      expect(draggable?(card_in(:checkout), :checkout)).to be(true)
    end

    it "builds its completion url" do
      expect(presenter.complete_checkout_path(card_in(:checkout)))
        .to include("/checkout-requests/#{checkout.id}/complete")
    end
  end

  describe "a completed checkout" do
    let!(:checkout) do
      create(:check_out_request, booking: booking, status: 'completed', completed_at: Time.current)
    end

    # Completing a checkout has an endpoint of its own and no status route --
    # which is what used to make it undraggable, back when draggability was
    # gated on the card carrying a status URL.
    it "is draggable even though its status cannot be written" do
      card = card_in(:completed)

      expect(card.status_updatable?).to be(false)
      expect(draggable?(card, :completed)).to be(true)
    end

    it "can be put in the archive" do
      card = card_in(:completed)

      result = HotelPortal::Requests::Move.new(
        hotel: hotel, kind: card.record_kind, display_kind: card.kind,
        request_id: card.request_id, to: :archived
      ).call

      expect(result).to be_ok
      expect(checkout.reload.metadata["archived_at"]).to be_present
    end
  end

  describe "an open checkout" do
    let!(:checkout) { create(:check_out_request, booking: booking, status: 'pending') }

    it "is draggable" do
      expect(draggable?(card_in(:checkout), :checkout)).to be(true)
    end
  end

  # Nothing on the board should be a card you cannot act on.
  it "leaves no card unreachable in any lane" do
    create(:housekeeping_request, booking: booking, status: 'pending', archived_at: nil)
    create(:complaint_request, booking: booking, status: 'pending', archived_at: nil)
    create(:housekeeping_request, booking: booking, status: 'completed',
           completed_at: Time.current, archived_at: nil)
    create(:check_out_request, booking: booking, status: 'pending')
    create(:complaint_request, booking: booking, status: 'resolved',
           completed_at: Time.current, archived_at: Time.current)

    cards = board.board_columns.values.flatten
    expect(cards).not_to be_empty
    cards.each do |card|
      expect(reachable?(card)).to be(true), "#{card.kind}##{card.request_id} could not be found"
    end
  end
end
