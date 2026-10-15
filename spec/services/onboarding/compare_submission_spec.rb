# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::CompareSubmission do
  let(:hotel) { create(:hotel) }

  it "keeps the comparison stable when the date advances" do
    travel_to(Time.zone.local(2026, 9, 20, 12)) do
      snapshot = Onboarding::SubmissionSnapshot.call(hotel:)
      submission = create(:onboarding_submission, hotel:, snapshot: snapshot.data, configuration_digest: snapshot.digest)

      travel 3.days

      expect(described_class.call(hotel:, submission:)).to have_attributes(success?: true, unchanged: true)
      expect(Onboarding::SubmissionSnapshot.call(hotel:).digest).not_to eq(submission.configuration_digest)
      hotel.update!(name: "Changed property")
      expect(described_class.call(hotel:, submission:).unchanged).to be(false)
    end
  end

  it "rejects absent, malformed, and reversed coverage dates" do
    [ {}, { "start_date" => "invalid", "end_date" => "2026-09-30" },
      { "start_date" => "2026-09-30", "end_date" => "2026-09-29" } ].each do |coverage|
      submission = build(:onboarding_submission, hotel:, snapshot: { "rates" => { "coverage" => coverage } })
      result = described_class.call(hotel:, submission:)
      expect(result).not_to be_success
      expect(result.error).to include("missing or invalid availability dates")
    end
  end
end
