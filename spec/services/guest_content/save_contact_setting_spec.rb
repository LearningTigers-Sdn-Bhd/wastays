# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestContent::SaveContactSetting do
  let(:hotel) { create(:hotel) }

  def save(params)
    described_class.new(hotel, ActionController::Parameters.new(params).permit!)
  end

  it "creates the row on the first save" do
    service = save(front_desk_phone: "+60 3 1234 5678", escalation_attempts: 2)

    expect { service.call }.to change { hotel.reload.guest_contact }.from(nil)
    expect(hotel.guest_contact.front_desk_phone).to eq("+60 3 1234 5678")
  end

  it "updates the row that is already there" do
    create(:hotel_guest_contact, hotel: hotel, front_desk_phone: "old")

    expect { save(front_desk_phone: "new").call }
      .to change { hotel.reload.guest_contact.front_desk_phone }.from("old").to("new")
  end

  it "drops the blank the checkbox group sends and any unknown trigger" do
    save(escalation_triggers: [ "", "complaint", "not_a_trigger" ]).call

    expect(hotel.reload.guest_contact.escalation_triggers).to eq([ "complaint" ])
  end

  it "clears the hours when the desk goes back to 24 hours" do
    create(:hotel_guest_contact, :with_hours, hotel: hotel)

    save(front_desk_open_24h: "1").call

    contact = hotel.reload.guest_contact
    expect(contact.front_desk_opens_at).to be_nil
    expect(contact.front_desk_closes_at).to be_nil
  end

  it "returns false and keeps the errors when the hours are missing" do
    service = save(front_desk_open_24h: "0", front_desk_opens_at: "", front_desk_closes_at: "")

    expect(service.call).to be(false)
    expect(service.contact.errors.attribute_names).to include(:front_desk_opens_at)
  end
end
