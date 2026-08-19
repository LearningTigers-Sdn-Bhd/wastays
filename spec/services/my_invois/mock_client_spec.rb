require "rails_helper"

RSpec.describe MyInvois::MockClient, type: :service do
  after { described_class.reset_overrides! }

  it "supports overriding submission response for rejection tests" do
    described_class.submit_documents_override = {
      "submissionUid" => "mock-sub",
      "acceptedDocuments" => [],
      "rejectedDocuments" => [
        {
          "error" => {
            "details" => [
              { "message" => "Rejected by test override" }
            ]
          }
        }
      ]
    }

    response = described_class.new.submit_documents([ { codeNumber: "INV-001" } ])

    expect(response.dig("rejectedDocuments", 0, "error", "details", 0, "message")).to eq("Rejected by test override")
  end
end
