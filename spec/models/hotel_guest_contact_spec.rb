# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelGuestContact do
  describe "validations" do
    it "does not need hours while the desk is open 24 hours" do
      expect(build(:hotel_guest_contact, front_desk_open_24h: true)).to be_valid
    end

    it "needs both hours once the desk closes" do
      contact = build(:hotel_guest_contact, front_desk_open_24h: false,
                      front_desk_opens_at: nil, front_desk_closes_at: nil)

      expect(contact).not_to be_valid
      expect(contact.errors.attribute_names).to include(:front_desk_opens_at, :front_desk_closes_at)
    end

    it "keeps the escalation attempts inside the allowed range" do
      expect(build(:hotel_guest_contact, escalation_attempts: 6)).not_to be_valid
      expect(build(:hotel_guest_contact, escalation_attempts: 3)).to be_valid
    end

    it "allows only one row per hotel" do
      hotel = create(:hotel)
      create(:hotel_guest_contact, hotel: hotel)

      expect(build(:hotel_guest_contact, hotel: hotel)).not_to be_valid
    end
  end

  describe "clock attributes" do
    it "reads back the clock time a form string wrote" do
      contact = create(:hotel_guest_contact, :with_hours)

      expect(contact.reload.front_desk_opens_at.strftime("%H:%M")).to eq("07:00")
      expect(contact.reload.front_desk_closes_at.strftime("%H:%M")).to eq("23:00")
    end
  end

  describe "#escalates_on?" do
    it "answers for a stored trigger" do
      contact = build(:hotel_guest_contact, escalation_triggers: %w[complaint])

      expect(contact.escalates_on?("complaint")).to be(true)
      expect(contact.escalates_on?("payment_question")).to be(false)
    end
  end

  describe "#emergency_present?" do
    it "is false only when every emergency field is empty" do
      expect(build(:hotel_guest_contact).emergency_present?).to be(true)
      expect(build(:hotel_guest_contact, emergency_phone: nil, emergency_services_number: nil,
                   emergency_instructions: nil).emergency_present?).to be(false)
    end
  end
end
