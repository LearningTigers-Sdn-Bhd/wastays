require "rails_helper"

RSpec.describe Admin::SyncHotelSalesperson, type: :service do
  let(:account) { create(:account) }
  let(:current_user) { create(:user, :superadmin, account: account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:salesperson_name) { "Target Salesperson" }
  let(:salesperson_email) { "sales@example.com" }

  subject do
    described_class.new(
      hotel: hotel,
      name: salesperson_name,
      email: salesperson_email,
      current_user: current_user
    )
  end

  describe "#call" do
    context "when salesperson does not exist" do
      it "creates a new salesperson and associates them with the hotel" do
        expect {
          subject.call
        }.to change(User.where(role: "salesperson"), :count).by(1)

        new_salesperson = User.find_by(name: salesperson_name)
        expect(new_salesperson.email).to eq(salesperson_email)
        expect(hotel.reload.salesperson).to eq(new_salesperson)
      end
    end

    context "when salesperson already exists in the account by name" do
      before { current_user }

      let!(:existing_salesperson) do
        create(:user, :salesperson, account: account, name: salesperson_name, email: "old@example.com")
      end

      it "updates the existing salesperson and associates them with the hotel" do
        expect {
          subject.call
        }.not_to change(User, :count)

        existing_salesperson.reload
        expect(existing_salesperson.email).to eq(salesperson_email)
        expect(hotel.reload.salesperson).to eq(existing_salesperson)
      end
    end

    context "when hotel already has a salesperson" do
      let(:old_salesperson) { create(:user, :salesperson, account: account, name: "Old Name") }
      before { hotel.update!(salesperson: old_salesperson) }

      it "updates the current salesperson's contact info" do
        subject.call
        old_salesperson.reload
        expect(old_salesperson.name).to eq(salesperson_name)
        expect(old_salesperson.email).to eq(salesperson_email)
      end
    end
  end
end
