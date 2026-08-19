# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoiceSetting do
  describe "#covers?" do
    let(:hotel) { create(:hotel) }

    it "stamps effective_from the first time e-invoicing is switched on" do
      setting = create(:e_invoice_setting, hotel: hotel, enabled: true)

      expect(setting.effective_from).to be_present
    end

    it "does not stamp effective_from while the feature is off" do
      setting = create(:e_invoice_setting, hotel: hotel, enabled: false)

      expect(setting.effective_from).to be_nil
    end

    it "keeps the original date when the setting is edited again" do
      setting = create(:e_invoice_setting, hotel: hotel, enabled: true)
      original = setting.effective_from

      setting.update!(supplier_city: "Sandakan")

      expect(setting.reload.effective_from).to be_within(1.second).of(original)
    end

    # Switching the feature on must not retroactively file historical stays.
    it "excludes a payment concluded before the feature was switched on" do
      setting = create(:e_invoice_setting, hotel: hotel, enabled: true)

      expect(setting.covers?(setting.effective_from - 1.day)).to be(false)
    end

    it "includes a payment concluded after the feature was switched on" do
      setting = create(:e_invoice_setting, hotel: hotel, enabled: true)

      expect(setting.covers?(setting.effective_from + 1.hour)).to be(true)
    end

    it "covers nothing while disabled, even for a recent payment" do
      setting = create(:e_invoice_setting, hotel: hotel, enabled: false)

      expect(setting.covers?(Time.current)).to be(false)
    end

    it "is false when the payment date is unknown" do
      setting = create(:e_invoice_setting, hotel: hotel, enabled: true)

      expect(setting.covers?(nil)).to be(false)
    end
  end
end
