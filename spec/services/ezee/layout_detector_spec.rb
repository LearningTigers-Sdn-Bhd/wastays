# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::LayoutDetector do
  let(:csv) { Rails.root.join("spec/fixtures/files/ezee_reservation_csv_sample.csv") }
  let(:xls) { Rails.root.join("spec/fixtures/files/ezee_reservation_list_sample.xls") }

  def detect(path, filename) = described_class.call(path: path, filename: filename)

  it "recognises the reservation CSV by its header row" do
    expect(detect(csv, "export.csv")).to eq(:reservation_csv)
  end

  it "treats a spreadsheet as the Reservation List" do
    expect(detect(xls, "Reservation List.xls")).to eq(:reservation_list)
    expect(detect(xls, "Reservation List.xlsx")).to eq(:reservation_list)
  end

  it "returns nil for a CSV that is not the reservation CSV" do
    other = Tempfile.new([ "other", ".csv" ])
    other.write("name,email\nA,a@example.com\n")
    other.flush

    expect(detect(other.path, "other.csv")).to be_nil
  end

  it "returns nil for a file type it does not read" do
    expect(detect(csv, "notes.pdf")).to be_nil
  end
end
