# frozen_string_literal: true

require "rails_helper"

# The commercial phase: what a property sells beyond the room, what reduces
# those charges, how guests pay, and which companies are billed directly.
RSpec.describe "Onboarding commercial setup" do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }

  def resolve_through!(last_key)
    Onboarding::InitializeProgress.new(hotel: hotel).call
    keys = Onboarding::SectionCatalog.keys
    keys[0..keys.index(last_key)].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  def seed_transaction_codes!
    Financials::EnsureDefaultTransactionCodes.call(hotel)
  end

  describe Onboarding::SaveExtraCharges do
    before do
      seed_transaction_codes!
      resolve_through!("rates_availability")
    end

    def charge_entry(overrides = {})
      {
        "client_key" => "draft-1",
        "name" => "Airport transfer",
        "code" => "TRANSFER",
        "category" => "other",
        "pricing_type" => "fixed",
        "rate_value" => "80",
        "charging_unit" => "per_item",
        "allow_amount_override" => "true",
        "active" => "true",
        "tax_rule_keys" => []
      }.merge(overrides)
    end

    def save(entries:, complete: false)
      described_class.call(hotel: hotel, actor: actor, entries: entries, complete: complete)
    end

    it "creates a real extra charge and resolves the section without a placeholder" do
      result = save(entries: { "draft-1" => charge_entry }, complete: true)

      expect(result.success?).to be(true)
      charge = hotel.hotel_extra_charges.sole
      expect(charge).to have_attributes(
        name: "Airport transfer", code: "TRANSFER", pricing_type: "fixed",
        rate_value: 80.to_d, charging_unit: "per_item"
      )
      expect(result.section).to have_attributes(state: "complete")
      expect(result.section.decision_metadata).not_to have_key("placeholder")
    end

    # The page offers the seeded revenue codes as unsaved rows. Saving one has to
    # attach to that code rather than mint a second code with the same value.
    it "adopts a seeded revenue code instead of creating a duplicate code" do
      code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")

      result = save(entries: {
        "suggested" => charge_entry(
          "transaction_code_id" => code.id.to_s, "name" => "Food & Beverage",
          "code" => "FNB", "category" => "fb", "pricing_type" => "manual", "rate_value" => ""
        )
      }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_extra_charges.sole.transaction_code_id).to eq(code.id)
      expect(hotel.transaction_codes.where(code: "FNB").count).to eq(1)
    end

    it "attaches the selected taxes to the charge" do
      tax = hotel.hotel_taxes.create!(name: "Heritage levy", charge_type: "tax", rate_type: "percentage", amount: 2, enabled: true)

      result = save(entries: {
        "draft-1" => charge_entry("tax_rule_keys" => [ "primary:sst_tax", "hotel_tax:#{tax.id}" ])
      })

      expect(result.success?).to be(true)
      expect(hotel.hotel_extra_charges.sole.transaction_code.tax_rule_keys)
        .to contain_exactly("primary:sst_tax", "hotel_tax:#{tax.id}")
    end

    it "rolls every row back when one row is invalid" do
      result = save(entries: {
        "first" => charge_entry("client_key" => "first"),
        "second" => charge_entry("client_key" => "second", "code" => "SPA", "name" => "", "rate_value" => "0")
      })

      expect(result.success?).to be(false)
      expect(result.error).to start_with("Extra charge 2:")
      expect(hotel.hotel_extra_charges).to be_empty
    end

    # Two codes that normalize alike would otherwise reach the per-hotel unique
    # index and surface as a 500 rather than something the owner can fix.
    it "refuses two rows whose codes normalize to the same value" do
      result = save(entries: {
        "first" => charge_entry("client_key" => "first", "code" => "AIR-PORT"),
        "second" => charge_entry("client_key" => "second", "name" => "Spa", "code" => "AIR PORT")
      })

      expect(result.success?).to be(false)
      expect(result.error).to include("AIR_PORT")
      expect(hotel.hotel_extra_charges).to be_empty
    end

    it "refuses rows belonging to another property" do
      other = create(:hotel)
      Financials::EnsureDefaultExtraCharges.call(other)

      result = save(entries: { "draft-1" => charge_entry("id" => other.hotel_extra_charges.first.id.to_s) })

      expect(result.success?).to be(false)
      expect(result.error).to include("do not belong to this property")
    end

    it "will not complete with nothing to sell" do
      result = save(entries: {}, complete: true)

      expect(result.success?).to be(false)
      expect(result.error).to include("no extra charges for now")
    end

    it "saves a draft without completing the section" do
      result = save(entries: { "draft-1" => charge_entry }, complete: false)

      expect(result.success?).to be(true)
      expect(result.section.state).to eq("in_progress")
    end

    it "keeps a charge a payment surcharge depends on" do
      save(entries: { "draft-1" => charge_entry }, complete: true)
      charge = hotel.hotel_extra_charges.sole
      PaymentMethods::EnsureDefaults.call(hotel)
      hotel.hotel_payment_methods.find_by!(transaction_code: hotel.transaction_codes.find_by(system_key: "card_payment"))
           .update!(surcharge_posting_type: "fixed", surcharge_value: 5, surcharge_extra_charge: charge)

      result = save(entries: { "draft-1" => charge_entry("id" => charge.id.to_s, "_destroy" => "1") })

      expect(result.success?).to be(false)
      expect(result.error).to include("surcharge")
      expect(hotel.hotel_extra_charges.reload).to be_present
    end

    it "reopens downstream commercial sections when a charge stops being sellable" do
      save(entries: { "draft-1" => charge_entry }, complete: true)
      charge = hotel.hotel_extra_charges.sole
      hotel.onboarding_sections.find_by!(section_key: "payment_methods").update!(state: "complete")

      result = save(entries: { "draft-1" => charge_entry("id" => charge.id.to_s, "active" => "false") }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.onboarding_sections.find_by(section_key: "payment_methods").state).to eq("needs_attention")
    end
  end

  describe Onboarding::SkipOptionalSection do
    before { resolve_through!("rates_availability") }

    it "records an explicit decision and an audit event" do
      result = described_class.call(hotel: hotel, actor: actor, section_key: "extra_charges")

      expect(result.success?).to be(true)
      expect(result.section).to have_attributes(state: "skipped")
      expect(result.section.decision_metadata).to include("decision" => "no_extra_charges")
      expect(result.section.decision_metadata).not_to have_key("placeholder")
      expect(hotel.onboarding_audit_events.where(section_key: "extra_charges", event_type: "skipped")).to be_present
    end

    it "refuses a section that is not skippable" do
      result = described_class.call(hotel: hotel, actor: actor, section_key: "payment_methods")

      expect(result.success?).to be(false)
    end
  end
end
