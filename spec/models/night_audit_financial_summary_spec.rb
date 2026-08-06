require "rails_helper"

RSpec.describe NightAuditFinancialSummary, type: :model do
  describe "associations" do
    it { should belong_to(:night_audit) }
  end

  describe "validations" do
    it "requires numeric financial totals" do
      summary = build(:night_audit_financial_summary, room_revenue: "invalid")

      expect(summary).not_to be_valid
      expect(summary.errors[:room_revenue]).to include("is not a number")
    end

    it "is valid with zero-value totals" do
      summary = build(:night_audit_financial_summary)

      expect(summary).to be_valid
    end
  end

  describe "#log_change" do
    it "appends audit details to the changelog" do
      user = create(:user, name: "Night Auditor")
      summary = build(:night_audit_financial_summary, changelog: [])
      timestamp = Time.zone.local(2026, 5, 18, 3, 0, 0)

      with_frozen_time(timestamp) do
        summary.log_change(
          user: user,
          previous_values: { "room_revenue" => "100.00" },
          new_values: { "room_revenue" => "120.00" },
          reason: "Corrected late posting"
        )
      end

      expect(summary.changelog.size).to eq(1)
      expect(summary.changelog.last).to include(
        "timestamp" => timestamp.iso8601(3),
        "user_id" => user.id,
        "user_name" => "Night Auditor",
        "reason" => "Corrected late posting",
        "previous_values" => { "room_revenue" => "100.00" },
        "new_values" => { "room_revenue" => "120.00" }
      )
    end

    it "preserves existing changelog entries" do
      existing_entry = { "reason" => "Initial correction" }
      summary = build(:night_audit_financial_summary, changelog: [ existing_entry ])

      summary.log_change(user: nil, previous_values: {}, new_values: {}, reason: "Second correction")

      expect(summary.changelog.first).to eq(existing_entry)
      expect(summary.changelog.last["reason"]).to eq("Second correction")
      expect(summary.changelog.last["user_id"]).to be_nil
    end
  end
end
