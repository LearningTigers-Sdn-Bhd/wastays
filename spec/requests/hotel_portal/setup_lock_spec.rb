# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel portal setup lock", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "setup") }
  let(:role) { create(:role, account:) }
  let(:owner) { create(:user, account:) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role:, permission:)
    create(:user_hotel_access, user: owner, hotel:, role:)
    Onboarding::InitializeProgress.new(hotel:).call
  end

  context "when the hotel has not opted in" do
    context "as someone who can finish setup" do
      before { sign_in_as(owner) }

      it "leaves the portal reachable" do
        get edit_hotel_profile_path(hotel)

        expect(response).to have_http_status(:ok)
      end

      # The dashboard is not a portal page for a property that is not open yet — it used
      # to render a dead-end "Pending Review" panel. Onboarding is the real page.
      it "still sends the dashboard to onboarding" do
        get hotel_dashboard_path(hotel)

        expect(response).to redirect_to(
          hotel_onboarding_section_path(hotel, section_key: "property_profile")
        )
      end

      it "sends the dashboard to the review section once submitted" do
        hotel.update!(status: "pending_review")

        get hotel_dashboard_path(hotel)

        expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "review"))
      end
    end

    context "as staff who cannot finish setup" do
      let(:staff_role) { create(:role, account:) }
      let(:staff) { create(:user, account:) }

      before do
        create(:user_hotel_access, user: staff, hotel:, role: staff_role)
        sign_in_as(staff)
      end

      it "sends the setup dashboard to the explainer" do
        get hotel_dashboard_path(hotel)

        expect(response).to redirect_to(hotel_setup_lock_path(hotel))
      end

      it "sends the pending-review dashboard to the explainer" do
        hotel.update!(status: "pending_review")

        get hotel_dashboard_path(hotel)

        expect(response).to redirect_to(hotel_setup_lock_path(hotel))
      end
    end
  end

  context "when the lock is enabled" do
    before { hotel.update!(setup_lock_enabled: true) }

    context "as someone who can finish setup" do
      before { sign_in_as(owner) }

      it "redirects portal pages to where onboarding left off" do
        get edit_hotel_profile_path(hotel)

        expect(response).to redirect_to(
          hotel_onboarding_section_path(hotel, section_key: "property_profile")
        )
      end

      it "resumes at the first unresolved section rather than always the first" do
        hotel.onboarding_sections.find_by!(section_key: "property_profile")
             .update!(state: "complete", completed_at: Time.current)

        get edit_hotel_profile_path(hotel)

        expect(response).to redirect_to(
          hotel_onboarding_section_path(hotel, section_key: Onboarding::ResumePageResolver.new(hotel:).call.key)
        )
      end

      it "leaves onboarding itself reachable" do
        get hotel_onboarding_section_path(hotel, section_key: "property_profile")

        expect(response).to have_http_status(:ok)
      end

      it "leaves the user's own profile reachable" do
        get edit_hotel_user_profile_path(hotel)

        expect(response).to have_http_status(:ok)
      end

      it "leaves logging out reachable" do
        delete logout_path

        expect(response).to redirect_to(root_path)
      end
    end

    context "as staff who cannot finish setup" do
      let(:staff_role) { create(:role, account:) }
      let(:staff) { create(:user, account:) }

      before do
        create(:user_hotel_access, user: staff, hotel:, role: staff_role)
        sign_in_as(staff)
      end

      it "sends them to the explainer rather than into onboarding" do
        get edit_hotel_profile_path(hotel)

        expect(response).to redirect_to(hotel_setup_lock_path(hotel))
      end

      it "renders the explainer" do
        get hotel_setup_lock_path(hotel)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("still being set up")
      end

      it "sends them back to the dashboard once the hotel is live" do
        hotel.update!(status: "live")

        get hotel_setup_lock_path(hotel)

        expect(response).to redirect_to(hotel_dashboard_path(hotel))
      end
    end

    context "as a superadmin" do
      before { sign_in_as(create(:user, :superadmin)) }

      it "is unaffected" do
        get edit_hotel_profile_path(hotel)

        expect(response).to have_http_status(:ok)
      end
    end

    context "once the property has been submitted" do
      before do
        hotel.update!(status: "pending_review")
        sign_in_as(owner)
      end

      it "sends portal pages to the review section, not back into the wizard" do
        get edit_hotel_profile_path(hotel)

        expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "review"))
      end
    end

    it "stops once the property is live" do
      hotel.update!(status: "live")
      sign_in_as(owner)

      get edit_hotel_profile_path(hotel)

      expect(response).to have_http_status(:ok)
    end

    it "stops while the property is suspended" do
      hotel.update!(status: "suspended")
      sign_in_as(owner)

      get edit_hotel_profile_path(hotel)

      expect(response).to have_http_status(:ok)
    end
  end
end
