require "rails_helper"

RSpec.describe HotelPortal::TaxesFeesPresenter do
  let(:hotel) { create(:hotel, sst_enabled: true, tourism_tax_enabled: false, tourism_tax_amount: 12.5) }
  let(:user) { create(:user, account: hotel.account) }

  describe "#active_tab" do
    it "accepts known tabs and falls back to registry" do
      expect(described_class.new(hotel: hotel, current_user: user, active_tab: "malaysia_reference").active_tab).to eq("malaysia_reference")
      expect(described_class.new(hotel: hotel, current_user: user, active_tab: "unknown").active_tab).to eq("registry")
    end
  end

  describe "#registry_rows" do
    it "normalizes system taxes, taxes, fees, and legacy records" do
      HotelTax.create!(hotel: hotel, name: "Zulu Fee", code: "ZF", charge_type: "charge", rate_type: "percentage", amount: 10.0, foreign_guests_only: true)
      HotelTax.create!(hotel: hotel, name: "Alpha Tax", code: "AT", charge_type: "tax", rate_type: "flat", amount: 2.0)
      HotelTax.create!(hotel: hotel, name: "Legacy Other", code: "LO", charge_type: "others", rate_type: "flat", amount: 3.0)

      rows = described_class.new(hotel: hotel, current_user: user).registry_rows

      expect(rows.map(&:name)).to eq([ "Service Tax (SST)", "Tourism Tax (TTx)", "Alpha Tax", "Legacy Other", "Zulu Fee" ])
      expect(rows.first).to have_attributes(system: true, code: "TAX_SST", applies_to: "All guests", charge_rule: "Percentage", charge_amount: "8.00%", enabled: true)
      expect(rows.second).to have_attributes(system: true, code: "TAX_TTX", applies_to: "Foreign guests only", charge_rule: "Fixed", charge_amount: "RM 12.50 / room / night", enabled: false)
      expect(rows.third).to have_attributes(system: false, type_label: "Tax", code: "TAX_AT", charge_amount: "RM 2.00")
      expect(rows.fourth).to have_attributes(type_label: "Fee", code: "LO")
      expect(rows.fifth).to have_attributes(type_label: "Fee", code: "ZF", applies_to: "Foreign guests only", charge_amount: "10.00%")
    end
  end
end
