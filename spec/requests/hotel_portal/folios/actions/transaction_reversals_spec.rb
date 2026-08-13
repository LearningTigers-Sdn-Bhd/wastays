# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Folios::Actions transaction reversals", type: :request, frozen_time: Time.zone.local(2026, 6, 10, 3) do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, status: "open") }

  before do
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
    grant_permission("view_bookings")
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def folio_operations_path(folio_id = nil, **params)
    query = { tab: "folio_operations" }.merge(params)
    query[:folio_id] = folio_id if folio_id.present?
    hotel_booking_workspace_path(hotel, booking, query)
  end

  def reverse_path(transaction, **params)
    hotel_folio_action_reverse_transaction_path(hotel, booking, transaction, **params)
  end

  def reverse_transaction(transaction, params)
    post reverse_path(transaction), params: { folio_transaction: params }
  end

  def reverse_transaction_with(transaction, params, extra: {}, headers: {})
    post reverse_path(transaction), params: { folio_transaction: params }.merge(extra), headers: headers
  end

  context "with post_folio_corrections" do
    before do
      grant_permission("post_folio_corrections")
      folio
    end

    describe "GET the reversal form" do
      it "renders the reversal Sheet in the primary folio-action frame" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

        get reverse_path(transaction), headers: { "Turbo-Frame" => "folio_action_sheet" }

        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML(response.body)
        expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-reverse-transaction-sheet[data-controller='panels-ui--sheet']")).to be_present
        expect(response.body).to include("Reason")
        expect(response.body).to include("Note")
        expect(response.body).not_to include("offcanvas")
      end

      it "renders into the secondary frame when launched from a stacked sheet" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

        get reverse_path(transaction), headers: { "Turbo-Frame" => "folio_action_sheet_secondary" }

        document = Nokogiri::HTML(response.body)
        expect(document.at_css("turbo-frame#folio_action_sheet_secondary dialog#folio-reverse-transaction-sheet")).to be_present
      end

      # The reversal policy mixes authorization with business state, so a
      # blocked row must explain itself instead of returning a bare redirect.
      it "explains why a generated tax row cannot be reversed" do
        parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100)
        tax = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", amount: 8,
          metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } })

        get reverse_path(tax), headers: { "Turbo-Frame" => "folio_action_sheet" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Generated tax rows reverse with their parent charge.")
        expect(response.body).not_to include("folio_transaction[correction_reason]")
      end

      it "explains that an already reversed row cannot be reversed again" do
        transaction = create(:folio_transaction, booking_folio: folio)
        expect(::Folios::Transactions::ReverseTransaction.call(
          transaction: transaction, user: user, correction_reason: "Posting error", correction_note: "Initial correction"
        )).to be_success

        get reverse_path(transaction), headers: { "Turbo-Frame" => "folio_action_sheet" }

        expect(response.body).to include("Transaction has already been reversed.")
      end

      it "does not find a booking belonging to another hotel" do
        transaction = create(:folio_transaction, booking_folio: folio)
        foreign_booking = create(:booking, hotel: other_hotel, status: "checked_in")

        get hotel_folio_action_reverse_transaction_path(hotel, foreign_booking, transaction),
          headers: { "Turbo-Frame" => "folio_action_sheet" }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST the reversal" do
      it "reverses a folio transaction with correction details" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

        expect {
          reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
        }.to change { folio.folio_transactions.adjustment.count }.by(1)

        expect(response).to redirect_to(folio_operations_path)
        expect(flash[:notice]).to eq("Folio transaction reversed.")
        reversal = folio.folio_transactions.order(:id).last
        expect(reversal.reversal_of_transaction).to eq(transaction)
        expect(reversal.amount).to eq(-100.to_d)
        expect(transaction.reload.voided_by_transaction).to eq(reversal)
      end

      it "completes the sheet on a Turbo submission" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

        reverse_transaction_with(transaction,
          { correction_reason: "Posting error", correction_note: "Wrong booking" },
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" })

        expect(response).to have_http_status(:success)
        expect(response.body).to include('action="complete_sheet"')
        expect(response.body).to include('target="folio_action_sheet"')
      end

      it "completes the frame that launched the sheet" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

        reverse_transaction_with(transaction,
          { correction_reason: "Posting error", correction_note: "Wrong booking" },
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet_secondary" })

        expect(response.body).to include('target="folio_action_sheet_secondary"')
      end

      it "reverses a taxable parent and generated tax child as a group" do
        parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100)
        tax = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", amount: 8,
          metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } })

        expect {
          reverse_transaction(parent, correction_reason: "Posting error", correction_note: "Wrong taxable charge")
        }.to change(FolioTransaction, :count).by(2)

        expect(parent.reload.voided_by_transaction).to be_present
        expect(tax.reload.voided_by_transaction).to be_present
      end

      it "rejects direct generated tax child reversal through the controller policy" do
        parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100)
        tax = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", amount: 8,
          metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } })

        expect {
          reverse_transaction(tax, correction_reason: "Posting error", correction_note: "Tax only")
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Generated tax rows reverse with their parent charge.")
      end

      it "reverses a payment posted on a secondary company folio" do
        company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
        transaction = create(:folio_transaction, booking_folio: company_folio, transaction_type: "payment", category: "cash", amount: 100)

        expect {
          reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong company folio payment")
        }.to change { company_folio.folio_transactions.payment.where(category: "refund").count }.by(1)

        reversal = company_folio.folio_transactions.order(:id).last
        expect(reversal.reversal_of_transaction).to eq(transaction)
        expect(reversal.amount).to eq(-100.to_d)
        expect(transaction.reload.voided_by_transaction).to eq(reversal)
      end

      it "rejects reversal while night audit is running" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")
        hotel.current_business_date_record.update!(status: "audit_running")

        expect {
          reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to include("currently in night audit")
      end

      it "rejects reversal while night audit is blocked" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")
        hotel.current_business_date_record.update!(status: "audit_blocked")

        expect {
          reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to include("blocked by night audit")
      end

      it "rejects reversal without a correction reason" do
        transaction = create(:folio_transaction, booking_folio: folio)

        expect {
          reverse_transaction(transaction, correction_reason: "", correction_note: "Wrong booking", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Correction reason can't be blank.")
      end

      it "rejects reversal without a correction note" do
        transaction = create(:folio_transaction, booking_folio: folio)

        expect {
          reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Correction note can't be blank.")
      end

      it "rejects already reversed transactions" do
        transaction = create(:folio_transaction, booking_folio: folio)
        expect(::Folios::Transactions::ReverseTransaction.call(
          transaction: transaction, user: user, correction_reason: "Posting error", correction_note: "Initial correction"
        )).to be_success

        expect {
          reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Duplicate correction", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Transaction has already been reversed.")
      end

      it "does not allow override_night_audit params to bypass closed-date controls" do
        transaction = create(:folio_transaction, booking_folio: folio)
        closed_date = hotel.current_business_date
        create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed")
        hotel.current_business_date_record.update!(status: "closed")

        expect {
          reverse_transaction_with(transaction,
            { correction_reason: "Posting error", correction_note: "Wrong booking" },
            extra: { override_night_audit: "true" })
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to include("override_financial_date_lock")
      end
    end

    describe "the return_to destination" do
      it "honours a same-origin hotel path" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")
        destination = folio_operations_path(folio.id)

        reverse_transaction_with(transaction,
          { correction_reason: "Posting error", correction_note: "Wrong booking" },
          extra: { return_to: destination })

        expect(response).to redirect_to(destination)
      end

      it "falls back to the folio tab for an off-origin return_to" do
        transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

        reverse_transaction_with(transaction,
          { correction_reason: "Posting error", correction_note: "Wrong booking" },
          extra: { return_to: "https://evil.example.com/steal" })

        expect(response).to redirect_to(folio_operations_path)
      end
    end
  end

  describe "without post_folio_corrections" do
    before { folio }

    it "explains the missing permission on the form instead of reversing" do
      transaction = create(:folio_transaction, booking_folio: folio)

      get reverse_path(transaction), headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("You do not have permission to post folio corrections.")
      expect(response.body).not_to include("folio_transaction[correction_reason]")
    end

    it "refuses the reversal" do
      transaction = create(:folio_transaction, booking_folio: folio)

      expect {
        reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(flash[:alert]).to eq("You do not have permission to post folio corrections.")
    end
  end
end
