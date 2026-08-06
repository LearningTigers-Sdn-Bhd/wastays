require "rails_helper"

RSpec.describe NightAudits::Reporting::AuditPacketPdfExport do
  it "backs the public PDF exporter" do
    audit = create(:night_audit)
    create(:night_audit_financial_summary, night_audit: audit)

    expect(described_class.new(night_audit: audit).generate).to start_with("%PDF")
  end
end
