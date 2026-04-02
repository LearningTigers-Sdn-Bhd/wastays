require 'rails_helper'

RSpec.describe "HotelPortal::InventoryDashboards routing", type: :routing do
  it "routes GET /hotel/inventory to the inventory dashboards controller" do
    expect(get: "/hotel/inventory").to route_to(
      controller: "hotel_portal/inventory_dashboards",
      action: "index"
    )
  end
end
