require "rails_helper"

RSpec.describe FolioForecastedCharge, type: :model do
  describe "associations" do
    it { should belong_to(:booking_folio) }
    it { should belong_to(:actualizing_transaction).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:stay_date) }
    it { should validate_presence_of(:charge_kind) }
    it { should validate_presence_of(:identity) }
    it { should validate_presence_of(:amount) }
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[forecast actualized superseded]) }
    it { should validate_inclusion_of(:charge_kind).in_array(%w[accommodation tax]) }
  end

  describe "scopes" do
    let(:folio) { create(:booking_folio) }
    let!(:forecast_record) { create(:folio_forecasted_charge, booking_folio: folio, status: "forecast") }
    let!(:actualized_record) { create(:folio_forecasted_charge, booking_folio: folio, status: "actualized", stay_date: Date.tomorrow) }
    let!(:superseded_record) { create(:folio_forecasted_charge, booking_folio: folio, status: "superseded", stay_date: Date.tomorrow + 1) }

    it "returns forecast records" do
      expect(described_class.forecast).to contain_exactly(forecast_record)
    end

    it "returns actualized records" do
      expect(described_class.actualized).to contain_exactly(actualized_record)
    end

    it "returns superseded records" do
      expect(described_class.superseded).to contain_exactly(superseded_record)
    end

    it "filters by date" do
      expect(described_class.for_date(Date.current)).to contain_exactly(forecast_record)
    end
  end

  describe "#actualize!" do
    let(:folio) { create(:booking_folio) }
    let(:forecast) { create(:folio_forecasted_charge, booking_folio: folio, status: "forecast") }
    let(:transaction) { create(:folio_transaction, booking_folio: folio) }

    it "sets status to actualized and links the transaction" do
      forecast.actualize!(transaction: transaction)

      expect(forecast.reload.status).to eq("actualized")
      expect(forecast.actualizing_transaction).to eq(transaction)
    end
  end

  describe "#supersede!" do
    let(:folio) { create(:booking_folio) }
    let(:forecast) { create(:folio_forecasted_charge, booking_folio: folio, status: "forecast") }

    it "sets status to superseded" do
      forecast.supersede!

      expect(forecast.reload.status).to eq("superseded")
    end
  end

  describe ".supersede_all!" do
    let(:folio) { create(:booking_folio) }
    let!(:forecast1) { create(:folio_forecasted_charge, booking_folio: folio, status: "forecast") }
    let!(:forecast2) { create(:folio_forecasted_charge, booking_folio: folio, status: "forecast", stay_date: Date.tomorrow) }
    let!(:actualized_record) { create(:folio_forecasted_charge, booking_folio: folio, status: "actualized", stay_date: Date.tomorrow + 1) }

    it "supersedes all forecast records but leaves actualized records unchanged" do
      described_class.supersede_all!

      expect(forecast1.reload.status).to eq("superseded")
      expect(forecast2.reload.status).to eq("superseded")
      expect(actualized_record.reload.status).to eq("actualized")
    end
  end
end
