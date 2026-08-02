# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Folios::Actions transactions", type: :request, frozen_time: Time.zone.local(2026, 6, 10, 3) do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
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

  def post_transaction(params)
    post hotel_folio_action_post_transaction_path(hotel, booking), params: { folio_transaction: params }
  end

  def post_transaction_with(params, extra: {}, headers: {})
    post hotel_folio_action_post_transaction_path(hotel, booking),
      params: { folio_transaction: params }.merge(extra),
      headers: headers
  end

  def open_form(**query)
    get hotel_folio_action_post_transaction_path(hotel, booking, **query), headers: { "Turbo-Frame" => "folio_action_sheet" }
  end

  context "with granular folio permissions" do
    before do
      %w[
        post_folio_charges
        post_folio_payments
        execute_folio_refunds
        post_folio_adjustments
        post_folio_corrections
        post_folio_write_offs
      ].each { |slug| grant_permission(slug) }
      folio
    end

    describe "GET the posting form" do
      it "renders the payment Sheet in the primary folio-action frame" do
        open_form(transaction_type: "payment", active_folio_id: folio.id)

        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML(response.body)
        expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-post-transaction-sheet[data-controller='panels-ui--sheet']")).to be_present
        expect(response.body).to include("Post payment")
        expect(response.body).to include("Target folio")
        expect(response.body).to include(folio.display_name)
        expect(response.body).not_to include("offcanvas")
      end

      it "renders into the secondary frame when launched from a stacked sheet" do
        get hotel_folio_action_post_transaction_path(hotel, booking, transaction_type: "payment", active_folio_id: folio.id),
          headers: { "Turbo-Frame" => "folio_action_sheet_secondary" }

        document = Nokogiri::HTML(response.body)
        expect(document.at_css("turbo-frame#folio_action_sheet_secondary dialog#folio-post-transaction-sheet")).to be_present
      end

      it "offers a refund source on the refund form" do
        open_form(transaction_type: "payment", category: "refund", active_folio_id: folio.id)

        expect(response.body).to include("Issue refund")
        expect(response.body).to include("Refund source")
      end

      it "renders a locked checkout payment for the selected folio" do
        token = Checkouts::SettlementToken.issue(booking: booking, folio: folio, kind: "payment", amount: 125)
        open_form(
          transaction_type: "payment",
          settlement_token: token
        )

        document = Nokogiri::HTML(response.body)
        expect(document.at_css("dialog#folio-post-transaction-sheet").text).to include("Settle checkout payment", "MYR 125.00")
        expect(document.at_css("input[name='settlement_token'][value='#{token}']")).to be_present
        expect(document.css("input[name='folio_transaction[amount]'][type='number']")).to be_empty
        expect(document.at_css("input[name='folio_transaction[description]'][readonly]")["value"]).to eq("Checkout payment for #{folio.display_name}")
      end

      it "offers the allowed adjustment categories" do
        open_form(transaction_type: "adjustment", active_folio_id: folio.id)

        expect(response.body).to include("Post adjustment")
        expect(response.body).to include("Write off")
        expect(response.body).to include("Correction")
      end

      it "explains the situation when the booking has no open folio" do
        folio.update!(status: "closed")

        open_form(transaction_type: "payment")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No open folio window")
      end

      it "does not find a booking belonging to another hotel" do
        foreign_booking = create(:booking, hotel: other_hotel, status: "checked_in")

        get hotel_folio_action_post_transaction_path(hotel, foreign_booking, transaction_type: "payment"),
          headers: { "Turbo-Frame" => "folio_action_sheet" }

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "posting payments" do
      it "posts a cash payment" do
        expect {
          post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash payment", posting_date: Date.current)
        }.to change { folio.folio_transactions.payment.count }.by(1)

        expect(response).to redirect_to(folio_operations_path)
        expect(folio.folio_transactions.last.category).to eq("cash")
      end

      it "posts a cash payment to the selected secondary folio" do
        target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
        primary_payment_count = folio.folio_transactions.payment.count

        expect {
          post_transaction(
            transaction_type: "payment",
            category: "cash",
            payment_source: "cash",
            amount: "100.00",
            description: "Cash payment",
            posting_date: Date.current,
            booking_folio_id: target_folio.id
          )
        }.to change { target_folio.folio_transactions.payment.count }.by(1)

        expect(folio.folio_transactions.payment.count).to eq(primary_payment_count)
        expect(target_folio.folio_transactions.last.category).to eq("cash")
      end

      it "stores reference and note metadata for staff-posted cash payments" do
        expect {
          post_transaction(
            transaction_type: "payment",
            category: "cash",
            payment_source: "cash",
            amount: "100.00",
            description: "Cash payment",
            posting_date: Date.current,
            reference: "RCP-000821",
            note: "Front desk receipt"
          )
        }.to change { folio.folio_transactions.payment.count }.by(1)

        transaction = folio.folio_transactions.payment.last
        expect(transaction.category).to eq("cash")
        expect(transaction.transaction_code.code).to eq("CASH")
        expect(transaction.metadata["reference"]).to eq("RCP-000821")
        expect(transaction.metadata["source_references"]).to eq("receipt_reference" => "RCP-000821")
        expect(transaction.metadata["note"]).to eq("Front desk receipt")
      end

      [
        { source: "cash", reference_key: :receipt_reference, reference: "RCP-123", code: "CASH", category: "cash" },
        { source: "bank", reference_key: :bank_reference, reference: "BNK-123", code: "BANK", category: "booking_payment" },
        { source: "card", reference_key: :card_reference, reference: "AUTH-123", code: "CARD", category: "gateway_payment" },
        { source: "gateway", reference_key: :gateway_reference, reference: "cap_123", code: "GATEWAY", category: "gateway_payment", manual_recovery: true },
        { source: "ota", reference_key: :ota_reference, reference: "AGD-123", code: "OTA", category: "booking_payment" }
      ].each do |example|
        it "posts #{example[:source]} payments using the server-mapped transaction code" do
          Financials::EnsureDefaultTransactionCodes.call(hotel)
          forged_code = hotel.transaction_codes.find_by!(system_key: "refund")
          tax_count = folio.folio_transactions.where(category: "tax").count

          expect {
            post_transaction(
              transaction_type: "payment",
              category: "cash",
              transaction_code_id: forged_code.id,
              payment_source: example[:source],
              amount: "100.00",
              description: "#{example[:source].humanize} payment",
              posting_date: Date.current,
              reference: example[:reference],
              note: "Front desk note"
            )
          }.to change { folio.folio_transactions.payment.count }.by(1)

          transaction = folio.folio_transactions.payment.order(:id).last
          expect(folio.folio_transactions.where(category: "tax").count).to eq(tax_count)
          expect(transaction.amount).to eq(100.to_d)
          expect(transaction.category).to eq(example[:category])
          expect(transaction.transaction_code.code).to eq(example[:code])
          expect(transaction.metadata["payment_source"]).to eq(example[:source])
          expect(transaction.metadata["source_references"]).to eq(example[:reference_key].to_s => example[:reference])
          expect(transaction.metadata["reference"]).to eq(example[:reference])
          expect(transaction.metadata["note"]).to eq("Front desk note")
          expect(transaction.metadata["posting_source"]).to eq("staff")
          expect(transaction.metadata["posted_by_user_id"]).to eq(user.id)
          expect(transaction.metadata["manual_recovery"]).to eq(true) if example[:manual_recovery]
          expect(folio.reload.outstanding_balance).to eq(-100.to_d)
        end
      end

      it "rejects staff payments without a payment source" do
        expect {
          post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash payment", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Payment source is required.")
      end

      it "rejects staff payments with an invalid payment source" do
        expect {
          post_transaction(transaction_type: "payment", category: "cash", payment_source: "crypto", amount: "100.00", description: "Payment", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Payment source is not valid.")
      end

      it "requires gateway references for gateway manual recovery payments" do
        expect {
          post_transaction(transaction_type: "payment", category: "cash", payment_source: "gateway", amount: "100.00", description: "Gateway recovery", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Gateway Manual Recovery reference is required.")
      end

      it "requires OTA references for OTA collected payments" do
        expect {
          post_transaction(transaction_type: "payment", category: "cash", payment_source: "ota", amount: "100.00", description: "OTA collected", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("OTA Collected reference is required.")
      end

      it "completes the sheet after a Turbo Stream post" do
        expect {
          post_transaction_with(
            { transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash payment", posting_date: Date.current },
            headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
          )
        }.to change { folio.folio_transactions.payment.count }.by(1)

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(action="complete_sheet"))
        expect(response.body).to include(%(target="folio_action_sheet"))
        expect(flash[:notice]).to eq("Folio transaction posted.")
      end

      it "completes the frame that launched the sheet" do
        post_transaction_with(
          { transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash payment", posting_date: Date.current },
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet_secondary" }
        )

        expect(response.body).to include(%(target="folio_action_sheet_secondary"))
      end

      it "posts a locked checkout payment and closes only its sheet" do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 125)
        token = Checkouts::SettlementToken.issue(booking: booking, folio: folio, kind: "payment", amount: 125)
        expect {
          post_transaction_with(
            {
              transaction_type: "payment",
              payment_source: "cash",
              amount: "1.00",
              description: "Changed in request",
              posting_date: Date.current,
              reference: "RCP-125",
              note: "Paid at checkout",
              booking_folio_id: folio.id
            },
            extra: {
              settlement_token: token
            },
            headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
          )
        }.to change { folio.folio_transactions.payment.count }.by(1)

        transaction = folio.folio_transactions.payment.last
        expect(transaction.amount).to eq(125.to_d)
        expect(transaction.description).to eq("Checkout payment for #{folio.display_name}")
        expect(transaction.metadata).to include("reference" => "RCP-125", "note" => "Paid at checkout")
        expect(response.body).to include(%(action="complete_sheet"), %(target="folio_action_sheet"))
        expect(response.body).not_to include("url=")
      end

      it "rejects a stale checkout settlement amount" do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 100)
        token = Checkouts::SettlementToken.issue(booking: booking, folio: folio, kind: "payment", amount: 100)
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 25)

        expect {
          post_transaction_with(
            {
              transaction_type: "payment",
              payment_source: "cash",
              description: "Checkout payment",
              posting_date: Date.current,
              booking_folio_id: folio.id
            },
            extra: { settlement_token: token },
            headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
          )
        }.not_to change { folio.folio_transactions.payment.count }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Folio balance changed")
      end

      it "rejects a forged checkout payment category" do
        create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 100)
        token = Checkouts::SettlementToken.issue(booking: booking, folio: folio, kind: "payment", amount: 100)

        expect {
          post_transaction_with(
            {
              transaction_type: "payment",
              category: "booking_payment",
              payment_source: "cash",
              description: "Checkout payment",
              posting_date: Date.current,
              booking_folio_id: folio.id
            },
            extra: { settlement_token: token },
            headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
          )
        }.not_to change { folio.folio_transactions.payment.count }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("does not match the requested transaction")
      end
    end

    describe "posting charges" do
      it "posts an other charge" do
        code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other")

        expect {
          post_transaction(transaction_type: "charge", transaction_code_id: code.id, amount: "25.00", description: "Lost key", posting_date: Date.current)
        }.to change { folio.folio_transactions.charge.count }.by(1)

        expect(folio.folio_transactions.last.category).to eq("other")
        expect(folio.folio_transactions.last.transaction_code).to eq(code)
      end

      it "posts a charge to the selected secondary folio" do
        target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
        code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other")
        primary_charge_count = folio.folio_transactions.charge.count

        expect {
          post_transaction(transaction_type: "charge", transaction_code_id: code.id, amount: "25.00", description: "Lost key", posting_date: Date.current, booking_folio_id: target_folio.id)
        }.to change { target_folio.folio_transactions.charge.count }.by(1)

        expect(folio.folio_transactions.charge.count).to eq(primary_charge_count)
        expect(target_folio.folio_transactions.last.transaction_code).to eq(code)
      end

      it "adds a charge from a transaction code and generates the attached taxes" do
        hotel.update!(sst_enabled: true)
        Financials::EnsureDefaultTransactionCodes.call(hotel)
        code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
        code.update!(is_taxable: true)
        code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

        expect {
          post_transaction(
            transaction_type: "charge",
            category: "tax",
            transaction_code_id: code.id,
            amount: "100.00",
            description: "Restaurant charge",
            posting_date: Date.current,
            reference: "RCPT-42",
            note: "Manager approved",
            override_closed_folio: "true",
            tax_ids: [ 999 ]
          )
        }.to change(FolioTransaction, :count).by(2)

        parent = folio.folio_transactions.find_by!(transaction_code: code)
        tax = folio.folio_transactions.where(category: "tax").sole
        expect(parent.category).to eq("fb")
        expect(parent.metadata["reference"]).to eq("RCPT-42")
        expect(parent.metadata["note"]).to eq("Manager approved")
        expect(tax.amount).to eq(8.to_d)
        expect(tax.transaction_code.system_key).to eq("sst_tax")
        expect(tax.metadata["parent_folio_transaction_id"]).to eq(parent.id)
        expect(tax.metadata["source_transaction_code_id"]).to eq(code.id)
      end

      it "rejects disallowed manual charge categories" do
        expect {
          post_transaction(transaction_type: "charge", category: "tax", amount: "10.00", description: "Tax", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Transaction code is required for manual charges.")
      end

      it "rejects non-charge transaction codes for add charge posting" do
        code = create(:transaction_code, hotel: hotel, kind: "payment", category: "cash")

        expect {
          post_transaction(transaction_type: "charge", transaction_code_id: code.id, amount: "10.00", description: "Cash", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Transaction code must be a charge code.")
      end
    end

    describe "issuing refunds" do
      it "posts an exact checkout refund with a generated description" do
        create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 50)
        token = Checkouts::SettlementToken.issue(booking: booking, folio: folio, kind: "refund", amount: 50)

        expect {
          post_transaction_with(
            {
              transaction_type: "payment",
              category: "refund",
              refund_source: "cash",
              description: "Changed in request",
              posting_date: Date.current,
              booking_folio_id: folio.id
            },
            extra: { settlement_token: token },
            headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
          )
        }.to change { folio.folio_transactions.payment.count }.by(1)

        transaction = folio.folio_transactions.payment.order(:id).last
        expect(transaction).to have_attributes(amount: -50.to_d, description: "Checkout refund for #{folio.display_name}")
        expect(response.body).to include(%(action="complete_sheet"), %(target="folio_action_sheet"))
      end

      it "records a refund as a negative payment" do
        post_transaction(transaction_type: "payment", category: "refund", refund_source: "bank_transfer", amount: "50.00", description: "Refund", posting_date: Date.current)

        transaction = folio.folio_transactions.payment.last
        expect(transaction.category).to eq("refund")
        expect(transaction.amount).to eq(-50.0)
        expect(transaction.metadata["refund_source"]).to eq("bank_transfer")
      end

      it "stores reference and note metadata for manually issued refunds" do
        expect {
          post_transaction(
            transaction_type: "payment",
            category: "refund",
            refund_source: "cash",
            amount: "50.00",
            description: "Refund",
            posting_date: Date.current,
            reference: "RF-102",
            note: "Returned cash deposit"
          )
        }.to change { folio.folio_transactions.payment.count }.by(1)

        transaction = folio.folio_transactions.payment.last
        expect(transaction.category).to eq("refund")
        expect(transaction.transaction_code.code).to eq("REFUND")
        expect(transaction.metadata["refund_source"]).to eq("cash")
        expect(transaction.metadata["reference"]).to eq("RF-102")
        expect(transaction.metadata["note"]).to eq("Returned cash deposit")
      end

      it "rejects manual refunds without a refund source" do
        expect {
          post_transaction(transaction_type: "payment", category: "refund", amount: "50.00", description: "Refund", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(response).to redirect_to(folio_operations_path)
        expect(flash[:alert]).to eq("Refund source is required.")
      end

      it "rejects manual refunds with an invalid refund source" do
        expect {
          post_transaction(transaction_type: "payment", category: "refund", refund_source: "crypto_wallet", amount: "50.00", description: "Refund", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Refund source is not valid.")
      end

      it "does not allow payment_source to bypass refund permissions or source validation" do
        role.role_permissions.destroy_all
        grant_permission("view_bookings")
        grant_permission("post_folio_payments")

        expect {
          post_transaction(transaction_type: "payment", category: "refund", payment_source: "cash", amount: "50.00", description: "Refund", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to include("not authorized")

        grant_permission("execute_folio_refunds")

        expect {
          post_transaction(transaction_type: "payment", category: "refund", payment_source: "cash", amount: "50.00", description: "Refund", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Refund source is required.")
      end
    end

    describe "posting adjustments" do
      it "posts a write-off adjustment" do
        expect {
          post_transaction(transaction_type: "adjustment", category: "write_off", amount: "50.00", description: "Manager write-off", posting_date: Date.current)
        }.to change { folio.folio_transactions.adjustment.count }.by(1)

        expect(folio.folio_transactions.last.category).to eq("write_off")
      end

      it "posts an adjustment to the selected secondary folio" do
        target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
        primary_adjustment_count = folio.folio_transactions.adjustment.count

        expect {
          post_transaction(transaction_type: "adjustment", category: "adjustment", amount: "50.00", description: "Manager adjustment", posting_date: Date.current, booking_folio_id: target_folio.id)
        }.to change { target_folio.folio_transactions.adjustment.count }.by(1)

        expect(folio.folio_transactions.adjustment.count).to eq(primary_adjustment_count)
        expect(target_folio.folio_transactions.last.category).to eq("adjustment")
      end
    end

    describe "guarding the target folio and the business date" do
      it "rejects a selected folio from another booking" do
        other_booking = create(:booking, hotel: hotel)
        other_folio = create(:booking_folio, booking: other_booking, hotel: hotel)

        expect {
          post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current, booking_folio_id: other_folio.id)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Selected folio is not available for this booking.")
      end

      it "rejects a selected closed folio" do
        target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, status: "closed")

        expect {
          post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current, booking_folio_id: target_folio.id)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to eq("Selected folio is not available for this booking.")
      end

      it "rejects closed folios" do
        folio.update!(status: "closed")

        expect {
          post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to include("Folio is closed")
      end

      it "rejects closed business dates" do
        closed_date = 1.day.ago.to_date
        create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed")
        create(:hotel_business_date, hotel: hotel, business_date: closed_date, status: "closed")

        post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: closed_date)

        expect(flash[:alert]).to include("business date #{closed_date} is already closed")
      end

      it "rejects staff inserts while night audit is running" do
        hotel.current_business_date_record.update!(status: "audit_running")
        code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other")

        expect {
          post_transaction(transaction_type: "charge", transaction_code_id: code.id, amount: "25.00", description: "Lost key", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to include("currently in night audit")
      end

      it "rejects staff inserts while night audit is blocked" do
        hotel.current_business_date_record.update!(status: "audit_blocked")
        code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other")

        expect {
          post_transaction(transaction_type: "charge", transaction_code_id: code.id, amount: "25.00", description: "Lost key", posting_date: Date.current)
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to include("blocked by night audit")
      end

      it "does not allow override_closed_folio params to bypass closed folio controls" do
        folio.update!(status: "closed")

        expect {
          post_transaction(
            transaction_type: "payment",
            category: "cash",
            payment_source: "cash",
            amount: "100.00",
            description: "Cash",
            posting_date: Date.current,
            override_closed_folio: "true"
          )
        }.not_to change(FolioTransaction, :count)

        expect(flash[:alert]).to include("Folio is closed")
      end
    end

    describe "the return_to destination" do
      it "honours a same-origin hotel path" do
        destination = folio_operations_path(folio.id)

        post_transaction_with(
          { transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current },
          extra: { return_to: destination }
        )

        expect(response).to redirect_to(destination)
      end

      it "falls back to the folio tab for an off-origin return_to" do
        post_transaction_with(
          { transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current },
          extra: { return_to: "https://evil.example.com/steal" }
        )

        expect(response).to redirect_to(folio_operations_path)
      end
    end
  end

  describe "permission gates" do
    it "requires the matching granular permission to post" do
      folio

      expect {
        post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end

    it "requires the matching granular permission to open the form" do
      folio

      open_form(transaction_type: "payment", active_folio_id: folio.id)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end

    it "does not allow the legacy post_folio_transactions permission to post" do
      grant_permission("post_folio_transactions")
      folio

      expect {
        post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end

    it "requires execute_folio_refunds permission for manual refunds" do
      grant_permission("post_folio_payments")
      folio

      expect {
        post_transaction(transaction_type: "payment", category: "refund", amount: "50.00", description: "Refund", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end

    it "requires post_folio_write_offs permission for write-offs" do
      grant_permission("post_folio_adjustments")
      folio

      expect {
        post_transaction(transaction_type: "adjustment", category: "write_off", amount: "50.00", description: "Write-off", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end

    it "opens the adjustment form for a user holding only one adjustment sub-permission" do
      grant_permission("post_folio_write_offs")
      folio

      open_form(transaction_type: "adjustment", active_folio_id: folio.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Write off")
      expect(response.body).not_to include("Correction")
    end
  end

  it "reports that the booking has no folio" do
    grant_permission("post_folio_payments")

    post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)

    expect(response).to redirect_to(folio_operations_path)
    expect(flash[:alert]).to eq("Booking has no folio.")
  end
end
