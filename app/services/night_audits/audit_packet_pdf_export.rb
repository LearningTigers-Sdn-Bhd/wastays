# frozen_string_literal: true

module NightAudits
  class AuditPacketPdfExport
    def initialize(night_audit:, prepared_by:)
      @implementation = Reporting::AuditPacketPdfExport.new(night_audit: night_audit, prepared_by: prepared_by)
    end

    delegate :generate, to: :@implementation
  end
end
