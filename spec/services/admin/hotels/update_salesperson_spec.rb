require "rails_helper"

RSpec.describe Admin::Hotels::UpdateSalesperson, type: :service do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel) }

  def update_salesperson(operation:, salesperson_id: nil, name: nil, email: nil)
    described_class.call(hotel:, account:, operation:, salesperson_id:, name:, email:)
  end

  it "assigns an existing salesperson and can clear the assignment" do
    person = create(:user, :salesperson, account:)

    expect(update_salesperson(operation: "assign", salesperson_id: person.id)).to be(true)
    expect(hotel.reload.salesperson).to eq(person)

    update_salesperson(operation: "assign")
    expect(hotel.reload.salesperson).to be_nil
  end

  it "creates and assigns a salesperson" do
    expect {
      update_salesperson(operation: "create", name: "New seller", email: "seller@example.com")
    }.to change { account.users.where(role: "salesperson").count }.by(1)

    expect(hotel.reload.salesperson).to have_attributes(name: "New seller", email: "seller@example.com")
  end

  it "updates the assigned salesperson contact wherever they are assigned" do
    person = create(:user, :salesperson, account:)
    hotel.update!(salesperson: person)
    other_hotel = create(:hotel, salesperson: person)

    update_salesperson(operation: "update_contact", name: "Updated seller", email: "updated@example.com")

    expect(other_hotel.reload.salesperson).to have_attributes(name: "Updated seller", email: "updated@example.com")
  end

  it "rejects a salesperson outside the selected account" do
    person = create(:user, :salesperson)

    expect {
      update_salesperson(operation: "assign", salesperson_id: person.id)
    }.to raise_error(ActiveRecord::RecordNotFound)
    expect(hotel.reload.salesperson).to be_nil
  end

  it "rejects invalid contact details without changing the salesperson" do
    person = create(:user, :salesperson, account:, email: "original@example.com")
    hotel.update!(salesperson: person)

    expect {
      update_salesperson(operation: "update_contact", name: "Updated seller", email: "invalid")
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(person.reload.email).to eq("original@example.com")
  end
end
