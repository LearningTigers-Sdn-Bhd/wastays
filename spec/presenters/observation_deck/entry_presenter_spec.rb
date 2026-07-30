# frozen_string_literal: true

require "rails_helper"

RSpec.describe ObservationDeck::EntryPresenter do
  describe "identity" do
    it "loads tagged user once outside ERB" do
      user = create(:user, name: "Deck User", email: "deck@example.com")
      entry = build(:observation_entry, tags: [ "user:#{user.id}", "booking:44", "incident" ])

      presenter = described_class.new(entry)

      expect(presenter.identity).to eq("Admin: Deck User")
      expect(presenter.context_rows).to include([ "Booking", "#44" ])
      expect(presenter.visible_tags).to eq([ "incident" ])
    end
  end

  describe "presentation" do
    it "builds safe labels and payload values for SQL entries" do
      entry = build(:observation_entry, entry_type: "sql", path: "Order Load", duration: 1200, payload: { "sql" => "SELECT * FROM orders" })

      presenter = described_class.new(entry)

      expect(presenter.title).to eq("Database: Order Load")
      expect(presenter.slow?).to be(true)
      expect(presenter.payload_kind).to eq(:sql)
      expect(presenter.payload_text).to eq("SELECT * FROM orders")
    end

    it "removes remote resources from captured email HTML" do
      entry = build(
        :observation_entry,
        entry_type: "mail",
        payload: { "html_body" => '<img src="https://tracker.example/pixel"><link href="https://tracker.example/mail.css"><div style="background: url(https://tracker.example/image)">Hello</div>' }
      )

      preview = described_class.new(entry).mail_html

      expect(preview).to include("Hello")
      expect(preview).not_to include("https://tracker.example")
    end

    it "escapes quotes so the sanitized HTML can't break out of the srcdoc attribute" do
      entry = build(
        :observation_entry,
        entry_type: "mail",
        payload: { "html_body" => '<a href="https://example.com" title="Say &quot;hi&quot;">Click</a>' }
      )

      srcdoc = described_class.new(entry).mail_srcdoc

      expect(srcdoc).to be_html_safe
      expect(srcdoc).not_to include('"')
      expect(srcdoc).to include("&quot;https://example.com&quot;")
    end
  end
end
