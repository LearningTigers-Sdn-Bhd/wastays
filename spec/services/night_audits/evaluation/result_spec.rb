require "rails_helper"

RSpec.describe NightAudits::Evaluation::Result do
  it "returns the compatibility hash without changing its values" do
    blocked_details = { "missing_folio" => [] }
    exceptions = { "due_out_detected" => [] }
    summary = { "arrivals_count" => 0 }

    result = described_class.new(
      blocked_details: blocked_details,
      exceptions: exceptions,
      summary: summary
    )

    expect(result.to_h).to eq(
      blocked_details: blocked_details,
      exceptions: exceptions,
      summary: summary
    )
  end
end
