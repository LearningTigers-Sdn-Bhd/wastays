require "rails_helper"

RSpec.describe Admin::CompleteOnboarding, type: :service do
  let(:hotel) { create(:hotel, status: "pending_review") }
  let(:start_date) { 1.week.ago.beginning_of_day }
  let(:end_date) { Time.zone.now.end_of_day }

  subject { described_class.new(hotel: hotel, start_date: start_date, end_date: end_date) }

  describe "#call" do
    it "updates hotel status to approved" do
      expect {
        subject.call
      }.to change { hotel.reload.status }.from("pending_review").to("approved")
    end

    it "creates a final onboarding session record" do
      expect {
        subject.call
      }.to change(OnboardingSession, :count).by(1)

      final_session = hotel.onboarding_sessions.find_by(notes: "FINAL_ONBOARDING_COMPLETION")
      expect(final_session.status).to eq("completed")
      expect(final_session.trainer_name).to eq("Onboarding System")
      expect(final_session.scheduled_at).to be_within(1.second).of(start_date)
      expect(final_session.completed_at).to be_within(1.second).of(end_date)
    end

    context "when hotel is already live" do
      let(:hotel) { create(:hotel, status: "live") }

      it "does not change the status" do
        expect {
          subject.call
        }.not_to change { hotel.reload.status }
      end
    end
  end
end
