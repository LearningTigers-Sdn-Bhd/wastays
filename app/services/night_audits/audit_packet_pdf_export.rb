# frozen_string_literal: true

module NightAudits
  class AuditPacketPdfExport
    def initialize(night_audit:)
      @implementation = Reporting::AuditPacketPdfExport.new(night_audit: night_audit)
    end

    delegate :generate, to: :@implementation
  end
end
