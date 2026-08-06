# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::AccountsReceivable::CorporateAccountsPresenter do
  let(:hotel) { create(:hotel) }

  def presenter(params = {})
    described_class.new(hotel: hotel, params: ActionController::Parameters.new(params))
  end

  def named_account(name)
    create(:account, :corporate, name: name)
  end

  describe "pinned invitation rows" do
    it "separates live invitations from lapsed ones" do
      live = create(:corporate_invitation, hotel: hotel, account: hotel.account, expires_at: 3.days.from_now)
      lapsed = create(:corporate_invitation, hotel: hotel, account: hotel.account, expires_at: 2.days.ago)

      rows = presenter.pinned_rows.index_by { |row| row.invitation.id }

      expect(rows[live.id].status).to eq("pending")
      expect(rows[live.id].status_variant).to eq(:info)
      expect(rows[lapsed.id].status).to eq("expired")
      expect(rows[lapsed.id].status_variant).to eq(:destructive)
    end

    it "excludes accepted invitations" do
      create(:corporate_invitation, hotel: hotel, account: hotel.account, accepted_at: 1.day.ago)

      expect(presenter.pinned_rows).to be_empty
    end

    it "exposes the same reader set as an account row" do
      create(:corporate_invitation, :direct_bill, hotel: hotel, account: hotel.account,
        email: "billing@atlas.test", account_type: "travel_agent", payment_terms_days: 30,
        credit_limit: 5_000, credit_currency: "MYR")

      row = presenter.pinned_rows.sole

      expect(row.account_name).to be_nil
      expect(row.agent_code).to be_nil
      expect(row.credit_exposure).to be_nil
      expect(row.contact_email).to eq("billing@atlas.test")
      expect(row.account_type_label).to eq("Travel agent")
      expect(row.terms_label).to eq("Direct bill · 30 days")
      expect(row.proposed_credit_currency).to eq("MYR")
      expect(row.proposed_credit_limit).to eq(5_000.to_d)
      expect(row.dom_id).to eq("external-invitation-row-#{row.invitation.id}")
    end
  end

  describe "status filter" do
    let!(:active) { create(:hotel_corporate_account, hotel: hotel, status: "active") }
    let!(:suspended) { create(:hotel_corporate_account, hotel: hotel, status: "suspended") }
    let!(:invitation) { create(:corporate_invitation, hotel: hotel, account: hotel.account, expires_at: 3.days.from_now) }

    it "shows both sources when unfiltered" do
      subject = presenter

      expect(subject.paginated_rows.map(&:id)).to contain_exactly(active.id, suspended.id)
      expect(subject.pinned_rows.map(&:id)).to eq([ invitation.id ])
    end

    it "suppresses invitations when an account status is selected" do
      subject = presenter(status: "active")

      expect(subject.paginated_rows.map(&:id)).to eq([ active.id ])
      expect(subject.pinned_rows).to be_empty
    end

    it "suppresses accounts when an invitation status is selected" do
      subject = presenter(status: "pending")

      expect(subject.paginated_rows).to be_empty
      expect(subject.pinned_rows.map(&:id)).to eq([ invitation.id ])
    end

    it "returns only lapsed invitations for the expired status" do
      lapsed = create(:corporate_invitation, hotel: hotel, account: hotel.account, expires_at: 1.day.ago)

      expect(presenter(status: "expired").pinned_rows.map(&:id)).to eq([ lapsed.id ])
    end
  end

  describe "account type tabs" do
    before do
      create(:hotel_corporate_account, hotel: hotel, account_type: "company", corporate_account: named_account("Strata"))
      create(:hotel_corporate_account, hotel: hotel, account_type: "company", corporate_account: named_account("Northstar"))
      create(:hotel_corporate_account, hotel: hotel, account_type: "government", corporate_account: named_account("Ministry"))
      create(:corporate_invitation, hotel: hotel, account: hotel.account, account_type: "travel_agent", email: "strata-travel@example.com")
    end

    it "counts both sources and totals them under All" do
      tabs = presenter.account_type_tabs.index_by { |tab| tab[:name] }

      expect(tabs["all"][:count]).to eq(4)
      expect(tabs["company"][:count]).to eq(2)
      expect(tabs["government"][:count]).to eq(1)
      expect(tabs["travel_agent"][:count]).to eq(1)
      expect(tabs["airline"][:count]).to eq(0)
      expect(tabs["salesperson"][:count]).to eq(0)
    end

    it "narrows counts by the active search but not by the selected tab" do
      tabs = presenter(query: "strata", account_type: "company").account_type_tabs.index_by { |tab| tab[:name] }

      # Both the Strata account and the strata-travel invitation match the search;
      # selecting the Company tab must not shrink the other tabs' counts.
      expect(tabs["all"][:count]).to eq(2)
      expect(tabs["company"][:count]).to eq(1)
      expect(tabs["travel_agent"][:count]).to eq(1)
    end

    it "filters both sources by the selected tab" do
      subject = presenter(account_type: "travel_agent")

      expect(subject.paginated_rows).to be_empty
      expect(subject.pinned_rows.size).to eq(1)
    end

    it "marks the active tab" do
      expect(presenter.account_type_tabs.find { |tab| tab[:active] }[:name]).to eq("all")
      expect(presenter(account_type: "government").account_type_tabs.find { |tab| tab[:active] }[:name]).to eq("government")
    end
  end

  describe "credit exposure" do
    it "reports foreign-currency AR instead of reading as a clean account" do
      relationship = create(:hotel_corporate_account, hotel: hotel, credit_limit: 1_000, credit_currency: "MYR")
      booking = create(:booking, hotel: hotel, currency: "USD")
      folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship, currency: "USD")
      create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship,
        amount: 800, outstanding_amount: 800, currency: "USD")

      exposure = presenter.paginated_rows.sole.credit_exposure

      expect(exposure.current_outstanding).to eq(0.to_d)
      expect(exposure.non_comparable_totals).to eq("USD" => 800.to_d)
      expect(exposure).to be_requires_override
    end
  end

  describe "query cost" do
    it "does not scale with the number of rows" do
      create_list(:hotel_corporate_account, 12, hotel: hotel)
      create_list(:corporate_invitation, 3, hotel: hotel, account: hotel.account)

      baseline = count_queries do
        subject = described_class.new(hotel: hotel, params: ActionController::Parameters.new)
        subject.account_type_tabs
        subject.pinned_rows.each(&:status_label)
        subject.paginated_rows.each(&:credit_exposure)
      end

      create_list(:hotel_corporate_account, 12, hotel: hotel)

      scaled = count_queries do
        subject = described_class.new(hotel: hotel, params: ActionController::Parameters.new)
        subject.account_type_tabs
        subject.pinned_rows.each(&:status_label)
        subject.paginated_rows.each(&:credit_exposure)
      end

      expect(scaled).to eq(baseline)
    end
  end

  def count_queries(&block)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
    end
    block.call
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
