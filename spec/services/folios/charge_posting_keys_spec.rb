# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ChargePostingKeys do
  let(:booking) { build_stubbed(:booking, id: 123) }
  let(:date) { Date.new(2026, 6, 10) }

  it "preserves existing nightly charge key format" do
    expect(described_class.nightly_charge_key(booking: booking, date: date, charge_kind: "tax", identity: "sst:0"))
      .to eq("123:2026-06-10:tax:sst:0")
  end

  it "preserves existing catch-up charge key format" do
    expect(described_class.catch_up_charge_key(booking: booking, date: date, charge_kind: "accommodation", identity: 456))
      .to eq("catch_up:123:2026-06-10:accommodation:456")
  end

  it "preserves existing early checkout charge key format" do
    expect(described_class.early_checkout_charge_key(booking: booking, date: date, charge_kind: "tax", identity: "sst:0"))
      .to eq("early_checkout:123:2026-06-10:tax:sst:0")
  end
end
