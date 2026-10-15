# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::AgencyFromGuest do
  def row(guest, agency: nil, source: nil, note: nil)
    Ezee::ReservationRow.new(
      guest_name: guest, agency_name: agency, source: source || (agency ? "Travel Agent" : "Unlabeled"),
      internal_note: note, layout: :reservation_csv
    )
  end

  def run(*rows) = described_class.call(rows)

  let(:known) { row("Someone", agency: "PERFECT VACATION SDN.BHD") }

  it "reads 'AGENCY (CONTACT)' in the guest field as the agency, and keeps the contact" do
    perfect = row("PERFECT HOLIDAY(SABRINA)")

    run(known, perfect)

    expect(perfect).to have_attributes(source: "Travel Agent", source_key: "travel_agent")
    expect(perfect.internal_note).to include("Contact: SABRINA")
  end

  it "counts Holiday, Holidays and Vacation as the same word, so Perfect Holidays is Perfect Vacation Sdn. Bhd." do
    rows = [ row("PERFECT HOLIDAY ( RACHEL KA )"), row("PERFECT HOLIDAYS ( SABRINA CHIN )"), row("PERFECT VACATION  ( RACHEL KA )") ]

    run(known, *rows)

    expect(rows.map(&:agency_name)).to all(eq("PERFECT VACATION SDN.BHD"))
  end

  it "gives an agency the file never names in Business Source its own account, as typed" do
    dreamy = row("DREAMY ISLAND ( MOON )")

    run(known, dreamy)

    expect(dreamy.agency_name).to eq("DREAMY ISLAND")
    expect(dreamy.internal_note).to include("Contact: MOON")
  end

  it "matches a shortened agency name to the full one the file spells out" do
    full = row("Someone", agency: "GOOD EARTH TRAVEL AND TOUR SDN. BHD.")
    short = row("GOOD EARTH TRAVEL")
    inside = row("YOUXIEREN(HUANG LEI)")
    youxieren = row("Other", agency: "GUANGZHOU YOUXIEREN TRIP SERVICE CO.LTD")

    run(full, short, inside, youxieren)

    expect(short.agency_name).to eq("GOOD EARTH TRAVEL AND TOUR SDN. BHD.")
    expect(inside.agency_name).to eq("GUANGZHOU YOUXIEREN TRIP SERVICE CO.LTD")
  end

  it "reads a person who is also an agency elsewhere in the file as that agency" do
    agent = row("Someone", agency: "ZENG JIAMING")
    same = row("ZENG JIAMING")

    run(agent, same)

    expect(same.agency_name).to eq("ZENG JIAMING")
  end

  it "does not guess when two known agencies fit equally" do
    first = row("A", agency: "GUANGZHOU ASIAN WORLD TRAVEL")
    second = row("B", agency: "GUANGZHOU ASIAN GLOBAL TOURS")
    ambiguous = row("GUANGZHOU ASIAN")

    run(first, second, ambiguous)

    expect(ambiguous.agency_name).to be_nil
  end

  it "leaves an ordinary guest alone" do
    person = row("KUMARAN RAJAGOPAL")

    run(known, person)

    expect(person).to have_attributes(agency_name: nil, source: "Unlabeled", internal_note: nil)
  end

  it "does not touch a row that already has a Business Source" do
    labelled = row("PERFECT HOLIDAY(SABRINA)", agency: "SOMEONE ELSE SDN BHD")

    run(known, labelled)

    expect(labelled.agency_name).to eq("SOMEONE ELSE SDN BHD")
  end

  it "replaces the 'unlabeled agent booking' note but keeps the rest" do
    perfect = row("PERFECT HOLIDAY(SABRINA)", note: "#{Ezee::ReservationCsvParser::UNLABELED_NOTE} Title in eZee: Mr.")

    run(known, perfect)

    expect(perfect.internal_note).not_to include("Unlabeled agent booking")
    expect(perfect.internal_note).to include("Title in eZee: Mr.")
  end
end
