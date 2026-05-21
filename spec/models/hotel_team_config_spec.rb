require "rails_helper"

RSpec.describe HotelTeamConfig, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:hotel) }
  end

  describe "validations" do
    subject { build(:hotel_team_config) }
    
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:template_type) }
    it { is_expected.to validate_numericality_of(:frequency).only_integer.is_greater_than(0).allow_nil }
  end

  describe "encryption" do
    let(:hotel) { create(:hotel) }
    let(:emails) { "admin@hotel.com, finance@hotel.com" }
    let(:config) { create(:hotel_team_config, hotel: hotel, emails: emails) }

    it "encrypts the emails field" do
      expect(config.emails_before_type_cast).not_to include("admin@hotel.com")
      expect(config.emails).to eq(emails)
    end
  end

  describe "callbacks" do
    it "sets default frequency on create" do
      config = HotelTeamConfig.create!(hotel: create(:hotel), name: "Test", template_type: "test")
      expect(config.frequency).to eq(86400)
    end
  end
end
