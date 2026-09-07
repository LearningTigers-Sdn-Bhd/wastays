require "rails_helper"

RSpec.describe "Hotel Portal Guest Content amenities", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:pool) { Amenity.hotel.find_by!(slug: "swimming_pool") }
  let(:gym) { Amenity.hotel.find_by!(slug: "fitness_center") }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    hotel.update!(amenities: [ pool.slug ])
    sign_in_as(user)
  end

  it "lists the selected amenities in a table with their content status" do
    create(:hotel_amenity_detail, hotel: hotel, amenity: pool, location: "Rooftop", opening_hours: "8 AM to 8 PM", fee_information: nil)

    get hotel_guest_amenities_path(hotel)

    expect(response).to have_http_status(:ok)
    body = Nokogiri::HTML(response.body)
    rows = body.css("[data-testid='amenities-table'] tbody tr")
    expect(rows.size).to eq(1)
    expect(rows.first.text).to include("Swimming Pool", "Rooftop", "Incomplete")
  end

  it "opens the manage amenities sheet with every amenity in the catalog" do
    get edit_hotel_amenity_selection_path(hotel)

    expect(response).to have_http_status(:ok)
    body = Nokogiri::HTML(response.body)
    checkboxes = body.css("[data-testid='amenity-selection-list'] input[type='checkbox']")
    expect(checkboxes.size).to eq(Amenity.hotel.count)
    expect(checkboxes.select { |box| box["checked"] }.map { |box| box["value"] }).to eq([ pool.slug ])
  end

  it "puts the saved amenities in a Selected group above the catalog" do
    hotel.update!(amenities: [ gym.slug, pool.slug ])

    get edit_hotel_amenity_selection_path(hotel)

    list = Nokogiri::HTML(response.body).at_css("[data-testid='amenity-selection-list']")
    expect(list.css("h4").map { |heading| heading.text.squish }.first).to eq("Selected")
    first_group = list.at_css("[data-amenity-selection-target='group']")
    expect(first_group.css("input[type='checkbox']").map { |box| box["value"] }).to contain_exactly(pool.slug, gym.slug)
    expect(first_group.css("input[type='checkbox']").all? { |box| box["checked"] }).to be true
    # No amenity appears twice: the catalog groups hold only what is unselected.
    values = list.css("input[type='checkbox']").map { |box| box["value"] }
    expect(values.uniq.size).to eq(values.size)
  end

  it "shows no Selected group when the property offers no amenities" do
    hotel.update!(amenities: [])

    get edit_hotel_amenity_selection_path(hotel)

    list = Nokogiri::HTML(response.body).at_css("[data-testid='amenity-selection-list']")
    expect(list.css("h4").map { |heading| heading.text.squish }).not_to include("Selected")
  end

  it "replaces the property amenities from the sheet" do
    patch hotel_amenity_selection_path(hotel), params: { hotel: { amenities: [ "", gym.slug ] } }

    expect(response).to have_http_status(:see_other)
    expect(hotel.reload.amenities).to eq([ gym.slug ])
  end

  it "reports an invalid amenity instead of saving it" do
    patch hotel_amenity_selection_path(hotel), params: { hotel: { amenities: [ "helipad_and_submarine_dock" ] } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(hotel.reload.amenities).to eq([ pool.slug ])
  end

  it "saves the guest details of one amenity from its own sheet" do
    patch hotel_amenity_detail_path(hotel, pool), params: {
      hotel_amenity_detail: { location: "Rooftop", opening_hours: "8 AM to 8 PM", reservation_required: "1" }
    }

    expect(response).to have_http_status(:see_other)
    detail = hotel.hotel_amenity_details.find_by!(amenity: pool)
    expect(detail.location).to eq("Rooftop")
    expect(detail).to be_reservation_required
  end

  it "refuses guest details for an amenity the property does not offer" do
    get edit_hotel_amenity_detail_path(hotel, gym)

    expect(response).to have_http_status(:not_found)
  end
end
