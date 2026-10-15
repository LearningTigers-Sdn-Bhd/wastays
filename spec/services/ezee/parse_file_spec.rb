# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::ParseFile do
  let(:csv) { Rails.root.join("spec/fixtures/files/ezee_reservation_csv_sample.csv") }
  let(:xls) { Rails.root.join("spec/fixtures/files/ezee_reservation_list_sample.xls") }

  def parse(path, filename, **options) = described_class.call(path: path, filename: filename, **options)

  it "reads the reservation CSV with the CSV parser" do
    result = parse(csv, "export.csv")

    expect(result).to be_success
    expect(result.layout).to eq(:reservation_csv)
    expect(result.rows).to all(have_attributes(layout: :reservation_csv))
  end

  it "reads a Reservation List spreadsheet with the Reservation List parser" do
    result = parse(xls, "Reservation List.xls")

    expect(result).to be_success
    expect(result.layout).to eq(:reservation_list)
  end

  it "refuses a file it does not recognise, saying what it expects, rather than guessing" do
    other = Tempfile.new([ "other", ".csv" ])
    other.write("name,email\nA,a@example.com\n")
    other.flush

    result = parse(other.path, "other.csv")

    expect(result).not_to be_success
    expect(result.error).to include("not a recognised eZee report", "Business Source")
  end

  it "refuses a file type it does not read" do
    expect(parse(csv, "notes.pdf")).not_to be_success
  end

  it "reads a file as the layout the operator named, over what it looks like" do
    result = parse(csv, "export.csv", layout: "reservation_list")

    expect(result.layout).to eq(:reservation_list)
    expect(result).not_to be_success
  end

  it "refuses a layout it does not know (the controller only passes the ones it offers)" do
    result = parse(csv, "export.csv", layout: "nonsense")

    expect(result).not_to be_success
    expect(result.error).to include("not a recognised eZee report")
  end

  it "labels every layout it can read" do
    expect(described_class::LABELS.keys).to match_array(described_class::PARSERS.keys)
  end
end
