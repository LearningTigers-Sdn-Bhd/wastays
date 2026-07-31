require 'rails_helper'

# Every card the board draws has to be reachable by the actions it offers. Two
# ways of getting that wrong have already shipped: a completed checkout that
# could not be dragged because dragging was gated on a URL it never has, and a
# checkout's room cleaning whose every action looked its id up in the wrong
# table. Both are pinned here, per lane, so a new lane cannot reopen either
# quietly.
RSpec.describe "board cards are reachable", type: :model do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Sena") }

  def board = HotelPortal::RequestsBoard.new(hotel, {})

  def card_in(lane)
    board.board_columns[lane].first
  end

  def draggable?(card, lane)
    presenter = HotelPortal::RequestsBoardPresenter.new(
      pages: board.pages, board_counts: board.board_counts, current_hotel: hotel,
      view_context: ApplicationController.new.view_context, date_window: board.date_window
    )
    presenter.card_draggable?(card, HotelPortal::Requests::Column.find(lane))
  end

  # The card names the table it is in, so a lookup made from it finds it.
  def reachable?(card)
    HotelPortal::Requests::Finder.new(
      hotel: hotel, kind: card.record_kind, request_id: card.request_id
    ).call.present?
  end

  describe "the checkout lane" do
    # A housekeeping row wearing a checkout badge. Its every action used to be
    # built from the badge, which sent a housekeeping id to check_out_requests.
    let!(:cleaning) do
      create(:housekeeping_request, booking: booking, status: 'pending',
             request_details: 'Checkout Room Cleaning', archived_at: nil)
    end

    it "shows the cleaning as a checkout but names it as housekeeping" do
      card = card_in(:checkout)

      expect(card.kind).to eq("checkout")
      expect(card.record_kind).to eq("housekeeping")
      expect(card.request_id).to eq(cleaning.id)
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
      expect(cleaning.reload.archived_at).to be_present
    end

    it "is draggable" do
      expect(draggable?(card_in(:checkout), :checkout)).to be(true)
    end

    it "builds its urls against the table it lives in" do
      expect(card_in(:checkout).update_url).to include("/requests/housekeeping/#{cleaning.id}")
    end
  end

  describe "a completed checkout" do
    let!(:checkout) do
      create(:check_out_request, booking: booking, status: 'completed', completed_at: Time.current)
    end

    # Completing a checkout has an endpoint of its own, so the card carries no
    # update_url -- which is what used to make it undraggable.
    it "is draggable even though it has no status url" do
      card = card_in(:completed)

      expect(card.update_url).to be_blank
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
