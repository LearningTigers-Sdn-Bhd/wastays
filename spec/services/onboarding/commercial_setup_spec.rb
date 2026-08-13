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

    # The four fields the table submits. A code is derived from the name unless
    # the row already carries one.
    def charge_entry(overrides = {})
      {
        "client_key" => "draft-1",
        "name" => "Airport transfer",
        "rate_value" => "80",
        "charging_unit" => "per_item",
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
        name: "Airport transfer", code: "AIRPORT_TR", pricing_type: "fixed",
        rate_value: 80.to_d, charging_unit: "per_item"
      )
      expect(result.section).to have_attributes(state: "complete")
      expect(result.section.decision_metadata).not_to have_key("placeholder")
    end

    # An owner naming what the property sells is not keeping the books, so the
    # table does not ask for a code — but the record still needs a unique one.
    it "derives a code from the name, sidestepping codes already taken" do
      hotel.transaction_codes.find_by!(system_key: "fnb_revenue").update!(code: "AIRPORT_TR")

      result = save(entries: { "draft-1" => charge_entry })

      expect(result.success?).to be(true)
      expect(hotel.hotel_extra_charges.sole.code).to eq("AIRPORT_2")
    end

    # An empty price is how the table says "staff decide when they post it": it
    # is the only pricing method a single field can express alongside an amount.
    it "treats an empty price as a charge staff price themselves" do
      result = save(entries: { "draft-1" => charge_entry("rate_value" => "") })

      expect(result.success?).to be(true)
      expect(hotel.hotel_extra_charges.sole).to have_attributes(pricing_type: "manual", rate_value: nil)
    end

    # Percentage pricing is set up in the settings portal and has no field here.
    # Saving the section must not flatten it into a fixed amount.
    it "keeps the pricing of a percentage charge the table cannot express" do
      save(entries: { "draft-1" => charge_entry }, complete: true)
      charge = hotel.hotel_extra_charges.sole
      charge.update!(pricing_type: "percentage", rate_value: 10, percentage_basis: "room_charges",
                     allow_amount_override: false)

      result = save(entries: {
        "draft-1" => charge_entry("id" => charge.id.to_s, "code" => charge.code, "rate_value" => "")
      })

      expect(result.success?).to be(true)
      expect(charge.reload).to have_attributes(
        pricing_type: "percentage", rate_value: 10.to_d, percentage_basis: "room_charges"
      )
    end

    # Nothing in the table stands for the description or the reporting category,
    # so a charge the settings portal filled in has to come back out unchanged.
    it "leaves the fields the table does not show as they stand" do
      save(entries: { "draft-1" => charge_entry }, complete: true)
      charge = hotel.hotel_extra_charges.sole
      charge.update!(description: "Book at reception the day before")
      charge.transaction_code.update!(category: "parking")

      save(entries: { "draft-1" => charge_entry("id" => charge.id.to_s, "code" => charge.code) })

      expect(charge.reload.description).to eq("Book at reception the day before")
      expect(charge.category).to eq("parking")
    end

    # The page offers the seeded revenue codes as unsaved rows. Saving one has to
    # attach to that code rather than mint a second code with the same value.
    it "adopts a seeded revenue code instead of creating a duplicate code" do
      code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")

      result = save(entries: {
        "suggested" => charge_entry(
          "transaction_code_id" => code.id.to_s, "name" => "Food & Beverage",
          "code" => "FNB", "rate_value" => ""
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
        "second" => charge_entry("client_key" => "second", "name" => "Spa", "rate_value" => "0")
      })

      expect(result.success?).to be(false)
      expect(result.error).to start_with("Extra charge 2:")
      expect(hotel.hotel_extra_charges).to be_empty
    end

    # Derived codes are unique by construction, so this now guards the codes the
    # table carries for rows that already have one. Two that normalize alike
    # would otherwise reach the per-hotel unique index and surface as a 500
    # rather than something the owner can fix.
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
      save(entries: {
        "draft-1" => charge_entry,
        "draft-2" => charge_entry("client_key" => "draft-2", "name" => "Spa")
      }, complete: true)
      charge, kept = hotel.hotel_extra_charges.ordered.to_a
      hotel.onboarding_sections.find_by!(section_key: "payment_methods").update!(state: "complete")

      result = save(entries: {
        "draft-1" => charge_entry("id" => charge.id.to_s, "code" => charge.code, "_destroy" => "1"),
        "draft-2" => charge_entry("client_key" => "draft-2", "name" => kept.name, "id" => kept.id.to_s,
                                  "code" => kept.code)
      }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.onboarding_sections.find_by(section_key: "payment_methods").state).to eq("needs_attention")
    end
  end

  describe Onboarding::SaveDiscounts do
    before do
      seed_transaction_codes!
      resolve_through!("extra_charges")
    end

    def discount_entry(overrides = {})
      {
        "client_key" => "draft-1",
        "name" => "Early bird",
        "pricing_type" => "percentage",
        "rate_value" => "10",
        "application_scope" => "all_eligible_charges"
      }.merge(overrides)
    end

    def save(entries:, complete: false)
      described_class.call(hotel: hotel, actor: actor, entries: entries, complete: complete)
    end

    it "creates a real discount and resolves the section" do
      result = save(entries: { "draft-1" => discount_entry }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_discounts.sole).to have_attributes(
        name: "Early bird", code: "EARLY_BIRD", pricing_type: "percentage", rate_value: 10.to_d
      )
      expect(result.section).to have_attributes(state: "complete")
      expect(result.section.decision_metadata).not_to have_key("placeholder")
    end

    # An owner naming the offers a property makes is not keeping the books, so
    # the table does not ask for a code — but the record still needs a unique one.
    it "derives a code from the name, sidestepping codes already taken" do
      hotel.transaction_codes.find_by!(system_key: "rebate").update!(code: "EARLY_BIRD")

      result = save(entries: { "draft-1" => discount_entry })

      expect(result.success?).to be(true)
      expect(hotel.hotel_discounts.sole.code).to eq("EARLY_BI_2")
    end

    # Nothing in the table stands for the description, whether the offer is
    # active, or whether staff may amend the calculated amount, so a discount the
    # settings portal filled in has to come back out unchanged.
    it "leaves the fields the table does not show as they stand" do
      save(entries: { "draft-1" => discount_entry("pricing_type" => "fixed", "rate_value" => "20") }, complete: true)
      discount = hotel.hotel_discounts.sole
      discount.update!(description: "Ask the duty manager first", allow_amount_override: false)
      discount.transaction_code.update!(active: false)

      save(entries: {
        "draft-1" => discount_entry("id" => discount.id.to_s, "code" => discount.code,
                                    "pricing_type" => "fixed", "rate_value" => "20")
      })

      expect(discount.reload).to have_attributes(
        description: "Ask the duty manager first", allow_amount_override: false
      )
      expect(discount.active?).to be(false)
    end

    it "adopts the seeded rebate code instead of minting a duplicate" do
      code = hotel.transaction_codes.find_by!(system_key: "rebate")

      result = save(entries: {
        "suggested" => discount_entry(
          "transaction_code_id" => code.id.to_s, "name" => "Rebate", "code" => "REBATE",
          "pricing_type" => "manual", "rate_value" => ""
        )
      }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_discounts.sole.transaction_code_id).to eq(code.id)
      expect(hotel.transaction_codes.where(code: "REBATE").count).to eq(1)
    end

    it "targets only the charges chosen" do
      code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")

      result = save(entries: {
        "draft-1" => discount_entry(
          "application_scope" => "selected_charges",
          "applicable_transaction_code_ids" => [ code.id.to_s ]
        )
      }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_discounts.sole.applicable_transaction_codes).to contain_exactly(code)
    end

    it "refuses a chosen-charges discount with nothing chosen" do
      result = save(entries: {
        "draft-1" => discount_entry("application_scope" => "selected_charges", "applicable_transaction_code_ids" => [])
      })

      expect(result.success?).to be(false)
      expect(result.error).to start_with("Discount 1:")
      expect(hotel.hotel_discounts).to be_empty
    end

    # Discounts::Save writes join rows before validating and unwinds with its own
    # Rollback, which is a no-op nested inside ours. The outer transaction is
    # what has to leave the join table clean.
    it "leaves no join rows behind when a later row fails" do
      code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")

      expect {
        save(entries: {
          "first" => discount_entry(
            "client_key" => "first", "application_scope" => "selected_charges",
            "applicable_transaction_code_ids" => [ code.id.to_s ]
          ),
          "second" => discount_entry("client_key" => "second", "name" => "", "code" => "STAFF")
        })
      }.not_to change(HotelDiscountTransactionCode, :count)

      expect(hotel.hotel_discounts).to be_empty
    end

    it "will not complete with nothing offered" do
      result = save(entries: {}, complete: true)

      expect(result.success?).to be(false)
      expect(result.error).to include("no discounts for now")
    end
  end

  describe Onboarding::SavePaymentMethods do
    before do
      seed_transaction_codes!
      resolve_through!("discounts")
    end

    def method_entry(overrides = {})
      {
        "client_key" => "draft-1",
        "name" => "Cash",
        "code" => "CASHDESK",
        "payment_method_type" => "cash",
        "guest_advance" => "false",
        "default_cash" => "true",
        "active" => "true",
        "surcharge_enabled" => "false"
      }.merge(overrides)
    end

    def save(entries:, complete: false)
      described_class.call(hotel: hotel, actor: actor, entries: entries, complete: complete)
    end

    it "completes once one method can take money" do
      result = save(entries: { "draft-1" => method_entry }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_payment_methods.sole).to have_attributes(name: "Cash", payment_method_type: "cash", default_cash: true)
      expect(result.section).to have_attributes(state: "complete")
      expect(result.section.decision_metadata).not_to have_key("placeholder")
    end

    it "refuses to complete with nothing guests can pay with" do
      result = save(entries: { "draft-1" => method_entry("active" => "false", "default_cash" => "false") }, complete: true)

      expect(result.success?).to be(false)
      expect(result.error).to include("at least one payment method")
    end

    # A partial unique index allows one per hotel and the domain save demotes the
    # others as it goes, so two claims would silently resolve to the last row.
    it "refuses two rows claiming the default cash method" do
      result = save(entries: {
        "first" => method_entry("client_key" => "first"),
        "second" => method_entry("client_key" => "second", "name" => "Petty cash", "code" => "PETTY")
      })

      expect(result.success?).to be(false)
      expect(result.error).to include("single default cash method")
      expect(hotel.hotel_payment_methods).to be_empty
    end

    # The table has no field for it, so the rows settle it between them.
    it "gives the default cash drawer to the first cash method taken at the desk" do
      result = save(entries: {
        "first" => method_entry("client_key" => "first", "name" => "Card", "code" => "CARDPAY",
                                "payment_method_type" => "bank_gateway", "default_cash" => "false"),
        "second" => method_entry("client_key" => "second", "default_cash" => "false")
      }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_payment_methods.find_by!(default_cash: true).name).to eq("Cash")
    end

    # The table shows a standard code as text and offers no remove control for
    # it. Both hold here, so a forged row changes nothing.
    it "keeps a standard payment code as the property was given it" do
      PaymentMethods::EnsureDefaults.call(hotel)
      card = hotel.hotel_payment_methods.joins(:transaction_code)
                  .find_by!(transaction_codes: { system_key: "card_payment" })

      result = save(entries: { "draft-1" => method_entry(
        "id" => card.id.to_s, "name" => "Renamed", "code" => "RENAMED",
        "payment_method_type" => "cash", "default_cash" => "false"
      ) })

      expect(result.success?).to be(true)
      expect(card.reload).to have_attributes(name: "Card Payment", code: "CARD", payment_method_type: "bank_gateway")
    end

    it "refuses to remove a standard payment code" do
      PaymentMethods::EnsureDefaults.call(hotel)
      card = hotel.hotel_payment_methods.joins(:transaction_code)
                  .find_by!(transaction_codes: { system_key: "card_payment" })

      result = save(entries: { "draft-1" => method_entry("id" => card.id.to_s, "_destroy" => "true") })

      expect(result.success?).to be(true)
      expect(card.reload).to be_persisted
    end

    it "derives a code from the name of a row typed from scratch" do
      result = save(entries: { "draft-1" => method_entry("name" => "Front desk cash", "code" => "") })

      expect(result.success?).to be(true)
      expect(hotel.hotel_payment_methods.sole.code).to eq("FRONT_DESK")
    end

    # Nothing in setup can hand the default to another row first, so refusing
    # the removal would leave an owner stuck with a method they do not take.
    it "removes the default cash method and hands the drawer to what is left" do
      save(entries: {
        "first" => method_entry("client_key" => "first"),
        "second" => method_entry("client_key" => "second", "name" => "Petty cash", "code" => "PETTY",
                                 "default_cash" => "false")
      })
      cash = hotel.hotel_payment_methods.find_by!(default_cash: true)

      result = save(entries: {
        "first" => method_entry("client_key" => "first", "id" => cash.id.to_s, "_destroy" => "true"),
        "second" => method_entry("client_key" => "second", "id" => hotel.hotel_payment_methods.where.not(id: cash.id).sole.id.to_s,
                                 "name" => "Petty cash", "code" => "PETTY", "default_cash" => "false")
      }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_payment_methods.sole).to have_attributes(name: "Petty cash", default_cash: true)
    end

    it "refuses a half-configured surcharge" do
      result = save(entries: {
        "draft-1" => method_entry(
          "payment_method_type" => "bank_gateway", "default_cash" => "false",
          "surcharge_enabled" => "true", "surcharge_posting_type" => "percentage"
        )
      })

      expect(result.success?).to be(false)
      expect(result.error).to start_with("Payment method 1:")
      expect(hotel.hotel_payment_methods).to be_empty
    end

    it "refuses a surcharge pointing at another property's extra charge" do
      other = create(:hotel)
      Financials::EnsureDefaultExtraCharges.call(other)

      result = save(entries: {
        "draft-1" => method_entry(
          "payment_method_type" => "bank_gateway", "default_cash" => "false",
          "surcharge_enabled" => "true", "surcharge_posting_type" => "fixed",
          "surcharge_value" => "5", "surcharge_extra_charge_id" => other.hotel_extra_charges.first.id.to_s
        )
      })

      expect(result.success?).to be(false)
      expect(result.error).to include("do not belong to this property")
    end

    it "posts a surcharge to one of this property's extra charges" do
      Financials::EnsureDefaultExtraCharges.call(hotel)
      charge = hotel.hotel_extra_charges.first

      result = save(entries: {
        "draft-1" => method_entry(
          "name" => "Card", "code" => "CARDPAY", "payment_method_type" => "bank_gateway", "default_cash" => "false",
          "surcharge_enabled" => "true", "surcharge_posting_type" => "fixed",
          "surcharge_value" => "5", "surcharge_extra_charge_id" => charge.id.to_s
        )
      }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.hotel_payment_methods.sole.surcharge_extra_charge).to eq(charge)
    end

    it "cannot be skipped" do
      result = Onboarding::UpdateSection.new(
        hotel: hotel, section_key: "payment_methods", state: "skipped", actor: actor, metadata: {}
      ).call

      expect(result.success?).to be(false)
    end
  end

  describe Onboarding::SaveCorporateDrafts do
    before { resolve_through!("payment_methods") }

    def draft_entry(overrides = {})
      {
        "client_key" => "draft-1",
        "email" => "accounts@acme.com",
        "company_name" => "Acme Sdn Bhd",
        "account_type" => "company",
        "credit_limit" => "5000",
        "credit_currency" => "MYR",
        "payment_terms_days" => "30"
      }.merge(overrides)
    end

    def save(entries:, complete: false)
      described_class.call(hotel: hotel, actor: actor, entries: entries, complete: complete)
    end

    it "queues a draft without sending anything" do
      expect {
        result = save(entries: { "draft-1" => draft_entry }, complete: true)
        expect(result.success?).to be(true)
      }.not_to change(Invitation, :count)

      draft = hotel.onboarding_corporate_drafts.sole
      expect(draft).to have_attributes(
        email: "accounts@acme.com", company_name: "Acme Sdn Bhd",
        relationship_type: "direct_bill", credit_limit: 5000.to_d, payment_terms_days: 30
      )
      expect(draft).not_to be_delivered
      expect(hotel.onboarding_sections.find_by(section_key: "corporate_accounts").decision_metadata)
        .not_to have_key("placeholder")
    end

    it "keeps onboarding corporate accounts on direct bill when a forged row says otherwise" do
      result = save(entries: { "draft-1" => draft_entry("relationship_type" => "standard") }, complete: true)

      expect(result.success?).to be(true)
      expect(hotel.onboarding_corporate_drafts.sole.relationship_type).to eq("direct_bill")
    end

    it "does not enqueue an invitation email" do
      expect {
        save(entries: { "draft-1" => draft_entry }, complete: true)
      }.not_to have_enqueued_mail(CorporateInvitationMailer, :invite)
    end

    it "refuses two rows sharing an email" do
      result = save(entries: {
        "first" => draft_entry("client_key" => "first"),
        "second" => draft_entry("client_key" => "second", "company_name" => "Other")
      })

      expect(result.success?).to be(false)
      expect(result.error).to include("accounts@acme.com")
      expect(hotel.onboarding_corporate_drafts).to be_empty
    end

    # `invitations` has a unique index on (hotel_id, email) for anything not yet
    # accepted, and it is not scoped by kind — so this would explode at delivery
    # rather than here.
    it "refuses an email already queued as a staff member" do
      role = create(:role, account: hotel.account, slug: "front_desk")
      hotel.onboarding_staff_drafts.create!(email: "accounts@acme.com", role: role, name: "Sam")

      result = save(entries: { "draft-1" => draft_entry })

      expect(result.success?).to be(false)
      expect(result.error).to include("staff member")
    end

    # A changes-requested edit after submission must not be able to erase the
    # marker that stops delivery sending twice.
    it "keeps a delivered draft when the section is re-saved" do
      delivered = create(:onboarding_corporate_draft, hotel: hotel, email: "sent@acme.com",
                                                      invitation: create(:corporate_invitation, hotel: hotel, account: hotel.account, email: "sent@acme.com"))

      result = save(entries: { "draft-1" => draft_entry })

      expect(result.success?).to be(true)
      expect(delivered.reload).to be_persisted
      expect(hotel.onboarding_corporate_drafts.count).to eq(2)
    end

    it "refuses to remove a draft that has already been invited" do
      delivered = create(:onboarding_corporate_draft, hotel: hotel, email: "sent@acme.com",
                                                      invitation: create(:corporate_invitation, hotel: hotel, account: hotel.account, email: "sent@acme.com"))

      result = save(entries: { "draft-1" => draft_entry("id" => delivered.id.to_s, "_destroy" => "1") })

      expect(result.success?).to be(false)
      expect(result.error).to include("already been invited")
      expect(delivered.reload).to be_persisted
    end

    # Continuing past an empty table is how most properties will leave this
    # section, so it records the same decision as the skip button rather than
    # blocking on a button the owner did not press.
    it "records no corporate accounts when completing an empty table" do
      queued = create(:onboarding_corporate_draft, hotel: hotel, email: "queued@acme.com")

      result = save(entries: {}, complete: true)

      expect(result.success?).to be(true)
      expect(result.section).to have_attributes(state: "skipped")
      expect(result.section.decision_metadata).to include("decision" => "no_corporate_accounts")
      expect(OnboardingCorporateDraft.where(id: queued.id)).to be_empty
    end
  end

  describe Onboarding::DecideNoCorporateAccounts do
    before { resolve_through!("payment_methods") }

    it "discards queued drafts but keeps delivered ones" do
      create(:onboarding_corporate_draft, hotel: hotel, email: "queued@acme.com")
      delivered = create(:onboarding_corporate_draft, hotel: hotel, email: "sent@acme.com",
                                                      invitation: create(:corporate_invitation, hotel: hotel, account: hotel.account, email: "sent@acme.com"))

      result = described_class.call(hotel: hotel, actor: actor)

      expect(result.success?).to be(true)
      expect(result.section).to have_attributes(state: "skipped")
      expect(hotel.onboarding_corporate_drafts.reload).to contain_exactly(delivered)
    end
  end

  describe Onboarding::SaveOtaCredentials do
    before { resolve_through!("corporate_accounts") }

    def entry(overrides = {})
      {
        "channel_name" => "Booking.com", "property_code" => "623847",
        "username" => "acme-hotel", "password" => "extranet-secret",
        "market_manager_email" => "dana@booking.com", "_destroy" => "false"
      }.merge(overrides)
    end

    def save(entries, complete: true)
      described_class.call(hotel: hotel, actor: actor, entries: entries, complete: complete)
    end

    it "stores a login and completes the section" do
      result = save({ "0" => entry })

      expect(result.success?).to be(true)
      expect(result.section).to have_attributes(state: "complete")
      expect(hotel.hotel_ota_credentials.sole)
        .to have_attributes(channel_name: "Booking.com", password: "extranet-secret", status: "pending")
    end

    it "leaves the password out of what it hands back" do
      result = save({ "0" => entry })

      expect(result.entries.sole).to include("password_saved" => "true")
      expect(result.entries.sole).not_to have_key("password")
    end

    it "keeps a stored password when the row is saved again without one" do
      save({ "0" => entry })
      credential = hotel.hotel_ota_credentials.sole

      save({ "0" => entry("id" => credential.id.to_s, "password" => "", "property_code" => "111111") })

      expect(credential.reload).to have_attributes(password: "extranet-secret", property_code: "111111")
    end

    it "rejects two rows naming the same channel" do
      result = save({ "0" => entry, "1" => entry("property_code" => "999999") })

      expect(result.success?).to be(false)
      expect(result.error).to include("Booking.com is listed more than once")
      expect(hotel.hotel_ota_credentials).to be_empty
    end

    it "redacts the password from a failed submission" do
      result = save({ "0" => entry, "1" => entry })

      expect(result.entries.first).not_to have_key("password")
      expect(result.entries.first).to include("password_typed" => "true")
    end

    it "ignores the trailing blank row the table renders" do
      result = save({ "0" => entry, "1" => { "channel_name" => "", "_destroy" => "false" } })

      expect(result.success?).to be(true)
      expect(hotel.hotel_ota_credentials.count).to eq(1)
    end

    it "reads continuing from an empty table as no channel manager for now" do
      result = save({ "0" => { "channel_name" => "", "_destroy" => "false" } })

      expect(result.success?).to be(true)
      expect(result.section).to have_attributes(state: "skipped")
      expect(result.section.decision_metadata).to include("decision" => "no_channel_manager_now")
    end

    it "honours a row the owner removed before continuing from the emptied table" do
      save({ "0" => entry })
      credential = hotel.hotel_ota_credentials.sole

      result = save({ "0" => entry("id" => credential.id.to_s, "_destroy" => "true") })

      expect(result.success?).to be(true)
      expect(result.section).to have_attributes(state: "skipped")
      expect(hotel.hotel_ota_credentials.reload).to be_empty
    end

    it "saves a draft with nothing entered" do
      result = save({}, complete: false)

      expect(result.success?).to be(true)
      expect(result.section).to have_attributes(state: "in_progress")
    end

    it "removes a discarded row" do
      save({ "0" => entry })
      credential = hotel.hotel_ota_credentials.sole

      result = save({ "0" => entry("id" => credential.id.to_s, "_destroy" => "true") }, complete: false)

      expect(result.success?).to be(true)
      expect(hotel.hotel_ota_credentials.reload).to be_empty
    end

    it "refuses a row belonging to another property" do
      other = create(:hotel_ota_credential)

      result = save({ "0" => entry("id" => other.id.to_s) })

      expect(result.success?).to be(false)
      expect(result.error).to include("do not belong to this property")
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
