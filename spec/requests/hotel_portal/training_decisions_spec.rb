# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel portal training decisions", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "ready_to_launch") }
  let(:role) { create(:role, account:) }
  let(:owner) { create(:user, account:) }
  let(:result) { double("training decision result", success?: true, error: nil) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role:, permission:)
    create(:user_hotel_access, user: owner, hotel:, role:)
    sign_in_as(owner)
  end

  it "records the owner's keep decision through the lifecycle service" do
    allow(Onboarding::CompleteTraining).to receive(:call).and_return(result)

    post keep_hotel_training_decision_path(hotel)

    expect(Onboarding::CompleteTraining).to have_received(:call).with(hotel:, actor: owner, decision: "keep")
    expect(response).to redirect_to(hotel_dashboard_path(hotel))
  end

  it "requests an asynchronous reset through the reset service" do
    reset_service = class_double("Onboarding::RequestTrainingReset", call: result).as_stubbed_const

    post reset_hotel_training_decision_path(hotel)

    expect(reset_service).to have_received(:call).with(hotel:, actor: owner)
    expect(response).to redirect_to(hotel_dashboard_path(hotel))
  end

  it "does not let unprivileged staff make the launch decision" do
    staff_role = create(:role, account:)
    staff = create(:user, account:)
    create(:user_hotel_access, user: staff, hotel:, role: staff_role)
    sign_in_as(staff)
    allow(Onboarding::CompleteTraining).to receive(:call).and_return(result)

    post keep_hotel_training_decision_path(hotel), headers: { "HTTP_REFERER" => hotel_dashboard_url(hotel) }

    expect(Onboarding::CompleteTraining).not_to have_received(:call)
    expect(response).to redirect_to(hotel_dashboard_url(hotel))
    expect(flash[:alert]).to eq("You are not authorized to perform this action.")
  end
end
