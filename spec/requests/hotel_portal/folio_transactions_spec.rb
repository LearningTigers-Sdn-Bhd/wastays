# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::FolioTransactions", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, status: "open") }

  before do
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def post_transaction(params)
    post hotel_folio_transactions_path(hotel, booking), params: { folio_transaction: params }
  end

  def reverse_transaction(transaction, params)
    post reverse_hotel_folio_transaction_path(hotel, booking, transaction), params: { folio_transaction: params }
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

    it "renders the posting sheet in the offcanvas frame" do
      get new_hotel_folio_transaction_path(hotel, booking, transaction_type: "payment", active_folio_id: folio.id, redirect_to_folio: true)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="offcanvas_drawer"))
      expect(response.body).to include("Post Payment")
      expect(response.body).to include("Target Folio")
      expect(response.body).to include(folio.display_name)
    end

    it "posts a cash payment" do
      expect {
        post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash payment", posting_date: Date.current)
      }.to change { folio.folio_transactions.payment.count }.by(1)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
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

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
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
      {
        source: "cash",
        reference_key: :receipt_reference,
        reference: "RCP-123",
        code: "CASH",
        category: "cash"
      },
      {
        source: "bank",
        reference_key: :bank_reference,
        reference: "BNK-123",
        code: "BANK",
        category: "booking_payment"
      },
      {
        source: "card",
        reference_key: :card_reference,
        reference: "AUTH-123",
        code: "CARD",
        category: "gateway_payment"
      },
      {
        source: "gateway",
        reference_key: :gateway_reference,
        reference: "cap_123",
        code: "GATEWAY",
        category: "gateway_payment",
        manual_recovery: true
      },
      {
        source: "ota",
        reference_key: :ota_reference,
        reference: "AGD-123",
        code: "OTA",
        category: "booking_payment"
      }
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

    it "preserves folios origin when redirecting back to folio after posting" do
      expect {
        post hotel_folio_transactions_path(hotel, booking), params: {
          redirect_to_folio: "true",
          folio_origin: "folios",
          folio_transaction: {
            transaction_type: "payment",
            category: "cash",
            payment_source: "cash",
            amount: "100.00",
            description: "Cash payment",
            posting_date: Date.current
          }
        }
      }.to change { folio.folio_transactions.payment.count }.by(1)

      expect(response).to redirect_to(hotel_folio_path(hotel, booking, origin: "folios", active_folio_id: folio.id))
    end

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

    it "adds a charge from a transaction code and generated attached taxes, then redirects to folio" do
      hotel.update!(sst_enabled: true)
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
      code.update!(is_taxable: true)
      code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

      expect {
        post hotel_folio_transactions_path(hotel, booking), params: {
          redirect_to_folio: "true",
          folio_transaction: {
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
          }
        }
      }.to change(FolioTransaction, :count).by(2)

      expect(response).to redirect_to(hotel_folio_path(hotel, booking, active_folio_id: folio.id))
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

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Refund source is required.")
    end

    it "rejects manual refunds with an invalid refund source" do
      expect {
        post_transaction(transaction_type: "payment", category: "refund", refund_source: "crypto_wallet", amount: "50.00", description: "Refund", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Refund source is not valid.")
    end

    it "does not allow payment_source to bypass refund permissions or source validation" do
      role.role_permissions.destroy_all
      grant_permission("post_folio_payments")

      expect {
        post_transaction(transaction_type: "payment", category: "refund", payment_source: "cash", amount: "50.00", description: "Refund", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to include("permission")

      grant_permission("execute_folio_refunds")

      expect {
        post_transaction(transaction_type: "payment", category: "refund", payment_source: "cash", amount: "50.00", description: "Refund", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Refund source is required.")
    end

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

    it "rejects disallowed manual charge categories" do
      expect {
        post_transaction(transaction_type: "charge", category: "tax", amount: "10.00", description: "Tax", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Transaction code is required for manual charges.")
    end

    it "rejects non-charge transaction codes for add charge posting" do
      code = create(:transaction_code, hotel: hotel, kind: "payment", category: "cash")

      expect {
        post_transaction(transaction_type: "charge", transaction_code_id: code.id, amount: "10.00", description: "Cash", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Transaction code must be a charge code.")
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

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to include("currently in night audit")
    end

    it "rejects staff inserts while night audit is blocked" do
      hotel.current_business_date_record.update!(status: "audit_blocked")
      code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other")

      expect {
        post_transaction(transaction_type: "charge", transaction_code_id: code.id, amount: "25.00", description: "Lost key", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to include("blocked by night audit")
    end

    it "reverses a folio transaction with correction details" do
      transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

      expect {
        reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
      }.to change { folio.folio_transactions.adjustment.count }.by(1)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:notice]).to eq("Folio transaction reversed.")
      reversal = folio.folio_transactions.order(:id).last
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

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to include("currently in night audit")
    end

    it "rejects reversal while night audit is blocked" do
      transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")
      hotel.current_business_date_record.update!(status: "audit_blocked")

      expect {
        reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to include("blocked by night audit")
    end

    it "reverses a taxable parent and generated tax child as a group" do
      parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100)
      tax = create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "charge",
        category: "tax",
        amount: 8,
        metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } }
      )

      expect {
        reverse_transaction(parent, correction_reason: "Posting error", correction_note: "Wrong taxable charge")
      }.to change(FolioTransaction, :count).by(2)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(parent.reload.voided_by_transaction).to be_present
      expect(tax.reload.voided_by_transaction).to be_present
    end

    it "rejects direct generated tax child reversal through the controller policy" do
      parent = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "fb", amount: 100)
      tax = create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "charge",
        category: "tax",
        amount: 8,
        metadata: { "parent_folio_transaction_id" => parent.id, "tax_line" => { "type" => "sst" } }
      )

      expect {
        reverse_transaction(tax, correction_reason: "Posting error", correction_note: "Tax only")
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Generated tax rows reverse with their parent charge.")
    end

    it "preserves folios origin when redirecting back to folio after reversal" do
      transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

      expect {
        post reverse_hotel_folio_transaction_path(hotel, booking, transaction), params: {
          redirect_to_folio: "true",
          folio_origin: "folios",
          folio_transaction: {
            correction_reason: "Posting error",
            correction_note: "Wrong booking",
            posting_date: Date.current
          }
        }
      }.to change { folio.folio_transactions.adjustment.count }.by(1)

      expect(response).to redirect_to(hotel_folio_path(hotel, booking, origin: "folios"))
    end

    it "requires manage_folio_movements permission to move charges" do
      transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
      target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)

      expect {
        post move_hotel_folio_transaction_path(hotel, booking, transaction), params: {
          redirect_to_folio: "true",
          folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" }
        }
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_folio_path(hotel, booking, active_folio_id: folio.id))
      expect(flash[:alert]).to include("permission")
    end

    it "moves a posted charge to another folio and keeps the active folio selected" do
      grant_permission("manage_folio_movements")
      transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
      target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)

      expect {
        post move_hotel_folio_transaction_path(hotel, booking, transaction), params: {
          redirect_to_folio: "true",
          folio_operation: { target_folio_id: target_folio.id, reason: "Route to company" }
        }
      }.to change(FolioTransaction, :count).by(2)
        .and change(FolioOperationLog.where(operation_type: "move_transaction"), :count).by(1)

      moved = target_folio.folio_transactions.charge.order(:id).last
      expect(moved.amount).to eq(100.to_d)
      expect(moved.moved_from_transaction).to eq(transaction)
      expect(transaction.reload.voided_by_transaction).to be_present
      expect(response).to redirect_to(hotel_folio_path(hotel, booking, active_folio_id: target_folio.id))
    end

    it "splits a posted charge to another folio and keeps the active folio selected" do
      grant_permission("manage_folio_movements")
      transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
      target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)

      expect {
        post split_hotel_folio_transaction_path(hotel, booking, transaction), params: {
          redirect_to_folio: "true",
          folio_operation: { target_folio_id: target_folio.id, amount: "40.00", reason: "Company covers part" }
        }
      }.to change(FolioTransaction, :count).by(3)
        .and change(FolioOperationLog.where(operation_type: "split_transaction"), :count).by(1)

      source_remainder = folio.folio_transactions.charge.where(split_from_transaction: transaction).order(:id).last
      target_split = target_folio.folio_transactions.charge.where(split_from_transaction: transaction).order(:id).last
      expect(source_remainder.amount).to eq(60.to_d)
      expect(target_split.amount).to eq(40.to_d)
      expect(transaction.reload.voided_by_transaction).to be_present
      expect(response).to redirect_to(hotel_folio_path(hotel, booking, active_folio_id: target_folio.id))
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
      result = Folios::ReverseTransaction.call(
        transaction: transaction,
        user: user,
        correction_reason: "Posting error",
        correction_note: "Initial correction"
      )
      expect(result).to be_success

      expect {
        reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Duplicate correction", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(flash[:alert]).to eq("Transaction has already been reversed.")
    end
  end

  it "requires the matching granular permission to post" do
    folio

    expect {
      post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "requires the matching granular permission to render the posting sheet" do
    folio

    get new_hotel_folio_transaction_path(hotel, booking, transaction_type: "payment", active_folio_id: folio.id)

    expect(response).to redirect_to(hotel_folio_path(hotel, booking, active_folio_id: folio.id))
    expect(flash[:alert]).to include("permission")
  end

  it "does not allow the legacy post_folio_transactions permission to post" do
    grant_permission("post_folio_transactions")
    folio

    expect {
      post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "requires post_folio_corrections permission to reverse" do
    folio
    transaction = create(:folio_transaction, booking_folio: folio)

    expect {
      reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "requires execute_folio_refunds permission for manual refunds" do
    grant_permission("post_folio_payments")
    folio

    expect {
      post_transaction(transaction_type: "payment", category: "refund", amount: "50.00", description: "Refund", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "requires post_folio_write_offs permission for write-offs" do
    grant_permission("post_folio_adjustments")
    folio

    expect {
      post_transaction(transaction_type: "adjustment", category: "write_off", amount: "50.00", description: "Write-off", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "does not allow override_closed_folio params to bypass closed folio controls" do
    grant_permission("post_folio_payments")
    folio.update!(status: "closed")

    expect {
      post hotel_folio_transactions_path(hotel, booking), params: {
        folio_transaction: {
          transaction_type: "payment",
          category: "cash",
          payment_source: "cash",
          amount: "100.00",
          description: "Cash",
          posting_date: Date.current,
          override_closed_folio: "true"
        }
      }
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("Folio is closed")
  end

  it "does not allow override_night_audit params to bypass closed-date reversal controls" do
    grant_permission("post_folio_corrections")
    transaction = create(:folio_transaction, booking_folio: folio)
    closed_date = hotel.current_business_date
    create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed")
    hotel.current_business_date_record.update!(status: "closed")

    expect {
      reverse_transaction(
        transaction,
        correction_reason: "Posting error",
        correction_note: "Wrong booking",
        override_night_audit: "true"
      )
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("override_financial_date_lock")
  end

  it "redirects with an error when the booking has no folio" do
    grant_permission("post_folio_payments")

    post_transaction(transaction_type: "payment", category: "cash", payment_source: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to eq("Booking has no folio.")
  end
end
