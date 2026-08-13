require "rails_helper"

RSpec.describe "HotelPortal::ReservationPolicies", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live") }
  let(:user) { create(:user, account:) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    role = create(:role, account:, permissions: [ permission ])
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  def policy(policy_type)
    ReservationPolicies::EnsureDefaults.call(hotel)
    hotel.hotel_reservation_policies.find_by!(policy_type:)
  end

  def destination
    hotel_room_revenue_path(hotel, tab: "reservation_policies")
  end

  it "renders the late checkout sheet with the gate switch first" do
    get edit_hotel_reservation_policy_path(hotel, policy("late_checkout"))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Late checkout policy", "Charge for late checkout", "Add a note for guests")
  end

  it "seeds exactly one tier row on the cancellation sheet" do
    get edit_hotel_reservation_policy_path(hotel, policy("cancellation"))

    expect(response).to have_http_status(:ok)
    rows = Nokogiri::HTML(response.body)
      .css("[data-reservation-policy-form-target~='rows'] > [data-reservation-policy-form-target~='row']")
    expect(rows.size).to eq(1)
    expect(response.body).to include("Returning the balance", "Worked example")
  end

  it "offers no pricing type other than nights for no-show" do
    get edit_hotel_reservation_policy_path(hotel, policy("no_show"))

    values = Nokogiri::HTML(response.body)
      .css("select[name='hotel_reservation_policy[pricing_type]'] option").map { |option| option["value"] }
    expect(values.reject(&:blank?)).to eq([ "nights" ])
  end

  it "saves a percentage late checkout policy" do
    record = policy("late_checkout")

    patch hotel_reservation_policy_path(hotel, record), params: { hotel_reservation_policy: {
      active: "1", pricing_type: "percentage", rate_value: "50", percentage_basis: "first_night",
      allow_amount_override: "1", description: "Waived for delayed flights."
    } }

    expect(response).to redirect_to(destination)
    expect(record.reload).to have_attributes(pricing_type: "percentage", rate_value: 50, percentage_basis: "first_night")
    expect(record.pricing_label).to eq("50.00% of first night")
  end

  it "saves cancellation tiers and refund terms" do
    record = policy("cancellation")

    patch hotel_reservation_policy_path(hotel, record), params: { hotel_reservation_policy: {
      active: "1", pricing_type: "percentage", rate_value: "100", percentage_basis: "total_stay",
      refund_method: "original_payment_method", refund_processing_days: "14",
      cancellation_tiers_attributes: {
        "0" => { days_before_arrival: "14", pricing_type: "percentage", rate_value: "0", percentage_basis: "total_stay" },
        "1" => { days_before_arrival: "7", pricing_type: "percentage", rate_value: "50", percentage_basis: "total_stay" }
      }
    } }

    expect(response).to redirect_to(destination)
    expect(record.reload.cancellation_tiers.map(&:days_before_arrival)).to eq([ 7, 14 ])
    expect(record.refund_method).to eq("original_payment_method")
    expect(record.refund_processing_days).to eq(14)
  end

  it "rejects a no-show policy that is not priced in nights" do
    record = policy("no_show")

    patch hotel_reservation_policy_path(hotel, record), params: { hotel_reservation_policy: {
      active: "1", pricing_type: "fixed", rate_value: "100"
    } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("whole nights")
    expect(record.reload.pricing_type).to eq("nights")
  end

  it "turns a policy off from the summary row" do
    record = policy("no_show")

    patch status_hotel_reservation_policy_path(hotel, record), params: { active: "0" }

    expect(response).to redirect_to(destination)
    expect(record.reload).not_to be_active
  end

  it "does not leak another hotel's policy" do
    other = create(:hotel, account:)
    ReservationPolicies::EnsureDefaults.call(other)
    foreign = other.hotel_reservation_policies.first

    get edit_hotel_reservation_policy_path(hotel, foreign)

    expect(response).to have_http_status(:not_found)
  end
end
