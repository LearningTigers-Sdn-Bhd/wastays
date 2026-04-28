require "rails_helper"

RSpec.describe Admin::Salespersons::CreateService, type: :service do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:params) { { name: "Mira Tan", email: "mira@example.com" } }
  let(:hotel_ids) { [ hotel.id ] }

  subject { described_class.new(account: account, params: params, hotel_ids: hotel_ids) }

  describe "#call" do
    it "creates a salesperson and assigns hotels" do
      result = nil
      expect {
        result = subject.call
      }.to change(User.where(role: "salesperson"), :count).by(1)

      expect(result.success?).to be true
      expect(result.salesperson.name).to eq("Mira Tan")
      expect(hotel.reload.salesperson).to eq(result.salesperson)
    end

    context "with empty email" do
      let(:params) { { name: "Mira Tan", email: "" } }

      it "generates a default email" do
        result = subject.call
        expect(result.success?).to be true
        expect(result.salesperson.email).to include("@wastays.local")
      end
    end
  end
end
