# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "hotel_ops rake tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  describe "hotel_ops:clean_state" do
    let(:task) { Rake::Task["hotel_ops:clean_state"] }
    let(:hotel) { create(:hotel, name: "Aurora Crown Resort Langkawi") }
    let(:other_hotel) { create(:hotel, name: "Other Hotel") }

    before do
      task.reenable
      allow_any_instance_of(Object).to receive(:sleep)
    end

    it "deletes night audit history only for the selected hotel" do
      create(:room_type, hotel: hotel)
      create(:room_type, hotel: other_hotel)

      night_audit = create(:night_audit, hotel: hotel)
      other_night_audit = create(:night_audit, hotel: other_hotel)

      NightAuditLog.create!(
        night_audit: night_audit,
        hotel: hotel,
        action_type: "completed",
        message: "Completed"
      )
      create(:night_audit_financial_summary, night_audit: night_audit)

      other_log = NightAuditLog.create!(
        night_audit: other_night_audit,
        hotel: other_hotel,
        action_type: "completed",
        message: "Completed"
      )
      other_summary = create(:night_audit_financial_summary, night_audit: other_night_audit)

      expect do
        task.invoke(hotel.name)
      end.to change { hotel.night_audits.count }.from(1).to(0)

      expect(NightAudit.exists?(night_audit.id)).to be(false)
      expect(NightAuditLog.where(night_audit_id: night_audit.id)).to be_empty
      expect(NightAuditFinancialSummary.where(night_audit_id: night_audit.id)).to be_empty

      expect(NightAudit.exists?(other_night_audit.id)).to be(true)
      expect(NightAuditLog.exists?(other_log.id)).to be(true)
      expect(NightAuditFinancialSummary.exists?(other_summary.id)).to be(true)
    end
  end
end
