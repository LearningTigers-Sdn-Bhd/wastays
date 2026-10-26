# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::DifferentPerson do
  def guest(name, document_type: "malaysian_nric", government_id: nil, passport_number: nil)
    build(:guest, name:, country: "Malaysia", document_type:, government_id:, passport_number:)
  end

  it "takes a different IC as a different person, whatever the name" do
    expect(described_class.call(guest("Ali Bin Abu", government_id: "900101-12-5555"), name: "Ali Bin Abu",
      document_type: "malaysian_nric", government_id: "900101125556")).to be(true)
  end

  it "takes the same IC as the same person, punctuation aside" do
    expect(described_class.call(guest("Rolleand Marinus", government_id: "900101-12-5555"), name: "Someone Else",
      document_type: "malaysian_nric", government_id: "900101125555")).to be(false)
  end

  it "does not weigh a passport number against a MyKad" do
    expect(described_class.call(guest("Existing Guest", government_id: "old-ic"), name: "Existing Guest",
      document_type: "passport", government_id: "new-passport")).to be(false)
  end

  {
    [ "Rolleand Marinus", "ROLLEANNY MARINUS" ] => false,
    [ "Le Tshun Siong", "LEE TSHUN SIONG" ] => false,
    [ "Kenneth Yapp Kim Ya", "Kenneth Yapp Kim Yaw" ] => false,
    [ "Chua Fu Chee @ Ann Chua", "CHUA FUI CHEE @ ANN CHUA" ] => false,
    [ "Alice", "Alice Tan" ] => false,
    [ "Ezza", "Ibrahim Bin Ayub" ] => true,
    [ "Hendry Lepizus Datu", "Ruben Bin Tinting" ] => true,
    [ "Jaime Bin Gampawi", "Md Julfize Bin Mairon" ] => true,
    [ "Siti Nurul Shatina Binti Abdul Raji", "Noormalah Binti Abdul Asli" ] => true,
    [ "Muhammad Ali", "Muhammad Amin" ] => true
  }.each do |(profile, typed), different|
    it "#{different ? 'separates' : 'keeps together'} #{profile} and #{typed} by name" do
      expect(described_class.call(guest(profile), name: typed)).to be(different)
    end
  end

  it "never calls a blank name a different person" do
    expect(described_class.call(guest("Ezza"), name: "")).to be(false)
  end
end
