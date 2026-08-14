# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding taxes and room revenue services" do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }

  def resolve_prerequisites!
    Onboarding::InitializeProgress.new(hotel: hotel).call
    %w[property_profile property_photos roles_permissions staff_setup].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  def tax_params(overrides = {})
    ActionController::Parameters.new(
      {
        hotel: { sst_enabled: "1", tourism_tax_enabled: "0", tourism_tax_amount: "10.0" },
        tax_entries: {}
      }.deep_merge(overrides)
    )
  end

  def save_taxes(complete: true, confirmed: true, params: tax_params)
    Onboarding::SaveTaxesFees.new(
      hotel: hotel, actor: actor, params: params, confirmed: confirmed, complete: complete
    ).call
  end

  def save_room_revenue(keys:, complete: true, application: "new_bookings_only")
    Onboarding::SaveRoomRevenue.new(
      hotel: hotel,
      actor: actor,
      params: ActionController::Parameters.new(
        transaction_code: { tax_rule_keys: keys },
        hotel_transaction_configuration: { room_revenue_tax_rule_application: application }
      ),
      complete: complete
    ).call
  end

  before { resolve_prerequisites! }

  describe "Onboarding::SaveTaxesFees" do
    it "refuses to complete without an explicit confirmation" do
      result = save_taxes(confirmed: false)

      expect(result.success?).to be(false)
      expect(result.error).to include("Confirm that you reviewed")
      expect(hotel.onboarding_sections.find_by!(section_key: "taxes_fees").state).not_to eq("complete")
    end

    it "saves a draft without confirmation" do
      result = save_taxes(complete: false, confirmed: false)

      expect(result.success?).to be(true)
      expect(hotel.onboarding_sections.find_by!(section_key: "taxes_fees").state).to eq("in_progress")
    end

    it "requires a usable amount when tourism tax is charged" do
      blank = save_taxes(params: tax_params(hotel: { tourism_tax_enabled: "1", tourism_tax_amount: "" }))
      expect(blank.success?).to be(false)
      expect(blank.error).to include("tourism tax amount")

      negative = save_taxes(params: tax_params(hotel: { tourism_tax_enabled: "1", tourism_tax_amount: "-5" }))
      expect(negative.success?).to be(false)
      expect(negative.error).to include("cannot be negative")
    end

    it "provisions the default transaction codes as part of the save" do
      hotel.transaction_codes.destroy_all

      expect { save_taxes }.to change { hotel.transaction_codes.reload.count }.from(0)
      expect(hotel.transaction_codes.find_by(system_key: "room_revenue")).to be_present
    end

    it "records a tax fingerprint and the custom tax count on completion" do
      result = save_taxes(params: tax_params(tax_entries: {
        "0" => { name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00", enabled: "1" }
      }))

      expect(result.success?).to be(true)
      expect(result.section.decision_metadata).to include(
        "confirmed" => true,
        "custom_tax_count" => 1,
        "tax_fingerprint" => be_present
      )
      expect(hotel.hotel_taxes.pluck(:name)).to eq([ "Heritage levy" ])
    end

    # The step no longer asks whether a tax is levied — listing it is the answer.
    it "charges a tax the form listed without being asked" do
      result = save_taxes(params: tax_params(tax_entries: {
        "0" => { name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00" }
      }))

      expect(result.success?).to be(true)
      expect(hotel.hotel_taxes.sole.enabled).to be(true)
    end

    # Settings still owns the toggle, and revisiting onboarding must not undo it.
    it "leaves a tax retired under Settings retired" do
      save_taxes(params: tax_params(tax_entries: {
        "0" => { name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00" }
      }))
      tax = hotel.hotel_taxes.sole
      tax.update!(enabled: false)

      save_taxes(params: tax_params(tax_entries: {
        "0" => { id: tax.id.to_s, name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "6.00" }
      }))

      expect(tax.reload).to have_attributes(enabled: false, amount: 6.00)
    end

    it "reports which row failed validation and saves nothing" do
      result = save_taxes(params: tax_params(tax_entries: {
        "0" => { name: "Valid fee", charge_type: "charge", rate_type: "flat", amount: "5.00", enabled: "1" },
        "1" => { name: "Broken fee", charge_type: "charge", rate_type: "flat", amount: "0", enabled: "1" }
      }))

      expect(result.success?).to be(false)
      expect(result.error).to start_with("Row 2:")
      expect(hotel.hotel_taxes.count).to eq(0)
    end

    it "refuses to delete a tax that room revenue assigns" do
      save_taxes(params: tax_params(tax_entries: {
        "0" => { name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00", enabled: "1" }
      }))
      tax = hotel.hotel_taxes.sole
      save_room_revenue(keys: [ "hotel_tax:#{tax.id}" ])

      result = save_taxes(params: tax_params(tax_entries: {}))

      expect(result.success?).to be(false)
      expect(result.error).to include("Heritage levy", "room revenue tax rules")
      expect(hotel.hotel_taxes.count).to eq(1)
    end
  end

  describe "Onboarding::SaveRoomRevenue" do
    before { save_taxes }

    it "assigns tax rules and derives is_taxable from the selection" do
      result = save_room_revenue(keys: [ "primary:sst_tax" ])

      expect(result.success?).to be(true)
      code = TransactionCodes::Resolver.for(hotel).room_revenue
      expect(code.transaction_code_taxes.map(&:tax_rule_key)).to eq([ "primary:sst_tax" ])
      expect(code.is_taxable).to be(true)
    end

    it "completes with no taxes at all" do
      result = save_room_revenue(keys: [])

      expect(result.success?).to be(true)
      expect(TransactionCodes::Resolver.for(hotel).room_revenue.is_taxable).to be(false)
      expect(hotel.onboarding_sections.find_by!(section_key: "room_revenue").state).to eq("complete")
    end

    it "provisions the stay-event policies on save" do
      expect { save_room_revenue(keys: []) }.to change { hotel.hotel_reservation_policies.count }.from(0).to(4)
    end

    it "saves the tax rule application" do
      save_room_revenue(keys: [], application: "open_folio_forecasts")

      expect(hotel.reload.transaction_configuration.room_revenue_tax_rule_application).to eq("open_folio_forecasts")
    end

    it "rejects a tax rule the hotel does not have" do
      other_tax = create(:hotel_tax, hotel: create(:hotel))

      result = save_room_revenue(keys: [ "hotel_tax:#{other_tax.id}" ])

      expect(result.success?).to be(false)
      expect(result.error).to include("unavailable for this hotel")
    end
  end

  describe "Onboarding::InvalidateRoomRevenue" do
    let(:room_revenue_section) { hotel.onboarding_sections.find_by!(section_key: "room_revenue") }

    before do
      save_taxes(params: tax_params(tax_entries: {
        "0" => { name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00", enabled: "1" }
      }))
    end

    it "invalidates a completed room revenue when an assigned tax changes" do
      tax = hotel.hotel_taxes.sole
      save_room_revenue(keys: [ "hotel_tax:#{tax.id}" ])
      expect(room_revenue_section.reload.state).to eq("complete")

      save_taxes(params: tax_params(tax_entries: {
        "0" => { id: tax.id.to_s, name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "9.00", enabled: "1" }
      }))

      expect(room_revenue_section.reload.state).to eq("needs_attention")
      expect(hotel.onboarding_audit_events.where(event_type: "invalidated", section_key: "room_revenue")).to exist
    end

    it "invalidates when an assigned tax is switched off" do
      save_room_revenue(keys: [ "primary:sst_tax" ])

      save_taxes(params: tax_params(hotel: { sst_enabled: "0" }, tax_entries: {
        "0" => { id: hotel.hotel_taxes.sole.id.to_s, name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00", enabled: "1" }
      }))

      expect(room_revenue_section.reload.state).to eq("needs_attention")
    end

    it "leaves room revenue alone when an unassigned fee changes" do
      tax = hotel.hotel_taxes.sole
      save_room_revenue(keys: [ "primary:sst_tax" ])

      save_taxes(params: tax_params(tax_entries: {
        "0" => { id: tax.id.to_s, name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "9.00", enabled: "1" }
      }))

      expect(room_revenue_section.reload.state).to eq("complete")
    end
  end

  describe "readiness" do
    it "stops treating the finance sections as placeholders, and still blocks the stubs" do
      save_taxes
      save_room_revenue(keys: [ "primary:sst_tax" ])

      blocking = Onboarding::Readiness.new(hotel: hotel).call.blocking_issues

      expect(blocking.map(&:section_key)).not_to include("taxes_fees", "room_revenue")
      expect(hotel.onboarding_sections.where(section_key: %w[taxes_fees room_revenue]).map(&:decision_metadata))
        .to all(satisfy { |metadata| !metadata.key?("placeholder") })
      expect(blocking.map(&:section_key)).to include(
        "rooms", "rates_availability", "extra_charges", "discounts",
        "payment_methods", "corporate_accounts", "channel_manager"
      )
    end
  end
end
