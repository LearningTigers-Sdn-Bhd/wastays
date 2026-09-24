require "rails_helper"

RSpec.describe Guest::StatusBadges do
  it "gives every booking status a guest word, a tone, and an icon" do
    Booking::STATUSES.each do |status|
      badge = described_class.booking(status)

      expect(badge.icon).not_to eq("circle-question-mark"), "#{status} has no guest badge"
    end
  end

  it "never shows a guest an internal status" do
    expect(described_class.booking("due_out_detected").label).to eq("Checked in")
    expect(described_class.booking("checkout_required").label).to eq("Checked in")
    expect(described_class.booking("no_show_detected").label).to eq("Confirmed")
    expect(described_class.booking("overbooked").label).to eq("Confirmed")
    expect(described_class.booking("voided").label).to eq("Cancelled")
  end

  it "maps refund statuses" do
    expect(described_class.refund("completed")).to have_attributes(label: "Refunded", tone: :success)
    expect(described_class.refund("rejected")).to have_attributes(label: "Not approved", tone: :destructive)
  end

  it "falls back to a muted badge for a status it does not know" do
    expect(described_class.refund("on_hold")).to have_attributes(label: "On hold", tone: :muted, icon: "circle-question-mark")
  end
end
