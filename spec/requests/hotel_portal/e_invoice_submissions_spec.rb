require "rails_helper"

RSpec.describe "HotelPortal::EInvoiceSubmissions", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:booking) { create(:booking, hotel: hotel) }
  let!(:folio) { create(:booking_folio, booking: booking, status: "closed") }

  before do
    # Add permissions for accessing hotel portal
    role = create(:role, account: account, slug: "hotel_owner")
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |p| p.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Enable e-invoice
    create(:e_invoice_setting, hotel: hotel, enabled: true)

    # Sign in
    sign_in_as(user)
  end

  describe "POST /create" do
    context "when e-invoice setting is disabled" do
      before do
        hotel.e_invoice_setting.update!(enabled: false)
      end

      it "redirects back with alert" do
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        expect(response).to redirect_to(hotel_folio_path(hotel, booking))
        expect(flash[:alert]).to include("E-Invoice is not enabled")
      end
    end

    context "when booking folio is not closed" do
      before do
        folio.update!(status: "open")
      end

      it "redirects back with alert" do
        post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        expect(response).to redirect_to(hotel_folio_path(hotel, booking))
        expect(flash[:alert]).to include("does not have a closed folio")
      end
    end

    context "when validation passes" do
      it "enqueues SubmitJob and redirects to submission page" do
        ActiveJob::Base.queue_adapter = :test
        expect {
          post hotel_e_invoice_submissions_path(hotel, booking_id: booking.id)
        }.to have_enqueued_job(EInvoice::SubmitJob).with(booking.id)

        submission = booking.reload.e_invoice_submission
        expect(submission).to be_present
        expect(submission.status).to eq("pending")
        expect(response).to redirect_to(hotel_e_invoice_submission_path(hotel, submission))
        expect(flash[:notice]).to include("queued")
      end
    end
  end
end
