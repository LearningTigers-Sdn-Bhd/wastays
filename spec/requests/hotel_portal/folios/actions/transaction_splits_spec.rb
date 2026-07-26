# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Folios::Actions transaction splits", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, status: "open") }
  let(:transaction) do
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
  end
  let(:target_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, label: "Company Folio") }

  before do
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
    grant_permission("view_bookings")
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def folio_operations_path(**params)
    hotel_booking_workspace_path(hotel, booking, { tab: "folio_operations" }.merge(params))
  end

  def split_path(record = transaction, **params)
    hotel_folio_action_split_transaction_path(hotel, booking, record, **params)
  end

  describe "GET the split form" do
    before { grant_permission("manage_folio_movements") }

    it "renders the split Sheet in the primary folio-action frame" do
      target_folio

      get split_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet dialog#folio-split-transaction-sheet[data-controller='panels-ui--sheet']")).to be_present
      expect(response.body).to include("Split transaction")
      expect(response.body).to include("Company Folio")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders into the secondary frame when launched from a stacked sheet" do
      target_folio

      get split_path, headers: { "Turbo-Frame" => "folio_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#folio_action_sheet_secondary dialog#folio-split-transaction-sheet")).to be_present
    end

    it "explains the situation when there is no other open folio to split to" do
      get split_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No other open folio window")
    end

    it "does not find a booking belonging to another hotel" do
      foreign_booking = create(:booking, hotel: other_hotel, status: "checked_in")

      get hotel_folio_action_split_transaction_path(hotel, foreign_booking, transaction),
        headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST the split" do
    before { grant_permission("manage_folio_movements") }

    it "splits a posted charge by amount and completes the sheet" do
      transaction
      target_folio

      expect {
        post split_path,
          params: { folio_operation: { target_folio_id: target_folio.id, amount: "40.00", reason: "Company covers part" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }
      }.to change(FolioTransaction, :count).by(3)
        .and change(FolioOperationLog.where(operation_type: "split_transaction"), :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="folio_action_sheet"')

      source_remainder = folio.folio_transactions.charge.where(split_from_transaction: transaction).order(:id).last
      target_split = target_folio.folio_transactions.charge.where(split_from_transaction: transaction).order(:id).last
      expect(source_remainder.amount).to eq(60.to_d)
      expect(target_split.amount).to eq(40.to_d)
      expect(transaction.reload.voided_by_transaction).to be_present
      expect(flash[:notice]).to eq("Folio transaction split.")
    end

    it "splits by percent" do
      transaction
      target_folio

      post split_path, params: { folio_operation: { target_folio_id: target_folio.id, percent: "25", reason: "Quarter to company" } }

      target_split = target_folio.folio_transactions.charge.where(split_from_transaction: transaction).order(:id).last
      expect(target_split.amount).to eq(25.to_d)
      expect(response).to redirect_to(folio_operations_path)
    end

    it "completes the frame that launched the sheet" do
      post split_path,
        params: { folio_operation: { target_folio_id: target_folio.id, amount: "40.00", reason: "Company covers part" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet_secondary" }

      expect(response.body).to include('target="folio_action_sheet_secondary"')
    end

    it "closes the sheet with a flash alert when the split fails" do
      allow(::Folios::Transactions::SplitTransaction).to receive(:call)
        .and_return(double(success?: false, error: "Transaction cannot be split."))

      post split_path,
        params: { folio_operation: { target_folio_id: target_folio.id, amount: "40.00", reason: "Company covers part" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "folio_action_sheet" }

      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to eq("Transaction cannot be split.")
    end
  end

  describe "without manage_folio_movements" do
    it "forbids the form" do
      get split_path, headers: { "Turbo-Frame" => "folio_action_sheet" }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end

    it "forbids the split before it reaches the service" do
      transaction
      target_folio

      expect(::Folios::Transactions::SplitTransaction).not_to receive(:call)

      expect {
        post split_path, params: { folio_operation: { target_folio_id: target_folio.id, amount: "40.00", reason: "Company covers part" } }
      }.not_to change(FolioTransaction, :count)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include("not authorized")
    end
  end

  describe "the return_to destination" do
    before { grant_permission("manage_folio_movements") }

    it "honours a same-origin hotel path" do
      destination = folio_operations_path(folio_id: folio.id)

      post split_path(transaction, return_to: destination),
        params: { folio_operation: { target_folio_id: target_folio.id, amount: "40.00", reason: "Company covers part" } }

      expect(response).to redirect_to(destination)
    end

    it "falls back to the folio tab for an off-origin return_to" do
      post split_path(transaction, return_to: "https://evil.example.com/steal"),
        params: { folio_operation: { target_folio_id: target_folio.id, amount: "40.00", reason: "Company covers part" } }

      expect(response).to redirect_to(folio_operations_path)
    end
  end
end
