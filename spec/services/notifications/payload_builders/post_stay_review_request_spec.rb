require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::PostStayReviewRequest do
  let(:booking) { create(:booking, status: "completed", checked_out_at: Time.zone.local(2026, 5, 8, 13, 0)) }

  it "builds the post-stay review payload" do
    payload = described_class.new(
      booking: booking,
      review_link: "https://g.page/r/example/review"
    ).call

    expect(payload[:notification_type]).to eq("post_stay_review_request")
    expect(payload[:review_link]).to eq("https://g.page/r/example/review")
    expect(payload[:trigger_event]).to eq("booking_completed")
    expect(payload[:confirmation_token]).to eq(booking.confirmation_token)
  end

  it "raises when review link is missing" do
    expect {
      described_class.new(booking: booking, review_link: "").call
    }.to raise_error(ArgumentError, "Review link is missing")
  end
end
