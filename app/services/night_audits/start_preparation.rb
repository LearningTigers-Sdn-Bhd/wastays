# frozen_string_literal: true

module NightAudits
  class StartPreparation
    def self.call(hotel:, business_date:, trigger_mode: "manual")
      preview = NightAudits::Prepare.call(hotel: hotel, business_date: business_date, trigger_mode: trigger_mode)
      audit = preview.night_audit || hotel.night_audits.build(business_date: business_date)
      return preview if audit.running? || audit.completed? || audit.blocked? || audit.failed?

      audit.assign_attributes(
        status: "preparing",
        trigger_mode: trigger_mode,
        started_at: nil,
        completed_at: nil,
        performed_by_user: nil,
        blocked_details: preview.evaluation[:blocked_details],
        exceptions: preview.evaluation[:exceptions],
        summary: audit.summary.to_h.merge(preview.evaluation[:summary]),
        force_closed: false
      )
      audit.save!
      NightAudits::Prepare::Result.new(night_audit: audit, evaluation: preview.evaluation, ready: preview.ready)
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end
end
