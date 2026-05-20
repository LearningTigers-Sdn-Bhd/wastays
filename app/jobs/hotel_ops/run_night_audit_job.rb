# frozen_string_literal: true

module HotelOps
  class RunNightAuditJob < ApplicationJob
    queue_as :default

    def perform(night_audit_id, performed_by_user_id)
      night_audit = NightAudit.find(night_audit_id)
      performed_by_user = User.find_by(id: performed_by_user_id)

      HotelOps::RunNightAudit.new(
        hotel: night_audit.hotel,
        business_date: night_audit.business_date,
        performed_by_user: performed_by_user,
        trigger_mode: night_audit.trigger_mode,
        notes: night_audit.notes
      ).call
    end
  end
end
