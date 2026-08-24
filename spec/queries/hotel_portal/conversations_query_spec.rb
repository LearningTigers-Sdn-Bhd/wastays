# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::ConversationsQuery do
  let(:hotel) { create(:hotel) }

  def thread(**attributes)
    create(:conversation, hotel: hotel, prospect: create(:prospect, hotel: hotel), **attributes)
  end

  describe "threads waiting on a person" do
    # Two ways a thread ends up needing somebody: staff took it, or the guest
    # asked for them. The tab and its count have to agree about both.
    it "counts the ones staff hold and the ones a guest asked for" do
      thread(mode: "human")
      thread(mode: "bot").request_human!
      thread(mode: "bot")

      expect(described_class.new(hotel: hotel).counts[:awaiting_staff]).to eq(2)
    end

    it "lists the same threads it counted" do
      held = thread(mode: "human")
      asked = thread(mode: "bot")
      asked.request_human!
      untouched = thread(mode: "bot")

      listed = described_class.new(hotel: hotel, params: { filter: "awaiting_staff" }).call

      expect(listed).to contain_exactly(held, asked)
      expect(listed).not_to include(untouched)
    end

    it "leaves a closed thread out however it was flagged" do
      asked = thread(mode: "bot")
      asked.request_human!
      asked.close!

      expect(described_class.new(hotel: hotel).counts[:awaiting_staff]).to eq(0)
    end
  end
end
